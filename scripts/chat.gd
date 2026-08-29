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
var _panel: PanelContainer            ## der dunkle Kasten hinter dem Verlauf
var _hide_timer: Timer                ## blendet den Kasten nach Ruhe aus
var _open := false

## Wie lange der Kasten nach einer Nachricht (bei geschlossener Eingabe) bleibt.
const IDLE_HIDE := 5.0


func _ready() -> void:
	# Der dedizierte Server verteilt nur - keine Oberflaeche.
	if Net.is_dedicated:
		return

	add_to_group("chat")
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
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _bg_style(Color(0, 0, 0, 0.55)))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false          # nur bei Tippen oder eingehender Nachricht
	col.add_child(_panel)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(480, 156)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_scroll)

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

	# Blendet den Kasten nach Ruhe wieder aus (nur bei geschlossener Eingabe).
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = IDLE_HIDE
	_hide_timer.timeout.connect(_on_hide_timeout)
	add_child(_hide_timer)

	_apply_open_state()


func _on_hide_timeout() -> void:
	if not _open and _panel:
		_panel.visible = false


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
	if _open:
		# Beim Tippen ist der Kasten immer da.
		_panel.visible = true
		_hide_timer.stop()
	else:
		_entry.text = ""
		# Beim Schliessen: kurz sichtbar lassen (falls Verlauf da), dann weg.
		if _history and _history.get_child_count() > 0:
			_hide_timer.start()
		else:
			_panel.visible = false


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
	# Befehle (/...) nicht als normale Nachricht verteilen, sondern ausfuehren.
	if text.begins_with("/"):
		_run_command(sender, multiplayer.get_remote_sender_id(), text)
		return
	_show_chat.rpc(sender, text)


const AdminsScript := preload("res://scripts/admins.gd")


## Server: einen Admin-Befehl ausfuehren. Nur Admins duerfen; andere bekommen
## eine Absage. Antworten gehen als Systemzeile NUR an den Absender zurueck.
func _run_command(sender: String, sender_id: int, text: String) -> void:
	var parts := text.strip_edges().split(" ", false)
	var cmd := String(parts[0]).to_lower()
	if not AdminsScript.is_admin(sender):
		_sys_to(sender_id, "Bu komut icin yetkin yok.")
		return
	match cmd:
		"/rain":
			var on := not _weather_raining()
			if parts.size() > 1:
				on = String(parts[1]).to_lower() in ["on", "1", "acik", "ac", "true"]
			_weather_set(on)
			_sys_to(sender_id, "Yagmur: %s" % ("acik" if on else "kapali"))
		"/day":
			_set_time(0.5)
			_sys_to(sender_id, "Gunduz yapildi.")
		"/night":
			_set_time(0.0)
			_sys_to(sender_id, "Gece yapildi.")
		"/tp":
			_cmd_tp(sender, sender_id, parts)
		_:
			_sys_to(sender_id, "Bilinmeyen komut: %s" % cmd)


## /tp to <isim>  ODER  /tp <isim> to <isim2>
func _cmd_tp(sender: String, sender_id: int, parts: PackedStringArray) -> void:
	var ng := get_tree().get_first_node_in_group("net_game")
	if ng == null:
		_sys_to(sender_id, "Isinlanma su an mumkun degil.")
		return
	# "to" finden und Namen links/rechts davon zusammensetzen.
	var to_idx := -1
	for i in range(1, parts.size()):
		if String(parts[i]).to_lower() == "to":
			to_idx = i
			break
	if to_idx == -1 or to_idx + 1 >= parts.size():
		_sys_to(sender_id, "Kullanim: /tp to <isim>  veya  /tp <isim> to <isim2>")
		return
	var dest_name := " ".join(_slice(parts, to_idx + 1, parts.size()))
	var dest_id: int = ng.peer_id_of_name(dest_name)
	if dest_id == -1:
		_sys_to(sender_id, "Oyuncu bulunamadi: %s" % dest_name)
		return
	# Zielperson: entweder der Absender (/tp to X) oder ein genannter Name.
	var target_id := sender_id
	if to_idx > 1:
		var target_name := " ".join(_slice(parts, 1, to_idx))
		target_id = ng.peer_id_of_name(target_name)
		if target_id == -1:
			_sys_to(sender_id, "Oyuncu bulunamadi: %s" % target_name)
			return
	ng.teleport_peer(target_id, ng.peer_pos(dest_id))
	_sys_to(sender_id, "Isinlandi.")


## PackedStringArray-Ausschnitt [from, to) als Array.
func _slice(parts: PackedStringArray, from: int, to: int) -> Array:
	var out: Array = []
	for i in range(from, to):
		out.append(String(parts[i]))
	return out


func _weather_raining() -> bool:
	var w := get_tree().get_first_node_in_group("weather")
	return w != null and w.has_method("is_raining") and w.is_raining()


func _weather_set(on: bool) -> void:
	var w := get_tree().get_first_node_in_group("weather")
	if w != null and w.has_method("set_rain_forced"):
		w.set_rain_forced(on)


func _set_time(t: float) -> void:
	var d := get_tree().get_first_node_in_group("day_night")
	if d != null:
		d.time_of_day = t


## Systemzeile nur an einen bestimmten Spieler (Befehls-Rueckmeldung).
func _sys_to(peer_id: int, msg: String) -> void:
	_show_chat.rpc_id(peer_id, "Sistem", msg)


## Lokale Systemzeile (nur bei diesem Spieler, ohne Netzwerk) - z. B. Hinweise
## wie der gespeicherte Spawnpunkt.
func local_system(msg: String) -> void:
	_add_line("Sistem", msg)


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
	# Neue Nachricht: Kasten zeigen. Bei geschlossener Eingabe nach IDLE_HIDE
	# wieder ausblenden; offen bleibt er stehen.
	_panel.visible = true
	if not _open and _hide_timer:
		_hide_timer.start()
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
