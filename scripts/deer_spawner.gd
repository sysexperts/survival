extends Node

## Spawnt selten Rehe in der Naehe des Spielers und entfernt zu weit entfernte.
##
## ERSTE VERSION rein clientseitig (siehe deer.gd) - Node in main.tscn.

const DeerScript := preload("res://scripts/deer.gd")

@export var world_path: NodePath = ^"../World"
## Hoechstzahl gleichzeitiger Rehe.
@export var max_deer := 3
## Spawn-Versuch alle N Sekunden ...
@export var try_interval := 6.0
## ... mit dieser Wahrscheinlichkeit (klein = "nicht so oft").
@export var spawn_chance := 0.25
## Spawn-Ring um den Spieler (Zellen) - ausserhalb des Sichtfelds.
@export var spawn_min := 9
@export var spawn_max := 16
## Weiter als das weg -> Reh entladen.
@export var despawn_dist := 26.0

var world: IsoWorld
var player: Node2D
var _deer: Array = []
var _accum := 0.0


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld


func _process(delta: float) -> void:
	if world == null or world.props_root == null:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	# Entfernte / kaputte Rehe aufraeumen.
	var pcell := world.world_to_cell(player.global_position, int(player.get("level")))
	for i in range(_deer.size() - 1, -1, -1):
		var d = _deer[i]
		if not is_instance_valid(d):
			_deer.remove_at(i)
			continue
		if _cell_dist(world.world_to_cell(d.global_position, d.level), pcell) > despawn_dist:
			d.queue_free()
			_deer.remove_at(i)

	_accum += delta
	if _accum < try_interval:
		return
	_accum = 0.0
	if _deer.size() >= max_deer or randf() > spawn_chance:
		return
	_try_spawn(pcell)


func _try_spawn(pcell: Vector2i) -> void:
	# Ein paar Zufallszellen im Spawn-Ring probieren.
	for _n in 12:
		var ang := randf() * TAU
		var r := randf_range(spawn_min, spawn_max)
		var cell := pcell + Vector2i(roundi(cos(ang) * r), roundi(sin(ang) * r * 2.0))
		if world.top_level_at(cell) < 0 or world.has_prop(cell) or world.blocker_at(cell) != null:
			continue
		var deer = DeerScript.new()
		world.props_root.add_child(deer)
		deer.setup(world, cell)
		_deer.append(deer)
		return


func _cell_dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()
