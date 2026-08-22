extends Control
class_name Compass

## Kompassleiste über der Hotbar - wie in Militärshootern.
##
## Ein waagerechter Balken, zentriert auf die Blickrichtung des Spielers.
## N/O/S/W (und die Zwischenrichtungen) sowie die Wegpunkte wandern je nach
## Blickrichtung nach links/rechts. Wegpunkte außerhalb des Sichtwinkels kleben
## als Pfeil am jeweiligen Ende. Die Wegpunkte kommen aus der Vollbildkarte (M).

const SPAN_DEG := 120.0      ## Sichtwinkel, den der Balken abdeckt (±60°)
const BAR_H := 26.0
const METERS_PER_CELL := 1.0

const C_BAR := Color(0.04, 0.05, 0.08, 0.55)
const C_EDGE := Color(0, 0, 0, 0.5)
const C_TICK := Color(0.82, 0.80, 0.70)
const C_FWD := Color(1.0, 0.92, 0.3)

## Richtungen im Bildschirmraum (Norden = oben). Deutsche Kürzel.
const CARDINALS := [
	["N", Vector2(0, -1)], ["NO", Vector2(1, -1)], ["O", Vector2(1, 0)], ["SO", Vector2(1, 1)],
	["S", Vector2(0, 1)], ["SW", Vector2(-1, 1)], ["W", Vector2(-1, 0)], ["NW", Vector2(-1, -1)],
]

const FACE := {
	"north": Vector2(0, -1), "south": Vector2(0, 1),
	"east": Vector2(1, 0), "west": Vector2(-1, 0),
	"north-east": Vector2(1, -1), "north-west": Vector2(-1, -1),
	"south-east": Vector2(1, 1), "south-west": Vector2(-1, 1),
}

@export var minimap_path: NodePath = ^"../Minimap"
@export var world_path: NodePath = ^"../../World"
## Abstand der Unterkante vom Bildschirmrand - so hoch, dass die Leiste über
## der Hotbar sitzt.
@export var bottom_offset := 104.0
@export var bar_width := 470.0

var world: IsoWorld
var player: Node2D
var minimap: Node


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	if world == null:
		world = get_tree().root.find_child("World", true, false) as IsoWorld
	minimap = get_node_or_null(minimap_path)
	if minimap == null:
		minimap = get_tree().root.find_child("Minimap", true, false)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5; anchor_right = 0.5; anchor_top = 1.0; anchor_bottom = 1.0
	offset_left = -bar_width * 0.5
	offset_right = bar_width * 0.5
	offset_bottom = -bottom_offset
	offset_top = -bottom_offset - BAR_H - 20.0


func _process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	queue_redraw()


func _draw() -> void:
	if player == null or world == null:
		return
	var w := size.x
	var cx := w * 0.5
	var top := size.y - BAR_H
	var font := get_theme_default_font()

	# Balken.
	draw_rect(Rect2(0, top, w, BAR_H), C_BAR)
	draw_rect(Rect2(0, top, w, BAR_H), C_EDGE, false, 1.0)

	var fa := _facing_angle()

	# Himmelsrichtungen.
	for entry in CARDINALS:
		var diff := _wrap(rad_to_deg(atan2(entry[1].y, entry[1].x)) - fa)
		if absf(diff) <= SPAN_DEG * 0.5:
			var x := cx + (diff / (SPAN_DEG * 0.5)) * (w * 0.5)
			draw_line(Vector2(x, top), Vector2(x, top + 6.0), C_TICK, 1.0)
			if font != null:
				var s: String = entry[0]
				var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				_label(font, Vector2(x - tw * 0.5, top + BAR_H - 6.0), s, 14, C_TICK)

	# Vorne-Markierung (Mitte).
	draw_line(Vector2(cx, top - 5.0), Vector2(cx, top + BAR_H + 5.0), C_FWD, 2.0)

	# Wegpunkte.
	var lvl: int = int(player.get("level")) if player.get("level") != null else 0
	var ppos := player.global_position
	var pcell := world.world_to_cell(ppos, lvl)
	for wp in _waypoints():
		var d := world.cell_to_world(wp["cell"], lvl) - ppos
		if d.length() < 1.0:
			continue
		var col: Color = wp["color"]
		var m := int(round(Vector2(wp["cell"] - pcell).length() * METERS_PER_CELL))
		var diff := _wrap(rad_to_deg(atan2(d.y, d.x)) - fa)
		if absf(diff) <= SPAN_DEG * 0.5:
			var x := cx + (diff / (SPAN_DEG * 0.5)) * (w * 0.5)
			_marker(x, top, col)
			if font != null:
				var t := "%dm" % m
				var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				_label(font, Vector2(x - tw * 0.5, top - 8.0), t, 12, col)
		else:
			# Außerhalb: Pfeil am Rand, der die Richtung anzeigt.
			var right := diff > 0
			var ex := (w - 8.0) if right else 8.0
			_edge_arrow(ex, top + BAR_H * 0.5, col, right)


func _facing_angle() -> float:
	var v: Vector2 = FACE.get(str(player.get("facing")), Vector2(0, 1))
	return rad_to_deg(atan2(v.y, v.x))


## Winkel auf [-180, 180] normieren.
func _wrap(a: float) -> float:
	return fposmod(a + 180.0, 360.0) - 180.0


func _waypoints() -> Array:
	if minimap != null and minimap.has_method("get_waypoints"):
		return minimap.get_waypoints()
	return []


func _marker(x: float, top: float, col: Color) -> void:
	# Kleines Dreieck über dem Balken, das nach unten auf ihn zeigt.
	var pts := PackedVector2Array([
		Vector2(x, top + 3.0), Vector2(x - 6.0, top - 7.0), Vector2(x + 6.0, top - 7.0),
	])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.85), 1.0, true)


func _edge_arrow(x: float, y: float, col: Color, right: bool) -> void:
	var s := 7.0
	var dir := 1.0 if right else -1.0
	var pts := PackedVector2Array([
		Vector2(x + s * dir, y), Vector2(x - s * dir, y - s), Vector2(x - s * dir, y + s),
	])
	draw_colored_polygon(pts, col)


func _label(font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
