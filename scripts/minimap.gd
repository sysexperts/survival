extends Control
class_name Minimap

## Übersichtskarte oben rechts, mit M auf Vollbild umschaltbar, mit Wegpunkten.
##
## Draufsicht, der Spieler immer in der Mitte, ein Pfeil zeigt die Blickrichtung.
## Weil die Welt deterministisch generiert wird (WorldGen), zeigt die Karte auch
## noch nicht geladene Gebiete.
##
## Das Terrain wird als Textur zwischengespeichert und nur bei einem Zellwechsel
## neu gebaut - sonst würde jeder Frame tausende Einzelkacheln zeichnen und beim
## Laufen ruckeln. Zellfarben sind zusätzlich gecacht.
##
## Wegpunkte: im Vollbild Linksklick setzen (Name + Farbe), Rechtsklick löschen.
## Sie bleiben am Kartenrand kleben, wenn sie außerhalb liegen (zeigen also die
## Richtung), mit Entfernungsangabe. Gespeichert in user://.

const WorldGenScript := preload("res://scripts/world_gen.gd")

const CELL_SMALL := 2.6
const CELL_FULL := 6.0
const SMALL_SIZE := 200.0
const SMALL_MARGIN := 14.0
const FULL_PAD := Vector2(70, 90)

const IDLE_REFRESH := 0.6
const WP_FILE := "user://waypoints.json"
const METERS_PER_CELL := 1.0     ## Umrechnung Zellen -> "Meter" für die Anzeige

const C_FRAME := Color(0.85, 0.83, 0.72)
const C_FRAME_DARK := Color(0.10, 0.11, 0.14)
const C_SHADOW := Color(0, 0, 0, 0.45)
const C_BACKDROP := Color(0.03, 0.04, 0.06, 0.88)
const C_PLAYER := Color(1.0, 0.92, 0.3)
const C_TREE := Color(0.11, 0.20, 0.09)

const SWATCHES: Array[Color] = [
	Color(0.95, 0.30, 0.28), Color(0.98, 0.62, 0.20), Color(0.96, 0.86, 0.30),
	Color(0.45, 0.82, 0.38), Color(0.35, 0.72, 0.95), Color(0.55, 0.45, 0.90),
	Color(0.95, 0.55, 0.80), Color(0.95, 0.96, 0.98),
]

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
var _color_cache: Dictionary = {}

var _terrain_tex: ImageTexture
var _tex_cols := 0
var _tex_rows := 0
var _dirty := true

var _waypoints: Array = []

var _editor: Panel
var _name_edit: LineEdit
var _edit_color: Color = SWATCHES[0]
var _pending_cell: Vector2i
var _swatches: Array = []


func _ready() -> void:
	world = get_node_or_null(world_path) as IsoWorld
	if world == null:
		world = get_tree().root.find_child("World", true, false) as IsoWorld
	var cm := get_node_or_null(chunk_manager_path)
	if cm == null:
		cm = get_tree().root.find_child("ChunkManager", true, false)
	var seed_value: int = int(cm.get("world_seed")) if cm != null and cm.get("world_seed") != null else 1337
	gen = WorldGenScript.new(seed_value)

	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_editor()
	_load_waypoints()
	_apply_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_full = not _full
		if not _full:
			_editor.visible = false
		_dirty = true
		_apply_layout()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not _full or _editor.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_open_editor(_cell_at(event.position))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_remove_waypoint_near(event.position)
			accept_event()


func _process(delta: float) -> void:
	if world == null:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
		_connect_player()
	var lvl: int = int(player.get("level")) if player.get("level") != null else 0
	var cell := world.world_to_cell(player.global_position, lvl)
	if cell != _pcell or _dirty:
		_pcell = cell
		_dirty = false
		_rebuild_terrain()
		_accum = 0.0
		queue_redraw()
		return
	_accum += delta
	if _accum >= IDLE_REFRESH:
		_accum = 0.0
		queue_redraw()


func _connect_player() -> void:
	if player.has_signal("felled"):
		player.felled.connect(func(c, _l, _a): _invalidate(c))
	if player.has_signal("stump_cleared"):
		player.stump_cleared.connect(func(c): _invalidate(c))
	if player.has_signal("stone_collected"):
		player.stone_collected.connect(func(c, _l, _g): _invalidate(c))


func _invalidate(cell: Vector2i) -> void:
	_color_cache.erase(cell)
	_dirty = true


func _apply_layout() -> void:
	if _full:
		anchor_left = 0.0; anchor_top = 0.0; anchor_right = 1.0; anchor_bottom = 1.0
		offset_left = 0.0; offset_top = 0.0; offset_right = 0.0; offset_bottom = 0.0
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		anchor_left = 1.0; anchor_top = 0.0; anchor_right = 1.0; anchor_bottom = 0.0
		offset_left = -SMALL_MARGIN - SMALL_SIZE
		offset_top = SMALL_MARGIN
		offset_right = -SMALL_MARGIN
		offset_bottom = SMALL_MARGIN + SMALL_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- Terrain-Textur (nur bei Zellwechsel neu) ---------------------------

