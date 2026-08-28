extends CanvasLayer
class_name InventoryHUD

## Hotbar unten, Tasche (Buch) auf Tastendruck.
##
## SEIT DEM SZENEN-UMBAU: Der Aufbau steht in scenes/inventory_hud.tscn als
## editierbare Knoten (Buchbild, Kopfzeilen, Stat-Icons, die 4x5-Tasche und die
## Hotbar) - so laesst sich das Layout im Godot-Editor mit der Maus schieben.
## setup() bindet die Knoten (_bind) und haengt die dynamischen Teile an, die
## sich schlecht klicken lassen: +/- Buttons, Tabs/Lesezeichen, Scrollleiste,
## Punkte-Anzeige. Die Logik (Fenster-Scrolling, Drag & Drop, Stat-Vergabe)
## ist unveraendert.

const UiAtlas := preload("res://scripts/ui_atlas.gd")
const CharStats := preload("res://scripts/char_stats.gd")
const SkillsXP := preload("res://scripts/skills_xp.gd")

## Referenzen für die verstellbaren Stats (linke Buchseite).
var _stat_value_labels: Dictionary = {}
## Alle +/- Buttons (zum Ausblenden, sobald keine Punkte mehr uebrig sind).
var _stat_buttons: Array[Button] = []
var _points_label: Label = null

const SLOT := 46
const PAD := 4

## --- Buch-Layout ---
## Alle Knoten liegen in der Szene bereits x3 skaliert (Buchbild 230x138 -> 690x414).
const BOOK_SCALE := 3
## ENVANTER-Vertiefung (rechte Seite) - Ankerbereich der Scrollleiste (Quell-px).
const WELL := Rect2i(120, 30, 100, 98)
## Das gezeichnete Raster ist 4 Spalten x 5 Reihen sichtbar.
const VIEW_COLS := 4
const VIEW_ROWS := 5
## STATS (links): y-Mitte der 4 Zeilen (Quell-px) - fuer die +/- Buttons.
const ICON_BOX := [Vector2(21, 20.5), Vector2(21, 33.5), Vector2(21, 46.5), Vector2(21, 59.5)]
## +/- Buttons je Zeile (Quell-x) und Punkte-Anzeige (Quell-Mitte).
const MINUS_X := 90
const PLUS_X := 99
const POINTS_CENTER := Vector2(58, 116)
## Rastergroesse des Pixel-Fonts (kleiner Begleittext).
const INFO_FONT := 11

## Pack-Grafiken für Tabs/Lesezeichen (aus Book_UI) und Icons (aus UI_Icons).
const TAB_BG := Rect2i(590, 78, 20, 18)          ## tan Top-Tab
const RIBBON_BG := [                               ## farbige Lesezeichen (rechts)
	Rect2i(750, 79, 28, 18),   # rot
	Rect2i(798, 79, 28, 18),   # blau
	Rect2i(846, 79, 28, 18),   # grün
	Rect2i(894, 79, 28, 18),   # gelb
	Rect2i(990, 79, 28, 18),   # braun
]
## Obere Reiter: [Icon-Zelle, Name]. Rucksack / Basic Crafts / Einstellungen.
const TOP_TABS := [
	[Vector2i(9, 2), "Rucksack"],       # Rucksack-Icon
	[Vector2i(3, 1), "Basic Crafts"],   # Schraubenschlüssel
	[Vector2i(2, 1), "Einstellungen"],  # Zahnrad
]
const RIBBON_ICONS := [Vector2i(14, 1), Vector2i(0, 1), Vector2i(8, 1), Vector2i(3, 0), Vector2i(9, 2)]  # Mail/Chat/Gift/Star/Bag

var inventory: Inventory
var selected := 0

## DropSync (im Multiplayer) - fuer "aus dem Inventar in die Welt werfen".
var drop_sync: Node
## Welches Feld gerade gezogen wird (fuer das Fallenlassen ausserhalb).
var drag_from := -1

var _slot_nodes: Array[InventorySlot] = []
## Die sichtbaren Taschen-Ansichten (Fenster-Scrolling) + aktueller Zeilen-Offset.
var _bag_views: Array[InventorySlot] = []
var _bag_offset := 0
var _bag_scroll: VScrollBar = null
var _bag: Control
var _dim: ColorRect
var _bar: HBoxContainer
var _name_label: Label
var _hint_label: Label

