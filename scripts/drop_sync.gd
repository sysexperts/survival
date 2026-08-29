extends Node

## Fallengelassene Items auf dem Boden - fuer alle sichtbar, server-autoritativ.
##
## Q laesst den ausgewaehlten Hotbar-Stapel fallen. Der Client bittet den
## Server, das Item zu setzen; der Server vergibt eine Id, verteilt das Item an
## ALLE (Anzeige) und merkt es sich fuer Aufheben + Despawn. Aufheben laeuft
## ebenfalls ueber den Server, damit nicht zwei Spieler dasselbe Item greifen.
## Nach 5 Minuten verschwindet ein Item.

const DESPAWN_SECONDS := 300.0
## Aufhebe-Reichweite in Zellen (wie bei Steinen gemessen).
const PICKUP_RADIUS := 1.4
## Reichweite fuers automatische Aufheben beim Drueberlaufen (enger).
const AUTO_PICKUP_RADIUS := 0.9
## So lange nach dem Fallenlassen kann man ein Item NICHT automatisch aufheben -
## sonst saugt man sein gerade abgelegtes Item sofort wieder ein.
const PICKUP_PROTECT_MS := 800
## Per preload statt ueber den class_name - so bleibt der ausgelieferte Client
## (dessen Basis-EXE die Klasse noch nicht kannte) kompilierbar.
const DroppedItemScript := preload("res://scripts/dropped_item.gd")

var _world: IsoWorld
var _player: Player
var _pinv: Node
## Auf dem Server: id -> {item_id, count}. Auf Clients: id -> {node, item_id, count, cell, level}.
var _drops: Dictionary = {}
var _next_id := 1                    ## nur Server


func _ready() -> void:
	if not Net.active:
		return
	_world = get_node_or_null(^"../World") as IsoWorld
	_pinv = get_node_or_null(^"../Inventory")
	if not Net.is_dedicated:
		_player = get_tree().get_first_node_in_group("player") as Player


# --- Client: fallen lassen -----------------------------------------------

func drop_selected() -> void:
	if _pinv:
		drop_index(_pinv.hud.selected)


## Laesst den Stapel aus einem bestimmten Inventar-Feld fallen (Q oder Maus).
func drop_index(slot_index: int) -> void:
	if _player == null or _pinv == null or _world == null:
		return
	var stack: Dictionary = _pinv.inventory.take(slot_index)   # leert das Feld
	if stack.is_empty():
		return
	var cell := _world.world_to_cell(_player.global_position, _player.level)
	var lvl := maxi(_world.top_level_at(cell), 0)
	_request_drop.rpc_id(1, String(stack["id"]), int(stack["count"]), cell, lvl)


## Naechstes Item in Reichweite (Id) oder -1.
func dropped_in_reach() -> int:
	if _player == null or _world == null:
		return -1
	var best := -1
	var best_d := PICKUP_RADIUS
	for id in _drops:
		var d: Dictionary = _drops[id]
		var to := _world.cell_to_world(d["cell"], d["level"]) - _player.global_position
		var dist := Vector2(to.x / IsoWorld.TILE_SIZE.x, to.y / IsoWorld.TILE_SIZE.y).length()
		if dist <= best_d:
			best_d = dist
			best = id
	return best


func info(id: int) -> Dictionary:
	return _drops.get(id, {})


func pickup(id: int) -> void:
	_request_pickup.rpc_id(1, id)


## Laeuft der lokale Spieler ueber ein Item, wird es automatisch eingesammelt -
## mit kleiner Flug-Animation zum Charakter.
func _process(_delta: float) -> void:
	if Net.is_dedicated or not Net.active or _player == null or _world == null:
		return
	var now := Time.get_ticks_msec()
	for id in _drops.keys():
		var d: Dictionary = _drops[id]
		if now - int(d.get("t", 0)) < PICKUP_PROTECT_MS:
			continue
		var to := _world.cell_to_world(d["cell"], d["level"]) - _player.global_position
		var dist := Vector2(to.x / IsoWorld.TILE_SIZE.x, to.y / IsoWorld.TILE_SIZE.y).length()
		if dist <= AUTO_PICKUP_RADIUS:
			_auto_collect(id)
			return                   # pro Bild nur eins


