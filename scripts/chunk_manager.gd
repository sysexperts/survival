extends Node
class_name ChunkManager

## Streamt Boden + Höhe chunk-weise um den Spieler herum.
##
## Minecraft-Prinzip: läuft der Spieler nach außen, entstehen neue
## Kartenteile, weit entfernte werden wieder entladen, damit der Node-Baum
## nicht unbegrenzt wächst. Der gemalte Handbau-Bereich bleibt unangetastet -
## seine Zellen werden nie generiert und beim Entladen nie gelöscht.
##
## Milestone 1+2: Boden (mit Varianz + Erdflächen), Höhe, Bäume und Rohstoffe
## pro Chunk. Der Änderungs-Diff (Gefälltes bleibt weg) ist Milestone 3 und
## fehlt noch - ein neu geladener Chunk zeigt gefällte Bäume wieder.

## Kantenlänge eines Chunks in Zellen. Gearbeitet wird im DURCHGEHENDEN
## Zellkoordinatensystem (nicht in lokalen Chunk-Koords), sonst kippt die
## Stacked-Parität an den Grenzen (siehe README/neighbors).
const CHUNK := 16

## Chunks in diesem Radius um den Spieler sind geladen. Ab RADIUS+1 entladen -
## der eine Ring Hysterese verhindert Flackern an der Chunk-Grenze.
const RADIUS := 2

## Höchstens so viele Chunks pro Update generieren. Ein Chunk kann einige
## tausend set_block-Aufrufe bedeuten; ohne Deckel ruckelt es beim Laufen.
## Der erzwungene erste Load ignoriert den Deckel bewusst.
const LOAD_BUDGET := 1

## So viele ZELLEN werden pro Frame generiert (statt einen ganzen Chunk = 256
## Zellen auf einmal). Verteilt die Last -> kein Ruckeln beim Chunk-Laden.
const CELL_BUDGET := 32

## Per preload eingebunden statt über den class_name `WorldGen`: so läuft der
## Generator auch dann, wenn das Spiel direkt mit F5 gestartet wird, ohne dass
## der Editor die neue Klasse vorher registriert hat.
const WorldGenScript := preload("res://scripts/world_gen.gd")

@export var world_path: NodePath = ^"../World"
@export var world_seed: int = 20260901

## Weit abgelegene Zone fuer betretbare Huetten-Innenraeume (interior.gd stempelt
## dort hinein). Hier wird bewusst KEIN Gelaende generiert -> schwarzes Leeres
## rundherum, damit sich der Innenraum wie eine eigene Karte anfuehlt.
const INTERIOR_ZONE := Rect2i(960, 960, 120, 120)
## Wie oft die Spielerposition geprüft wird. Jeden Frame wäre Verschwendung -
## der Spieler wechselt selten den Chunk.
@export var update_interval := 0.2

var world: IsoWorld
var player: Node2D
var gen                          ## WorldGen; untypisiert, siehe WorldGenScript oben
## Regrowth kennt die gefällten/geernteten Zellen. Beim Generieren gefragt,
## damit ein nachgeladener Chunk Gefälltes nicht wieder erzeugt (Milestone 3).
var regrowth: Node

## Chunk-Koordinate -> {"blocks": [[cell, level], ...], "props": [cell, ...]}.
## Beim Entladen wird genau das wieder weggeräumt - sonst wüchse der Node-Baum.
var _loaded: Dictionary = {}
var _accum := 0.0
## Wartende Zellen (durchgehende Koords), die noch generiert werden muessen.
## Wird jeden Frame haeppchenweise (CELL_BUDGET) abgearbeitet.
var _queue: Array[Vector2i] = []
var _qhead := 0                  ## Index der naechsten zu generierenden Zelle


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	if world == null:
		push_warning("ChunkManager: keine Welt unter %s" % world_path)
		return
	gen = WorldGenScript.new(world_seed)
	regrowth = get_node_or_null(^"../Regrowth")
	# Der Spieler landet erst nach seinem eigenen _ready in der Gruppe, und er
	# hängt sich zur Laufzeit um (siehe README) - deshalb über die Gruppe und
	# einen Frame später.
	_first_load.call_deferred()


