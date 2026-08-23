extends CanvasLayer
class_name CreativeHUD

## Kreativ-Inventar fuer Admins (Taste X, siehe Net.is_admin).
##
## Zeigt ALLE bekannten Gegenstaende in einem Raster. Ein Klick legt einen
## vollen Stapel ins Inventar. Rein clientseitig - der Vorrat kommt aus dem
## Nichts, gedacht zum Testen und fuers Bauen als Admin.
##
## Wie das restliche HUD komplett im Code aufgebaut, damit die Szene dafuer
## nicht angefasst werden muss. Eigene CanvasLayer ueber der Hotbar.

const SLOT := 46
const PAD := 4
const INFO_FONT := 11
const COLUMNS := 8

var inventory: Inventory
var _dim: ColorRect
var _panel: PanelContainer
## Kurze Rueckmeldung ("+64 Odun"), damit man sieht, dass der Klick griff.
var _feedback: Label
var _feedback_left := 0.0


func setup(p_inventory: Inventory) -> void:
	inventory = p_inventory
	layer = 115                      # ueber Hotbar (110) und Tasche
	_build()


func _process(delta: float) -> void:
	if _feedback_left > 0.0:
		_feedback_left -= delta
		if _feedback_left <= 0.0 and _feedback:
			_feedback.text = ""


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sperrflaeche: dunkelt ab und schluckt Klicks (kein Laufbefehl durch).
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.96)
	style.border_color = Color(0.95, 0.85, 0.55, 0.95)   # Admin-Gold
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var title := Label.new()
	title.text = "Admin  ·  Tüm Esyalar"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	column.add_child(title)

	# Scrollbar, falls mal mehr Items dazukommen als in ein paar Zeilen passen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (SLOT + PAD) + PAD, 5 * (SLOT + PAD))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", PAD)
	grid.add_theme_constant_override("v_separation", PAD)
	scroll.add_child(grid)

	for id in ItemDB.ids():
		grid.add_child(_make_item(String(id)))

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_font_size_override("font_size", INFO_FONT)
	_feedback.add_theme_color_override("font_color", Color(0.7, 1, 0.7))
	column.add_child(_feedback)


func _make_item(id: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT, SLOT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.9)
	sb.border_color = Color(0.35, 0.37, 0.45, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = ItemDB.display_name(id)
	panel.gui_input.connect(_on_item_input.bind(id))

	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = PAD
	icon.offset_top = PAD
	icon.offset_right = -PAD
	icon.offset_bottom = -PAD
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	return panel


func _on_item_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var amount := ItemDB.max_stack(id)
	inventory.add(id, amount)
	if _feedback:
		_feedback.text = "+%d  %s" % [amount, ItemDB.display_name(id)]
		_feedback_left = 2.0


func toggle() -> void:
	set_open(not is_open())


func set_open(open: bool) -> void:
	_panel.visible = open
	_dim.visible = open


func is_open() -> bool:
	return _panel.visible
