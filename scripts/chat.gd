extends Control

## Einfacher Multiplayer-Chat.
##
## Enter oeffnet die Eingabe, Enter sendet, Esc bricht ab. Nachrichten laufen
## - wie die Spielerpositionen - ueber den dedizierten Server: der Absender
## schickt an den Server, der Server verteilt an alle anderen (Relay). Die
## eigene Nachricht wird lokal sofort angezeigt.
##
## Solange die Eingabe offen ist, wird die Spielsteuerung ueber Net.chat_open
## pausiert (siehe player.gd).

## So viele Zeilen bleiben sichtbar.
const MAX_LINES := 8
## Nach so vielen Sekunden verschwindet eine Zeile wieder.
const FADE_AFTER := 12.0

var _log: VBoxContainer
var _entry: LineEdit
var _hint: Label


func _ready() -> void:
	# Der dedizierte Server braucht keine Oberflaeche - er verteilt nur.
	if Net.is_dedicated:
		return

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_log = VBoxContainer.new()
	_log.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_log.position = Vector2(12, 12)
	_log.add_theme_constant_override("separation", 2)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)

	_entry = LineEdit.new()
	_entry.placeholder_text = "Nachricht ... (Enter senden, Esc abbrechen)"
	_entry.max_length = 120
	_entry.custom_minimum_size = Vector2(420, 0)
	_entry.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_entry.position = Vector2(12, -40)
	_entry.visible = false
	_entry.text_submitted.connect(_on_submit)
	add_child(_entry)

	_hint = Label.new()
	_hint.text = "Enter: Chat"
	_hint.modulate = Color(1, 1, 1, 0.45)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(12, -22)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if Net.is_dedicated or not Net.active:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not _entry.visible:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_open()
			get_viewport().set_input_as_handled()
	else:
		if event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()


func _open() -> void:
	_entry.visible = true
	_entry.grab_focus()
	Net.chat_open = true


func _close() -> void:
	_entry.text = ""
	_entry.visible = false
	_entry.release_focus()
	Net.chat_open = false


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		_recv_chat.rpc(multiplayer.get_unique_id(), Net.player_name, text)
		_add_line(Net.player_name, text)
	_close()


## Nachricht empfangen. Reliable, damit keine Chatzeile verloren geht.
@rpc("any_peer", "reliable")
func _recv_chat(owner_id: int, sender: String, text: String) -> void:
	# Server: an alle anderen weiterreichen, selbst nichts anzeigen.
	if Net.is_dedicated:
		for pid in multiplayer.get_peers():
			if pid != owner_id:
				_recv_chat.rpc_id(pid, owner_id, sender, text)
		return
	if owner_id == multiplayer.get_unique_id():
		return                       # eigenes Echo (schon lokal angezeigt)
	_add_line(sender, text)


func _add_line(sender: String, text: String) -> void:
	if _log == null:
		return
	var line := Label.new()
	line.text = "%s: %s" % [sender, text]
	line.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	line.add_theme_constant_override("outline_size", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_child(line)
	while _log.get_child_count() > MAX_LINES:
		_log.get_child(0).free()
	# Zeile nach einer Weile ausblenden und entfernen.
	var tw := create_tween()
	tw.tween_interval(FADE_AFTER)
	tw.tween_property(line, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func():
		if is_instance_valid(line):
			line.queue_free())
