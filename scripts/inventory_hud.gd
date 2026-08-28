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

## --- Buch-Layout (fertiges Bild inventar2 + überlagerte dynamische Teile) ---
const BOOK_SCALE := 3
## Blankes Buch (Kacheln, ohne Text/Icons) - Text/Icons legen wir selbst drauf.
const BOOK_IMG := "res://assets/UI/Cute_Fantasy_UI/UI/inventar1.png"
const BOOK_W_PX := 230
const BOOK_H_PX := 138
## ENVANTER-Vertiefung (rechte Seite) - Ankerbereich der Scrollleiste.
const WELL := Rect2i(120, 30, 100, 98)
## Die gezeichneten Kacheln: 4x4 sichtbar. Items liegen transparent GENAU darauf;
## eine Scrollleiste schiebt, welche 16 der Taschen-Slots gezeigt werden.
const VIEW_COLS := 4
const VIEW_ROWS := 4
const CELL0 := Vector2(135.0, 46.0)   ## Quell-Mitte der ersten Kachel
const CELL_PITCH := 22.3
const SLOT_VIEW := 20                  ## Slot-Kantenlänge in Quell-px
## Header-Positionen (Quell-Mitte).
const HEADER_LEFT := Vector2(58, 13)
const HEADER_RIGHT := Vector2(168, 13)
## STATS (links): Mitte der 4 Icon-Boxen + x der Wert-Schrift (Quell-px).
const ICON_BOX := [Vector2(21, 20), Vector2(21, 36), Vector2(21, 51), Vector2(21, 63)]
const STAT_ICON_SRC := 13
const STAT_VALUE_X := 33
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
## Die 16 sichtbaren Taschen-Ansichten (Fenster-Scrolling) + aktueller Zeilen-Offset.
var _bag_views: Array[InventorySlot] = []
var _bag_offset := 0
var _bag_scroll: VScrollBar = null
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


func _make_slot(index: int, size: int = SLOT, boxed := true, track := true) -> InventorySlot:
	var panel := InventorySlot.new()
	panel.hud = self
	panel.index = index
	panel.custom_minimum_size = Vector2(size, size)
	if boxed:
		panel.add_theme_stylebox_override("panel", _style(false))
	else:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Aktuellen Index zur Ereigniszeit lesen (Fenster-Scrolling ändert ihn).
	panel.gui_input.connect(func(e): _on_slot_input(e, panel.index))
	# Hover-Effekt: leicht aufhellen + „poppen" für mehr haptisches Gefühl.
	panel.pivot_offset = Vector2(size, size) * 0.5
	panel.mouse_entered.connect(func():
		panel.modulate = Color(1.22, 1.22, 1.22)
		panel.scale = Vector2(1.07, 1.07)
		panel.z_index = 1)
	panel.mouse_exited.connect(func():
		panel.modulate = Color(1, 1, 1)
		panel.scale = Vector2.ONE
		panel.z_index = 0)

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

	if track:
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

	# Buch (Tasche) - fertiges Bild inventar2 als Hintergrund.
	_bag = Control.new()
	_bag.visible = false
	var bw := BOOK_W_PX * BOOK_SCALE
	var bh := BOOK_H_PX * BOOK_SCALE
	_bag.custom_minimum_size = Vector2(bw, bh)
	_bag.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_bag)

	var book_bg := TextureRect.new()
	book_bg.texture = load(BOOK_IMG)
	book_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	book_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	book_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.add_child(book_bg)

	_build_left_page(_bag)
	_build_right_page(_bag)
	_build_tabs(_bag, bw)

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


## Icon-Zelle (UI_Icons) je Stat.
const STAT_ICONS := {
	"vitalitaet": Vector2i(0, 0),   # Herz
	"staerke": Vector2i(1, 1),      # Schwert
	"ruestung": Vector2i(12, 0),    # Schild
	"tempo": Vector2i(9, 0),        # Blitz
}
## Banner (UI_Ribbons) für Header und Punkte-Leiste.
const BANNER_HEADER := Rect2i(90, 32, 92, 25)
const BANNER_SMALL := Rect2i(1, 33, 78, 24)


