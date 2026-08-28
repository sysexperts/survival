extends Control

## Spieler-Status oben links: Porträt (eigener Kopf) + drei beschriftete Balken
## mit Icon davor - Leben (rot, Herz), Ausdauer (blau, Blitz) und Hunger (gelb,
## Fleisch). Groesser und eindeutig, damit man auf einen Blick sieht, was was ist.
##
## Die Balken sind dynamisch: die Fuellung kommt aus PlayerStats (aktuell meist
## voll, bis Verbrauch/Survival-Bedarf aktiv ist).

const UiAtlas := preload("res://scripts/ui_atlas.gd")
const CCFrames := preload("res://scripts/cc_frames.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")
const PlayerStats := preload("res://scripts/player_stats.gd")

## Porträt-Kantenlaenge und Balken-Masse (alles vergroessert).
const PORTRAIT := 60
const BAR_W := 150
const BAR_H := 18
const ICON := 22
const ROW_GAP := 6
const HEAD_MAX_Y := 25

## Pack-Balken (aus UI_Bars gesliced, gruen->gelb umgefaerbt fuer Hunger).
const BAR_DIR := "res://assets/UI/Cute_Fantasy_UI/UI/"

## Die drei Zeilen: key -> [Balken-Grafik, Icon]. Reihenfolge = Anzeige oben->unten.
const ROWS := [
	{"key": "health", "bar": BAR_DIR + "bar_red.png", "icon": Vector2i(0, 0)},    # Herz
	{"key": "stamina", "bar": BAR_DIR + "bar_blue.png", "icon": Vector2i(9, 0)},  # Blitz
	{"key": "hunger", "bar": BAR_DIR + "bar_yellow.png", "item": "kizarmis_et"},  # Fleisch
]

## TextureProgressBar je key, zum Aktualisieren der Fuellung.
var _fills: Dictionary = {}
var _poll := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Porträt-Rahmen (dunkel, gerundet) + Kopf.
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", _frame_style())
	frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	frame.size = Vector2(PORTRAIT, PORTRAIT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var head := _head_texture()
	if head != null:
		var pad := 6
		var clip := Control.new()
		clip.position = Vector2(pad, pad)
		clip.size = Vector2(PORTRAIT - pad * 2, PORTRAIT - pad * 2)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(clip)
		var tr := TextureRect.new()
		tr.texture = head
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(tr)

	# Balken rechts vom Porträt, vertikal gestapelt und mittig zur Porträthoehe.
	var rows_h := ROWS.size() * BAR_H + (ROWS.size() - 1) * ROW_GAP
	var bx := PORTRAIT + 8
	var by := int((PORTRAIT - rows_h) * 0.5)
	for i in ROWS.size():
		_build_row(ROWS[i], bx, by + i * (BAR_H + ROW_GAP))

	_refresh()


func _build_row(row: Dictionary, x: int, y: int) -> void:
	# Icon davor.
	var icon := TextureRect.new()
	if row.has("item"):
		icon.texture = ItemDB.icon(row["item"]) if ItemDB.has(row["item"]) else null
	else:
		var cell: Vector2i = row["icon"]
		icon.texture = UiAtlas.cell("icons", cell.x, cell.y)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(x, y + (BAR_H - ICON) * 0.5)
	icon.size = Vector2(ICON, ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

	# Balken: dunkle Schiene + Pack-Balken als Fuellung (klippt nach rechts).
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", _track_style())
	track.position = Vector2(x + ICON + 6, y)
	track.size = Vector2(BAR_W, BAR_H)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(track)

	var bar := TextureProgressBar.new()
	bar.texture_progress = load(row["bar"])
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 7
	bar.stretch_margin_right = 5
	bar.stretch_margin_top = 1
	bar.stretch_margin_bottom = 1
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.min_value = 0
	bar.max_value = 100
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 2
	bar.offset_top = 2
	bar.offset_right = -2
	bar.offset_bottom = -2
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar)
	_fills[row["key"]] = bar


## Anteil (0..1) je Status aus PlayerStats.
func _ratio(key: String) -> float:
	match key:
		"health": return PlayerStats.health_ratio()
		"stamina": return PlayerStats.stamina_ratio()
		"hunger": return clampf(PlayerStats.hunger / maxf(PlayerStats.hunger_max, 1.0), 0.0, 1.0)
	return 1.0


func _refresh() -> void:
	for key in _fills:
		var bar: TextureProgressBar = _fills[key]
		bar.value = _ratio(key) * 100.0


func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	_refresh()


## Abgerundeter dunkler Rahmen fuers Porträt.
func _frame_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.9)
	sb.border_color = Color(0.75, 0.62, 0.42, 0.95)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	return sb


## Dunkle Balken-Schiene.
func _track_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.85)
	sb.border_color = Color(0, 0, 0, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	return sb


## Kopf des eigenen Charakters aus dem Idle-Frame ausschneiden.
func _head_texture() -> Texture2D:
	var sf := CCFrames.build(AppearanceStore.local())
	if not sf.has_animation(&"idle_south") or sf.get_frame_count(&"idle_south") == 0:
		return null
	var img := sf.get_frame_texture(&"idle_south", 0).get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var max_y: int = mini(HEAD_MAX_Y, img.get_height())
	var mnx := img.get_width()
	var mxx := 0
	var mny := img.get_height()
	var mxy := 0
	for y in range(max_y):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.4:
				mnx = mini(mnx, x); mxx = maxi(mxx, x)
				mny = mini(mny, y); mxy = maxi(mxy, y)
	if mxx < mnx:
		return null
	var crop := Rect2i(mnx, mny, mxx - mnx + 1, mxy - mny + 1)
	return ImageTexture.create_from_image(img.get_region(crop))
