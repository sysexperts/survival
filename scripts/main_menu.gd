extends Control

## Hauptmenue im "Pine & Patch"-Stil (Cute-Fantasy-UI-Pack).
##
## Links liegt ein zerrissenes Pergament-Panel mit Logo, Titel, gruenem
## Untertitel-Band und den Menue-Knoepfen OYNA / AYARLAR / CIKIS. Der
## Hintergrund ist unser Landschaftsbild. Alles wird hier im Code aufgebaut
## (kein class_name -> Auto-Updater-freundlich, siehe AGENTS.md).
##
## Die Grafiken kommen aus einer einzigen Atlas-Datei (login_screen.png). Die
## Rechtecke stammen aus tools/atlas_scan.gd (Alpha-Segmentierung).

const BG_IMAGE := "res://assets/UI/landscape2.jpg"
const ATLAS := "res://assets/UI/Cute_Fantasy_UI/UI/login_screen.png"
const FONT := "res://assets/UI/Cute_Fantasy_UI/Fonts/CuteFantasy-5x9.ttf"
const SETTINGS_PATH := "user://settings.cfg"

const UiCursor := preload("res://scripts/ui_cursor.gd")

# --- Atlas-Rechtecke (Originalpixel, aus atlas_scan.gd) -------------------
const R_PANEL := Rect2(53, 29, 582, 715)           # grosses zerrissenes Pergament
const R_NOTE := Rect2(651, 247, 439, 467)          # zweites Pergament (Ayarlar)
const R_PLAY := Rect2(1127, 203, 207, 112)         # orange Knopf + Lagerfeuer
const R_PLAY_HI := Rect2(1348, 203, 203, 111)      # orange, ohne Icon (Hover-Ton)
const R_OPTIONS := Rect2(1127, 346, 207, 112)      # tan Knopf + Rucksack
const R_QUIT := Rect2(1126, 640, 209, 114)         # tan Knopf + Wegweiser
const R_TAN := Rect2(1351, 346, 204, 112)          # tan Knopf, schlicht
const R_BANNER := Rect2(1129, 66, 207, 110)        # gruenes Band (Untertitel)
const R_TREE := Rect2(63, 903, 120, 124)
const R_TENT := Rect2(211, 902, 119, 125)
const R_FIRE := Rect2(366, 902, 117, 124)
const R_ARROW := Rect2(1904, 1473, 44, 60)         # gruener Pfeil (Auswahl)
const R_ICON_SPEAKER := Rect2(1442, 853, 104, 105)
const R_ICON_MONITOR := Rect2(1723, 853, 104, 105)
const R_ICON_GEAR := Rect2(1302, 853, 103, 105)
const R_TOGGLE_ON := Rect2(1377, 1177, 145, 66)
const R_TOGGLE_OFF := Rect2(1780, 1178, 144, 67)
const R_BAR_EMPTY := Rect2(145, 1607, 397, 47)     # heller Balken (Slider-Spur)
const R_KNOB := Rect2(1600, 1698, 44, 45)

var _atlas_img: Image

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _pages: Control          # Container fuer Menue / Play-Formular
var _menu_page: Control
var _play_page: Control
var _options: Control        # Ayarlar-Overlay
var _vol_slider: HSlider
var _fs_toggle: Button


func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server") or args.has("--server") or args.has("server"):
		Net.start_dedicated_server()
		return

	UiCursor.apply()
	_atlas_img = (load(ATLAS) as Texture2D).get_image()
	_load_settings()

	_setup_background()
	_build_panel()
	_build_options()

	Net.connection_failed.connect(_on_connection_failed)


# --- Atlas-Helfer --------------------------------------------------------

func _tex(region: Rect2) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load(ATLAS)
	at.region = region
	at.filter_clip = true
	return at

