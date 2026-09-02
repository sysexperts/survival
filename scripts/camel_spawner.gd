extends Node

## Kamele: Spawn (NUR in der Wueste), Wander-Simulation + Multiplayer-Sync.
## Nutzt dasselbe Tier-Skript wie das Reh (deer.gd), nur mit Kamel-Werten
## (andere Frames, groesser, langsamer, meidet Wasser, flieht nicht). Host-
## autoritativ und relay-basiert genau wie deer_spawner.gd.
##
## KEIN class_name (Auto-Updater) - Node in main.tscn.

const AnimalScript := preload("res://scripts/deer.gd")
const CAMEL_FRAMES := preload("res://resources/camel_frames.tres")

@export var world_path: NodePath = ^"../World"
@export var max_camel := 3
@export var try_interval := 4.0
@export var spawn_chance := 0.5
@export var spawn_min := 8
@export var spawn_max := 18
@export var despawn_dist := 30.0
const SEND_HZ := 10.0

var world: IsoWorld
var player: Node2D
var _netgame: Node
var _chunk: Node
var _camel: Dictionary = {}
var _remote: Dictionary = {}
var _next_id := 1
var _accum := 0.0
var _send_accum := 0.0
var _host_id := 0


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	_netgame = get_node_or_null(^"../NetGame")
	_chunk = get_node_or_null(^"../ChunkManager")
	if Net.is_dedicated:
		multiplayer.peer_connected.connect(func(_id): _assign_host())
		multiplayer.peer_disconnected.connect(func(_id): _assign_host())
		return


## Kamel-Werte auf eine deer.gd-Instanz setzen (bevor sie in den Baum kommt).
func _config(c) -> void:
	c.frames = CAMEL_FRAMES
	c.art_scale = 1.0
	c.move_speed = 18.0
	c.flee_speed = 30.0
	c.flee_radius = 0.0            # Kamele fliehen nicht
	c.avoid_water = true
	c.sprite_offset = Vector2(0, -18)


func _assign_host() -> void:
	var peers := multiplayer.get_peers()
	var host := 0
	for p in peers:
		if host == 0 or p < host:
			host = p
	_set_host.rpc(host)


@rpc("any_peer", "reliable", "call_local")
func _set_host(id: int) -> void:
	_host_id = id
	if not _am_host():
		for c in _camel.values():
			if is_instance_valid(c): c.queue_free()
		_camel.clear()


func _am_host() -> bool:
	if not Net.active:
		return true
	return multiplayer.get_unique_id() == _host_id


func _process(delta: float) -> void:
	if world == null or world.props_root == null or Net.is_dedicated:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	if not _am_host():
		return

	var positions := player_positions()

	for id in _camel.keys():
		var c = _camel[id]
		if not is_instance_valid(c):
			_camel.erase(id); _broadcast_removed(id); continue
		if _px_dist_to_nearest(c.global_position, positions) > despawn_dist * IsoWorld.TILE_SIZE.x * 0.5:
			c.queue_free(); _camel.erase(id); _broadcast_removed(id)

	_accum += delta
	if _accum >= try_interval:
		_accum = 0.0
		if _camel.size() < max_camel and randf() <= spawn_chance and not positions.is_empty():
			var around: Vector2 = positions[randi() % positions.size()]
			_try_spawn(world.world_to_cell(around, 0))

	if Net.active:
		_send_accum += delta
		if _send_accum >= 1.0 / SEND_HZ:
			_send_accum = 0.0
			for id in _camel:
				var c = _camel[id]
				if is_instance_valid(c):
					_camel_state.rpc(id, c.global_position, c.anim_name(), c.level)


func _try_spawn(pcell: Vector2i) -> void:
	for _n in 14:
		var ang := randf() * TAU
		var r := randf_range(spawn_min, spawn_max)
		var cell := pcell + Vector2i(roundi(cos(ang) * r), roundi(sin(ang) * r * 2.0))
		if not _free(cell):
			continue
		_spawn_one(cell)
		return


func _spawn_one(cell: Vector2i) -> void:
	var c = AnimalScript.new()
	c.spawner = self
	_config(c)
	world.props_root.add_child(c)
	c.setup(world, cell)
	_camel[_next_id] = c
	_next_id += 1


func player_positions() -> Array:
	if _netgame and _netgame.has_method("all_player_positions"):
		var ps: Array = _netgame.all_player_positions()
		if not ps.is_empty():
			return ps
	return [player.global_position] if player else []


func _px_dist_to_nearest(pos: Vector2, positions: Array) -> float:
	var best := INF
	for p in positions:
		best = minf(best, pos.distance_to(p))
	return best


## deer.gd fragt das fuer sein Verhalten - Kamele fliehen zwar nicht
## (flee_radius 0), aber die Schnittstelle muss da sein.
func nearest_player(pos: Vector2) -> Dictionary:
	var best_pos := Vector2.ZERO
	var best := INF
	for p in player_positions():
		var d := pos.distance_to(p)
		if d < best:
			best = d; best_pos = p
	return {"found": best < INF, "pos": best_pos, "dist": best}


## Frei UND in der Wueste (Kamele spawnen nur dort). Biom aus dem Generator.
func _free(cell: Vector2i) -> bool:
	if world.top_level_at(cell) < 0 or world.has_prop(cell) \
			or world.blocker_at(cell) != null or world.is_water(cell):
		return false
	return _is_desert(cell)


func _is_desert(cell: Vector2i) -> bool:
	if _chunk == null or _chunk.gen == null:
		return false
	return String(_chunk.gen.biome_at(cell)) == "desert"


# --- Netzwerk (Relay ueber den Server) ----------------------------------

func _broadcast_removed(id: int) -> void:
	if Net.active:
		_camel_removed.rpc(id)


@rpc("any_peer", "unreliable")
func _camel_state(id: int, pos: Vector2, anim: StringName, lvl: int) -> void:
	if Net.is_dedicated:
		var from := multiplayer.get_remote_sender_id()
		for pid in multiplayer.get_peers():
			if pid != from:
				_camel_state.rpc_id(pid, id, pos, anim, lvl)
		return
	if _am_host():
		return
	var c = _remote.get(id)
	if c == null or not is_instance_valid(c):
		c = AnimalScript.new()
		c.remote = true
		_config(c)
		world.props_root.add_child(c)
		_remote[id] = c
	c.apply_state(pos, anim, lvl)


@rpc("any_peer", "reliable")
func _camel_removed(id: int) -> void:
	if Net.is_dedicated:
		var from := multiplayer.get_remote_sender_id()
		for pid in multiplayer.get_peers():
			if pid != from:
				_camel_removed.rpc_id(pid, id)
		return
	var c = _remote.get(id)
	if c and is_instance_valid(c):
		c.queue_free()
	_remote.erase(id)
