extends Control

## Multiplayer-Chat, unten links ueber der Item-Leiste.
##
## Mit T oeffnet sich die Eingabe, Enter sendet, Esc/T schliesst. Der Verlauf
## bleibt sichtbar (scrollbar, wenn offen) und wird gedimmt, wenn die Eingabe
## zu ist.
##
## Server-autoritativ, damit nichts doppelt ankommt: der Client schickt die
## Nachricht NUR an den Server (_submit_chat), der Server schickt sie an ALLE
## Clients zurueck (_show_chat) - auch an den Absender. So gibt es genau einen
## Anzeigeweg.
##
## Solange die Eingabe offen ist, pausiert die Spielsteuerung (Net.chat_open).

const MAX_HISTORY := 100

var _scroll: ScrollContainer
var _history: VBoxContainer
var _entry: LineEdit
var _hint: Label
var _open := false


func _ready() -> void:
	# Der dedizierte Server verteilt nur - keine Oberflaeche.
	if Net.is_dedicated:
		return

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_left = 12
	col.offset_bottom = -70          # ueber der Hotbar
	col.custom_minimum_size = Vector2(460, 0)
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(460, 150)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_scroll)

	_history = VBoxContainer.new()
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_history)

	_entry = LineEdit.new()
	_entry.placeholder_text = "Nachricht ... (Enter senden, Esc schliessen)"
	_entry.max_length = 120
	_entry.custom_minimum_size = Vector2(460, 0)
	_entry.visible = false
	_entry.text_submitted.connect(_on_submit)
	_entry.focus_exited.connect(_on_focus_lost)
	col.add_child(_entry)

	_hint = Label.new()
	_hint.text = "T: Chat"
	_hint.modulate = Color(1, 1, 1, 0.4)
	col.add_child(_hint)

	_apply_open_state()


func _unhandled_input(event: InputEvent) -> void:
	if Net.is_dedicated or not Net.active:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not _open:
		if event.keycode == KEY_T:
			_set_open(true)
			get_viewport().set_input_as_handled()
	else:
		if event.keycode == KEY_ESCAPE:
			_set_open(false)
			get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_open = open
	Net.chat_open = open
	_apply_open_state()
	if open:
		_entry.grab_focus()


func _apply_open_state() -> void:
	if _entry == null:
		return
	_entry.visible = _open
	_hint.visible = not _open
	# Offen: voll sichtbar und scrollbar. Zu: gedimmter Verlauf, kein Fokusklau.
	_scroll.modulate.a = 1.0 if _open else 0.55
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if _open else Control.MOUSE_FILTER_IGNORE
	if not _open:
		_entry.text = ""


func _on_focus_lost() -> void:
	# Verhindert, dass die Steuerung blockiert bleibt, wenn der Fokus weggeht.
	if _open:
		_set_open(false)


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		# Nur an den Server - der verteilt an alle (auch an uns).
		_submit_chat.rpc_id(1, Net.player_name, text)
	_set_open(false)


## Client -> Server. Laeuft ausschliesslich auf dem Server.
@rpc("any_peer", "reliable")
func _submit_chat(sender: String, text: String) -> void:
	if not multiplayer.is_server():
		return
	_show_chat.rpc(sender, text)


## Server -> alle Clients. Nur der Server (Autoritaet) darf senden.
@rpc("authority", "call_remote", "reliable")
func _show_chat(sender: String, text: String) -> void:
	_add_line(sender, text)


func _add_line(sender: String, text: String) -> void:
	if _history == null:
		return
	var line := Label.new()
	line.text = "%s: %s" % [sender, text]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(452, 0)
	line.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	line.add_theme_constant_override("outline_size", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_history.add_child(line)
	while _history.get_child_count() > MAX_HISTORY:
		_history.get_child(0).free()
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		var sb := _scroll.get_v_scroll_bar()
		_scroll.scroll_vertical = int(sb.max_value)