func _auto_collect(id: int) -> void:
	var d: Dictionary = _drops.get(id, {})
	if d.is_empty():
		return
	_drops.erase(id)                 # nicht mehr erkennen; Server-_remove wird no-op
	pickup(id)                       # Server um die Beute bitten
	var node = d.get("node")
	if is_instance_valid(node) and node.has_method("fly_to"):
		node.fly_to(_player)


# --- Server ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_drop(item_id: String, count: int, cell: Vector2i, lvl: int, offset: Vector2 = Vector2.ZERO) -> void:
	if not multiplayer.is_server():
		return
	_do_spawn(item_id, count, cell, lvl, offset)


## Direkt vom Server erzeugter Boden-Drop (z. B. Holz beim Baumfaellen, siehe
## world_sync.gd). Wie _request_drop, aber ohne den RPC-Umweg - der Aufrufer
## laeuft schon auf dem Server. `offset` streut das Bild etwas vom Zellmittel-
## punkt weg (in Bildschirmpixeln), damit mehrere Drops nicht exakt stapeln.
func server_spawn_drop(item_id: String, count: int, cell: Vector2i, lvl: int, offset := Vector2.ZERO) -> void:
	if not multiplayer.is_server():
		return
	_do_spawn(item_id, count, cell, lvl, offset)


func _do_spawn(item_id: String, count: int, cell: Vector2i, lvl: int, offset := Vector2.ZERO) -> void:
	if not ItemDB.has(item_id) or count <= 0:
		return
	var id := _next_id
	_next_id += 1
	_drops[id] = {"item_id": item_id, "count": count}
	_spawn.rpc(id, item_id, count, cell, lvl, offset)
	var t := get_tree().create_timer(DESPAWN_SECONDS)
	t.timeout.connect(_despawn.bind(id))


func _despawn(id: int) -> void:
	if not multiplayer.is_server():
		return
	if _drops.has(id):
		_drops.erase(id)
		_remove.rpc(id)


@rpc("any_peer", "reliable")
func _request_pickup(id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _drops.has(id):
		return                       # schon weg (jemand anderes war schneller)
	var d: Dictionary = _drops[id]
	_drops.erase(id)
	_remove.rpc(id)                  # bei allen ausblenden
	var sender := multiplayer.get_remote_sender_id()
	_grant.rpc_id(sender, String(d["item_id"]), int(d["count"]))


# --- Client: Anzeige ------------------------------------------------------

@rpc("any_peer", "reliable")
func _spawn(id: int, item_id: String, count: int, cell: Vector2i, lvl: int, offset: Vector2) -> void:
	if Net.is_dedicated or _world == null or _world.props_root == null:
		return
	if _drops.has(id):
		return
	var node := DroppedItemScript.new()
	node.setup(item_id, count)
	_world.props_root.add_child(node)
	# `offset` streut das Bild leicht vom Zellmittelpunkt weg (z. B. Holz um den
	# Baum herum). Die Zelle bleibt fuer die Aufheb-Reichweite massgeblich.
	node.global_position = _world.cell_to_world(cell, lvl) + offset
	_drops[id] = {"node": node, "item_id": item_id, "count": count, "cell": cell,
		"level": lvl, "t": Time.get_ticks_msec()}


@rpc("any_peer", "reliable")
func _remove(id: int) -> void:
	if Net.is_dedicated:
		return
	if _drops.has(id):
		var n = _drops[id].get("node")
		if is_instance_valid(n):
			n.queue_free()
		_drops.erase(id)


@rpc("any_peer", "reliable")
func _grant(item_id: String, count: int) -> void:
	if _pinv == null:
		return
	var left: int = _pinv.inventory.add(item_id, count)
	# Passt nicht alles rein? Der Rest faellt wieder vor die Fuesse.
	if left > 0 and _player and _world:
		var cell := _world.world_to_cell(_player.global_position, _player.level)
		var lvl := maxi(_world.top_level_at(cell), 0)
		_request_drop.rpc_id(1, item_id, left, cell, lvl)