func _cell_px() -> float:
	return CELL_FULL if _full else CELL_SMALL


func _rebuild_terrain() -> void:
	var cell_px := _cell_px()
	var cols: int
	var rows: int
	var circular := not _full
	if _full:
		var panel := _panel_rect()
		cols = maxi(1, int(panel.size.x / cell_px)) | 1
		rows = maxi(1, int(panel.size.y / cell_px)) | 1
	else:
		cols = maxi(1, int(SMALL_SIZE / cell_px)) | 1
		rows = cols
	var img := Image.create_empty(cols, rows, false, Image.FORMAT_RGBA8)
	var hx := cols >> 1
	var hy := rows >> 1
	var rad := float(mini(hx, hy))
	for iy in rows:
		for ix in cols:
			var col := _cell_color(_pcell + Vector2i(ix - hx, iy - hy))
			if circular and Vector2(ix - hx, iy - hy).length() > rad:
				col = Color(0, 0, 0, 0)
			img.set_pixel(ix, iy, col)
	_terrain_tex = ImageTexture.create_from_image(img)
	_tex_cols = cols
	_tex_rows = rows


# --- Zeichnen -----------------------------------------------------------

func _draw() -> void:
	if world == null:
		return
	if _full:
		_draw_full()
	else:
		_draw_small()


func _draw_small() -> void:
	var d := SMALL_SIZE
	var c := Vector2(d, d) * 0.5
	var rad := d * 0.5

	draw_circle(c + Vector2(2, 3), rad, C_SHADOW)
	draw_circle(c, rad, C_FRAME_DARK)

	if _terrain_tex != null:
		var sz := Vector2(_tex_cols, _tex_rows) * CELL_SMALL
		draw_texture_rect(_terrain_tex, Rect2(c - sz * 0.5, sz), false)

	var font := get_theme_default_font()
	for w in _waypoints:
		var off: Vector2 = Vector2(w["cell"] - _pcell) * CELL_SMALL
		var maxr := rad - 8.0
		var clamped := off.length() > maxr
		if clamped:
			off = off.normalized() * maxr
		_draw_pin(c + off, 4.0, w["color"])
		if clamped and font != null:
			var m := int(round(Vector2(w["cell"] - _pcell).length() * METERS_PER_CELL))
			_label(font, c + off + Vector2(6, 4), "%dm" % m, 11, w["color"])

	draw_arc(c, rad - 1.0, 0, TAU, 64, C_FRAME, 3.0, true)
	draw_arc(c, rad - 4.0, 0, TAU, 64, Color(0, 0, 0, 0.5), 1.0, true)

	_draw_player(c, 6.0)
	_draw_north(c + Vector2(0, -rad + 11.0))


func _draw_full() -> void:
	var rect := size
	draw_rect(Rect2(Vector2.ZERO, rect), C_BACKDROP)

	var panel := _panel_rect()
	draw_rect(Rect2(panel.position + Vector2(0, 4), panel.size), C_SHADOW)
	draw_rect(panel, C_FRAME_DARK)

	var pc := panel.position + panel.size * 0.5
	if _terrain_tex != null:
		var sz := Vector2(_tex_cols, _tex_rows) * CELL_FULL
		draw_texture_rect(_terrain_tex, Rect2(pc - sz * 0.5, sz), false)

	var font := get_theme_default_font()
	var margin := 12.0
	for w in _waypoints:
		var p: Vector2 = pc + Vector2(w["cell"] - _pcell) * CELL_FULL
		var inside := panel.has_point(p)
		if not inside:
			p.x = clampf(p.x, panel.position.x + margin, panel.position.x + panel.size.x - margin)
			p.y = clampf(p.y, panel.position.y + margin, panel.position.y + panel.size.y - margin)
		_draw_pin(p, 6.0, w["color"])
		if font != null:
			var m := int(round(Vector2(w["cell"] - _pcell).length() * METERS_PER_CELL))
			_label(font, p + Vector2(9, 5), "%s  %dm" % [w["name"], m], 16, w["color"])

	draw_rect(panel, C_FRAME, false, 3.0)
	_draw_player(pc, 9.0)

	if font != null:
		_label(font, Vector2(FULL_PAD.x, FULL_PAD.y - 16.0), "Karte", 28, C_FRAME)
		var hint := "Linksklick: Wegpunkt   Rechtsklick: löschen   M: schliessen    x %d  y %d" % [_pcell.x, _pcell.y]
		_label(font, Vector2(FULL_PAD.x, rect.y - FULL_PAD.y + 26.0), hint, 16, Color(0.72, 0.74, 0.68))
	_draw_north(Vector2(panel.position.x + panel.size.x - 22.0, panel.position.y + 22.0))


