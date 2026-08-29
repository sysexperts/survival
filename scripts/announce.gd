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
	add_to_group("announce")
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


# --- Schön animiertes Info-Banner (z. B. "Günaydın") ---------------------

var _flash_center: CenterContainer
var _flash_panel: PanelContainer
var _flash_label: Label
var _flash_tween: Tween


func _build_flash() -> void:
	# CenterContainer ueber die volle Breite -> das Banner ist immer waagerecht
	# zentriert, egal wie breit der Text ist (das manuelle Positionieren hatte es
	# nach links verschoben).
	_flash_center = CenterContainer.new()
	_flash_center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_flash_center.offset_top = 34
	_flash_center.offset_bottom = 120
	_flash_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_center)

	_flash_panel = PanelContainer.new()
	_flash_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.78, 0.42, 0.95)     # warmes Sonnenaufgang-Gold
	sb.border_color = Color(1, 0.94, 0.7, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	_flash_panel.add_theme_stylebox_override("panel", sb)
	_flash_center.add_child(_flash_panel)

	_flash_label = Label.new()
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_font_size_override("font_size", 26)
	_flash_label.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	_flash_label.add_theme_color_override("font_outline_color", Color(1, 0.97, 0.85))
	_flash_label.add_theme_constant_override("outline_size", 4)
	_flash_panel.add_child(_flash_label)
	_flash_center.visible = false


## Zeigt `text` oben mit einer weichen Animation (einschweben, halten, ausblenden).
func flash(text: String, hold := 2.6) -> void:
	if _flash_panel == null:
		_build_flash()
	_flash_label.text = text
	_flash_center.visible = true
	# Groesse jetzt kennen, um den Skalier-Pivot in die Panel-Mitte zu legen
	# (sonst skaliert es aus der Ecke und wandert).
	_flash_panel.reset_size()
	_flash_panel.pivot_offset = _flash_panel.size * 0.5
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# Einschweben (fade + leichtes Aufskalieren), halten, ausblenden.
	_flash_panel.modulate = Color(1, 1, 1, 0)
	_flash_panel.scale = Vector2(0.85, 0.85)
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(_flash_panel, "modulate:a", 1.0, 0.45)
	_flash_tween.tween_property(_flash_panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flash_tween.set_parallel(false)
	_flash_tween.tween_interval(hold)
	_flash_tween.tween_property(_flash_panel, "modulate:a", 0.0, 0.6)
	_flash_tween.tween_callback(func(): _flash_center.visible = false)
