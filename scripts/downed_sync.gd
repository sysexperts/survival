extends Node

## Verteilt den Bewusstlos-Zustand der Spieler im Multiplayer und wickelt das
## Aufhelfen ab. Topologie wie net_game: Clients reden ueber den Server (relay).
##
##  - Wird der eigene Spieler bewusstlos/wach, meldet dieser Node es dem Server;
##    der verteilt es an alle anderen (downed_owners je Client).
##  - Aufhelfen: der Helfer bittet den Server, der schickt dem Ziel-Client den
##    Aufsteh-Befehl (revive_in_place).
##
## KEIN class_name (Auto-Updater) - Node in main.tscn.

var _local: Node = null
var downed_owners: Dictionary = {}     ## owner_id (peer) -> true, solange bewusstlos


func _ready() -> void:
	add_to_group("downed_sync")
	_hook.call_deferred()


func _hook() -> void:
	_local = get_tree().get_first_node_in_group("player")
	if _local == null:
		get_tree().create_timer(1.0).timeout.connect(_hook)
		return
	if _local.has_signal("downed_changed") and not _local.downed_changed.is_connected(_on_local_downed):
		_local.downed_changed.connect(_on_local_downed)


func is_downed_owner(owner_id: int) -> bool:
	return bool(downed_owners.get(owner_id, false))


# --- Ausgehend: eigener Zustand ----------------------------------------

func _on_local_downed(is_down: bool) -> void:
	if not Net.active or Net.is_dedicated:
		return
	_srv_downed.rpc_id(1, multiplayer.get_unique_id(), is_down)


## Helfer bittet den Server, das Ziel aufzuwecken (nach 10 Sek Aufhelfen).
func request_revive(target_owner: int) -> void:
	if not Net.active or Net.is_dedicated:
		return
	_srv_revive.rpc_id(1, target_owner)


# --- Server (relay) ----------------------------------------------------

@rpc("any_peer", "reliable")
func _srv_downed(owner_id: int, is_down: bool) -> void:
	if not Net.is_dedicated:
		return
	for pid in multiplayer.get_peers():
		if pid != owner_id:
			_set_downed.rpc_id(pid, owner_id, is_down)


@rpc("any_peer", "reliable")
func _srv_revive(target_owner: int) -> void:
	if not Net.is_dedicated:
		return
	# Nur an einen tatsaechlich verbundenen Ziel-Client weiterreichen.
	if multiplayer.get_peers().has(target_owner):
		_do_revive.rpc_id(target_owner)


# --- Client-Empfang ----------------------------------------------------

@rpc("authority", "reliable")
func _set_downed(owner_id: int, is_down: bool) -> void:
	if Net.is_dedicated:
		return
	if is_down:
		downed_owners[owner_id] = true
	else:
		downed_owners.erase(owner_id)


@rpc("authority", "reliable")
func _do_revive() -> void:
	if Net.is_dedicated:
		return
	if _local != null and _local.has_method("revive_in_place"):
		_local.revive_in_place()
