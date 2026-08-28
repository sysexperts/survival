extends CanvasLayer
class_name InventoryHUD

## Hotbar unten, Tasche (Buch) auf Tastendruck.
##
## Wird komplett im Code aufgebaut, damit die Spielszene dafür nicht
## angefasst werden muss. Ein Slot ist ein Panel mit Icon und Anzahl.

const UiAtlas := preload("res://scripts/ui_atlas.gd")
const CCFrames := preload("res://scripts/cc_frames.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")
const CharStats := preload("res://scripts/char_stats.gd")

## Referenzen für die verstellbaren Stats (linke Buchseite).
var _stat_value_labels: Dictionary = {}
var _points_label: Label = null
## Braune Slot-Optik (Pack), einmal gebaut.
var _brown_style: StyleBoxFlat = null

const SLOT := 46
const PAD := 4

## --- Buch-Layout (Cute-Fantasy-UI) ---
const BOOK_SCALE := 3
## Tan-Buch (Doppelseite) in Book_UI.png.
const BOOK_REGION := Rect2i(8, 6, 224, 140)
## Nutzbare Seitenflächen in Buch-lokalen Pixeln (innerhalb der Zierränder).
const LEFT_PAGE := Rect2i(14, 12, 90, 114)
const RIGHT_PAGE := Rect2i(118, 12, 98, 114)
const BAG_COLS := 6
const BAG_SLOT := 34
## Platzhalter-Tabs oben.
const TAB_LABELS := ["Skills", "Lifeskill", "Tab 3", "Tab 4"]
## Rastergroesse des Pixel-Fonts. Alles, was kleiner sein soll als die
## Grundschrift, benutzt genau diesen Wert - Zwischengroessen verwaschen.
const INFO_FONT := 11

var inventory: Inventory
var selected := 0

## DropSync (im Multiplayer) - fuer "aus dem Inventar in die Welt werfen".
var drop_sync: Node
## Welches Feld gerade gezogen wird (fuer das Fallenlassen ausserhalb).
var drag_from := -1

var _slot_nodes: Array[InventorySlot] = []
var _bag: Control
var _dim: ColorRect
var _bar: HBoxContainer
var _name_label: Label
var _hint_label: Label


func setup(p_inventory: Inventory) -> void:
	inventory = p_inventory
	inventory.changed.connect(_refresh)
	layer = 110                      # über dem Overlay
	_build()
	_refresh()


# --- Aufbau -------------------------------------------------------------

func _style(bright: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.82)
	sb.border_color = Color(0.95, 0.85, 0.55, 0.95) if bright else Color(0.35, 0.37, 0.45, 0.9)
	sb.set_border_width_all(2 if bright else 1)
	sb.set_corner_radius_all(3)
	return sb


func _make_slot(index: int, size: int = SLOT) -> InventorySlot:
	var panel := InventorySlot.new()
	panel.hud = self
	panel.index = index
	panel.custom_minimum_size = Vector2(size, size)
	panel.add_theme_stylebox_override("panel", _style(false))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_slot_input.bind(index))

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = PAD
	icon.offset_top = PAD
	icon.offset_right = -PAD
	icon.offset_bottom = -PAD
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	var label := Label.new()
	label.name = "Count"
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -SLOT + PAD
	label.offset_top = -20
	label.offset_right = -3
	label.offset_bottom = -2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", INFO_FONT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	# Dayaniklilik-Cubugu am unteren Rand - nur bei Aleten sichtbar. Ein
	# dunkler Hintergrund mit einer eingefaerbten Fuellung (Breite = Rest).
	var dur_bg := ColorRect.new()
	dur_bg.name = "DurBg"
	dur_bg.color = Color(0, 0, 0, 0.6)
	dur_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dur_bg.offset_left = PAD
	dur_bg.offset_right = -PAD
	dur_bg.offset_top = -6
	dur_bg.offset_bottom = -3
	dur_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dur_bg.visible = false
	var dur_fill := ColorRect.new()
	dur_fill.name = "Fill"
	dur_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)   # links verankert, Breite per anchor_right
	dur_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dur_bg.add_child(dur_fill)
	panel.add_child(dur_bg)

	_slot_nodes.append(panel)
	return panel


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Hotbar unten mittig
	var bar := HBoxContainer.new()
	_bar = bar
	bar.add_theme_constant_override("separation", PAD)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -14
	root.add_child(bar)
	for i in inventory.hotbar_size:
		bar.add_child(_make_slot(i))

	# Name des ausgewählten Gegenstands über der Hotbar
	_name_label = Label.new()
	_name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_name_label.offset_bottom = -14 - SLOT - 6
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Die Rastergroesse des Fonts. Die Zeilen ueber der Hotbar sind
	# Begleittext - in der doppelten Groesse draengen sie sich vor.
	_name_label.add_theme_font_size_override("font_size", INFO_FONT)
	root.add_child(_name_label)

	# Hinweiszeile, z. B. waehrend des Platzierens. Ohne sie merkt man
	# nicht, dass ein Modus laeuft, der die Klicks abfaengt.
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.offset_bottom = -14 - SLOT - 28
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", INFO_FONT)
	_hint_label.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	root.add_child(_hint_label)

	# Tasche, standardmäßig zu.
	# Ein PanelContainer mit PRESET_CENTER setzt nur seine ECKE in die Mitte
	# und wächst nach rechts unten. Deshalb steckt er in einem
	# CenterContainer, der den ganzen Bildschirm einnimmt.
	# Sperrflaeche: dunkelt die Welt ab UND schluckt Klicks, damit bei
	# offener Tasche kein Laufbefehl in die Welt durchrutscht.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.4)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	# Buch (Tasche) - Hintergrund aus dem Cute-Fantasy-UI-Pack.
	_bag = Control.new()
	_bag.visible = false
	var bw := BOOK_REGION.size.x * BOOK_SCALE
	var bh := BOOK_REGION.size.y * BOOK_SCALE
	_bag.custom_minimum_size = Vector2(bw, bh)
	_bag.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_bag)

	var book_bg := TextureRect.new()
	book_bg.texture = UiAtlas.tex("book", BOOK_REGION)
	book_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	book_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	book_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.add_child(book_bg)

	_build_tabs(_bag, bw)
	_build_left_page(_bag)
	_build_right_page(_bag)

	# Die Hotbar nach ganz oben holen. Sie wird als Erstes gebaut, laege
	# also unter der Sperrflaeche - und damit koennte man bei offener
	# Tasche nichts in die Hotbar ziehen.
	root.move_child(bar, -1)


