extends Control
class_name Minimap

## Übersichtskarte oben rechts, mit M auf Vollbild, mit Wegpunkten.
##
## Aufbau in drei Ebenen, damit das Terrain WEICH scrollt und trotzdem sauber
## im Kreis (bzw. Panel) beschnitten bleibt:
##   1. dieses Control  - Hintergrund (Schatten, dunkler Grund / Abdunklung)
##   2. _map (clip_children) - zeichnet die Maske (Kreis/Panel); sein Kind
##      _terrain zeichnet die Terrain-Textur und wird auf die Maske beschnitten
##   3. _hud            - Rahmen, Wegpunkte, Spielerpfeil, Norden (immer obenauf)
##
## Die Terrain-Textur wird nur bei einem Zellwechsel neu gebaut (sonst ruckelt
## es). Verschoben wird sie jeden Frame um die Sub-Zellen-Position des Spielers,
## die aus seiner echten Weltposition gelöst wird - dadurch gleitet die Karte
## flüssig statt in Zellsprüngen.

const WorldGenScript := preload("res://scripts/world_gen.gd")

# Ganzzahlig halten: die Terrain-Textur wird mit NEAREST hochskaliert; bei
# einem krummen Faktor (z. B. 2.6) flimmern die Texel beim Scrollen.
const CELL_SMALL := 3.0
const CELL_FULL := 6.0
const SMALL_SIZE := 200.0
const SMALL_MARGIN := 14.0
const FULL_PAD := Vector2(70, 90)
const PAD_CELLS := 4              ## Zusatzrand der Textur, damit beim Scrollen keine Lücke am Rand entsteht

const IDLE_REFRESH := 0.6
const WP_FILE := "user://waypoints.json"
const METERS_PER_CELL := 1.0

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
var _scroll := Vector2.ZERO
var _color_cache: Dictionary = {}

var _terrain_tex: ImageTexture
var _tex_cols := 0
var _tex_rows := 0
var _dirty := true

var _waypoints: Array = []

var _map: Control
var _terrain: Control
var _hud: Control

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

	_map = Control.new()
	_map.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.draw.connect(_on_map_draw)
	add_child(_map)

	_terrain = Control.new()
	_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terrain.draw.connect(_on_terrain_draw)
	_map.add_child(_terrain)

	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.draw.connect(_on_hud_draw)
	add_child(_hud)

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
		_redraw_all()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not _full or _editor.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Wegpunkt entsteht IMMER an der aktuellen Spielerposition, nicht an
			# der angeklickten Stelle - man markiert, wo man gerade steht.
			_open_editor(_pcell)
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
	# Nur arbeiten, wenn die Vollbildkarte offen ist.
	if not _full:
		return
	var lvl: int = int(player.get("level")) if player.get("level") != null else 0
	var cell := world.world_to_cell(player.global_position, lvl)
	if cell != _pcell or _dirty:
		_pcell = cell
		_dirty = false
		_rebuild_terrain()
	# Sub-Zellen-Verschiebung: jeden Frame, damit die Karte weich gleitet.
	_scroll = _compute_scroll(lvl)
	_terrain.queue_redraw()
	_hud.queue_redraw()


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


func _redraw_all() -> void:
	queue_redraw()
	_map.queue_redraw()
	_terrain.queue_redraw()
	_hud.queue_redraw()


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
	# Die Karte gibt es nur noch als Vollbild (mit M). Das kleine Eck-Widget
	# ist raus - dafür zeigt die Kompassleiste die Wegpunkt-Richtungen.
	visible = _full
	_map.queue_redraw()


## Für die Kompassleiste: die aktuelle Wegpunkt-Liste.
func get_waypoints() -> Array:
	return _waypoints


func _cell_px() -> float:
	return CELL_FULL if _full else CELL_SMALL


## Player-Position -> Verschiebung in Minimap-Pixeln relativ zum Mittelpunkt.
## Gelöst über die lokale Zellbasis (ex, ey), damit es auch im halbversetzten
## Stacked-Raster stimmt.
func _compute_scroll(lvl: int) -> Vector2:
	var base := world.cell_to_world(_pcell, lvl)
	var ex := world.cell_to_world(_pcell + Vector2i(1, 0), lvl) - base
	var ey := world.cell_to_world(_pcell + Vector2i(0, 1), lvl) - base
	var det := ex.x * ey.y - ex.y * ey.x
	if absf(det) < 0.0001:
		return Vector2.ZERO
	var dw := player.global_position - base
	var a := (dw.x * ey.y - dw.y * ey.x) / det
	var b := (ex.x * dw.y - ex.y * dw.x) / det
	return Vector2(a, b) * _cell_px()