## Linke Seite (STATS): Header + Icons in den gezeichneten Boxen (mit Hover-
## Vergrößerung) + Werte daneben.
func _build_left_page(book: Control) -> void:
	_header(book, "İstatik", HEADER_LEFT)
	for i in range(CharStats.ORDER.size()):
		if i >= ICON_BOX.size():
			break
		var key := String(CharStats.ORDER[i])
		var isz: float = STAT_ICON_SRC * BOOK_SCALE
		# Icon in der Box, zentriert, mit Hover-Vergrößerung.
		var icon := TextureRect.new()
		icon.texture = UiAtlas.cell("icons", STAT_ICONS[key].x, STAT_ICONS[key].y)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size = Vector2(isz, isz)
		icon.position = ICON_BOX[i] * BOOK_SCALE - Vector2(isz, isz) * 0.5
		icon.pivot_offset = Vector2(isz, isz) * 0.5
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.mouse_entered.connect(func(): icon.scale = Vector2(1.3, 1.3); icon.z_index = 1)
		icon.mouse_exited.connect(func(): icon.scale = Vector2.ONE; icon.z_index = 0)
		book.add_child(icon)

		var lbl := Label.new()
		lbl.add_theme_font_override("font", UiAtlas.font())
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color("4a2f1c"))
		lbl.position = Vector2(STAT_VALUE_X * BOOK_SCALE, (ICON_BOX[i].y - 6) * BOOK_SCALE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		book.add_child(lbl)
		_stat_value_labels[key] = lbl
	_refresh_stats()


## Seiten-Überschrift (selbst geschrieben), zentriert um `center` (Quell-px).
func _header(book: Control, text: String, center: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", UiAtlas.font())
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color("4a2f1c"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(120, 20)
	lbl.position = center * BOOK_SCALE - Vector2(60, 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(lbl)


## Banner-Zeile: Pack-Banner (9-Patch) + zentrierte Schrift. Gibt [Control, Label].
func _banner_row(region: Rect2i, height: int, text: String, fsize: int) -> Array:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var np := NinePatchRect.new()
	np.texture = UiAtlas.tex("ribbons", region)
	np.patch_margin_left = 18
	np.patch_margin_right = 18
	np.patch_margin_top = 5
	np.patch_margin_bottom = 7
	np.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(np)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", UiAtlas.font())
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", Color("3a2418"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_bottom = -3
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(lbl)
	return [c, lbl]


## Rechte Seite (ENVANTER): 16 transparente Slots GENAU auf den gezeichneten
## Kacheln; eine Scrollleiste schiebt das Fenster über alle Taschen-Slots.
func _build_right_page(book: Control) -> void:
	_header(book, "Envanter", HEADER_RIGHT)
	var sv := SLOT_VIEW * BOOK_SCALE
	for r in range(VIEW_ROWS):
		for c in range(VIEW_COLS):
			var v := _make_slot(-1, sv, false, false)   # transparent, nicht getrackt
			var cx := (CELL0.x + c * CELL_PITCH) * BOOK_SCALE
			var cy := (CELL0.y + r * CELL_PITCH) * BOOK_SCALE
			v.position = Vector2(cx - sv * 0.5, cy - sv * 0.5)
			v.size = Vector2(sv, sv)
			book.add_child(v)
			_bag_views.append(v)

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
		book.add_child(bar)
		_bag_scroll = bar
	_apply_window()


## Verschiebt das sichtbare Fenster (Mausrad); hält die Scrollleiste im Gleichlauf.
func _scroll_bag(delta: int) -> void:
	if _bag_scroll == null:
		return
	_bag_scroll.value = clampf(_bag_scroll.value + delta, _bag_scroll.min_value, _bag_scroll.max_value)


## Ordnet den 16 Ansichten die aktuellen Taschen-Slots zu (nach Scroll-Offset).
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


## Eine Stat-Zeile: dunkle Pille mit Icon, „Name: Wert" und Hoch/Runter-Pfeilen.
func _stat_row(key: String) -> Control:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("15131a")
	sb.set_corner_radius_all(11)
	sb.border_color = Color("0c0b10")
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pill.add_theme_stylebox_override("panel", sb)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	pill.add_child(h)

	var icon := TextureRect.new()
	icon.texture = UiAtlas.cell("icons", STAT_ICONS[key].x, STAT_ICONS[key].y)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)

	var lbl := Label.new()
	lbl.add_theme_font_override("font", UiAtlas.font())
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color("ffffff"))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(lbl)
	_stat_value_labels[key] = lbl

	h.add_child(_arrow_button(key, 1, Color("4b9e3f"), Vector2i(0, 8)))    # grün, hoch
	h.add_child(_arrow_button(key, -1, Color("e0a020"), Vector2i(3, 8)))   # gold, runter
	return pill


## Farbiger Pfeil-Button (Pack-Pfeil-Icon auf farbigem Grund).
func _arrow_button(key: String, delta: int, color: Color, icon_cell: Vector2i) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 30)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = color.darkened(0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.icon = UiAtlas.cell("icons", icon_cell.x, icon_cell.y)
	b.expand_icon = true
	b.pressed.connect(_on_stat.bind(key, delta))
	return b


func _on_stat(key: String, delta: int) -> void:
	CharStats.adjust(key, delta)
	_refresh_stats()


func _refresh_stats() -> void:
	for key in _stat_value_labels:
		_stat_value_labels[key].text = "%s: %02d" % [
			CharStats.LABELS.get(key, key), int(CharStats.values.get(key, 0))]
	if _points_label:
		_points_label.text = "Verbleibende Punkte: %d" % CharStats.points


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
	# Hotbar (mit Box-Stil) + Taschen-Ansichten (transparent, Fenster-Scroll).
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
	# Mausrad über den Taschen-Feldern scrollt das Fenster.
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_bag(-1)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_bag(1)
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
