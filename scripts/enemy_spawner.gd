extends Node

## Setzt EINMAL ein Magier-Haus in Spawn-Naehe (nur auf Clients - der dedizierte
## Server simuliert keine Gegner). Das Haus kuemmert sich dann selbst um den
## Magier (mage_house.gd). Rein lokal.
##
## KEIN class_name (Auto-Updater) - Node haengt in main.tscn.

const MageHouse := preload("res://scripts/mage_house.gd")

## Ziel-Offset vom Startpunkt (Zellen) - ein Stueck abseits vom Spawn.
const TARGET_OFFSET := Vector2i(-16, -14)

var _done := false


func _ready() -> void:
	if Net.is_dedicated:
		return
	_try.call_deferred()


func _try() -> void:
	if _done:
		return
	var world := get_node_or_null(^"../World") as IsoWorld
	var player := get_tree().get_first_node_in_group("player")
	if world == null or player == null or world.props_root == null:
		get_tree().create_timer(0.5).timeout.connect(_try)
		return
	var here: Vector2i = world.world_to_cell(player.global_position, player.level)
	var target := here + TARGET_OFFSET
	var cell = _find_floor_near(world, target)
	if cell == null:
		get_tree().create_timer(0.5).timeout.connect(_try)
		return
	var house = MageHouse.create(world, player, cell)
	world.props_root.add_child(house)
	_done = true


## Naechste Zelle mit Boden, frei und nicht belegt - vom Ziel aus in Ringen.
func _find_floor_near(world: IsoWorld, target: Vector2i):
	for r in range(0, 10):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := Vector2i(target.x + dx, target.y + dy)
				if world.top_level_at(c) >= 0 and world.blocker_at(c) == null \
						and not world.has_prop(c):
					return c
	return null
