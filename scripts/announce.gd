extends Control

## Server-Durchsagen als Banner oben im Bild - vor allem der Countdown vor
## einem Neustart ("Neue Version - Neustart in 10, 9, 8 ...").
##
## Ablauf: Auf dem dedizierten Server wird eine Ausloeser-Datei geschrieben
## (erste Zeile = Sekunden, zweite Zeile = Nachricht). Der Server pollt sie,
## zaehlt runter und schickt die Meldung per RPC an alle Clients. Bei 0 beendet
## er sich - systemd startet ihn neu (mit der neuen Version).
##
## Die Clients zeigen nur das Banner an. Fliegt die Verbindung dann weg, kommt
## ein Hinweis, das Spiel fuer das Update neu zu starten.

## Ausloeser-Datei auf dem Server. Erste Zeile Sekunden, zweite Zeile Text.
const TRIGGER_FILE := "/tmp/survival_announce.txt"

var _panel: PanelContainer
var _label: Label
var _busy := false


func _ready() -> void:
	_build_ui()
	if not Net.active:
		return
	if Net.is_dedicated:
		var t := Timer.new()
		t.wait_time = 1.0
		t.autostart = true
		t.timeout.connect(_poll_trigger)
		add_child(t)
	else:
		multiplayer.server_disconnected.connect(_on_server_gone)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.position = Vector2(0, 14)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.12, 0.12, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	_panel.add_child(_label)

	_panel.visible = false


# --- Server: Ausloeser lesen und Countdown fahren ------------------------

func _poll_trigger() -> void:
	if _busy or not Net.is_dedicated:
		return
	if not FileAccess.file_exists(TRIGGER_FILE):
		return
	var f := FileAccess.open(TRIGGER_FILE, FileAccess.READ)
	if f == null:
		return
	var content := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(TRIGGER_FILE)   # nur einmal ausloesen
	var lines := content.strip_edges().split("\n")
	var secs := 10
	if lines.size() > 0 and lines[0].strip_edges().is_valid_int():
		secs = clampi(int(lines[0]), 1, 120)
	var msg := "Yeni surum mevcut"
	if lines.size() > 1:
		msg = lines[1].strip_edges()
	_run_countdown(secs, msg)


func _run_countdown(secs: int, msg: String) -> void:
	_busy = true
	for n in range(secs, 0, -1):
		_show.rpc("%s\nSunucu %d saniye icinde yeniden baslatiliyor ..." % [msg, n])
		await get_tree().create_timer(1.0).timeout
	_show.rpc("%s\nSunucu simdi yeniden baslatiliyor ..." % msg)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()             # systemd startet neu (mit neuer Version)


# --- Clients: Banner anzeigen --------------------------------------------

@rpc("any_peer", "reliable")
func _show(text: String) -> void:
	if Net.is_dedicated:
		return
	if text.strip_edges() == "":
		_panel.visible = false
	else:
		_label.text = text
		_panel.visible = true


func _on_server_gone() -> void:
	_label.text = "Sunucu yeniden baslatildi.\nGuncelleme icin oyunu yeniden baslat."
	_panel.visible = true