# --- Buch-Seiten --------------------------------------------------------

## Pack-Grafiken für Tabs/Lesezeichen (aus Book_UI) und Icons (aus UI_Icons).
const TAB_BG := Rect2i(590, 78, 20, 18)          ## tan Top-Tab
const RIBBON_BG := [                               ## farbige Lesezeichen (rechts)
	Rect2i(750, 79, 28, 18),   # rot
	Rect2i(798, 79, 28, 18),   # blau
	Rect2i(846, 79, 28, 18),   # grün
	Rect2i(894, 79, 28, 18),   # gelb
	Rect2i(990, 79, 28, 18),   # braun
]
## Icon-Zellen (Spalte, Zeile) in UI_Icons.
const TOP_ICONS := [Vector2i(14, 1), Vector2i(10, 1), Vector2i(2, 1), Vector2i(9, 1)]  # Mail/Screen/Gear/Save
const RIBBON_ICONS := [Vector2i(14, 1), Vector2i(0, 1), Vector2i(8, 1), Vector2i(3, 0), Vector2i(9, 2)]  # Mail/Chat/Gift/Star/Bag


## Tabs wie im Referenzbild: oben Icon-Reiter, rechts farbige Lesezeichen.
func _build_tabs(book: Control, book_w: int) -> void:
	# Oben: 4 tan Reiter mit Icons.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.position = Vector2(18 * BOOK_SCALE, -18 * BOOK_SCALE)
	book.add_child(tabs)
	for cell in TOP_ICONS:
		tabs.add_child(_icon_tab(TAB_BG, cell, 3, 2))

	# Rechts: farbige Lesezeichen, vertikal gestapelt, ragen nach rechts raus.
	var ry := 14 * BOOK_SCALE
	for i in RIBBON_BG.size():
		var ribbon := _icon_tab(RIBBON_BG[i], RIBBON_ICONS[i], 3, 2)
		ribbon.position = Vector2(book_w - 10 * BOOK_SCALE, ry)
		book.add_child(ribbon)
		ry += ribbon.custom_minimum_size.y + 6


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


## Linke Seite: Ausrüstungs-Slots + Gold + verstellbare Charakter-Stats.
func _build_left_page(book: Control) -> void:
	var area := _page_area(book, LEFT_PAGE)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14; col.offset_top = 14; col.offset_right = -14; col.offset_bottom = -14
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(col)

	# Ausrüstungs-Panel (braun, eingelassen) mit 6 Slots (3x2).
	var eq_panel := PanelContainer.new()
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color("a9713f")
	panel_sb.border_color = Color("5a3826")
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(6)
	panel_sb.set_content_margin_all(6)
	eq_panel.add_theme_stylebox_override("panel", panel_sb)
	eq_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(eq_panel)
	var eq := GridContainer.new()
	eq.columns = 3
	eq.add_theme_constant_override("h_separation", 5)
	eq.add_theme_constant_override("v_separation", 5)
	eq_panel.add_child(eq)
	for i in range(6):
		eq.add_child(_placeholder_slot(38))

	var gold := Label.new()
	gold.text = "Altin: 0"
	gold.add_theme_color_override("font_color", Color("6a4326"))
	col.add_child(gold)

	_points_label = Label.new()
	_points_label.add_theme_color_override("font_color", Color("6a4326"))
	col.add_child(_points_label)

	for key in CharStats.ORDER:
		col.add_child(_stat_row(String(key)))
	_refresh_stats()