# --- Terrain-Textur (nur bei Zellwechsel neu) ---------------------------

func _rebuild_terrain() -> void:
	var cell_px := _cell_px()
	var cols: int
	var rows: int
	if _full:
		var panel := _panel_rect()
		cols = maxi(1, int(panel.size.x / cell_px) + PAD_CELLS * 2) | 1
		rows = maxi(1, int(panel.size.y / cell_px) + PAD_CELLS * 2) | 1
	else:
		cols = maxi(1, int(SMALL_SIZE / cell_px) + PAD_CELLS * 2) | 1
		rows = cols
	var img := Image.create_empty(cols, rows, false, Image.FORMAT_RGBA8)
	var hx := cols >> 1
	var hy := rows >> 1
	for iy in rows:
		for ix in cols:
			img.set_pixel(ix, iy, _cell_color(_pcell + Vector2i(ix - hx, iy - hy)))
	_terrain_tex = ImageTexture.create_from_image(img)
	_tex_cols = cols
	_tex_rows = rows


# --- Zeichnen der drei Ebenen -------------------------------------------

func _draw() -> void:
	# Ebene 1: Hintergrund.
	if _full:
		draw_rect(Rect2(Vector2.ZERO, size), C_BACKDROP)
		var panel := _panel_rect()
		draw_rect(Rect2(panel.position + Vector2(0, 4), panel.size), C_SHADOW)
		draw_rect(panel, C_FRAME_DARK)
	else:
		var c := Vector2(SMALL_SIZE, SMALL_SIZE) * 0.5
		draw_circle(c + Vector2(2, 3), SMALL_SIZE * 0.5, C_SHADOW)
		draw_circle(c, SMALL_SIZE * 0.5, C_FRAME_DARK)


func _on_map_draw() -> void:
	# Ebene 2 (Maske): die weiße Form beschneidet das Terrain-Kind.
	if _full:
		_map.draw_rect(_panel_rect(), Color(1, 1, 1))
	else:
		var c := Vector2(SMALL_SIZE, SMALL_SIZE) * 0.5
		_map.draw_circle(c, SMALL_SIZE * 0.5 - 2.0, Color(1, 1, 1))


func _on_terrain_draw() -> void:
	if _terrain_tex == null:
		return
	var cell_px := _cell_px()
	var sz := Vector2(_tex_cols, _tex_rows) * cell_px
	# Auf ganze Pixel runden: NEAREST + Sub-Pixel-Position = Texel-Flimmern.
	var tl := (_map_center() - _scroll - sz * 0.5).round()
	_terrain.draw_texture_rect(_terrain_tex, Rect2(tl, sz), false)