## Itemleisten-Extras: EXP-Leiste (links/rechts) + Level-Stern.
var _exp_left: TextureProgressBar
var _exp_right: TextureProgressBar
var _level_label: Label
var _level_star: TextureRect
## Level, bei dem die EXP-Leiste zuletzt gezeichnet wurde (Poll-Vergleich).
var _last_level := -1
var _poll := 0.0
## Laeuft, waehrend sich die EXP-Leiste animiert fuellt.
var _exp_tween: Tween = null


func setup(p_inventory: Inventory) -> void:
	inventory = p_inventory
	inventory.changed.connect(_refresh)
	_bind()
	# Tasche startet zu. Die Sichtbarkeit steuert das Skript (nicht die Szene),
	# damit das Buch im Editor sichtbar/editierbar bleibt.
	_bag.visible = false
	_dim.visible = false
	_refresh()


# --- Bindung der Szenen-Knoten -----------------------------------------

func _bind() -> void:
	# Hotbar-Felder (aus der Szene) mit Index/Logik versehen.
	_bar = $Root/Hotbar
	_slot_nodes.clear()
	var i := 0
	for slot in _bar.get_children():
		if slot is InventorySlot:
			_init_slot(slot, i, true)
			_slot_nodes.append(slot)
			i += 1

	_dim = $Root/Dim
	_name_label = $Root/NameLabel
	_hint_label = $Root/HintLabel
	_bag = $Root/Center/Book

	# Taschen-Felder (4x5) - transparent, Index wird beim Scrollen gesetzt.
	_bag_views.clear()
	for v in _bag.get_node("BagGrid").get_children():
		if v is InventorySlot:
			_init_slot(v, -1, false)
			_bag_views.append(v)

	# Kopfzeilen (İstatik/Envanter) - Schrift ebenfalls im Editor einstellbar,
	# darum hier keine Font-Overrides mehr.
	_wire_left_page()
	_wire_right_page()
	# Tabs/Lesezeichen (bleiben im Code - werden hier an das Buch gehaengt).
	_build_tabs(_bag, int(_bag.custom_minimum_size.x))

	# Itemleisten-Extras (EXP-Leiste + Stern).
	_exp_left = $Root/LevelBar/ExpLeft
	_exp_right = $Root/LevelBar/ExpRight
	_level_star = $Root/LevelBar/LevelStar
	_level_label = _level_star.get_node("LevelLabel")
	_start_shimmer()

	# Hotbar + LevelBar in der Zeichenreihenfolge nach oben - sonst laegen sie
	# unter der Sperrflaeche (Dim) und man koennte bei offener Tasche nichts
	# hineinziehen bzw. die EXP-Leiste waere verdeckt.
	$Root.move_child($Root/LevelBar, -1)
	$Root.move_child(_bar, -1)
	_refresh_stats()
	_refresh_level()
	set_process(true)


## Versieht ein Szenen-Slotfeld mit Index, Stil, Hover und Klick-Logik. Die
## inneren Knoten (Icon/Count/DurBg) bringt die Slot-Szene bereits mit.
func _init_slot(panel: InventorySlot, index: int, boxed: bool) -> void:
	panel.hud = self
	panel.index = index
	var sz: float = panel.custom_minimum_size.x
	if boxed:
		panel.add_theme_stylebox_override("panel", _style(false))
	else:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Aktuellen Index zur Ereigniszeit lesen (Fenster-Scrolling ändert ihn).
	panel.gui_input.connect(func(e): _on_slot_input(e, panel.index))
	panel.pivot_offset = Vector2(sz, sz) * 0.5
	panel.mouse_entered.connect(func():
		panel.modulate = Color(1.22, 1.22, 1.22)
		panel.scale = Vector2(1.07, 1.07)
		panel.z_index = 1)
	panel.mouse_exited.connect(func():
		panel.modulate = Color(1, 1, 1)
		panel.scale = Vector2.ONE
		panel.z_index = 0)


