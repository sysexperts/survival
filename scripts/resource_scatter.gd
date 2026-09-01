extends Node
class_name ResourceScatter

## Streut Holz, Pflanzenfaser und Steine über die Karte.
##
## Läuft einmal beim Spielstart. Was der Spieler aufsammelt, bleibt weg -
## es gibt bewusst kein Nachwachsen: die Karte ist ein Vorrat, der zur
## Neige geht, und genau das treibt das Erkunden an.
##
## Welche Bilder benutzt werden und wie dicht gesät wird, steht in
## `scripts/gather_db.gd`.

@export var world_path: NodePath = ^"../World"
## Fester Startwert, damit dieselbe Karte immer gleich aussieht. 0 = zufällig.
@export var seed_value: int = 20250822
## Mindestabstand zwischen zwei Fundstücken, in Zellen. Ohne das klumpt
## der Zufall zu Nestern zusammen und lässt halbe Karten leer.
@export var min_spacing := 2
## Zellen rund um den Startpunkt des Spielers, die frei bleiben.
@export var spawn_clearance := 2

var world: IsoWorld

var _taken: Dictionary = {}     ## Vector2i -> true, belegte bzw. gesperrte Zellen


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	if world == null:
		push_warning("ResourceScatter: keine Welt unter %s" % world_path)
		return
	# Ein Frame warten wäre unnötig: World._ready läuft vor diesem Node,
	# die Prop-Nodes stehen also schon.
	_scatter()


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	var cells := world.free_ground_cells()
	if cells.is_empty():
		return
	_block_player_area()

	# Ohne Mischen läge alles in der Reihenfolge, in der die TileMap ihre
	# Zellen führt - also streifenweise.
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp

	var cursor := 0
	for id in GatherDB.ids():
		# Biom-gebundene Sorten (z. B. Wuesten-Flora) NICHT breit am Spawn streuen -
		# die setzt world_gen gezielt im richtigen Biom.
		if GatherDB.biome_of(id) != "":
			continue
		var wanted := int(round(cells.size() * GatherDB.density(id)))
		var placed := 0
		while placed < wanted and cursor < cells.size():
			var entry: Array = cells[cursor]
			cursor += 1
			var cell: Vector2i = entry[0]
			if not _is_free(cell):
				continue
			if world.spawn_gather(cell, int(entry[1]), id, GatherDB.random_prop(id, rng)):
				_reserve(cell)
				placed += 1


## Sperrt die Zelle und ihre Umgebung, damit nichts direkt aneinanderklebt.
func _reserve(cell: Vector2i) -> void:
	_taken[cell] = true
	for c in _cells_around(cell, min_spacing):
		_taken[c] = true


func _is_free(cell: Vector2i) -> bool:
	return not _taken.has(cell) and world.prop_node(cell) == null


## Der Spieler soll nicht zwischen Gestrüpp aufwachen.
func _block_player_area() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var here := world.world_to_cell(player.global_position, 0)
	_taken[here] = true
	for c in _cells_around(here, spawn_clearance):
		_taken[c] = true


## Alle Zellen im Umkreis von `radius` Schritten - über die echte
## Nachbarschaft gelaufen, weil das Raster halbversetzt ist und ein
## Rechteck in x/y hier schief liegen würde.
func _cells_around(cell: Vector2i, radius: int) -> Array:
	var out: Array = []
	var frontier: Array = [cell]
	var seen := {cell: true}
	for _step in radius:
		var next: Array = []
		for c in frontier:
			for n in world.neighbors(c):
				if seen.has(n):
					continue
				seen[n] = true
				next.append(n)
				out.append(n)
		frontier = next
	return out
