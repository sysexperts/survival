extends Node
class_name ChunkManager

## Streamt Boden + Höhe chunk-weise um den Spieler herum.
##
## Minecraft-Prinzip: läuft der Spieler nach außen, entstehen neue
## Kartenteile, weit entfernte werden wieder entladen, damit der Node-Baum
## nicht unbegrenzt wächst. Der gemalte Handbau-Bereich bleibt unangetastet -
## seine Zellen werden nie generiert und beim Entladen nie gelöscht.
##
## Milestone 1: nur Boden und Höhe. Props und Rohstoffe pro Chunk kommen in
## Milestone 2, der Änderungs-Diff in Milestone 3 (siehe AGENTS.md).

## Kantenlänge eines Chunks in Zellen. Gearbeitet wird im DURCHGEHENDEN
## Zellkoordinatensystem (nicht in lokalen Chunk-Koords), sonst kippt die
## Stacked-Parität an den Grenzen (siehe README/neighbors).
const CHUNK := 16

## Chunks in diesem Radius um den Spieler sind geladen. Ab RADIUS+1 entladen -
## der eine Ring Hysterese verhindert Flackern an der Chunk-Grenze.
const RADIUS := 2

## Gras-Kachel aus Quelle 0 - dieselbe, die auch der Handbau am häufigsten
## nutzt (in world.tscn nachgezählt). Später ersetzen Biome diesen Festwert.
const GRASS_ATLAS := Vector2i(2, 2)

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

## Chunk-Koordinate -> Array der generierten Blöcke ([cell, level]). Wird
## beim Entladen gebraucht, um genau diese Blöcke wieder zu löschen.
var _loaded: Dictionary = {}
var _accum := 0.0


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	if world == null:
		push_warning("ChunkManager: keine Welt unter %s" % world_path)
		return
	gen = WorldGenScript.new(world_seed)
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
	var total := 0
	for c in _loaded:
		total += _loaded[c].size()
	print("ChunkManager: %d Chunks geladen, %d Blöcke generiert" % [_loaded.size(), total])


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
	var placed: Array = []
	var base := chunk * CHUNK
	for oy in CHUNK:
		for ox in CHUNK:
			var cell := base + Vector2i(ox, oy)
			# Die gesamte Handbau-Bounding-Box aussparen - nicht nur bemalte
			# Zellen, sondern auch bewusste Lücken darin (z. B. den See), die
			# der Generator sonst mit Gras zuschütten würde.
			if world.in_authored_bounds(cell):
				continue
			# Explizit int: gen ist untypisiert (Variant), da ließe := keinen
			# Typ ableiten.
			var h: int = gen.height_at(cell, world.dist_to_authored(cell))
			for lvl in range(0, h + 1):
				world.set_block(cell, lvl, GRASS_ATLAS)
				placed.append([cell, lvl])
	_loaded[chunk] = placed


func _unload_chunk(chunk: Vector2i) -> void:
	for entry in _loaded[chunk]:
		# Nur generierte Blöcke löschen. Authored-Zellen sind hier ohnehin nie
		# eingetragen worden, weil _load_chunk sie überspringt.
		world.erase_block(entry[0], entry[1])
	_loaded.erase(chunk)


## Zelle -> Chunk-Koordinate. floori, damit es links/oben von 0 nicht kippt
## (Integer-Division rundet in GDScript zur Null hin).
func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
