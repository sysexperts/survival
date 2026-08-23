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
	col.custom_minimum_size = Vector2(480, 0)
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	# Dunkler, halbtransparenter Kasten hinter dem Verlauf - sonst verschwindet
	# heller Text im hellen Gras.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bg_style(Color(0, 0, 0, 0.55)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(panel)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(480, 156)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_scroll)

	_history = VBoxContainer.new()
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.add_theme_constant_override("separation", 4)
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_history)

	_entry = LineEdit.new()
	_entry.placeholder_text = "Mesaj ... (Enter gönder, Esc kapat)"
	_entry.max_length = 120
	_entry.custom_minimum_size = Vector2(480, 0)
	_entry.visible = false
	_entry.add_theme_font_size_override("font_size", 18)
	_entry.add_theme_stylebox_override("normal", _bg_style(Color(0, 0, 0, 0.7)))
	_entry.add_theme_stylebox_override("focus", _bg_style(Color(0.05, 0.07, 0.12, 0.85)))
	_entry.add_theme_color_override("font_color", Color(1, 1, 1))
	_entry.text_submitted.connect(_on_submit)
	_entry.focus_exited.connect(_on_focus_lost)
	col.add_child(_entry)

	_hint = Label.new()
	_hint.text = "T: Sohbet"
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_hint)

	_apply_open_state()


## Abgerundeter, halbtransparenter Hintergrund.
func _bg_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


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
	_scroll.modulate.a = 1.0 if _open else 0.85
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
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.custom_minimum_size = Vector2(456, 0)
	line.add_theme_font_size_override("normal_font_size", 17)
	line.add_theme_font_size_override("bold_font_size", 17)
	line.add_theme_color_override("default_color", Color(1, 1, 1))
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	line.add_theme_constant_override("outline_size", 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Name farbig hervorheben, Nachricht in Weiss. Eckige Klammern in der
	# Nutzereingabe escapen, sonst frisst der BBCode-Parser sie.
	line.text = "[color=#8fd0ff][b]%s[/b][/color]  %s" % [_esc(sender), _esc(text)]
	_history.add_child(line)
	while _history.get_child_count() > MAX_HISTORY:
		_history.get_child(0).free()
	_scroll_to_bottom()


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _scroll_to_bottom() -> void:
	# Zwei Frames warten: der RichTextLabel muss erst seine Hoehe ausrechnen,
	# sonst ist max_value noch veraltet und die letzte Zeile bleibt verdeckt.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		var sb := _scroll.get_v_scroll_bar()
		_scroll.scroll_vertical = int(sb.max_value)
