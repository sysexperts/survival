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
	if _player == null or _pinv == null or _world == null:
		return
	var sel: int = _pinv.hud.selected
	var stack: Dictionary = _pinv.inventory.take(sel)   # leert das Feld
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


# --- Server ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_drop(item_id: String, count: int, cell: Vector2i, lvl: int) -> void:
	if not multiplayer.is_server():
		return
	if not ItemDB.has(item_id) or count <= 0:
		return
	var id := _next_id
	_next_id += 1
	_drops[id] = {"item_id": item_id, "count": count}
	_spawn.rpc(id, item_id, count, cell, lvl)
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
func _spawn(id: int, item_id: String, count: int, cell: Vector2i, lvl: int) -> void:
	if Net.is_dedicated or _world == null or _world.props_root == null:
		return
	if _drops.has(id):
		return
	var node := Node2D.new()
	var spr := Sprite2D.new()
	spr.texture = ItemDB.icon(item_id)
	spr.scale = Vector2(0.55, 0.55)
	spr.position = Vector2(0, -6)    # leicht ueber dem Boden
	node.add_child(spr)
	_world.props_root.add_child(node)
	node.global_position = _world.cell_to_world(cell, lvl)
	_drops[id] = {"node": node, "item_id": item_id, "count": count, "cell": cell, "level": lvl}


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
