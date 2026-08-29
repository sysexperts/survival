extends Node

## Online-Lagertruhen: Inhalt liegt server-autoritativ, wird beim OEffnen
## angefordert und bei jeder Aenderung an alle verteilt + persistiert. So sehen
## alle Spieler denselben Truhen-Inhalt live.
##
## Voll-Zustand-Sync (die Truhe ist klein): ein Client schickt bei Aenderung die
## kompletten 30 Felder; der Server speichert sie und schickt sie an die ANDEREN.
## (Zwei gleichzeitige Editoren derselben Truhe -> Last-Write-Wins.)
##
## KEIN class_name (Auto-Updater) - Node in main.tscn.

const CHEST_DIR := "/opt/survival_world"
const CHEST_FILE := CHEST_DIR + "/chests.json"
const SIZE := 30

## Client: gefeuert, wenn der Server den Inhalt einer Truhe schickt.
signal chest_updated(cell: Vector2i, slots: Array)

var _chests: Dictionary = {}      ## Server: "x,y" -> Array(30) Slot-Dicts


func _ready() -> void:
	add_to_group("chest_sync")
	if Net.is_dedicated:
		_load()


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _empty() -> Array:
	var a: Array = []
	a.resize(SIZE)
	for i in SIZE:
		a[i] = {}
	return a


# --- Client-API --------------------------------------------------------

## Aktuellen Inhalt einer Truhe anfordern (Antwort per chest_updated).
func request(cell: Vector2i) -> void:
	if Net.active and not Net.is_dedicated:
		_srv_request.rpc_id(1, cell)


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
	_recv.rpc_id(sid, cell, _chests.get(_key(cell), _empty()))


@rpc("any_peer", "reliable")
func _srv_set(cell: Vector2i, slots: Array) -> void:
	if not Net.is_dedicated:
		return
	_chests[_key(cell)] = slots
	_save()
	var owner_id := multiplayer.get_remote_sender_id()
	for pid in multiplayer.get_peers():
		if pid != owner_id:
			_recv.rpc_id(pid, cell, slots)


# --- Client-Empfang ----------------------------------------------------

@rpc("authority", "reliable")
func _recv(cell: Vector2i, slots: Array) -> void:
	if Net.is_dedicated:
		return
	chest_updated.emit(cell, slots)


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
