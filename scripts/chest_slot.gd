extends Panel

## Ein Feld im Truhen-Fenster. Kennt seine Quelle ("chest" oder "player") und
## seinen Index. Drag & Drop verschiebt zwischen beiden Inventaren (owner_hud).
##
## KEIN class_name (Auto-Updater) - per preload eingebunden.

var owner_hud                     ## ChestHUD
var src := "chest"                ## "chest" oder "player"
var index := 0
var _icon: TextureRect
var _count: Label


func setup(p_hud, p_src: String, p_index: int) -> void:
	owner_hud = p_hud
	src = p_src
	index = p_index
	custom_minimum_size = Vector2(44, 44)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.85)
	sb.border_color = Color(0.35, 0.37, 0.45, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", sb)
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_count = Label.new()
	_count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.position = Vector2(-2, -2)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count.add_theme_font_size_override("font_size", 11)
	_count.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_count.add_theme_constant_override("outline_size", 4)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	refresh()


func _inv():
	return owner_hud.inv_of(src)


func refresh() -> void:
	var slot: Dictionary = _inv().slots[index]
	if slot.is_empty():
		_icon.texture = null
		_count.text = ""
	else:
		_icon.texture = ItemDB.icon(String(slot["id"]))
		_count.text = str(int(slot["count"])) if int(slot["count"]) > 1 else ""


func _get_drag_data(_pos: Vector2) -> Variant:
	var slot: Dictionary = _inv().slots[index]
	if slot.is_empty():
		return null
	# Vorschau in einem Wrap zentrieren, sonst haengt sie versetzt an der Maus.
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(String(slot["id"]))
	icon.size = Vector2(40, 40)
	icon.position = -icon.size * 0.5
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.modulate = Color(1, 1, 1, 0.85)
	wrap.add_child(icon)
	set_drag_preview(wrap)
	return {"src": src, "i": index}


## Shift+Linksklick: den Stapel sofort ins andere Inventar schieben (Minecraft-
## Stil). owner_hud.quick_move entscheidet Ziel + freien/mergebaren Slot.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
		if owner_hud.has_method("quick_move"):
			owner_hud.quick_move(src, index)
		accept_event()


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("src")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	owner_hud.transfer(String(data["src"]), int(data["i"]), src, index)