## Rechte Seite: das Taschen-Raster (9 Spalten) oben in die Seite gesetzt.
func _build_right_page(book: Control) -> void:
	var area := _page_area(book, RIGHT_PAGE)
	var grid := GridContainer.new()
	grid.columns = BAG_COLS
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	var grid_w := BAG_COLS * BAG_SLOT + (BAG_COLS - 1) * 3
	grid.position = Vector2(maxf(0.0, (area.size.x - grid_w) * 0.5), 10)
	area.add_child(grid)
	for i in range(inventory.hotbar_size, inventory.slots.size()):
		grid.add_child(_make_slot(i, BAG_SLOT))


# --- Buch-Bausteine -----------------------------------------------------

func _tab_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("d9a066") if active else Color("b0794e")
	sb.border_color = Color("5a3826")
	sb.set_border_width_all(2)
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	return sb


func _placeholder_slot(size: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.add_theme_stylebox_override("panel", _book_slot_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Eine Stat-Zeile:  Name   [−]  Wert  [+].
func _stat_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var name_lbl := Label.new()
	name_lbl.text = String(CharStats.LABELS.get(key, key))
	name_lbl.custom_minimum_size = Vector2(96, 0)
	name_lbl.add_theme_color_override("font_color", Color("4a2f1c"))
	row.add_child(name_lbl)

	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = Control.FOCUS_NONE
	minus.custom_minimum_size = Vector2(24, 24)
	minus.pressed.connect(_on_stat.bind(key, -1))
	row.add_child(minus)

	var val := Label.new()
	val.custom_minimum_size = Vector2(28, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_color_override("font_color", Color("3a2418"))
	row.add_child(val)
	_stat_value_labels[key] = val

	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.custom_minimum_size = Vector2(24, 24)
	plus.pressed.connect(_on_stat.bind(key, 1))
	row.add_child(plus)
	return row


func _on_stat(key: String, delta: int) -> void:
	CharStats.adjust(key, delta)
	_refresh_stats()


func _refresh_stats() -> void:
	for key in _stat_value_labels:
		_stat_value_labels[key].text = str(CharStats.values.get(key, 0))
	if _points_label:
		_points_label.text = "Puan: %d" % CharStats.points


func _spacer_h(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Hilfs-Control für eine Buchseite (in Buch-lokalen Pixeln, skaliert).
func _page_area(book: Control, page: Rect2i) -> Control:
	var area := Control.new()
	area.position = Vector2(page.position * BOOK_SCALE)
	area.custom_minimum_size = Vector2(page.size * BOOK_SCALE)
	area.size = Vector2(page.size * BOOK_SCALE)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(area)
	return area


## Brauner Slot-Stil fürs Buch (Pack-Look).
func _book_slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("8a5a3c")
	sb.border_color = Color("5a3826")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


## Passenden Slot-Stil je Index: Hotbar dunkel/hell, Tasche braun (Buch).
func _slot_style(i: int) -> StyleBoxFlat:
	if i >= inventory.hotbar_size:
		return _book_slot_style()
	return _style(i == selected)


# --- Anzeige ------------------------------------------------------------

func _refresh() -> void:
	for i in _slot_nodes.size():
		var slot: Dictionary = inventory.slots[i]
		var panel := _slot_nodes[i]
		var icon: TextureRect = panel.get_node("Icon")
		var label: Label = panel.get_node("Count")
		var dur_bg: ColorRect = panel.get_node("DurBg")
		if slot.is_empty():
			icon.texture = null
			label.text = ""
			panel.tooltip_text = ""
			dur_bg.visible = false
		else:
			icon.texture = ItemDB.icon(slot["id"])
			label.text = str(slot["count"]) if int(slot["count"]) > 1 else ""
			# Godot zeigt den Text von selbst, wenn die Maus stehen bleibt.
			panel.tooltip_text = ItemDB.display_name(slot["id"])
			_refresh_durability(dur_bg, slot)
		panel.add_theme_stylebox_override("panel", _slot_style(i))
	var sel: Dictionary = inventory.slots[selected]
	_name_label.text = ItemDB.display_name(sel["id"]) if not sel.is_empty() else ""


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
	# Gruen -> Gelb -> Rot ueber den HSV-Farbton (0.33 .. 0.0).
	fill.color = Color.from_hsv(0.33 * r, 0.85, 0.9)


## Das Bild, das beim Ziehen am Mauszeiger hängt.
func make_drag_preview(stack: Dictionary) -> Control:
	# Godot setzt die Vorschau mit ihrer linken oberen Ecke an den Zeiger.
	# Der Wrapper verschiebt das Bild auf die Zeigermitte.
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
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Ein Klick waehlt nur aus. Das Umlegen laeuft ueber Drag & Drop, das
	# Godot selbst startet, sobald man mit gedrueckter Taste zieht.
	if index < inventory.hotbar_size:
		select(index)


## Kurzer Hinweis ueber der Hotbar. Leerer Text blendet ihn aus.
## Wird vom Slot aufgerufen, wenn ein Zug ausserhalb der Felder endet.
func drop_to_world(index: int) -> void:
	if drop_sync:
		drop_sync.drop_index(index)


func set_hint(text: String) -> void:
	_hint_label.text = text
