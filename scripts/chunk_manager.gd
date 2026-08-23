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

## Per preload eingebunden statt über den class_name `WorldGen`: so läuft der
## Generator auch dann, wenn das Spiel direkt mit F5 gestartet wird, ohne dass
## der Editor die neue Klasse vorher registriert hat.
const WorldGenScript := preload("res://scripts/world_gen.gd")

@export var world_path: NodePath = ^"../World"
@export var world_seed: int = 1337
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

	var budget := wanted.size() if force else LOAD_BUDGET
	for i in mini(budget, wanted.size()):
		_load_chunk(wanted[i])

	# Alles außerhalb RADIUS+1 wieder entladen.
	for c in _loaded.keys():
		if absi(c.x - pchunk.x) > RADIUS + 1 or absi(c.y - pchunk.y) > RADIUS + 1:
			_unload_chunk(c)


func _load_chunk(chunk: Vector2i) -> void:
	var blocks: Array = []      # [cell, level] - generierte Bodenblöcke
	var props: Array = []       # cell - generierte Bäume/Rohstoffe (Nodes)
	var base := chunk * CHUNK
	for oy in CHUNK:
		for ox in CHUNK:
			var cell := base + Vector2i(ox, oy)
			# Nur einzelne gemalte Zellen aussparen (nicht die ganze Box),
			# sonst klafft am unregelmäßigen Rand eine Lücke.
			if world.is_authored(cell):
				continue
			_gen_cell(cell, blocks, props)
	_loaded[chunk] = {"blocks": blocks, "props": props}


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
	for lvl in range(0, h + 1):
		# Oberste Ebene bekommt die (evtl. braune) Deckkachel, darunter immer
		# Gras - man sieht die Seitenflächen der Blöcke ohnehin nur als Rand.
		world.set_block(cell, lvl, atlas if lvl == h else WorldGenScript.GRASS[0])
		blocks.append([cell, lvl])

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


## Zelle -> Chunk-Koordinate. floori, damit es links/oben von 0 nicht kippt
## (Integer-Division rundet in GDScript zur Null hin).
func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
