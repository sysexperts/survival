extends Control
class_name Minimap

## Übersichtskarte oben rechts, mit M auf Vollbild umschaltbar.
##
## Gezeichnet wird eine Draufsicht: das Terrain kommt als kleine Textur (ein
## Pixel je Zelle) und wird hart hochskaliert - das gibt saubere, gleichmäßige
## Kacheln statt fransiger Rechtecke. Weil die Welt deterministisch generiert
## wird (WorldGen), zeigt die Karte auch Gebiete, die noch gar nicht als Chunk
## geladen sind. Der Spieler sitzt immer in der Mitte, ein Pfeil zeigt seine
## Blickrichtung. Bäume sind dunkle Punkte, der Handbau in echten Kachelfarben.

const WorldGenScript := preload("res://scripts/world_gen.gd")

const CELL_SMALL := 2.6        ## Bildschirm-Pixel je Zelle (kompakt)
const CELL_FULL := 6.0         ## und im Vollbild
const SMALL_SIZE := 200.0      ## Durchmesser der runden Ecke-Karte
const SMALL_MARGIN := 14.0
const FULL_PAD := Vector2(70, 90)   ## Rand des Vollbild-Panels (oben mehr für Titel)

const IDLE_REFRESH := 0.6

## Farben des Rahmens/Panels.
const C_FRAME := Color(0.85, 0.83, 0.72)          # heller Rand
const C_FRAME_DARK := Color(0.10, 0.11, 0.14)     # innerer Absatz
const C_SHADOW := Color(0, 0, 0, 0.45)
const C_BACKDROP := Color(0.03, 0.04, 0.06, 0.88) # Vollbild-Abdunklung
const C_PLAYER := Color(1.0, 0.92, 0.3)
const C_TREE := Color(0.11, 0.20, 0.09)

## Blickrichtung -> Bildschirmvektor (Draufsicht, Norden oben).
const FACE := {
	"north": Vector2(0, -1), "south": Vector2(0, 1),
	"east": Vector2(1, 0), "west": Vector2(-1, 0),
	"north-east": Vector2(1, -1), "north-west": Vector2(-1, -1),
	"south-east": Vector2(1, 1), "south-west": Vector2(-1, 1),
}

@export var world_path: NodePath = ^"../../World"
@export var chunk_manager_path: NodePath = ^"../../ChunkManager"

var world: IsoWorld
var player: Node2D
var gen
var _full := false
var _accum := 0.0
var _pcell := Vector2i(2147483647, 0)


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	if world == null:
		world = get_tree().root.find_child("World", true, false) as IsoWorld
	var cm := get_node_or_null(chunk_manager_path)
	if cm == null:
		cm = get_tree().root.find_child("ChunkManager", true, false)
	var seed_value: int = int(cm.get("world_seed")) if cm != null and cm.get("world_seed") != null else 1337
	gen = WorldGenScript.new(seed_value)

	# Hart skalieren, damit die hochgezogene Terrain-Textur crisp bleibt und
	# nicht verwaschen wirkt.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_full = not _full
		_apply_layout()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if world == null:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	var lvl: int = int(player.get("level")) if player.get("level") != null else 0
	var cell := world.world_to_cell(player.global_position, lvl)
	if cell != _pcell:
		_pcell = cell
		_accum = 0.0
		queue_redraw()
		return
	# Im Stillstand nur selten (fängt gefällte Bäume auf) - Vollbild ist teuer.
	_accum += delta
	if _accum >= IDLE_REFRESH:
		_accum = 0.0
		queue_redraw()


func _apply_layout() -> void:
	if _full:
		# Ganzer Bildschirm, damit der abgedunkelte Hintergrund alles bedeckt.
		anchor_left = 0.0; anchor_top = 0.0; anchor_right = 1.0; anchor_bottom = 1.0
		offset_left = 0.0; offset_top = 0.0; offset_right = 0.0; offset_bottom = 0.0
	else:
		anchor_left = 1.0; anchor_top = 0.0; anchor_right = 1.0; anchor_bottom = 0.0
		offset_left = -SMALL_MARGIN - SMALL_SIZE
		offset_top = SMALL_MARGIN
		offset_right = -SMALL_MARGIN
		offset_bottom = SMALL_MARGIN + SMALL_SIZE


func _draw() -> void:
	if world == null:
		return
	if _full:
		_draw_full()
	else:
		_draw_small()


# --- Kompakte, runde Karte oben rechts ----------------------------------

