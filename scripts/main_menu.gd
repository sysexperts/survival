extends Control

## Startbildschirm: Name eingeben und Hosten / Beitreten / Einzelspieler.
##
## Die Oberflaeche wird hier im Code aufgebaut statt in der Szene - so bleibt
## main_menu.tscn eine einzige Zeile und Layout-Aenderungen laufen ueber
## normalen GDScript-Code.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label


func _ready() -> void:
	# Als dedizierter Server gestartet? Dann kein Menue, sondern sofort hosten.
	# Erkennung ueber das dedizierte Server-Build-Feature ODER die Flag
	# "--server" / "server" (egal ob als Engine- oder Nutzer-Argument).
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server") or args.has("--server") or args.has("server"):
		Net.start_dedicated_server()
		return

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
