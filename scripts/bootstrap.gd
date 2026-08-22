extends Control

## Start- und Update-Bildschirm. Ist die neue Hauptszene des Spiels.
##
## Ablauf beim Start:
##   1. Aktive Version bestimmen (aus res://version.txt bzw. einer frueher
##      heruntergeladenen .pck).
##   2. Server nach der neuesten Version fragen (version.json).
##   3. Ist der Server neuer -> game.pck herunterladen, per
##      load_resource_pack(..., replace=true) ueber die eingebauten Dateien
##      legen und lokal zwischenspeichern.
##   4. Ins Hauptmenue wechseln - ab da laeuft der jeweils neueste Stand.
##
## So muss nie wieder eine neue .exe verteilt werden: Updates sind nur die
## kleine game.pck auf dem Server. Nur wenn sich die Godot-Engine selbst
## aendert, braucht es einen neuen Installer.
##
## Der dedizierte Server ueberspringt den ganzen Update-Vorgang.

const VERSION_FILE := "res://version.txt"
const UPDATE_DIR := "user://update"
const UPDATE_PCK := "user://update/game.pck"
const UPDATE_VER := "user://update/version.txt"
const BASE_URL := "http://survival.vapur-it.de/"
const VERSION_URL := BASE_URL + "version.json"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var _label: Label
var _http: HTTPRequest
var _active_version := 0
var _server_version := 0
var _pck_url := ""


func _ready() -> void:
	# Dedizierter Server: kein Update-Check, direkt weiter.
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server") or args.has("--server") or args.has("server"):
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return

	_build_ui()
	_active_version = _read_version_from(VERSION_FILE)
	_load_cached_update()

	_http = HTTPRequest.new()
	add_child(_http)
	_check_server()


func _read_version_from(path: String) -> int:
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			return int(f.get_as_text().strip_edges())
	return 0


## Eine frueher heruntergeladene .pck sofort aktivieren, damit man auch offline
## auf dem zuletzt geladenen Stand spielt.
func _load_cached_update() -> void:
	if FileAccess.file_exists(UPDATE_PCK) and FileAccess.file_exists(UPDATE_VER):
		var v := _read_version_from(UPDATE_VER)
		if v > _active_version and ProjectSettings.load_resource_pack(UPDATE_PCK, true):
			_active_version = v


func _check_server() -> void:
	_set_status("Suche nach Updates ...")
	_http.request_completed.connect(_on_version_response, CONNECT_ONE_SHOT)
	if _http.request(VERSION_URL) != OK:
		_start_game()               # kein Netz -> einfach starten


func _on_version_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_start_game()
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_start_game()
		return
	_server_version = int(data.get("version", 0))
	_pck_url = str(data.get("pck", ""))
	if _server_version > _active_version and _pck_url != "":
		_download_update()
	else:
		_set_status("Aktuell (v%d)" % _active_version)
		_start_game()


func _download_update() -> void:
	_set_status("Lade Update v%d ..." % _server_version)
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	var tmp := UPDATE_PCK + ".tmp"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	_http.download_file = tmp
	_http.request_completed.connect(_on_pck_downloaded, CONNECT_ONE_SHOT)
	var url: String = _pck_url if _pck_url.begins_with("http") else BASE_URL + _pck_url
	if _http.request(url) != OK:
		_http.download_file = ""
		_start_game()


func _on_pck_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_http.download_file = ""
	var tmp := UPDATE_PCK + ".tmp"
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.file_exists(tmp):
		if FileAccess.file_exists(UPDATE_PCK):
			DirAccess.remove_absolute(UPDATE_PCK)
		DirAccess.rename_absolute(tmp, UPDATE_PCK)
		var vf := FileAccess.open(UPDATE_VER, FileAccess.WRITE)
		if vf:
			vf.store_string(str(_server_version))
			vf.close()
		if ProjectSettings.load_resource_pack(UPDATE_PCK, true):
			_active_version = _server_version
			_set_status("Update installiert (v%d)" % _active_version)
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


# --- kleine UI -----------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.text = "SerdarsGame"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_label = Label.new()
	_label.text = "Starte ..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)


func _set_status(t: String) -> void:
	print("[Updater] ", t)
	if _label:
		_label.text = t
