extends Control

## Startbildschirm: Name eingeben und Hosten / Beitreten / Einzelspieler.
##
## Die Oberflaeche wird hier im Code aufgebaut statt in der Szene - so bleibt
## main_menu.tscn eine einzige Zeile und Layout-Aenderungen laufen ueber
## normalen GDScript-Code.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label

## Video-Hintergrund im Startmenue + Umschalter (oben rechts).
const VIDEO_BG := "res://assets/UI/login.ogv"
const TOGGLE_ICON := "res://assets/UI/landscape.png"
const SETTINGS_CFG := "user://settings.cfg"
var _video: VideoStreamPlayer
var _video_toggle: TextureButton
var _video_on := true


const UiCursor := preload("res://scripts/ui_cursor.gd")


func _ready() -> void:
	# Als dedizierter Server gestartet? Dann kein Menue, sondern sofort hosten.
	# Erkennung ueber das dedizierte Server-Build-Feature ODER die Flag
	# "--server" / "server" (egal ob als Engine- oder Nutzer-Argument).
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server") or args.has("--server") or args.has("server"):
		Net.start_dedicated_server()
		return

	# Maus-Cursor aufs Pack setzen (bleibt für die ganze Sitzung, auch im Spiel).
	UiCursor.apply()

	# Video-Hintergrund (ganz hinten). Kann oben rechts an-/ausgeschaltet werden.
	_video_on = _load_video_pref()
	_setup_video_background()
	_build_video_toggle()

	# Aktuelle Version immer oben sichtbar. Nach einem Auto-Update liegt die
	# neue version.txt aus der game.pck ueber res:// - hier steht also der
	# tatsaechlich laufende Stand.
	var ver := Label.new()
	ver.text = "v%s" % Net.version_name(_read_version())
	ver.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.offset_top = 8
	ver.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	add_child(ver)

	# Volle Flaeche, Inhalt zentriert.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(320, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "SerdarsGame"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Cok Oyuncu  ·  v%s" % Net.version_name(_read_version())
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_spacer(8))

	box.add_child(_field_label("Adin"))
	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "Isim"
	box.add_child(_name_edit)

	box.add_child(_field_label("Sunucu adresi (katilmak icin)"))
	_ip_edit = LineEdit.new()
	_ip_edit.text = Net.DEFAULT_HOST
	_ip_edit.placeholder_text = "örn. 192.168.0.42"
	box.add_child(_ip_edit)

	box.add_child(_spacer(8))

	var join_btn := Button.new()
	join_btn.text = "Katil"
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	var solo_btn := Button.new()
	solo_btn.text = "Tek Oyuncu"
	solo_btn.pressed.connect(_on_solo)
	box.add_child(solo_btn)

	box.add_child(_spacer(6))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	Net.connection_failed.connect(_on_connection_failed)


func _read_version() -> int:
	if FileAccess.file_exists("res://version.txt"):
		var f := FileAccess.open("res://version.txt", FileAccess.READ)
		if f:
			return int(f.get_as_text().strip_edges())
	return 0


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "Oyuncu"
	Net.player_name = n


func _on_host() -> void:
	_apply_name()
	_status.text = "Sunucu baslatiliyor ..."
	var err := Net.host()
	if err != "":
		_status.text = err


func _on_join() -> void:
	_apply_name()
	_status.text = "%s adresine baglaniliyor ..." % _ip_edit.text.strip_edges()
	var err := Net.join(_ip_edit.text)
	if err != "":
		_status.text = err


func _on_solo() -> void:
	_apply_name()
	Net.singleplayer()


func _on_connection_failed() -> void:
	_status.text = "Baglanti basarisiz.\nSunucu calisiyor mu ve adres dogru mu?"


# --- Video-Hintergrund ---------------------------------------------------

## Vollflaechiges Video ganz hinten. Laeuft in Schleife und ignoriert die Maus,
## damit die Menue-Buttons darueber klickbar bleiben.
func _setup_video_background() -> void:
	_video = VideoStreamPlayer.new()
	_video.stream = load(VIDEO_BG)
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true                      # auf die Bildschirmgroesse strecken
	_video.loop = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video)
	move_child(_video, 0)                     # hinter allem anderen
	# Fallback-Schleife, falls die loop-Eigenschaft im Build nicht greift.
	_video.finished.connect(func(): if _video_on and _video: _video.play())
	_apply_video_state()


## Umschalter oben rechts (Icon = landscape.png). Aktiv = Video an.
func _build_video_toggle() -> void:
	_video_toggle = TextureButton.new()
	_video_toggle.texture_normal = load(TOGGLE_ICON)
	_video_toggle.ignore_texture_size = true
	_video_toggle.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_video_toggle.tooltip_text = "Video-Hintergrund an/aus"
	# Oben rechts, ~72x40 (16:9 wie das Bild), 12 px Rand.
	_video_toggle.anchor_left = 1.0
	_video_toggle.anchor_right = 1.0
	_video_toggle.offset_left = -84.0
	_video_toggle.offset_top = 12.0
	_video_toggle.offset_right = -12.0
	_video_toggle.offset_bottom = 52.0
	_video_toggle.pressed.connect(_toggle_video)
	add_child(_video_toggle)
	_apply_toggle_look()


func _toggle_video() -> void:
	_video_on = not _video_on
	_apply_video_state()
	_apply_toggle_look()
	_save_video_pref(_video_on)


func _apply_video_state() -> void:
	if _video == null:
		return
	_video.visible = _video_on
	if _video_on:
		_video.play()
	else:
		_video.stop()


## Aktiv voll sichtbar, inaktiv abgedunkelt - damit man den Zustand sieht.
func _apply_toggle_look() -> void:
	if _video_toggle:
		_video_toggle.modulate = Color(1, 1, 1, 1) if _video_on else Color(1, 1, 1, 0.4)


func _load_video_pref() -> bool:
	var c := ConfigFile.new()
	if c.load(SETTINGS_CFG) == OK:
		return bool(c.get_value("ui", "video_bg", true))
	return true


func _save_video_pref(on: bool) -> void:
	var c := ConfigFile.new()
	c.load(SETTINGS_CFG)                       # vorhandene Werte behalten
	c.set_value("ui", "video_bg", on)
	c.save(SETTINGS_CFG)
