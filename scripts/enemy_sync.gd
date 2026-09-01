extends Node

## Server-autoritatives Gegner-System (Magier). Der DEDIZIERTE SERVER simuliert
## die Gegner (Bewegung, Zielsuche, Schuesse, Leben, Tod, Respawn, Loot) und
## verteilt den Zustand an alle Clients; die Clients zeigen nur an (enemy_view)
## und melden Nahkampf-Treffer zurueck. So sehen alle dieselben Gegner und
## koennen gemeinsam kaempfen (fixt B7 / baut L1).
##
## Das Spiel laeuft immer ueber den Server; ohne Verbindung (Editor-Direktstart)
## tut dieser Node nichts. Gegner leben nahe dem gemalten Spawn-Bereich, weil nur
## dort auch der Server Boden hat (Chunks entstehen sonst nur um Spieler).
##
## KEIN class_name (Auto-Updater) - Node in main.tscn.

const EnemyView := preload("res://scripts/enemy_view.gd")
const OrbScript := preload("res://scripts/mage_orb.gd")

## Gegner-Posten als Zell-Offsets vom globalen Spawn (0,0). Im gemalten Bereich.
const POST_CELLS := [Vector2i(12, 9), Vector2i(-13, 7), Vector2i(6, -15)]

const MAX_HP := 40.0
const SHOOT_RANGE := 260.0
const SHOOT_INTERVAL := 2.2
const CAST_SHOW := 0.45
const WALK_SPEED := 42.0
const RETURN_SPEED := 50.0
const LEASH_MAX := 240.0
const CHASE_STOP := 70.0
const ORB_SPEED := 150.0
const ORB_DAMAGE := 8.0
const RESPAWN_DEATH := 30.0
const BCAST_DT := 1.0 / 12.0       ## Snapshot-Rate

var world = null
var _net: Node = null
var _drop: Node = null
var _enemies: Dictionary = {}      ## Server: id -> Zustand
var _views: Dictionary = {}        ## Client: id -> enemy_view
var _acc := 0.0
var _ready_done := false


func _ready() -> void:
	add_to_group("enemy_sync")
	if not Net.active:
		return                     # kein Server verbunden -> inaktiv
	_boot.call_deferred()


func _boot() -> void:
	world = get_node_or_null(^"../World")
	_drop = get_node_or_null(^"../DropSync")
	if world == null:
		get_tree().create_timer(0.5).timeout.connect(_boot)
		return
	if Net.is_dedicated:
		_server_init()
	_ready_done = true


func _server_init() -> void:
	var i := 0
	for off in POST_CELLS:
		var cell = _find_floor_near(off)
		if cell == null:
			continue
		var lvl: int = maxi(world.top_level_at(cell), 0)
		var pos: Vector2 = world.cell_to_world(cell, lvl)
		_enemies[i] = {
			"pos": pos, "home": pos, "hp": MAX_HP, "dir": 0,
			"cast": 0.0, "cd": 1.0, "alive": true, "respawn": 0.0,
		}
		i += 1


# --- Server-Simulation --------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _ready_done or not Net.is_dedicated:
		return
	for id in _enemies:
		_sim_one(_enemies[id], delta)
	_acc += delta
	if _acc >= BCAST_DT:
		_acc = 0.0
		_recv_snapshot.rpc(_snapshot())


func _sim_one(e: Dictionary, delta: float) -> void:
	if not e["alive"]:
		e["respawn"] = float(e["respawn"]) - delta
		if float(e["respawn"]) <= 0.0:
			e["alive"] = true
			e["hp"] = MAX_HP
			e["pos"] = e["home"]
		return
	if e["cast"] > 0.0:
		e["cast"] = float(e["cast"]) - delta
	e["cd"] = float(e["cd"]) - delta
	var tgt := _nearest_target(e["pos"])
	if tgt.is_empty():
		_return_home(e, delta)
		return
	var tpos: Vector2 = tgt["pos"]
	e["dir"] = _dir_index(tpos - e["pos"])
	# Nur aktiv, wenn ein Spieler nah genug am Posten ist (sonst heimkehren).
	if tpos.distance_to(e["home"]) > LEASH_MAX * 1.1:
		_return_home(e, delta)
		return
	var d: float = e["pos"].distance_to(tpos)
	if d <= SHOOT_RANGE and float(e["cd"]) <= 0.0 and float(e["cast"]) <= 0.0:
		e["cast"] = CAST_SHOW
		e["cd"] = SHOOT_INTERVAL
		_server_shoot(e, tgt)
	if float(e["cast"]) <= 0.0 and d > CHASE_STOP:
		_server_step(e, (tpos - e["pos"]).normalized() * WALK_SPEED * delta)


func _return_home(e: Dictionary, delta: float) -> void:
	if e["pos"].distance_to(e["home"]) > 6.0:
		_server_step(e, (e["home"] - e["pos"]).normalized() * RETURN_SPEED * delta)


## Ein Schritt, aber nicht auf Loecher/Bloecke/Wasser und nicht ueber die Leine.
func _server_step(e: Dictionary, v: Vector2) -> void:
	var np: Vector2 = e["pos"] + v
	if np.distance_to(e["home"]) > LEASH_MAX:
		return
	var cell: Vector2i = world.world_to_cell(np, 0)
	if world.top_level_at(cell) > world.NO_FLOOR and world.blocker_at(cell) == null \
			and not world.is_water(cell):
		e["pos"] = np


