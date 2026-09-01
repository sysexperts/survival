extends CanvasLayer

## Oberflaeche fuers Bewusstlos-System:
##  - Rote Rand-Vignette pulst kurz, wann immer Leben sinkt (Verhungern/Schaden).
##  - Ist der eigene Spieler bewusstlos: abgedunkeltes Overlay mit "Bayildin",
##    99-Sek-Countdown und einem Respawn-Knopf.
##  - Hilft man einem Mitspieler auf: kreisende Lade-Animation + Restzeit
##    (von interaction.gd gesteuert, 10 Sek).
##
## KEIN class_name (Auto-Updater) - per preload eingebunden, setup() aufrufen.

const PlayerStats := preload("res://scripts/player_stats.gd")
const ReviveRing := preload("res://scripts/revive_ring.gd")

var _player: Node = null
var _last_health := -1.0

var _pulse_time := 0.0             ## solange > 0: Vignette pulst
var _pulse_phase := 0.0
var _strength := 0.0

var _red: ColorRect
var _overlay: Control
var _count: Label
var _revive: Control
var _revive_ring: Control
var _revive_label: Label


func _ready() -> void:
	add_to_group("downed_hud")
	layer = 120
	_build()
	_hook.call_deferred()


func _hook() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		get_tree().create_timer(1.0).timeout.connect(_hook)
		return
	if _player.has_signal("downed_changed") and not _player.downed_changed.is_connected(_on_downed_changed):
		_player.downed_changed.connect(_on_downed_changed)


func _process(delta: float) -> void:
	# Rote Vignette: sobald Leben sinkt, fuer kurze Zeit rhythmisch PULSEN
	# (nicht nur konstant rot). Bei Dauerschaden bleibt der Puls an.
	var hp := float(PlayerStats.health)
	if _last_health >= 0.0 and hp < _last_health - 0.01:
		_pulse_time = 0.7
	_last_health = hp
	var mat := _red.material as ShaderMaterial
	if mat != null:
		if _pulse_time > 0.0:
			_pulse_time -= delta
			_pulse_phase += delta * PI * 1.4      # langsam, ~0.7 Pulse pro Sekunde
			_strength = 0.04 + 0.14 * (0.5 + 0.5 * sin(_pulse_phase))   # dezent
		else:
			_strength = move_toward(_strength, 0.0, delta * 0.9)
		mat.set_shader_parameter("strength", _strength)

	# Countdown aktualisieren, solange bewusstlos.
	if _player != null and _player.has_method("is_downed") and _player.is_downed():
		var left := int(ceil(float(_player.downed_time_left())))
		_count.text = "%d sn icinde spawn" % maxi(left, 0)


# --- Aufhelfen (von interaction.gd gesteuert) --------------------------

func show_revive(_target_name: String) -> void:
	_revive_ring.set_progress(0.0)
	_revive_label.text = "Kaldiriliyor  0%"
	_revive.visible = true


func update_revive(t01: float) -> void:
	_revive_ring.set_progress(t01)
	_revive_label.text = "Kaldiriliyor  %d%%" % int(clampf(t01, 0.0, 1.0) * 100.0)


func hide_revive() -> void:
	_revive.visible = false


# --- Reaktion auf Zustandswechsel --------------------------------------

func _on_downed_changed(is_down: bool) -> void:
	_overlay.visible = is_down


# --- Aufbau ------------------------------------------------------------

func _build() -> void:
	# Rote Rand-Vignette (immer da, Staerke 0 bis gepulst).
	_red = ColorRect.new()
	_red.set_anchors_preset(Control.PRESET_FULL_RECT)
	_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/red_vignette.gdshader")
	mat.set_shader_parameter("strength", 0.0)
	_red.material = mat
	add_child(_red)

	# Bewusstlos-Overlay.
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := Label.new()
	title.text = "Bayildin"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	box.add_child(title)

	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	box.add_child(_count)

	var hint := Label.new()
	hint.text = "Bir arkadas seni kaldirabilir"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	box.add_child(hint)

	var btn := Button.new()
	btn.text = "   Respawn   "
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(func():
		if _player != null and _player.has_method("respawn_from_downed"):
			_player.respawn_from_downed())
	box.add_child(btn)

	# Aufhelfen-Ladeanzeige (unten mittig).
	_revive = Control.new()
	_revive.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Hoeher setzen, damit der Ring NICHT in der XP-/Hotbar-Leiste unten liegt.
	_revive.offset_top = -260.0
	_revive.offset_left = -80.0
	_revive.offset_right = 80.0
	_revive.offset_bottom = -160.0
	_revive.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_revive.visible = false
	add_child(_revive)

	_revive_ring = ReviveRing.new()
	_revive_ring.custom_minimum_size = Vector2(52, 52)
	_revive_ring.size = Vector2(52, 52)
	_revive_ring.position = Vector2(54, 0)
	_revive.add_child(_revive_ring)

	_revive_label = Label.new()
	_revive_label.position = Vector2(0, 52)
	_revive_label.custom_minimum_size = Vector2(160, 0)
	_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_label.add_theme_font_size_override("font_size", 13)
	_revive_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	_revive.add_child(_revive_label)