## Zerschnittener (9-slice) StyleBox aus einer Atlas-Region.
func _sb(region: Rect2, ml: float, mr: float, mt: float, mb: float,
		modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _tex(region)
	sb.texture_margin_left = ml
	sb.texture_margin_right = mr
	sb.texture_margin_top = mt
	sb.texture_margin_bottom = mb
	sb.modulate_color = modulate
	return sb

func _icon(region: Rect2, height: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _tex(region)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.custom_minimum_size = Vector2(region.size.x / region.size.y * height, height)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _heading(text: String, size: int, color := Color(0.24, 0.18, 0.12)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(FONT))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# --- Hintergrund ---------------------------------------------------------

func _setup_background() -> void:
	var bg := TextureRect.new()
	bg.texture = load(BG_IMAGE)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Leichter dunkler Verlauf links, damit das Panel gut sitzt.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.18)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


# --- Linkes Pergament-Panel ---------------------------------------------

func _build_panel() -> void:
	# NinePatch-Pergament, links vertikal zentriert.
	var panel := NinePatchRect.new()
	panel.texture = _tex(R_PANEL)
	panel.patch_margin_left = 70
	panel.patch_margin_right = 70
	panel.patch_margin_top = 70
	panel.patch_margin_bottom = 70
	panel.custom_minimum_size = Vector2(470, 704)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 70
	panel.offset_right = 70 + 470
	panel.offset_top = -352
	panel.offset_bottom = 352
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 58)
	margin.add_theme_constant_override("margin_right", 58)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 64)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	# Logo-Reihe: Baum, Baum, Zelt.
	var logo := HBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", -6)
	logo.add_child(_icon(R_TREE, 60))
	logo.add_child(_icon(R_TREE, 74))
	logo.add_child(_icon(R_TENT, 66))
	col.add_child(logo)

	col.add_child(_heading("SerdarsGame", 40))

	# Gruenes Untertitel-Band.
	var banner := NinePatchRect.new()
	banner.texture = _tex(R_BANNER)
	banner.patch_margin_left = 40
	banner.patch_margin_right = 40
	banner.patch_margin_top = 20
	banner.patch_margin_bottom = 20
	banner.custom_minimum_size = Vector2(0, 46)
	var bl := _heading("COK OYUNCU HAYATTA KALMA", 15, Color(0.96, 0.94, 0.86))
	bl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_child(bl)
	col.add_child(banner)

	col.add_child(_spacer(14))

	# Umschaltbare Seiten (Menue <-> Play-Formular).
	_pages = Control.new()
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_pages)
	_build_menu_page()
	_build_play_page()

	# Versionszeile fest am unteren Panelrand (nicht im Fluss -> kein Ueberlappen).
	var ver := _heading("v%s" % Net.version_name(_read_version()), 14,
		Color(0.34, 0.26, 0.18))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver.anchor_top = 1.0
	ver.offset_top = -46
	ver.offset_bottom = -22
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(ver)


func _build_menu_page() -> void:
	_menu_page = VBoxContainer.new()
	_menu_page.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_menu_page.add_theme_constant_override("separation", 12)
	_pages.add_child(_menu_page)

	_menu_page.add_child(_menu_button(R_PLAY, "OYNA", _on_play, true))
	_menu_page.add_child(_menu_button(R_OPTIONS, "AYARLAR", _on_options))
	_menu_page.add_child(_menu_button(R_QUIT, "CIKIS", _on_quit))


func _build_play_page() -> void:
	_play_page = VBoxContainer.new()
	_play_page.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_play_page.add_theme_constant_override("separation", 3)
	_play_page.visible = false
	_pages.add_child(_play_page)

	_play_page.add_child(_field_label("Adin"))
	_name_edit = _line_edit(Net.player_name, "Isim")
	_name_edit.max_length = 16
	_play_page.add_child(_name_edit)

	_play_page.add_child(_field_label("Sunucu adresi"))
	_ip_edit = _line_edit(Net.DEFAULT_HOST, "orn. 192.168.0.42")
	_play_page.add_child(_ip_edit)

	_play_page.add_child(_spacer(4))
	_play_page.add_child(_menu_button(R_PLAY, "KATIL", _on_join, true, 62))
	_play_page.add_child(_menu_button(R_TAN, "TEK OYUNCU", _on_solo, false, 62))
	_play_page.add_child(_menu_button(R_TAN, "GERI", _show_menu, false, 58))

	_status = _heading("", 14, Color(0.7, 0.2, 0.15))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_play_page.add_child(_status)


## Ribbon-Knopf mit eingebackenem Icon links, Text daneben.
func _menu_button(region: Rect2, text: String, cb: Callable,
		primary := false, height := 74) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_override("font", load(FONT))
	b.add_theme_font_size_override("font_size", 24)
	var fg := Color(0.24, 0.17, 0.11)
	if region == R_PLAY:
		fg = Color(0.99, 0.95, 0.85)          # helle Schrift auf Orange
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	# Icon sitzt links (in der Textur) -> Text nach rechts einruecken.
	var has_icon := region in [R_PLAY, R_OPTIONS, R_QUIT]
	var pad_left := 170.0 if has_icon else 40.0
	var normal := _sb(region, 78, 34, 30, 34)
	normal.content_margin_left = pad_left
	normal.content_margin_right = 20
	var hover := _sb(region, 78, 34, 30, 34, Color(1.12, 1.12, 1.12))
	hover.content_margin_left = pad_left
	hover.content_margin_right = 20
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover if primary else normal)
	b.pressed.connect(cb)
	return b


