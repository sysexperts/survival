extends CanvasLayer
class_name InventoryHUD

## Hotbar unten, Tasche (Buch) auf Tastendruck.
##
## Wird komplett im Code aufgebaut, damit die Spielszene dafür nicht
## angefasst werden muss. Ein Slot ist ein Panel mit Icon und Anzahl.

const UiAtlas := preload("res://scripts/ui_atlas.gd")
const CCFrames := preload("res://scripts/cc_frames.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")

const SLOT := 46
const PAD := 4

## --- Buch-Layout (Cute-Fantasy-UI) ---
const BOOK_SCALE := 3
## Tan-Buch (Doppelseite) in Book_UI.png.
const BOOK_REGION := Rect2i(8, 6, 224, 140)
## Nutzbare Seitenflächen in Buch-lokalen Pixeln (innerhalb der Zierränder).
const LEFT_PAGE := Rect2i(14, 12, 90, 114)
const RIGHT_PAGE := Rect2i(118, 12, 98, 114)
const BAG_COLS := 9
const BAG_SLOT := 30
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

## Vier Platzhalter-Tabs oben auf dem Buch.
func _build_tabs(book: Control, book_w: int) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.position = Vector2(14 * BOOK_SCALE, -14 * BOOK_SCALE)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(tabs)
	for text in TAB_LABELS:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 22)
		tabs.add_child(b)


## Linke Seite: der eigene Charakter (Ganzkörper) als Vorschau.
func _build_left_page(book: Control) -> void:
	var area := _page_area(book, LEFT_PAGE)
	var sf := CCFrames.build(AppearanceStore.local())
	if sf.has_animation(&"idle_south") and sf.get_frame_count(&"idle_south") > 0:
		var portrait := TextureRect.new()
		portrait.texture = sf.get_frame_texture(&"idle_south", 0)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(portrait)


## Rechte Seite: das Taschen-Raster (9 Spalten) in Pack-Slots.
func _build_right_page(book: Control) -> void:
	var area := _page_area(book, RIGHT_PAGE)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(center)
	var grid := GridContainer.new()
	grid.columns = BAG_COLS
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	center.add_child(grid)
	for i in range(inventory.hotbar_size, inventory.slots.size()):
		grid.add_child(_make_slot(i, BAG_SLOT))


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
