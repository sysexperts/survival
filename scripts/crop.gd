extends Sprite2D

## Eine gepflanzte Nutzpflanze auf einer gehackten Ackerzelle.
##
## Waechst zeitbasiert durch die Stufen (aus CropDB), zeigt beim Ueberfahren mit
## der Maus die Restzeit bis reif und stirbt, wenn sie nach dem Reifwerden zu
## lange (rot_after) nicht geerntet wird. Die Phase ergibt sich - wie beim
## Gebaeude - allein aus `planted` (Unix-Zeit), damit alle Clients und ein neu
## geladener Stand dasselbe sehen.
##
## KEIN `class_name` (Auto-Updater). Per preload einbinden.

const CropDB := preload("res://scripts/crop_db.gd")

## Anker (nur noch fuer die Info-Karte). Das Sprite selbst wird pro Stufe
## anhand seines Bildinhalts zentriert (siehe _content_offset).
const ART_OFFSET := Vector2(-16, -30)
## Wie tief der Fuss der Pflanze unter der Rautenmitte sitzt (px).
const GROUND_Y := 3.0

## Das Sheet als Image (einmal, fuer die Inhalts-Bounds je Stufe).
static var _sheet_img: Image

## Wasserstand: fuellt sich bei Regen, sinkt sonst. Ist er leer, waechst die
## Pflanze nicht weiter (die Zeit wird eingefroren) und stirbt nach DROUGHT_DEATH
## Sekunden Trockenheit. Giessen (Sulama Kabi) fuellt ihn auf.
const WATER_MAX := 100.0
const WATER_START := 100.0
## Bewusst gemuetlich: eine Fuellung haelt ~17 min, danach noch 10 min Gnadenfrist
## bis zum Tod. Giessen soll nicht stressig sein - meist reicht 1x giessen.
const WATER_DRAIN := 0.1       ## pro Sekunde (leer nach ~17 min)
const RAIN_FILL := 4.0         ## pro Sekunde bei Regen (fuellt schnell)
const WATER_PER_CAN := 60.0    ## eine Giesskannen-Ladung
const DROUGHT_DEATH := 600.0   ## Sekunden komplett trocken bis zum Absterben (10 min)

var crop_id := ""
var cell: Vector2i
var level: int
var planted := 0.0
var world = null

var water := WATER_START
var _dry_time := 0.0           ## Sekunden am Stueck komplett trocken
var _drought_dead := false
var _weather = null
var _bar_water: ColorRect
var _bar_water_bg: ColorRect

var _atlas: Texture2D
var _shown := ""            ## zuletzt gesetztes Bild (Stufe/tot), gegen Neubau
var _panel: Control         ## kleine Info-Karte ueber der Pflanze (Hover)
var _bar_fill: ColorRect    ## Fortschrittsbalken (Wachstum)
var _bar_bg: ColorRect
var _label: Label
var _hovered := false

const BAR_W := 40.0
const BAR_H := 5.0


static func create(p_world, p_crop_id: String, p_cell: Vector2i, p_level: int, p_planted: float):
	var c = new()
	c.world = p_world
	c.crop_id = p_crop_id
	c.cell = p_cell
	c.level = p_level
	c.planted = p_planted
	c.centered = false
	c.offset = ART_OFFSET
	return c


func _ready() -> void:
	add_to_group("crop")
	_atlas = load(CropDB.SHEET)
	_weather = get_tree().get_first_node_in_group("weather")
	z_index = 1                          # knapp ueber dem Boden
	_build_info()
	_apply()


## Kleine Info-Karte: dunkle Pille mit Fortschrittsbalken + Restzeit-Text.
func _build_info() -> void:
	_panel = Control.new()
	_panel.z_index = 100
	# Kinder des Sprites sitzen an der Sprite-Position (= Zellmitte), NICHT am
	# offset - also horizontal genau ueber der Pflanzenmitte. Etwas nach oben.
	_panel.position = Vector2(0, ART_OFFSET.y - 12)
	_panel.visible = false
	add_child(_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 0.82)
	bg.position = Vector2(-BAR_W * 0.5 - 4, -4)
	bg.size = Vector2(BAR_W + 8, 34)     # Platz fuer zwei Balken (Wachstum + Wasser)
	_panel.add_child(bg)

	# Wachstums-Balken (oben).
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.15, 0.17, 0.2, 0.95)
	_bar_bg.position = Vector2(-BAR_W * 0.5, 16)
	_bar_bg.size = Vector2(BAR_W, BAR_H)
	_panel.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.5, 0.85, 0.35, 1.0)
	_bar_fill.position = Vector2(-BAR_W * 0.5, 16)
	_bar_fill.size = Vector2(0, BAR_H)
	_panel.add_child(_bar_fill)

	# Wasser-Balken (darunter, blau).
	_bar_water_bg = ColorRect.new()
	_bar_water_bg.color = Color(0.12, 0.15, 0.2, 0.95)
	_bar_water_bg.position = Vector2(-BAR_W * 0.5, 24)
	_bar_water_bg.size = Vector2(BAR_W, BAR_H)
	_panel.add_child(_bar_water_bg)

	_bar_water = ColorRect.new()
	_bar_water.color = Color(0.35, 0.65, 0.95, 1.0)
	_bar_water.position = Vector2(-BAR_W * 0.5, 24)
	_bar_water.size = Vector2(BAR_W, BAR_H)
	_panel.add_child(_bar_water)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-BAR_W * 0.5, -2)
	_label.size = Vector2(BAR_W, 16)
	_panel.add_child(_label)


