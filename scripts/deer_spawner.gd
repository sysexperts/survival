extends Node

## Rehe: Spawn, Wander-Simulation und Multiplayer-Sync.
##
## Damit ALLE Spieler dieselben Rehe sehen, simuliert genau EIN Client (der
## "Deer-Host") die Rehe und verteilt ihren Zustand ueber das Relay; die anderen
## zeigen sie als Remote-Rehe. Der dedizierte Server bestimmt den Host (Client
## mit kleinster Peer-ID) und leitet die Pakete weiter - er simuliert selbst
## nichts (er hat kein Terrain).
##
## Einzelspieler: dieser Client ist automatisch Host und sendet nichts.

const DeerScript := preload("res://scripts/deer.gd")

@export var world_path: NodePath = ^"../World"
@export var max_deer := 5
@export var try_interval := 3.0
@export var spawn_chance := 0.6
@export var baby_chance := 0.4            ## Chance, neben einem Reh ein Baby zu setzen
@export var spawn_min := 9
@export var spawn_max := 16
@export var despawn_dist := 26.0
const SEND_HZ := 10.0

var world: IsoWorld
var player: Node2D
var _netgame: Node
## Host: eigene, simulierte Rehe. id -> Deer
var _deer: Dictionary = {}
## Nicht-Host: gespiegelte Rehe. id -> Deer(remote)
var _remote: Dictionary = {}
var _next_id := 1
var _accum := 0.0
var _send_accum := 0.0
## Peer-ID des aktuellen Deer-Hosts (vom Server gesetzt). Im Einzelspieler egal.
var _host_id := 0


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	_netgame = get_node_or_null(^"../NetGame")
	if Net.is_dedicated:
		# Server: Host bestimmen und pflegen, sonst nur weiterleiten.
		multiplayer.peer_connected.connect(func(_id): _assign_host())
		multiplayer.peer_disconnected.connect(func(_id): _assign_host())
		return


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
	# Wer nicht (mehr) Host ist, raeumt seine simulierten Rehe weg.
	if not _am_host():
		for d in _deer.values():
			if is_instance_valid(d): d.queue_free()
		_deer.clear()


func _am_host() -> bool:
	if not Net.active:
		return true                       # Einzelspieler
	return multiplayer.get_unique_id() == _host_id


func _process(delta: float) -> void:
	if world == null or world.props_root == null or Net.is_dedicated:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	if not _am_host():
		return                            # Remotes werden per RPC aktualisiert

	var positions := player_positions()

	# Entfernte / kaputte Rehe entfernen (Host): weg, wenn von ALLEN Spielern
	# zu weit entfernt.
	for id in _deer.keys():
		var d = _deer[id]
		if not is_instance_valid(d):
			_deer.erase(id); _broadcast_removed(id); continue
		if _px_dist_to_nearest(d.global_position, positions) > despawn_dist * IsoWorld.TILE_SIZE.x * 0.5:
			d.queue_free(); _deer.erase(id); _broadcast_removed(id)

	# Spawnen - in der Naehe eines ZUFAELLIGEN Spielers, damit bei jedem welche
	# auftauchen, nicht nur beim Host.
	_accum += delta
	if _accum >= try_interval:
		_accum = 0.0
		if _deer.size() < max_deer and randf() <= spawn_chance and not positions.is_empty():
			var around: Vector2 = positions[randi() % positions.size()]
			_try_spawn(world.world_to_cell(around, 0))

	# Zustaende senden (nur im Multiplayer).
	if Net.active:
		_send_accum += delta
		if _send_accum >= 1.0 / SEND_HZ:
			_send_accum = 0.0
			for id in _deer:
				var d = _deer[id]
				if is_instance_valid(d):
					_deer_state.rpc(id, d.global_position, d.anim_name(), d.level, d.is_baby)


func _try_spawn(pcell: Vector2i) -> void:
	for _n in 12:
		var ang := randf() * TAU
		var r := randf_range(spawn_min, spawn_max)
		var cell := pcell + Vector2i(roundi(cos(ang) * r), roundi(sin(ang) * r * 2.0))
		if not _free(cell):
			continue
		_spawn_one(cell, false)
		# Ab und zu ein Baby direkt daneben.
		if randf() <= baby_chance and _deer.size() < max_deer:
			for nb in world.neighbors(cell):
				if _free(nb):
					_spawn_one(nb, true)
					break
		return


func _spawn_one(cell: Vector2i, baby: bool) -> void:
	var deer = DeerScript.new()
	deer.is_baby = baby
	deer.spawner = self               # fuer die Flucht-Abfrage (Spielernaehe)
	world.props_root.add_child(deer)
	deer.setup(world, cell)
	_deer[_next_id] = deer
	_next_id += 1


## Weltpositionen aller Spieler (fuer Spawn-Verteilung und Flucht).
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


## Naechster Spieler zu einer Position: {found:bool, pos:Vector2, dist:float(px)}.
## Vom Reh fuer sein scheues Verhalten gefragt.
func nearest_player(pos: Vector2) -> Dictionary:
	var best_pos := Vector2.ZERO
	var best := INF
	for p in player_positions():
		var d := pos.distance_to(p)
		if d < best:
			best = d; best_pos = p
	return {"found": best < INF, "pos": best_pos, "dist": best}


func _free(cell: Vector2i) -> bool:
	return world.top_level_at(cell) >= 0 and not world.has_prop(cell) \
		and world.blocker_at(cell) == null and not world.is_water(cell)


# --- Netzwerk (Relay ueber den Server) ----------------------------------

func _broadcast_removed(id: int) -> void:
	if Net.active:
		_deer_removed.rpc(id)


@rpc("any_peer", "unreliable")
func _deer_state(id: int, pos: Vector2, anim: StringName, lvl: int, baby: bool) -> void:
	# Server: an alle ausser dem Absender weiterreichen.
	if Net.is_dedicated:
		var from := multiplayer.get_remote_sender_id()
		for pid in multiplayer.get_peers():
			if pid != from:
				_deer_state.rpc_id(pid, id, pos, anim, lvl, baby)
		return
	if _am_host():
		return                            # der Host zeigt seine echten Rehe
	var d = _remote.get(id)
	if d == null or not is_instance_valid(d):
		d = DeerScript.new()
		d.is_baby = baby
		d.remote = true
		world.props_root.add_child(d)
		_remote[id] = d
	d.apply_state(pos, anim, lvl)


@rpc("any_peer", "reliable")
func _deer_removed(id: int) -> void:
	if Net.is_dedicated:
		var from := multiplayer.get_remote_sender_id()
		for pid in multiplayer.get_peers():
			if pid != from:
				_deer_removed.rpc_id(pid, id)
		return
	var d = _remote.get(id)
	if d and is_instance_valid(d):
		d.queue_free()
	_remote.erase(id)


func _cell_dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()