func _server_shoot(e: Dictionary, tgt: Dictionary) -> void:
	var from: Vector2 = e["pos"] + Vector2(0, -22)
	var to: Vector2 = tgt["pos"]
	_recv_orb.rpc(from, to)                     # Sicht-Orb bei allen Clients
	var travel: float = from.distance_to(to) / ORB_SPEED
	var owner_id: int = int(tgt["id"])
	# Schaden nach der Flugzeit an den Zielspieler (server-autoritativ).
	get_tree().create_timer(travel).timeout.connect(func():
		_hit_player.rpc_id(owner_id, ORB_DAMAGE))


## Naechster Spieler zu `pos` als {id, pos} - oder {} wenn keiner da ist.
func _nearest_target(pos: Vector2) -> Dictionary:
	if _net == null or not is_instance_valid(_net):
		_net = get_tree().get_first_node_in_group("net_game")
	if _net == null or not _net.has_method("player_positions"):
		return {}
	var best := {}
	var best_d := INF
	for entry in _net.player_positions():
		var p: Vector2 = entry[1]
		var d := pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = {"id": int(entry[0]), "pos": p}
	return best


# --- Nahkampf-Schaden (Client -> Server) --------------------------------

## Vom enemy_view aufgerufen (lokaler Nahkampf-Treffer).
func hit_enemy(id: int, dmg: float) -> void:
	if Net.is_dedicated:
		return
	_srv_hit.rpc_id(1, id, dmg)


@rpc("any_peer", "reliable")
func _srv_hit(id: int, dmg: float) -> void:
	if not Net.is_dedicated:
		return
	var e = _enemies.get(id)
	if e == null or not e["alive"]:
		return
	e["hp"] = float(e["hp"]) - dmg
	if float(e["hp"]) <= 0.0:
		e["alive"] = false
		e["respawn"] = RESPAWN_DEATH
		_drop_loot(e["pos"])


## Loot beim Tod: 1-2 Gold-Erz, selten 1 Rohdiamant (server -> alle Clients).
func _drop_loot(pos: Vector2) -> void:
	if _drop == null or not _drop.has_method("server_spawn_drop"):
		return
	var cell: Vector2i = world.world_to_cell(pos, 0)
	var lvl: int = maxi(world.top_level_at(cell), 0)
	_drop.server_spawn_drop("altin_cevheri", randi_range(1, 2), cell, lvl)
	if randf() < 0.15:
		_drop.server_spawn_drop("ham_elmas", 1, cell, lvl, Vector2(6, -4))


# --- Broadcast + Client-Anzeige -----------------------------------------

func _snapshot() -> Array:
	var a: Array = []
	for id in _enemies:
		var e: Dictionary = _enemies[id]
		a.append([id, e["pos"].x, e["pos"].y, e["dir"], e["cast"] > 0.0, e["hp"], e["alive"]])
	return a


@rpc("authority", "unreliable")
func _recv_snapshot(a: Array) -> void:
	if Net.is_dedicated:
		return
	var seen := {}
	for row in a:
		var id := int(row[0])
		seen[id] = true
		if not bool(row[6]):                 # tot
			if _views.has(id):
				_kill_view(id)
			continue
		var v = _views.get(id)
		if v == null or not is_instance_valid(v):
			v = _make_view(id)
			_views[id] = v
		v.set_state(Vector2(row[1], row[2]), int(row[3]), bool(row[4]), float(row[5]))
	for id in _views.keys():
		if not seen.has(id):
			_kill_view(id)


func _make_view(id: int):
	var v = EnemyView.new()
	v.enemy_id = id
	v.sync = self
	if world != null and world.props_root != null:
		world.props_root.add_child(v)
	else:
		add_child(v)
	return v


func _kill_view(id: int) -> void:
	var v = _views.get(id)
	if v != null and is_instance_valid(v) and v.has_method("die_out"):
		v.die_out()
	_views.erase(id)


@rpc("authority", "reliable")
func _recv_orb(from: Vector2, to: Vector2) -> void:
	if Net.is_dedicated:
		return
	var orb = OrbScript.new()
	if world != null and world.props_root != null:
		world.props_root.add_child(orb)
	else:
		add_child(orb)
	orb.setup_visual(from, to)


@rpc("authority", "reliable")
func _hit_player(dmg: float) -> void:
	if Net.is_dedicated:
		return
	var p = get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("take_damage"):
		p.take_damage(dmg)


# --- Hilfen -------------------------------------------------------------

## 8 Sektoren, 0 = Sued, im Uhrzeigersinn (Iso 2:1, wie mage.gd).
func _dir_index(v: Vector2) -> int:
	var a := atan2(v.x, v.y * 2.0)
	return (int(round(a / (PI / 4.0))) % 8 + 8) % 8


## Naechste begehbare, freie, nicht-wassrige Zelle um `center` (Ringe) - oder null.
func _find_floor_near(center: Vector2i):
	for r in range(0, 12):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := Vector2i(center.x + dx, center.y + dy)
				if world.top_level_at(c) > world.NO_FLOOR and world.blocker_at(c) == null \
						and not world.is_water(c) and not world.has_prop(c):
					return c
	return null
