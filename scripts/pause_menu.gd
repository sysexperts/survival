extends CanvasLayer

## ESC-Pausenmenü mit Görünüm-Editor (Aussehen wechseln).
##
## Über ESC (unhandled - andere Panels schließen zuerst) öffnet sich das Menü.
## Der Editor blättert je Slot durch die Varianten des Packs; jede Änderung
## wird sofort auf die eigene Figur angewandt, gespeichert und über NetGame an
## alle Mitspieler geschickt - so ist der neue Look sofort für alle sichtbar.

const CCCatalog := preload("res://scripts/cc_catalog.gd")
const CCFrames := preload("res://scripts/cc_frames.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")
const UIState := preload("res://scripts/ui_state.gd")

var _root: Control          ## Hauptmenü (Devam / Görünüm / Ana Menü)
var _editor: Control        ## Görünüm-Editor
var _preview: TextureRect
var _rows: Dictionary = {}  ## slot-id -> Label (aktueller Wert)
var _look: Dictionary = {}


func _ready() -> void:
	layer = 130
	_look = AppearanceStore.local().duplicate()
	_build_root()
	_build_editor()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _editor.visible:
		_editor.visible = false
		_root.visible = true
		return
	if visible:
		_close()
		return
	# Erst ein offenes Spiel-Fenster schliessen (Truhe/Station/Tasche/...); nur
	# wenn keines offen war, das Menue oeffnen. So schliesst Escape verlaesslich.
	if UIState.close_top_window():
		return
	_open()


func _open() -> void:
	visible = true
	_root.visible = true
	_editor.visible = false
	UIState.pause_open = true


func _close() -> void:
	visible = false
	UIState.pause_open = false


# --- Hauptmenü -----------------------------------------------------------

func _build_root() -> void:
	_root = _dim_background()
	add_child(_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(260, 0)
	_center(box, _root)

	var title := Label.new()
	title.text = "Menü"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	box.add_child(_spacer(6))

	box.add_child(_menu_button("Devam", _close))
	box.add_child(_menu_button("Bugdan Kurtar", _unstuck))
	box.add_child(_menu_button("Görünüm", func():
		_root.visible = false
		_editor.visible = true))
	box.add_child(_menu_button("Ana Menüye Dön", _to_main_menu))


## Bugdan Kurtar: Spieler zum naechsten freien Feld ruecken (steckt im Baum o.ae.).
func _unstuck() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("ensure_unstuck"):
		p.ensure_unstuck()
	_close()


func _to_main_menu() -> void:
	UIState.pause_open = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	Net.active = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Görünüm-Editor ------------------------------------------------------

func _build_editor() -> void:
	_editor = _dim_background()
	add_child(_editor)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	_center(h, _editor)

	# Links: Vorschau der eigenen Figur.
	var pv := PanelContainer.new()
	pv.custom_minimum_size = Vector2(220, 260)
	var pvbox := VBoxContainer.new()
	pv.add_child(pvbox)
	var pvtitle := Label.new()
	pvtitle.text = "Önizleme"
	pvtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvbox.add_child(pvtitle)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(192, 192)
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pvbox.add_child(_preview)
	h.add_child(pv)

	# Rechts: scrollbare Slot-Liste.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 420)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(300, 0)
	scroll.add_child(list)
	h.add_child(scroll)

	var title := Label.new()
	title.text = "Görünüm"
	title.add_theme_font_size_override("font_size", 20)
	list.add_child(title)

	for slot in CCCatalog.slots():
		list.add_child(_slot_row(slot))

	list.add_child(_spacer(8))
	var back := _menu_button("Geri", func():
		_editor.visible = false
		_root.visible = true)
	list.add_child(back)

	_refresh_preview()


func _slot_row(slot: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = String(slot["label"])
	name_lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_lbl)

	var prev := Button.new()
	prev.text = "‹"
	prev.pressed.connect(func(): _cycle(slot, -1))
	row.add_child(prev)

	var val := Label.new()
	val.custom_minimum_size = Vector2(120, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.clip_text = true
	row.add_child(val)
	_rows[slot["id"]] = val

	var next := Button.new()
	next.text = "›"
	next.pressed.connect(func(): _cycle(slot, 1))
	row.add_child(next)

	_update_row(slot)
	return row


## Optionsliste eines Slots inkl. "Yok" (leer), falls erlaubt.
func _options_of(slot: Dictionary) -> Array:
	var opts: Array = []
	if slot.get("allow_none", false):
		opts.append("")
	opts.append_array(slot["options"])
	return opts


func _cycle(slot: Dictionary, dir: int) -> void:
	var opts := _options_of(slot)
	var cur := String(_look.get(slot["id"], ""))
	var i := opts.find(cur)
	if i < 0:
		i = 0
	i = wrapi(i + dir, 0, opts.size())
	_look[slot["id"]] = opts[i]
	_update_row(slot)
	_apply()


func _update_row(slot: Dictionary) -> void:
	var lbl: Label = _rows[slot["id"]]
	lbl.text = _short(String(_look.get(slot["id"], "")))


## "Layer5_Shirt_Red" -> "Shirt Red", "" -> "Yok".
func _short(token: String) -> String:
	if token == "":
		return "Yok"
	var parts := token.split("_")
	if parts.size() >= 3:
		return "%s %s" % [parts[1], "_".join(parts.slice(2))]
	return token


## Wendet den Look auf die eigene Figur an, speichert und broadcastet ihn.
func _apply() -> void:
	AppearanceStore.set_local(_look)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("apply_look"):
		p.apply_look(_look)
	var net := get_parent().get_node_or_null(^"NetGame")
	if net and net.has_method("broadcast_look"):
		net.broadcast_look()
	_refresh_preview()


func _refresh_preview() -> void:
	var sf := CCFrames.build(_look)
	if sf.has_animation(&"idle_south") and sf.get_frame_count(&"idle_south") > 0:
		_preview.texture = sf.get_frame_texture(&"idle_south", 0)


# --- Bausteine -----------------------------------------------------------

func _dim_background() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.04, 0.05, 0.08, 0.72)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


func _center(node: Control, parent: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	center.add_child(node)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