func _on_hud_draw() -> void:
	var font := _hud.get_theme_default_font()
	var center := _map_center()
	if _full:
		var panel := _panel_rect()
		var margin := 12.0
		_hud.draw_rect(panel, C_FRAME, false, 3.0)
		for w in _waypoints:
			var p: Vector2 = center - _scroll + Vector2(w["cell"] - _pcell) * CELL_FULL
			if not panel.has_point(p):
				p.x = clampf(p.x, panel.position.x + margin, panel.position.x + panel.size.x - margin)
				p.y = clampf(p.y, panel.position.y + margin, panel.position.y + panel.size.y - margin)
			_pin(_hud, p, 6.0, w["color"])
			if font != null:
				_label(_hud, font, p + Vector2(9, 5), "%s  %dm" % [w["name"], _meters(w["cell"])], 16, w["color"])
		_player_arrow(_hud, center, 9.0)
		if font != null:
			_label(_hud, font, Vector2(FULL_PAD.x, FULL_PAD.y - 16.0), "Karte", 28, C_FRAME)
			var hint := "Sol tik: Isaret   Sag tik: sil   M: kapat    x %d  y %d" % [_pcell.x, _pcell.y]
			_label(_hud, font, Vector2(FULL_PAD.x, size.y - FULL_PAD.y + 26.0), hint, 16, Color(0.72, 0.74, 0.68))
		_north(_hud, font, Vector2(panel.position.x + panel.size.x - 22.0, panel.position.y + 22.0))
	else:
		var rad := SMALL_SIZE * 0.5
		# Rahmen zuerst, damit die Pins darüber liegen.
		_hud.draw_arc(center, rad - 1.0, 0, TAU, 64, C_FRAME, 3.0, true)
		_hud.draw_arc(center, rad - 4.0, 0, TAU, 64, Color(0, 0, 0, 0.5), 1.0, true)
		for w in _waypoints:
			var off: Vector2 = -_scroll + Vector2(w["cell"] - _pcell) * CELL_SMALL
			var on_ring := off.length() > rad - 6.0
			if on_ring:
				off = off.normalized() * (rad - 2.0)   # genau auf dem Rahmen
			_pin(_hud, center + off, 4.5, w["color"])
			if on_ring and font != null:
				# Text nach außen versetzt, damit er neben dem Rahmen lesbar ist.
				var dir := off.normalized()
				var lp := center + dir * (rad + 6.0)
				if dir.x < -0.3:
					lp.x -= 34.0
				_label(_hud, font, lp + Vector2(0, 4), "%dm" % _meters(w["cell"]), 11, w["color"])
		_player_arrow(_hud, center, 6.0)
		_north(_hud, font, center + Vector2(0, -rad + 11.0))


func _map_center() -> Vector2:
	if _full:
		var panel := _panel_rect()
		return panel.position + panel.size * 0.5
	return Vector2(SMALL_SIZE, SMALL_SIZE) * 0.5


func _meters(cell: Vector2i) -> int:
	return int(round(Vector2(cell - _pcell).length() * METERS_PER_CELL))


func _label(ci: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	ci.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _pin(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(p, r + 1.5, Color(0, 0, 0, 0.85))
	ci.draw_circle(p, r, col)


func _player_arrow(ci: CanvasItem, c: Vector2, s: float) -> void:
	if player == null:
		return
	var dir: Vector2 = FACE.get(str(player.get("facing")), Vector2(0, 1))
	var ang := dir.normalized().angle()
	var pts := PackedVector2Array([
		c + Vector2(s, 0).rotated(ang),
		c + Vector2(-s * 0.7, s * 0.7).rotated(ang),
		c + Vector2(-s * 0.7, -s * 0.7).rotated(ang),
	])
	ci.draw_colored_polygon(pts, C_PLAYER)
	ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.85), 1.5, true)


func _north(ci: CanvasItem, font: Font, pos: Vector2) -> void:
	if font != null:
		_label(ci, font, pos - Vector2(5, -5), "N", 16, C_FRAME)


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
	var center := _map_center() - _scroll
	return _pcell + Vector2i(roundi((pos.x - center.x) / CELL_FULL), roundi((pos.y - center.y) / CELL_FULL))


func _remove_waypoint_near(pos: Vector2) -> void:
	var panel := _panel_rect()
	var center := _map_center() - _scroll
	for i in range(_waypoints.size() - 1, -1, -1):
		var p: Vector2 = center + Vector2(_waypoints[i]["cell"] - _pcell) * CELL_FULL
		p.x = clampf(p.x, panel.position.x + 12.0, panel.position.x + panel.size.x - 12.0)
		p.y = clampf(p.y, panel.position.y + 12.0, panel.position.y + panel.size.y - 12.0)
		if p.distance_to(pos) <= 12.0:
			_waypoints.remove_at(i)
			_save_waypoints()
			_hud.queue_redraw()
			return


func _open_editor(cell: Vector2i) -> void:
	_pending_cell = cell
	_name_edit.text = "Isaret %d" % (_waypoints.size() + 1)
	_select_color(SWATCHES[0], _swatches[0][0])
	_editor.position = (size - _editor.size) * 0.5
	_editor.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func _confirm_wp() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm == "":
		nm = "Isaret"
	_waypoints.append({"cell": _pending_cell, "name": nm, "color": _edit_color})
	_editor.visible = false
	_save_waypoints()
	_hud.queue_redraw()


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
	title.text = "Isaret koy"
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
			"name": str(e.get("name", "Isaret")),
			"color": Color(col[0], col[1], col[2]),
		})
