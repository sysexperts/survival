extends Node

## Speichert den Spielstand (Inventar) pro NAME auf dem Server - ohne Account.
##
## Beim Beitreten fragt der Client seinen Stand an (ueber den Namen), der Server
## liest /opt/survival_saves/<name>.json und schickt ihn zurueck. Bei jeder
## Inventar-Aenderung (leicht verzoegert) schickt der Client seinen Stand, der
## Server schreibt die Datei. So ueberlebt der Fortschritt einen Server-
## Neustart: gleicher Name -> gleicher Stand.
##
## Bewusst simpel: der Server versteht die Daten nicht, er lagert sie nur unter
## dem Namen. Gleicher Name = gleicher Speicher (so gewuenscht).

const SAVE_DIR := "/opt/survival_saves"
## So lange nach der letzten Aenderung wird gewartet, bevor gespeichert wird -
## fasst schnelle Aenderungen (Handwerk, Sammeln) zu einem Schreibvorgang.
const SAVE_DELAY := 2.0

var _pinv: Node                      ## player_inventory
var _debounce: Timer
var _loaded := false                 ## erst nach dem ersten Laden speichern


func _ready() -> void:
	if not Net.active:
		return
	_pinv = get_node_or_null(^"../Inventory")

	if Net.is_dedicated:
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		return

	_debounce = Timer.new()
	_debounce.wait_time = SAVE_DELAY
	_debounce.one_shot = true
	_debounce.timeout.connect(_flush_save)
	add_child(_debounce)

	if _pinv and _pinv.inventory:
		_pinv.inventory.changed.connect(_on_changed)

	# Regelmaessig speichern - so bleibt die POSITION erhalten (Bewegung loest
	# kein inventory.changed aus). Beim naechsten Login startet man am Logout-Ort.
	var auto := Timer.new()
	auto.wait_time = 15.0
	auto.timeout.connect(func():
		if _loaded:
			_flush_save())
	add_child(auto)
	auto.start()

	# Ein Frame warten, damit Inventar + Startsachen stehen, dann laden.
	await get_tree().process_frame
	_request_load.rpc_id(1, Net.player_name)


func _on_changed() -> void:
	if _loaded and _debounce:
		_debounce.start()


func _flush_save() -> void:
	if _pinv == null:
		return
	_save.rpc_id(1, Net.player_name, JSON.stringify(_pinv.to_save()))


# --- Server ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_load(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var path := _path(pname)
	var json := ""
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			json = f.get_as_text()
			f.close()
	_send_load.rpc_id(id, json)


@rpc("any_peer", "reliable")
func _save(pname: String, json: String) -> void:
	if not multiplayer.is_server():
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(_path(pname), FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()


# --- Client ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _send_load(json: String) -> void:
	# Ab jetzt darf gespeichert werden.
	_loaded = true
	if json.strip_edges() == "":
		return                       # neuer Name -> Startsachen behalten
	var data: Variant = JSON.parse_string(json)
	if typeof(data) == TYPE_DICTIONARY and _pinv:
		_pinv.from_save(data)


# --- Hilfen ---------------------------------------------------------------

func _path(pname: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, _safe(pname)]


## Aus dem Namen einen sicheren Dateinamen machen (kleingeschrieben, nur
## a-z0-9_-), damit niemand ueber den Namen aus dem Save-Ordner ausbricht.
func _safe(pname: String) -> String:
	var out := ""
	for c in pname.to_lower():
		if "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(c):
			out += c
	return out if out != "" else "oyuncu"