## Einmaliger, ungedrosselter Load beim Start, damit der Spieler nicht ins
## Leere fällt, falls er am Rand des Handbau-Bereichs steht.
func _first_load() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_update_chunks(true)
	_process_queue(_queue.size())   # initialer Load auf einmal (Spawn nicht ins Leere)
	# Kurzer Beleg im Output, dass generiert wurde - hilft beim Prüfen, ob der
	# neue Boden wirklich entsteht (er liegt außen um den Handbau-Bereich).
	var blocks := 0
	var props := 0
	for c in _loaded:
		blocks += _loaded[c]["blocks"].size()
		props += _loaded[c]["props"].size()
	print("ChunkManager: %d Chunks, %d Blöcke, %d Props generiert" % [_loaded.size(), blocks, props])


func _physics_process(delta: float) -> void:
	if world == null:
		return
	# Jeden Frame ein Haeppchen der Warteschlange abarbeiten (verteilt die Last).
	if _qhead < _queue.size():
		_process_queue(CELL_BUDGET)
	_accum += delta
	if _accum < update_interval:
		return
	_accum = 0.0
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	_update_chunks(false)


func _update_chunks(force: bool) -> void:
	var lvl: int = int(player.get("level")) if player.get("level") != null else 0
	var pcell := world.world_to_cell(player.global_position, lvl)
	var pchunk := _chunk_of(pcell)

	# Fehlende Chunks im Radius laden - im Steady State nur wenige pro Update,
	# damit es nicht ruckt. Nächstgelegene zuerst, sonst poppt der Boden erst
	# spät direkt neben dem Spieler auf.
	var wanted: Array[Vector2i] = []
	for cy in range(pchunk.y - RADIUS, pchunk.y + RADIUS + 1):
		for cx in range(pchunk.x - RADIUS, pchunk.x + RADIUS + 1):
			var c := Vector2i(cx, cy)
			if not _loaded.has(c):
				wanted.append(c)
	wanted.sort_custom(func(a, b):
		return (a - pchunk).length_squared() < (b - pchunk).length_squared())

	# Fehlende Chunks (nearest-first) in die Warteschlange legen; _process_queue
	# generiert sie ueber mehrere Frames verteilt -> kein Ruckeln.
	for c in wanted:
		_enqueue_chunk(c)

	# Alles außerhalb RADIUS+1 wieder entladen.
	for c in _loaded.keys():
		if absi(c.x - pchunk.x) > RADIUS + 1 or absi(c.y - pchunk.y) > RADIUS + 1:
			_unload_chunk(c)


func _enqueue_chunk(chunk: Vector2i) -> void:
	if _loaded.has(chunk):
		return
	# Leerer Eintrag; die Bloecke/Props fuellen sich beim Abarbeiten der Queue.
	_loaded[chunk] = {"blocks": [], "props": []}
	var base := chunk * CHUNK
	for oy in CHUNK:
		for ox in CHUNK:
			var cell := base + Vector2i(ox, oy)
			# Nur einzelne gemalte Zellen aussparen (nicht die ganze Box),
			# sonst klafft am unregelmäßigen Rand eine Lücke.
			if world.is_authored(cell):
				continue
			# Huetten-Innenraum-Zone (weit weg): dort NICHTS generieren, damit
			# der eingestempelte Innenraum wie eine eigene Karte im Leeren steht.
			if INTERIOR_ZONE.has_point(cell):
				continue
			_queue.append(cell)


## Generiert bis zu `budget` wartende Zellen in ihre (evtl. teilfertigen) Chunks.
func _process_queue(budget: int) -> void:
	var done := 0
	while done < budget and _qhead < _queue.size():
		var cell := _queue[_qhead]
		_qhead += 1
		var chunk := _chunk_of(cell)
		var data: Variant = _loaded.get(chunk)
		if data == null:
			continue                       # Chunk zwischenzeitlich entladen
		_gen_cell(cell, data["blocks"], data["props"])
		done += 1
	# Verbrauchten Kopf gelegentlich abschneiden, damit das Array nicht waechst.
	if _qhead > 2048:
		_queue = _queue.slice(_qhead)
		_qhead = 0