func _draw_small() -> void:
	var d := SMALL_SIZE
	var c := Vector2(d, d) * 0.5
	var rad := d * 0.5

	# Schlagschatten + dunkler Grund.
	draw_circle(c + Vector2(2, 3), rad, C_SHADOW)
	draw_circle(c, rad, C_FRAME_DARK)

	# Terrain Zelle für Zelle, kreisförmig beschnitten.
	var steps := int(rad / CELL_SMALL) + 1
	var cs := Vector2(CELL_SMALL + 1.0, CELL_SMALL + 1.0)   # leicht überlappen -> keine Fugen
	for dy in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			var off := Vector2(dx, dy) * CELL_SMALL
			if off.length() > rad - CELL_SMALL:
				continue
			var col := _cell_color(_pcell + Vector2i(dx, dy))
			if col.a <= 0.0:
				continue
			draw_rect(Rect2(c + off - cs * 0.5, cs), col)

	# Doppelter Ring als Fassung.
	draw_arc(c, rad - 1.0, 0, TAU, 64, C_FRAME, 3.0, true)
	draw_arc(c, rad - 4.0, 0, TAU, 64, Color(0, 0, 0, 0.5), 1.0, true)

	_draw_player(c, 6.0)
	_draw_north(c + Vector2(0, -rad + 11.0))


# --- Vollbildkarte ------------------------------------------------------

func _draw_full() -> void:
	var rect := size
	draw_rect(Rect2(Vector2.ZERO, rect), C_BACKDROP)

	var panel := Rect2(FULL_PAD, rect - FULL_PAD * 2.0)
	# Panel mit Schatten und Fassung.
	draw_rect(Rect2(panel.position + Vector2(0, 4), panel.size), C_SHADOW)
	draw_rect(panel, C_FRAME_DARK)

	# Terrain Zelle für Zelle, auf das Panel begrenzt.
	var pc := panel.position + panel.size * 0.5
	var sx := int(panel.size.x / CELL_FULL / 2.0) + 1
	var sy := int(panel.size.y / CELL_FULL / 2.0) + 1
	var cs := Vector2(CELL_FULL + 1.0, CELL_FULL + 1.0)
	for dy in range(-sy, sy + 1):
		for dx in range(-sx, sx + 1):
			var col := _cell_color(_pcell + Vector2i(dx, dy))
			if col.a <= 0.0:
				continue
			draw_rect(Rect2(pc + Vector2(dx, dy) * CELL_FULL - cs * 0.5, cs), col)
	draw_rect(panel, C_FRAME, false, 3.0)

	_draw_player(panel.position + panel.size * 0.5, 9.0)

	var font := get_theme_default_font()
	if font != null:
		draw_string(font, Vector2(FULL_PAD.x, FULL_PAD.y - 16.0), "Karte", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_FRAME)
		var hint := "M schliessen    x %d  y %d" % [_pcell.x, _pcell.y]
		draw_string(font, Vector2(rect.x - FULL_PAD.x - 320.0, FULL_PAD.y - 16.0), hint, HORIZONTAL_ALIGNMENT_LEFT, 320, 18, Color(0.7, 0.72, 0.66))
	_draw_north(Vector2(panel.position.x + panel.size.x - 22.0, panel.position.y + 22.0))


## Farbe einer Zelle, transparent wenn dort nichts ist.
func _cell_color(cell: Vector2i) -> Color:
	if world.is_authored(cell):
		var n := world.prop_node(cell)
		if n != null and n.source_id == IsoWorld.PROP_SOURCE_ID:
			return C_TREE
		return world.ground_color(cell)

	if gen.prop_at(cell).get("kind", "") == "tree":
		return C_TREE
	var atlas: Vector2i = gen.ground_atlas(cell)
	var col: Color = world.atlas_color(IsoWorld.SOURCE_ID, atlas)
	if col.a <= 0.0:
		return col
	# Höhe leicht als Helligkeit andeuten, damit Hügel plastisch wirken.
	return col.lightened(0.07 * float(gen.noise_height(cell)))


# --- Marker -------------------------------------------------------------

func _draw_player(c: Vector2, s: float) -> void:
	if player == null:
		return
	var dir: Vector2 = FACE.get(str(player.get("facing")), Vector2(0, 1))
	var ang := dir.normalized().angle()
	var pts := PackedVector2Array([
		c + Vector2(s, 0).rotated(ang),
		c + Vector2(-s * 0.7, s * 0.7).rotated(ang),
		c + Vector2(-s * 0.7, -s * 0.7).rotated(ang),
	])
	draw_colored_polygon(pts, C_PLAYER)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.85), 1.5, true)


func _draw_north(pos: Vector2) -> void:
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, pos - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_FRAME)