func _data() -> Dictionary:
	return CropDB.CROPS[crop_id]


func _elapsed() -> float:
	return Time.get_unix_time_from_system() - planted


func ripe_seconds() -> float:
	return CropDB.ripe_seconds(crop_id)


func is_ripe() -> bool:
	var e := _elapsed()
	return e >= ripe_seconds() and not is_dead()


func is_dead() -> bool:
	return _drought_dead or _elapsed() >= ripe_seconds() + float(_data()["rot_after"])


## Von der Giesskanne aufgerufen (auch per Sync): Wasserstand auffuellen.
func add_water(amount: float) -> void:
	if _drought_dead:
		return
	water = clampf(water + amount, 0.0, WATER_MAX)
	_dry_time = 0.0


## Wasser-Simulation: Regen fuellt, sonst sinkt es. Ist es leer, friert das
## Wachstum ein (planted mitschieben) und die Trockenzeit laeuft bis zum Tod.
func _sim_water(delta: float) -> void:
	if _drought_dead:
		return
	var raining: bool = _weather != null and _weather.has_method("is_raining") and _weather.is_raining()
	if raining:
		water = minf(WATER_MAX, water + RAIN_FILL * delta)
	else:
		water = maxf(0.0, water - WATER_DRAIN * delta)
	if water <= 0.0:
		# Kein Wasser: Wachstum eingefroren (verstrichene Zeit bleibt gleich),
		# stattdessen zaehlt die Trockenzeit.
		planted += delta
		_dry_time += delta
		if _dry_time >= DROUGHT_DEATH:
			_drought_dead = true
	else:
		_dry_time = 0.0


## 0..N-1 (aktuelle Wachstumsstufe), unabhaengig von reif/tot.
func _stage_index() -> int:
	var secs: Array = _data()["stage_secs"]
	var e := _elapsed()
	var acc := 0.0
	for i in secs.size():
		acc += float(secs[i])
		if e < acc:
			return i
	return _data()["stages"].size() - 1


## Setzt das richtige Bild (Stufe oder tot) und die Info-Zeile.
func _apply() -> void:
	var d := _data()
	var key: String
	var atlas_cell: Vector2i
	if is_dead():
		key = "dead"
		atlas_cell = d["dead"]
	else:
		var si := _stage_index()
		key = "s%d" % si
		atlas_cell = d["stages"][si]
	if key != _shown:
		_shown = key
		var t := AtlasTexture.new()
		t.atlas = _atlas
		t.region = Rect2(atlas_cell.x * CropDB.CELL, atlas_cell.y * CropDB.CELL, CropDB.CELL, CropDB.CELL)
		t.filter_clip = true
		texture = t
		# Pro Stufe zentrieren: waagerecht auf die Inhalts-Mitte, Fuss auf die
		# Rautenmitte - so sitzt jede Grafik unabhaengig von ihrer Lage im 32er-
		# Feld mittig auf der Kachel.
		offset = _content_offset(atlas_cell)
	if _hovered:
		_update_info()


## Offset, der den sichtbaren Inhalt der 32er-Zelle waagerecht zentriert und
## seinen unteren Rand auf die Rautenmitte (+GROUND_Y) legt.
func _content_offset(atlas_cell: Vector2i) -> Vector2:
	if _sheet_img == null:
		_sheet_img = _atlas.get_image()
	var ox := atlas_cell.x * CropDB.CELL
	var oy := atlas_cell.y * CropDB.CELL
	var minx := CropDB.CELL
	var maxx := -1
	var maxy := -1
	for y in CropDB.CELL:
		for x in CropDB.CELL:
			if _sheet_img.get_pixel(ox + x, oy + y).a > 0.15:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	if maxx < minx:
		return ART_OFFSET               # leere Zelle: Fallback
	var center_x := (minx + maxx) * 0.5
	return Vector2(-center_x, GROUND_Y - float(maxy))


func _update_info() -> void:
	var dead := is_dead()
	# Wasser-Balken (bei toter Pflanze aus).
	_bar_water_bg.visible = not dead
	_bar_water.visible = not dead
	if not dead:
		_bar_water.size.x = BAR_W * clampf(water / WATER_MAX, 0.0, 1.0)
	if dead:
		_label.text = "Öldü"
		_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.5))
		_bar_bg.visible = false
		_bar_fill.visible = false
	elif is_ripe():
		_label.text = "Hazir"
		_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.55))
		_bar_bg.visible = true
		_bar_fill.visible = true
		_bar_fill.size.x = BAR_W
		_bar_fill.color = Color(0.55, 0.9, 0.4, 1.0)
	else:
		_bar_bg.visible = true
		_bar_fill.visible = true
		var ripe := ripe_seconds()
		_bar_fill.size.x = BAR_W * clampf(_elapsed() / ripe, 0.0, 1.0)
		_bar_fill.color = Color(0.85, 0.75, 0.3, 1.0)
		if water <= 0.0:
			# Trocken: Wachstum steht, Warnung statt Restzeit.
			_label.text = "Susuz!"
			_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4))
		else:
			var rest := int(ceil(ripe - _elapsed()))
			_label.text = "%d:%02d" % [rest / 60, rest % 60]
			_label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.85))


## Von der Interaktion gesetzt: Restzeit/Status ueber der Pflanze zeigen.
func set_hovered(on: bool) -> void:
	_hovered = on
	_panel.visible = on
	if on:
		_update_info()


func _process(delta: float) -> void:
	_sim_water(delta)
	_apply()