## Linke Seite: Kopfzeile/Werte formatieren (Knoten aus der Szene) und die
## +/- Buttons sowie die Punkte-Anzeige anhaengen.
func _wire_left_page() -> void:
	for i in range(CharStats.ORDER.size()):
		if i >= ICON_BOX.size():
			break
		var key := String(CharStats.ORDER[i])
		var lbl: Label = _bag.get_node("StatValue%d" % i)
		# Schrift/Groesse/Farbe NICHT mehr im Code setzen - so laesst sich die
		# Textart der Stat-Werte im Editor (Inspector -> Theme Overrides) aendern.
		_stat_value_labels[key] = lbl
		# +/- Buttons liegen jetzt als Knoten in der Szene (im Editor schiebbar) -
		# hier nur noch die Aktion verdrahten und fuer das spaetere Ausblenden merken.
		var plus: Button = _bag.get_node("Plus%d" % i)
		var minus: Button = _bag.get_node("Minus%d" % i)
		plus.pressed.connect(_on_stat.bind(key, 1))
		minus.pressed.connect(_on_stat.bind(key, -1))
		_stat_buttons.append(plus)
		_stat_buttons.append(minus)

	# Restpunkte-Anzeige (unterer Balken).
	_points_label = Label.new()
	_points_label.add_theme_font_override("font", UiAtlas.font())
	_points_label.add_theme_font_size_override("font_size", 14)
	_points_label.add_theme_color_override("font_color", Color("2a1a10"))
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_points_label.size = Vector2(200, 24)
	_points_label.position = POINTS_CENTER * BOOK_SCALE - Vector2(100, 12)
	_points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.add_child(_points_label)


## Rechte Seite: Scrollleiste anhaengen, wenn es mehr Taschen-Reihen als
## sichtbare gibt, dann das Fenster einmal anwenden.
func _wire_right_page() -> void:
	var bag_count := inventory.slots.size() - inventory.hotbar_size
	var total_rows := int(ceil(float(bag_count) / VIEW_COLS))
	if total_rows > VIEW_ROWS:
		var bar := VScrollBar.new()
		bar.min_value = 0
		bar.max_value = total_rows - VIEW_ROWS
		bar.step = 1
		bar.page = 1
		bar.position = Vector2((WELL.position.x + WELL.size.x - 1) * BOOK_SCALE, WELL.position.y * BOOK_SCALE)
		bar.custom_minimum_size = Vector2(12, WELL.size.y * BOOK_SCALE)
		bar.size = Vector2(12, WELL.size.y * BOOK_SCALE)
		bar.value_changed.connect(func(val): _bag_offset = int(val); _apply_window())
		_bag.add_child(bar)
		_bag_scroll = bar
	_apply_window()


# --- Stil-Bausteine -----------------------------------------------------

func _style(bright: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.82)
	sb.border_color = Color(0.95, 0.85, 0.55, 0.95) if bright else Color(0.35, 0.37, 0.45, 0.9)
	sb.set_border_width_all(2 if bright else 1)
	sb.set_corner_radius_all(3)
	return sb


## Brauner Slot-Stil fürs Buch (Pack-Look).
func _book_slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("8a5a3c")
	sb.border_color = Color("5a3826")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


## Passenden Slot-Stil je Index: Hotbar dunkel (ausgewaehlt heller), Tasche leer.
func _slot_style(i: int) -> StyleBox:
	if i >= inventory.hotbar_size or i < 0:
		return StyleBoxEmpty.new()
	return _style(i == selected)


# --- Tabs/Lesezeichen (Code, an das Buch gehaengt) ----------------------

## Tabs wie im Referenzbild: oben Icon-Reiter, rechts farbige Lesezeichen.
func _build_tabs(book: Control, book_w: int) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.position = Vector2(18 * BOOK_SCALE, -18 * BOOK_SCALE)
	book.add_child(tabs)
	for entry in TOP_TABS:
		var tab := _icon_tab(TAB_BG, entry[0], 3, 2)
		tab.tooltip_text = String(entry[1])
		tab.mouse_filter = Control.MOUSE_FILTER_STOP   # damit der Tooltip erscheint
		tabs.add_child(tab)
	# Farbige Lesezeichen rechts vom Buch entfernt (auf Nutzerwunsch).


