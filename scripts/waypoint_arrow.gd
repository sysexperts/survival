extends Control
class_name WaypointArrow

## Wegpunkt-Anzeige oben rechts.
##
## Ein großer Pfeil in der Farbe des aktiven Wegpunkts zeigt immer in dessen
## Richtung (Bildschirmrichtung vom Spieler aus). Zwei kleine Pfeile links und
## rechts schalten zwischen den Wegpunkten um. Darunter stehen Entfernung und
## Name. Die Wegpunkte kommen aus der Vollbildkarte (M).

const METERS_PER_CELL := 1.0
const ARROW_R := 36.0
const C_SIDE := Color(0.82, 0.80, 0.70)

@export var minimap_path: NodePath = ^"../Minimap"
@export var world_path: NodePath = ^"../../World"

var world: IsoWorld
var player: Node2D
var minimap: Node
var _index := 0

var _prev: Button
var _next: Button


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	if world == null:
		world = get_tree().root.find_child("World", true, false) as IsoWorld
	minimap = get_node_or_null(minimap_path)
	if minimap == null:
		minimap = get_tree().root.find_child("Minimap", true, false)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0; anchor_right = 1.0; anchor_top = 0.0; anchor_bottom = 0.0
	offset_left = -216.0
	offset_right = -16.0
	offset_top = 16.0
	offset_bottom = 150.0

	_prev = _make_side_button(Vector2(0, 22))
	_next = _make_side_button(Vector2(168, 22))
	_prev.pressed.connect(func(): _cycle(-1))
	_next.pressed.connect(func(): _cycle(1))


func _make_side_button(pos: Vector2) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(32, 48)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, empty)
	add_child(b)
	return b


func _cycle(dir: int) -> void:
	var n := _waypoints().size()
	if n > 0:
		_index = (_index + dir + n) % n
	queue_redraw()


func _process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	var n := _waypoints().size()
	var want := n > 1          # Seitenpfeile nur bei mehreren Wegpunkten
	_prev.visible = want
	_next.visible = want
	if n > 0:
		_index = clampi(_index, 0, n - 1)
	queue_redraw()


func _draw() -> void:
	if player == null or world == null:
		return
	var wps := _waypoints()
	var font := get_theme_default_font()
	var w := size.x

	if wps.is_empty():
		if font != null:
			_center_text(font, "keine Wegpunkte", 14.0, 40.0, C_SIDE)
		return

	_index = clampi(_index, 0, wps.size() - 1)
	var wp: Dictionary = wps[_index]
	var col: Color = wp["color"]

	var lvl: int = int(player.get("level")) if player.get("level") != null else 0
	var ppos := player.global_position
	var d := world.cell_to_world(wp["cell"], lvl) - ppos
	var ang := atan2(d.y, d.x) if d.length() > 0.5 else 0.0

	# Großer Zielpfeil.
	_draw_arrow(Vector2(w * 0.5, 40.0), ang, ARROW_R, col)

	# Seitenpfeile (nur wenn mehrere), passend zu den Buttons.
	if wps.size() > 1:
		_side_arrow(Vector2(16, 46), false)
		_side_arrow(Vector2(w - 16, 46), true)

	# Text: Entfernung + Name.
	if font != null:
		var pcell := world.world_to_cell(ppos, lvl)
		var m := int(round(Vector2(wp["cell"] - pcell).length() * METERS_PER_CELL))
		_center_text(font, "%d m" % m, 18, 96.0, col)
		_center_text(font, str(wp["name"]), 15, 120.0, Color(0.92, 0.92, 0.88))


func _draw_arrow(c: Vector2, ang: float, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(r, 0), Vector2(-r * 0.55, -r * 0.7),
		Vector2(-r * 0.2, 0), Vector2(-r * 0.55, r * 0.7),
	])
	for i in pts.size():
		pts[i] = c + pts[i].rotated(ang)
	draw_colored_polygon(pts, col)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.85), 2.0, true)


func _side_arrow(c: Vector2, right: bool) -> void:
	var s := 9.0
	var dir := 1.0 if right else -1.0
	var pts := PackedVector2Array([
		Vector2(s * dir, 0), Vector2(-s * dir, -s), Vector2(-s * dir, s),
	])
	for i in pts.size():
		pts[i] = c + pts[i]
	draw_colored_polygon(pts, C_SIDE)


func _center_text(font: Font, text: String, fs: int, y: float, col: Color) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := (size.x - tw) * 0.5
	draw_string(font, Vector2(x + 1, y + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _waypoints() -> Array:
	if minimap != null and minimap.has_method("get_waypoints"):
		return minimap.get_waypoints()
	return []
