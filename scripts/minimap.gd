extends Control
class_name Minimap

## Übersichtskarte oben rechts, mit M auf Vollbild umschaltbar.
##
## Gezeichnet wird eine Draufsicht: pro Zelle ein Punkt in der Farbe der
## obersten Kachel, der Spieler immer in der Mitte. Weil die Welt
## deterministisch generiert wird (WorldGen), kann die Karte auch Gebiete
## zeigen, die noch gar nicht als Chunk geladen sind - für die Vollbildkarte
## ist das entscheidend, sonst sähe man nur den kleinen geladenen Ring.
##
## Bäume werden als dunkle Punkte markiert, der gemalte Handbau-Bereich in
## seinen echten Kachelfarben.

const WorldGenScript := preload("res://scripts/world_gen.gd")

## Pixel pro Zelle - klein kompakt, Vollbild größer (grobe Zoomstufen).
const CELL_SMALL := 2.0
const CELL_FULL := 5.0
const SMALL_SIZE := Vector2(196, 196)
const SMALL_MARGIN := 12.0
const FULL_MARGIN := 48.0

## Im Stillstand nur selten neu zeichnen (fängt gefällte Bäume o. Ä. auf);
## bei Bewegung wird sofort neu gezeichnet.
const IDLE_REFRESH := 0.6

@export var world_path: NodePath = ^"../../World"
@export var chunk_manager_path: NodePath = ^"../../ChunkManager"

var world: IsoWorld
var player: Node2D
var gen                          ## eigene WorldGen-Instanz, gleicher Seed wie der ChunkManager
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

	clip_contents = true
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
	# Bei Stillstand nur gelegentlich - die Vollbildkarte ist sonst teuer.
	_accum += delta
	if _accum >= IDLE_REFRESH:
		_accum = 0.0
		queue_redraw()


func _apply_layout() -> void:
	if _full:
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 1.0
		offset_left = FULL_MARGIN
		offset_top = FULL_MARGIN
		offset_right = -FULL_MARGIN
		offset_bottom = -FULL_MARGIN
	else:
		anchor_left = 1.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 0.0
		offset_left = -SMALL_MARGIN - SMALL_SIZE.x
		offset_top = SMALL_MARGIN
		offset_right = -SMALL_MARGIN
		offset_bottom = SMALL_MARGIN + SMALL_SIZE.y


func _draw() -> void:
	if world == null:
		return
	var rect := size
	var cell_px := CELL_FULL if _full else CELL_SMALL
	var bg := Color(0.05, 0.06, 0.09, 0.9 if _full else 0.55)
	draw_rect(Rect2(Vector2.ZERO, rect), bg)

	var center := rect * 0.5
	var rx := int(rect.x / cell_px / 2.0) + 1
	var ry := int(rect.y / cell_px / 2.0) + 1
	var half := Vector2(cell_px, cell_px) * 0.5
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			var col := _cell_color(_pcell + Vector2i(dx, dy))
			if col.a <= 0.0:
				continue
			var p := center + Vector2(dx, dy) * cell_px
			draw_rect(Rect2(p - half, Vector2(cell_px, cell_px)), col)

	# Spieler: klar erkennbarer Punkt in der Mitte.
	var pr := maxf(3.0, cell_px)
	draw_circle(center, pr + 1.0, Color(0, 0, 0, 0.9))
	draw_circle(center, pr, Color(1.0, 0.95, 0.35))

	# Rahmen
	draw_rect(Rect2(Vector2.ZERO, rect), Color(0, 0, 0, 0.85), false, 2.0)


## Farbe einer Zelle für die Karte, transparent wenn dort nichts ist.
func _cell_color(cell: Vector2i) -> Color:
	if world.is_authored(cell):
		# Bäume/Props im Handbau markieren; sonst echte Kachelfarbe.
		var n := world.prop_node(cell)
		if n != null and n.source_id == IsoWorld.PROP_SOURCE_ID:
			return Color(0.12, 0.22, 0.10)
		return world.ground_color(cell)

	# Generiertes Gebiet: deterministisch aus dem WorldGen ableiten - auch für
	# noch nicht geladene Chunks, damit die Vollbildkarte weit reicht.
	if gen.prop_at(cell).get("kind", "") == "tree":
		return Color(0.12, 0.22, 0.10)
	var atlas: Vector2i = gen.ground_atlas(cell)
	var col: Color = world.atlas_color(IsoWorld.SOURCE_ID, atlas)
	if col.a <= 0.0:
		return col
	# Höhe leicht als Helligkeit andeuten, damit Hügel sichtbar werden.
	var h: int = gen.noise_height(cell)
	return col.lightened(0.06 * float(h))