## Erzeugt eine einzelne Zelle: Bodensäule (mit Varianz + bündigem Rand) und
## optional ein Prop. Trägt Erzeugtes in blocks/props ein, damit das Entladen
## es exakt wieder wegräumen kann.
func _gen_cell(cell: Vector2i, blocks: Array, props: Array) -> void:
	# Nur nahe der gemalten Map die genaue Randhöhe suchen - das ist teuer,
	# weit draußen zählt ohnehin nur die Noise-Höhe.
	var edge := Vector2i(-1, 0)
	if world.dist_to_authored(cell) <= WorldGenScript.EDGE_RING:
		edge = world.nearest_authored(cell, WorldGenScript.EDGE_RING)
	# Explizit int: gen ist untypisiert (Variant), da ließe := keinen Typ ab.
	var h: int = gen.height_at(cell, edge.x, edge.y)

	var atlas: Vector2i = gen.ground_atlas(cell)
	var fill: Vector2i = gen.fill_atlas(cell)
	for lvl in range(0, h + 1):
		# Oberste Ebene = Deckkachel, darunter die Biom-Fuellkachel (Gras bzw. in
		# der Wueste Sand - sonst schaut Gras unter dem Sand hervor).
		world.set_block(cell, lvl, atlas if lvl == h else fill)
		blocks.append([cell, lvl])

	# Untergrund (-1..-5) unter jede generierte Zelle legen (Dirt + Grundgestein),
	# damit man auch draussen buddeln kann und Loch-Waende solide sind.
	for i in range(IsoWorld.UNDER_COUNT):
		var ulvl := -(i + 1)
		world.set_block(cell, ulvl, IsoWorld.DIRT_ATLAS)
		blocks.append([cell, ulvl])

	_place_prop(cell, h, props)


func _place_prop(cell: Vector2i, h: int, props: Array) -> void:
	# Wurde hier schon gefällt/geerntet? Dann statt des Original-Props einen
	# Stumpf (wächst noch nach) oder gar nichts setzen - sonst käme Gefälltes
	# beim Nachladen des Chunks zurück.
	if regrowth:
		match regrowth.suppresses_prop(cell):
			"stump":
				if h + 1 < world.level_count() and world.prop_node(cell) == null:
					world.set_prop(cell, h + 1, regrowth.stump_atlas, IsoWorld.STUMP_SOURCE_ID)
					props.append(cell)
				return
			"empty":
				return
	var p: Dictionary = gen.prop_at(cell)
	if p.is_empty() or world.prop_node(cell) != null:
		return
	if p["kind"] == "tree":
		# Props sitzen eine Ebene ÜBER ihrem Bodenblock (siehe README).
		if h + 1 >= world.level_count():
			return
		world.set_prop(cell, h + 1, p["atlas"], IsoWorld.PROP_SOURCE_ID)
		props.append(cell)
	elif p["kind"] == "rock":
		# Fels: eigener Node aus dem rocks-Sheet, blockiert und ist abbaubar.
		if world.spawn_rock(cell, h, int(p["state"]), int(p["variant"])):
			props.append(cell)
	else:
		# Rohstoff: deterministisches Sheet-Bild, damit Reload dasselbe zeigt.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(cell) ^ world_seed
		var sheet_cell := GatherDB.random_prop(p["kind"], rng)
		if world.spawn_gather(cell, h, p["kind"], sheet_cell):
			props.append(cell)


func _unload_chunk(chunk: Vector2i) -> void:
	var data: Dictionary = _loaded[chunk]
	# Erst die Prop-Nodes weg, dann die Blöcke. Authored-Zellen stehen hier nie
	# drin, weil _load_chunk sie überspringt.
	for cell in data["props"]:
		world.remove_prop(cell)
	for entry in data["blocks"]:
		world.erase_block(entry[0], entry[1])
	_loaded.erase(chunk)
	# Noch wartende Zellen dieses Chunks aus der Queue nehmen - sonst wuerden sie
	# bei erneutem Eintritt ein zweites Mal generiert (Doppel-Bloecke).
	if _qhead < _queue.size():
		var kept: Array[Vector2i] = []
		for i in range(_qhead, _queue.size()):
			if _chunk_of(_queue[i]) != chunk:
				kept.append(_queue[i])
		_queue = kept
		_qhead = 0


## Zelle -> Chunk-Koordinate. floori, damit es links/oben von 0 nicht kippt
## (Integer-Division rundet in GDScript zur Null hin).
func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