# --- Ayarlar (Optionen) --------------------------------------------------

func _build_options() -> void:
	_options = Control.new()
	_options.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options.visible = false
	add_child(_options)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(_e): pass)   # schluckt Klicks dahinter
	_options.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options.add_child(center)

	var panel := NinePatchRect.new()
	panel.texture = _tex(R_NOTE)
	panel.patch_margin_left = 60
	panel.patch_margin_right = 60
	panel.patch_margin_top = 60
	panel.patch_margin_bottom = 60
	panel.custom_minimum_size = Vector2(560, 480)
	center.add_child(panel)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 64)
	m.add_theme_constant_override("margin_right", 64)
	m.add_theme_constant_override("margin_top", 66)
	m.add_theme_constant_override("margin_bottom", 66)
	panel.add_child(m)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	m.add_child(col)

	col.add_child(_heading("AYARLAR", 34))
	col.add_child(_spacer(6))

	# Lautstaerke.
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 14)
	vol_row.add_child(_icon(R_ICON_SPEAKER, 46))
	var vlab := _heading("Ses", 20)
	vlab.custom_minimum_size = Vector2(120, 0)
	vlab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vol_row.add_child(vlab)
	_vol_slider = _make_slider()
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.value = db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0
	_vol_slider.value_changed.connect(_on_volume)
	vol_row.add_child(_vol_slider)
	col.add_child(vol_row)

	# Tam Ekran (Vollbild).
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 14)
	fs_row.add_child(_icon(R_ICON_MONITOR, 46))
	var flab := _heading("Tam Ekran", 20)
	flab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	flab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs_row.add_child(flab)
	_fs_toggle = _make_toggle()
	_fs_toggle.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_fs_toggle.toggled.connect(_on_fullscreen)
	fs_row.add_child(_fs_toggle)
	col.add_child(fs_row)

	col.add_child(_spacer(10))
	col.add_child(_menu_button(R_TAN, "GERI", _close_options))


func _make_slider() -> HSlider:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.custom_minimum_size = Vector2(0, 40)
	s.add_theme_stylebox_override("slider", _sb(R_BAR_EMPTY, 24, 24, 20, 20))
	s.add_theme_stylebox_override("grabber_area", _sb(R_BANNER, 20, 20, 20, 20))
	s.add_theme_stylebox_override("grabber_area_highlight", _sb(R_BANNER, 20, 20, 20, 20))
	var knob := _tex(R_KNOB)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	return s


func _make_toggle() -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(96, 46)
	var off := _sb(R_TOGGLE_OFF, 30, 30, 20, 20)
	var on := _sb(R_TOGGLE_ON, 30, 30, 20, 20)
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", off)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", off)
	return b


# --- Seiten-Umschaltung --------------------------------------------------

func _show_menu() -> void:
	_menu_page.visible = true
	_play_page.visible = false

func _show_play() -> void:
	_menu_page.visible = false
	_play_page.visible = true

func _on_options() -> void:
	_options.visible = true

func _close_options() -> void:
	_options.visible = false
	_save_settings()

func _on_quit() -> void:
	get_tree().quit()


# --- Aktionen ------------------------------------------------------------

func _on_play() -> void:
	_show_play()

func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	Net.player_name = n if n != "" else "Oyuncu"

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
	if _status:
		_status.text = "Baglanti basarisiz.\nSunucu calisiyor mu ve adres dogru mu?"


# --- Einstellungen speichern/laden --------------------------------------

func _on_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(v / 100.0, 0.0001, 1.0)))

func _on_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on
		else DisplayServer.WINDOW_MODE_WINDOWED)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var vol := float(cfg.get_value("audio", "master", 1.0))
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(vol, 0.0001, 1.0)))
	if bool(cfg.get_value("video", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", db_to_linear(AudioServer.get_bus_volume_db(0)))
	cfg.set_value("video", "fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	cfg.save(SETTINGS_PATH)


# --- kleine Helfer -------------------------------------------------------

func _read_version() -> int:
	if FileAccess.file_exists("res://version.txt"):
		var f := FileAccess.open("res://version.txt", FileAccess.READ)
		if f:
			return int(f.get_as_text().strip_edges())
	return 0

func _field_label(text: String) -> Label:
	return _heading(text, 16, Color(0.30, 0.22, 0.15))

func _line_edit(value: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", load(FONT))
	e.add_theme_font_size_override("font_size", 20)
	e.custom_minimum_size = Vector2(0, 40)
	return e

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
