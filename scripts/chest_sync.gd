extends Node

## Online-Lagertruhen: Inhalt liegt server-autoritativ, wird beim OEffnen
## angefordert und bei jeder Aenderung an alle verteilt + persistiert. So sehen
## alle Spieler denselben Truhen-Inhalt live.
##
## Voll-Zustand-Sync (die Truhe ist klein): ein Client schickt bei Aenderung die
## kompletten 30 Felder; der Server speichert sie und schickt sie an die ANDEREN.
##
## EXKLUSIVER LOCK (fixt Item-Dupe, Bug B2): eine Truhe kann immer nur EIN Spieler
## offen haben. Beim Oeffnen fordert der Client den Lock an; hat ihn schon ein
## anderer, kommt eine Absage (chest_denied) und das Fenster geht nicht auf.
## Nur der Lock-Halter darf pushen; beim Schliessen/Disconnect wird freigegeben.
## So kann kein zweiter Spieler auf einem veralteten Stand arbeiten -> kein Dupe.
##
## KEIN class_name (Auto-Updater) - Node in main.tscn.

const CHEST_DIR := "/opt/survival_world"
const CHEST_FILE := CHEST_DIR + "/chests.json"
const SIZE := 30

## Client: gefeuert, wenn der Server den Inhalt einer Truhe schickt (Freigabe).
signal chest_updated(cell: Vector2i, slots: Array)
## Client: die Truhe ist gerade von jemand anderem offen (Lock verweigert).
signal chest_denied(cell: Vector2i)

var _chests: Dictionary = {}      ## Server: "x,y" -> Array(30) Slot-Dicts
var _locks: Dictionary = {}       ## Server: "x,y" -> peer_id des aktuellen Halters


func _ready() -> void:
	add_to_group("chest_sync")
	if Net.is_dedicated:
		_load()
		# Verbindungsabbruch: alle Locks dieses Spielers freigeben.
		multiplayer.peer_disconnected.connect(_free_locks_of)


## Ist dies ein echter Multiplayer-Client (nicht Einzelspieler, nicht Server)?
func is_mp() -> bool:
	return Net.active and not Net.is_dedicated


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _empty() -> Array:
	var a: Array = []
	a.resize(SIZE)
	for i in SIZE:
		a[i] = {}
	return a


# --- Client-API --------------------------------------------------------

## Truhe oeffnen: Lock + aktuellen Inhalt anfordern. Freigabe -> chest_updated,
## belegt -> chest_denied.
func request(cell: Vector2i) -> void:
	if is_mp():
		_srv_request.rpc_id(1, cell)


## Truhe schliessen: Lock wieder freigeben.
func release(cell: Vector2i) -> void:
	if is_mp():
		_srv_release.rpc_id(1, cell)


## Geaenderten Inhalt an den Server schicken (er verteilt + speichert).
func push(cell: Vector2i, slots: Array) -> void:
	if Net.is_dedicated:
		return
	if Net.active:
		_srv_set.rpc_id(1, cell, slots)


# --- Server ------------------------------------------------------------

@rpc("any_peer", "reliable")
func _srv_request(cell: Vector2i) -> void:
	if not Net.is_dedicated:
		return
	var sid := multiplayer.get_remote_sender_id()
	var k := _key(cell)
	var holder: int = int(_locks.get(k, 0))
	# Schon von einem ANDEREN (noch verbundenen) Spieler offen? -> Absage.
	if holder != 0 and holder != sid and multiplayer.get_peers().has(holder):
		_denied.rpc_id(sid, cell)
		return
	_locks[k] = sid
	_recv.rpc_id(sid, cell, _chests.get(k, _empty()))


@rpc("any_peer", "reliable")
func _srv_release(cell: Vector2i) -> void:
	if not Net.is_dedicated:
		return
	var sid := multiplayer.get_remote_sender_id()
	var k := _key(cell)
	if int(_locks.get(k, 0)) == sid:
		_locks.erase(k)


@rpc("any_peer", "reliable")
func _srv_set(cell: Vector2i, slots: Array) -> void:
	if not Net.is_dedicated:
		return
	var owner_id := multiplayer.get_remote_sender_id()
	# Nur der aktuelle Lock-Halter darf schreiben - verhindert veraltete Pushes.
	if int(_locks.get(_key(cell), 0)) != owner_id:
		return
	_chests[_key(cell)] = slots
	_save()
	for pid in multiplayer.get_peers():
		if pid != owner_id:
			_recv.rpc_id(pid, cell, slots)


## Alle Locks eines (getrennten) Spielers freigeben.
func _free_locks_of(peer_id: int) -> void:
	for k in _locks.keys():
		if int(_locks[k]) == peer_id:
			_locks.erase(k)


# --- Client-Empfang ----------------------------------------------------

@rpc("authority", "reliable")
func _recv(cell: Vector2i, slots: Array) -> void:
	if Net.is_dedicated:
		return
	chest_updated.emit(cell, slots)


@rpc("authority", "reliable")
func _denied(cell: Vector2i) -> void:
	if Net.is_dedicated:
		return
	chest_denied.emit(cell)


# --- Persistenz (Server) -----------------------------------------------

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(CHEST_DIR)
	var f := FileAccess.open(CHEST_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_chests))
		f.close()


func _load() -> void:
	if not FileAccess.file_exists(CHEST_FILE):
		return
	var f := FileAccess.open(CHEST_FILE, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		_chests = data
		print("ChestSync: %d Truhen geladen." % _chests.size())