func _label(font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_pin(p: Vector2, r: float, col: Color) -> void:
	draw_circle(p, r + 1.5, Color(0, 0, 0, 0.85))
	draw_circle(p, r, col)


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
		_label(font, pos - Vector2(5, -5), "N", 16, C_FRAME)


# --- Zellfarben (gecacht) -----------------------------------------------

func _cell_color(cell: Vector2i) -> Color:
	if world.is_authored(cell):
		var n := world.prop_node(cell)
		if n != null and n.source_id == IsoWorld.PROP_SOURCE_ID:
			return C_TREE
		return world.ground_color(cell)

	var cached = _color_cache.get(cell)
	if cached != null:
		return cached
	var col := _gen_color(cell)
	if _color_cache.size() > 80000:
		_color_cache.clear()
	_color_cache[cell] = col
	return col


func _gen_color(cell: Vector2i) -> Color:
	if gen.prop_at(cell).get("kind", "") == "tree":
		return C_TREE
	var atlas: Vector2i = gen.ground_atlas(cell)
	var col: Color = world.atlas_color(IsoWorld.SOURCE_ID, atlas)
	if col.a <= 0.0:
		return col
	return col.lightened(0.07 * float(gen.noise_height(cell)))


# --- Wegpunkte ----------------------------------------------------------

func _panel_rect() -> Rect2:
	return Rect2(FULL_PAD, size - FULL_PAD * 2.0)


func _cell_at(pos: Vector2) -> Vector2i:
	var panel := _panel_rect()
	var pc := panel.position + panel.size * 0.5
	return _pcell + Vector2i(roundi((pos.x - pc.x) / CELL_FULL), roundi((pos.y - pc.y) / CELL_FULL))


func _remove_waypoint_near(pos: Vector2) -> void:
	var panel := _panel_rect()
	var pc := panel.position + panel.size * 0.5
	for i in range(_waypoints.size() - 1, -1, -1):
		var p: Vector2 = pc + Vector2(_waypoints[i]["cell"] - _pcell) * CELL_FULL
		p.x = clampf(p.x, panel.position.x + 12.0, panel.position.x + panel.size.x - 12.0)
		p.y = clampf(p.y, panel.position.y + 12.0, panel.position.y + panel.size.y - 12.0)
		if p.distance_to(pos) <= 12.0:
			_waypoints.remove_at(i)
			_save_waypoints()
			queue_redraw()
			return


func _open_editor(cell: Vector2i) -> void:
	_pending_cell = cell
	_name_edit.text = "Wegpunkt %d" % (_waypoints.size() + 1)
	_select_color(SWATCHES[0], _swatches[0][0])
	_editor.position = (size - _editor.size) * 0.5
	_editor.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func _confirm_wp() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm == "":
		nm = "Wegpunkt"
	_waypoints.append({"cell": _pending_cell, "name": nm, "color": _edit_color})
	_editor.visible = false
	_save_waypoints()
	queue_redraw()


func _select_color(col: Color, btn: Button) -> void:
	_edit_color = col
	for entry in _swatches:
		var sb: StyleBoxFlat = entry[2]
		sb.set_border_width_all(3 if entry[0] == btn else 0)
		sb.border_color = Color(1, 1, 1)


func _build_editor() -> void:
	_editor = Panel.new()
	_editor.size = Vector2(360, 200)
	_editor.custom_minimum_size = _editor.size
	_editor.visible = false
	add_child(_editor)

	var vb := VBoxContainer.new()
	vb.position = Vector2(16, 14)
	vb.custom_minimum_size = Vector2(328, 0)
	vb.add_theme_constant_override("separation", 10)
	_editor.add_child(vb)

	var title := Label.new()
	title.text = "Wegpunkt setzen"
	vb.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(328, 0)
	_name_edit.text_submitted.connect(func(_t): _confirm_wp())
	vb.add_child(_name_edit)

	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 6)
	vb.add_child(sw)
	for col in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 26)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(3)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_select_color.bind(col, b))
		sw.add_child(b)
		_swatches.append([b, col, sb])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var ok := Button.new()
	ok.text = "Setzen"
	ok.custom_minimum_size = Vector2(150, 0)
	ok.pressed.connect(_confirm_wp)
	row.add_child(ok)
	var cancel := Button.new()
	cancel.text = "Abbrechen"
	cancel.custom_minimum_size = Vector2(150, 0)
	cancel.pressed.connect(func(): _editor.visible = false)
	row.add_child(cancel)


# --- Speichern / Laden --------------------------------------------------

func _save_waypoints() -> void:
	var arr: Array = []
	for w in _waypoints:
		var col: Color = w["color"]
		arr.append({
			"x": w["cell"].x, "y": w["cell"].y, "name": w["name"],
			"color": [col.r, col.g, col.b],
		})
	var f := FileAccess.open(WP_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(arr))
		f.close()


func _load_waypoints() -> void:
	if not FileAccess.file_exists(WP_FILE):
		return
	var f := FileAccess.open(WP_FILE, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_ARRAY:
		return
	for e in data:
		var col: Array = e.get("color", [1, 1, 1])
		_waypoints.append({
			"cell": Vector2i(int(e["x"]), int(e["y"])),
			"name": str(e.get("name", "Wegpunkt")),
			"color": Color(col[0], col[1], col[2]),
		})