## Ein Tab/Lesezeichen: Pack-Hintergrund + zentriertes Icon.
func _icon_tab(bg_region: Rect2i, icon_cell: Vector2i, bg_scale: int, icon_scale: int) -> Control:
	var tab := Control.new()
	tab.custom_minimum_size = Vector2(bg_region.size * bg_scale)
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	bg.texture = UiAtlas.tex("book", bg_region)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(bg)
	var icon := TextureRect.new()
	icon.texture = UiAtlas.cell("icons", icon_cell.x, icon_cell.y)
	icon.custom_minimum_size = Vector2(16 * icon_scale, 16 * icon_scale)
	icon.size = Vector2(16 * icon_scale, 16 * icon_scale)
	icon.position = (tab.custom_minimum_size - icon.size) * 0.5
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(icon)
	return tab


func _on_stat(key: String, delta: int) -> void:
	CharStats.adjust(key, delta)
	_refresh_stats()


func _refresh_stats() -> void:
	for key in _stat_value_labels:
		_stat_value_labels[key].text = "%s: %02d" % [
			CharStats.LABELS.get(key, key), int(CharStats.values.get(key, 0))]
	if _points_label:
		_points_label.text = "Kalan Puan: %d" % CharStats.points
	# +/- verschwinden, sobald alle Punkte verteilt sind.
	var has_points := CharStats.points > 0
	for b in _stat_buttons:
		b.visible = has_points


## Stern-Grafik je Level-Stufe (alle 5 Level eine andere). Leicht erweiterbar:
## weitere Zellen aus UI_Icons anhaengen. Aktuell blau -> gelb.
const STAR_CELLS := [Vector2i(9, 3), Vector2i(3, 0)]


## EXP-Leiste + Level-Stern aus skills_xp aktualisieren.
func _refresh_level() -> void:
	if _exp_left == null:
		return
	var lvl := SkillsXP.player_level()
	var prog := SkillsXP.level_progress()
	# EINE durchgehende Leiste: erst fuellt sich die linke Haelfte (0..0.5),
	# dann laeuft es rechts weiter (0.5..1). Sanft animiert.
	var left_t := clampf(prog * 2.0, 0.0, 1.0) * 100.0
	var right_t := clampf((prog - 0.5) * 2.0, 0.0, 1.0) * 100.0
	_animate_exp(left_t, right_t)
	_level_label.text = str(lvl)
	# Stern-Grafik nur bei Levelwechsel neu setzen (spart Arbeit).
	if lvl != _last_level:
		var tier: int = clampi(lvl / 5, 0, STAR_CELLS.size() - 1)
		_level_star.texture = UiAtlas.cell("icons", STAR_CELLS[tier].x, STAR_CELLS[tier].y)
		_last_level = lvl


## Leichtes, endloses Schimmern der gefuellten Leiste (heller/dunkler pulsen).
func _start_shimmer() -> void:
	var bright := Color(1.35, 1.3, 1.05)
	var base := Color(1, 1, 1)
	_exp_left.tint_progress = base
	_exp_right.tint_progress = base
	var sh := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Aufhellen (beide zugleich), dann wieder zurueck - endlos.
	sh.tween_property(_exp_left, "tint_progress", bright, 0.9)
	sh.parallel().tween_property(_exp_right, "tint_progress", bright, 0.9)
	sh.tween_property(_exp_left, "tint_progress", base, 0.9)
	sh.parallel().tween_property(_exp_right, "tint_progress", base, 0.9)


## Animiert beide Leisten-Haelften auf ihre Zielwerte (0..100).
func _animate_exp(left_t: float, right_t: float) -> void:
	if is_equal_approx(_exp_left.value, left_t) and is_equal_approx(_exp_right.value, right_t):
		return
	if _exp_tween != null and _exp_tween.is_valid():
		_exp_tween.kill()
	_exp_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_exp_tween.tween_property(_exp_left, "value", left_t, 0.35)
	_exp_tween.tween_property(_exp_right, "value", right_t, 0.35)


## XP aendert sich zur Laufzeit (Faellen/Handwerk) ohne Signal - leichter Poll.
func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.4:
		return
	_poll = 0.0
	_refresh_level()


# --- Fenster-Scrolling der Tasche ---------------------------------------

## Verschiebt das sichtbare Fenster (Mausrad); hält die Scrollleiste im Gleichlauf.
func _scroll_bag(delta: int) -> void:
	if _bag_scroll == null:
		return
	_bag_scroll.value = clampf(_bag_scroll.value + delta, _bag_scroll.min_value, _bag_scroll.max_value)


