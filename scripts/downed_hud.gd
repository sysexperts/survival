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
const LOADING_TEX := preload("res://assets/UI/Cute_Fantasy_UI/UI/Loading_Icon.png")

var _player: Node = null
var _last_health := -1.0

var _red: ColorRect
var _overlay: Control
var _count: Label
var _revive: Control
var _revive_icon: TextureRect
var _revive_label: Label
var _revive_spin := 0.0


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
	# Rote Vignette pulsen, sobald Leben gesunken ist.
	var hp := float(PlayerStats.health)
	if _last_health >= 0.0 and hp < _last_health - 0.01:
		_pulse()
	_last_health = hp

	# Countdown aktualisieren, solange bewusstlos.
	if _player != null and _player.has_method("is_downed") and _player.is_downed():
		var left := int(ceil(float(_player.downed_time_left())))
		_count.text = "%d sn icinde spawn" % maxi(left, 0)

	# Aufhelfen-Ladekreis drehen.
	if _revive.visible:
		_revive_spin += delta * 4.0
		_revive_icon.pivot_offset = _revive_icon.size * 0.5
		_revive_icon.rotation = _revive_spin


# --- Aufhelfen (von interaction.gd gesteuert) --------------------------

func show_revive(target_name: String) -> void:
	_revive_label.text = "Kaldiriliyor: %s" % target_name
	_revive.visible = true


func update_revive(t01: float) -> void:
	# einfache Restzeit-Anzeige ueber der Ladeanimation
	_revive_label.text = "Kaldiriliyor  %d%%" % int(clampf(t01, 0.0, 1.0) * 100.0)


func hide_revive() -> void:
	_revive.visible = false


# --- Reaktion auf Zustandswechsel --------------------------------------

func _on_downed_changed(is_down: bool) -> void:
	_overlay.visible = is_down


func _pulse() -> void:
	var mat := _red.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("strength", 0.55)
	var tw := create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("strength", v), 0.55, 0.0, 0.55)


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
	_revive.offset_top = -140.0
	_revive.offset_left = -80.0
	_revive.offset_right = 80.0
	_revive.offset_bottom = -40.0
	_revive.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_revive.visible = false
	add_child(_revive)

	_revive_icon = TextureRect.new()
	_revive_icon.texture = LOADING_TEX
	_revive_icon.custom_minimum_size = Vector2(48, 48)
	_revive_icon.size = Vector2(48, 48)
	_revive_icon.position = Vector2(56, 0)
	_revive_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_revive_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_revive.add_child(_revive_icon)

	_revive_label = Label.new()
	_revive_label.position = Vector2(0, 52)
	_revive_label.custom_minimum_size = Vector2(160, 0)
	_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_label.add_theme_font_size_override("font_size", 13)
	_revive_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	_revive.add_child(_revive_label)
