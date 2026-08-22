extends Node

## Synchronisiert Welt-Veraenderungen durch Abbau zwischen den Spielern.
##
## Die Welt ist auf allen Rechnern ueber denselben Seed identisch. Es genuegt
## also, die EREIGNISSE zu verteilen ("Baum bei X gefaellt") - jeder Client
## wendet dieselbe Aenderung an und bleibt so im Gleichschritt.
##
## Wichtig: Der ausloesende Spieler hat die Aenderung lokal bereits gemacht und
## sein Inventar gefuellt. Bei den ANDEREN wird nur die Welt angepasst (Baum
## weg, Stumpf hin, Nachwuchs geplant) - KEIN Inventar. So bekommt die Beute
## nur, wer wirklich abbaut.
##
## Der dedizierte Server spielt nicht mit: er leitet die Ereignisse nur weiter.

var _world: IsoWorld
var _regrowth: Node
var _player: Player


func _ready() -> void:
	if not Net.active:
		return
	_world = get_node_or_null(^"../World") as IsoWorld
	_regrowth = get_node_or_null(^"../Regrowth")
	if Net.is_dedicated:
		return                       # Server: nur weiterleiten (siehe RPC)
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_player.felled.connect(_on_local_felled)
		_player.stump_cleared.connect(_on_local_stump_cleared)
		_player.stone_collected.connect(_on_local_stone_collected)


# --- lokale Aktionen -> an alle senden -----------------------------------

func _on_local_felled(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	_event.rpc(multiplayer.get_unique_id(), "fell", cell, level, atlas, "")


func _on_local_stump_cleared(cell: Vector2i) -> void:
	_event.rpc(multiplayer.get_unique_id(), "stump", cell, 0, Vector2i.ZERO, "")


func _on_local_stone_collected(cell: Vector2i, level: int, gather_id: String) -> void:
	_event.rpc(multiplayer.get_unique_id(), "stone", cell, level, Vector2i.ZERO, gather_id)


# --- Empfang -------------------------------------------------------------

@rpc("any_peer", "reliable")
func _event(owner_id: int, kind: String, cell: Vector2i, level: int, atlas: Vector2i, gather_id: String) -> void:
	# Server: an alle anderen Clients weiterreichen.
	if Net.is_dedicated:
		for pid in multiplayer.get_peers():
			if pid != owner_id:
				_event.rpc_id(pid, owner_id, kind, cell, level, atlas, gather_id)
		return

	if owner_id == multiplayer.get_unique_id():
		return                       # eigene Aktion, schon lokal erledigt
	if _world == null:
		return
	match kind:
		"fell":
			_remove_tree(cell, level)
			if _regrowth:
				_regrowth.replicate_felled(cell, level, atlas)
		"stump":
			_world.remove_prop(cell, level)
			if _regrowth:
				_regrowth.replicate_stump_cleared(cell)
		"stone":
			_world.remove_prop(cell, level)
			if _regrowth:
				_regrowth.replicate_stone_collected(cell, level, gather_id)


## Entfernt einen Baum wie beim lokalen Faellen - mit Umkipp-Animation, wenn
## der Node noch da ist, sonst hart entfernen.
func _remove_tree(cell: Vector2i, level: int) -> void:
	var node: TreeActor = _world.prop_node(cell)
	if node:
		_world.detach_prop(cell)
		node.fell(Vector2(0, 1))
	else:
		_world.remove_prop(cell, level)