## Ordnet den Ansichten die aktuellen Taschen-Slots zu (nach Scroll-Offset).
func _apply_window() -> void:
	for r in range(VIEW_ROWS):
		for c in range(VIEW_COLS):
			var view: InventorySlot = _bag_views[r * VIEW_COLS + c]
			var data_idx := inventory.hotbar_size + (_bag_offset + r) * VIEW_COLS + c
			if data_idx < inventory.slots.size():
				view.index = data_idx
				view.visible = true
			else:
				view.index = -1
				view.visible = false
			_refresh_slot(view)


# --- Anzeige ------------------------------------------------------------

func _refresh() -> void:
	for panel in _slot_nodes:
		_refresh_slot(panel)
		panel.add_theme_stylebox_override("panel", _slot_style(panel.index))
	for view in _bag_views:
		_refresh_slot(view)
	var sel: Dictionary = inventory.slots[selected]
	_name_label.text = ItemDB.display_name(sel["id"]) if not sel.is_empty() else ""


## Aktualisiert Icon/Anzahl/Dauerhaftigkeit eines Slots aus seinem aktuellen
## Index (bei den Taschen-Ansichten ändert er sich beim Scrollen).
func _refresh_slot(panel: InventorySlot) -> void:
	var icon: TextureRect = panel.get_node("Icon")
	var label: Label = panel.get_node("Count")
	var dur_bg: ColorRect = panel.get_node("DurBg")
	if panel.index < 0 or panel.index >= inventory.slots.size() or inventory.slots[panel.index].is_empty():
		icon.texture = null
		label.text = ""
		panel.tooltip_text = ""
		dur_bg.visible = false
		return
	var slot: Dictionary = inventory.slots[panel.index]
	icon.texture = ItemDB.icon(slot["id"])
	label.text = str(slot["count"]) if int(slot["count"]) > 1 else ""
	panel.tooltip_text = ItemDB.display_name(slot["id"])
	_refresh_durability(dur_bg, slot)


## Stellt den Dayaniklilik-Cubugu eines Slots ein: sichtbar nur bei Aleten,
## Breite = Restanteil, Farbe von gruen (voll) ueber gelb nach rot (leer).
func _refresh_durability(dur_bg: ColorRect, slot: Dictionary) -> void:
	if not ItemDB.has_durability(slot["id"]):
		dur_bg.visible = false
		return
	var maxd := ItemDB.max_durability(slot["id"])
	var cur := int(slot.get("dur", maxd))
	var r := clampf(float(cur) / float(maxd), 0.0, 1.0)
	dur_bg.visible = true
	var fill: ColorRect = dur_bg.get_node("Fill")
	fill.anchor_right = r
	fill.offset_right = 0
	fill.color = Color.from_hsv(0.33 * r, 0.85, 0.9)


## Das Bild, das beim Ziehen am Mauszeiger hängt.
func make_drag_preview(stack: Dictionary) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(stack["id"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(SLOT - 8, SLOT - 8)
	icon.position = -icon.size * 0.5
	icon.modulate = Color(1, 1, 1, 0.85)
	wrap.add_child(icon)
	var count := int(stack["count"])
	if count > 1:
		var label := Label.new()
		label.text = str(count)
		label.add_theme_font_size_override("font_size", INFO_FONT)
		label.position = Vector2(6, 2)
		wrap.add_child(label)
	return wrap


# --- Eingabe ------------------------------------------------------------

func toggle_bag() -> void:
	_bag.visible = not _bag.visible
	_dim.visible = _bag.visible


func bag_open() -> bool:
	return _bag.visible


func select(index: int) -> void:
	selected = clampi(index, 0, inventory.hotbar_size - 1)
	_refresh()


func _on_slot_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	# Mausrad über den Taschen-Feldern scrollt das Fenster.
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_bag(-1)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_bag(1)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Ein Klick waehlt nur aus. Das Umlegen laeuft ueber Drag & Drop.
	if index >= 0 and index < inventory.hotbar_size:
		select(index)


## Wird vom Slot aufgerufen, wenn ein Zug ausserhalb der Felder endet.
func drop_to_world(index: int) -> void:
	if drop_sync:
		drop_sync.drop_index(index)


func set_hint(text: String) -> void:
	_hint_label.text = text
