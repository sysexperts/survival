extends Control

## Leben/Mana/Stamina oben links. Rahmen aus dem Cute-Fantasy-UI-Pack
## (9-Patch), innen eine gerundete Farbfüllung, die mit dem Wert skaliert.
## Preload-Muster; hängt in der Overlay-CanvasLayer.

const PlayerStats := preload("res://scripts/player_stats.gd")

const BAR_W := 160
const BAR_H := 20
const FILL_INSET := 4            ## Abstand der Füllung zum Rahmen
const GAP := 5                   ## Abstand zwischen den Balken

const HEALTH := Color("e43b44")
const MANA := Color("0095e9")
const STAMINA := Color("63c74d")
## Pack-Farben für Rahmen/Hintergrund (dunkel + warmes Braun wie die UI-Rahmen).
const FRAME_BORDER := Color("e4a672")
const TRACK_BG := Color("241c1a")

var _fills: Array[Panel] = []
var _ratios: Array[Callable] = []


func _ready() -> void:
	# Oben links, unter dem Bildschirmrand.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_add_bar(box, HEALTH, PlayerStats.health_ratio)
	_add_bar(box, MANA, PlayerStats.mana_ratio)
	_add_bar(box, STAMINA, PlayerStats.stamina_ratio)


func _add_bar(box: VBoxContainer, color: Color, ratio: Callable) -> void:
	var row := Control.new()
	row.custom_minimum_size = Vector2(BAR_W, BAR_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	# Rahmen/Spur (dunkel, gerundet, warmer Rand wie die Pack-UI).
	var track := Panel.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = TRACK_BG
	tsb.set_corner_radius_all(6)
	tsb.set_border_width_all(2)
	tsb.border_color = FRAME_BORDER
	track.add_theme_stylebox_override("panel", tsb)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(track)

	# Füllung, gerundet, innen eingerückt.
	var fill := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	fill.add_theme_stylebox_override("panel", sb)
	fill.position = Vector2(FILL_INSET, FILL_INSET)
	fill.size = Vector2(BAR_W - 2 * FILL_INSET, BAR_H - 2 * FILL_INSET)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)

	_fills.append(fill)
	_ratios.append(ratio)


func _process(_delta: float) -> void:
	var full := float(BAR_W - 2 * FILL_INSET)
	for i in range(_fills.size()):
		var r: float = _ratios[i].call()
		_fills[i].size.x = maxf(0.0, full * r)
