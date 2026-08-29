extends Sprite2D
class_name TerrainOcclusion

## Zeichnet Terrain, das HÖHER ist und VOR einem Möbel liegt, über dessen
## Silhouette - so verdeckt eine Stufe vor einem Bett dieses korrekt, ohne die
## globale Sortierung (Props über Terrain) anzutasten.
##
## Warum überhaupt: Alle Props (Bäume, Möbel, Jack) hängen bewusst in einem
## y-sortierten Container über dem Terrain (z_index 16), damit nichts hinter
## Terrain verschwindet. Der Preis war: eine höhere Kachel VOR einem Prop
## verdeckte ihn nicht. Statt die globale Sortierung umzuwerfen, ziehen wir
## hier die betreffenden Kacheln nach - aber NUR über dem Möbel.
##
## Aufbau: Dieser Node ist eine unsichtbare Kopie des Möbel-Sprites und dient
## über `clip_children` NUR als Maske. Sein Kind zeichnet die Terrain-Kacheln,
## die dadurch ausschließlich auf den Möbel-Pixeln erscheinen - nie auf einem
## Baum, der zufällig davor oder dahinter steht. Der Schatten bleibt Kind des
## Möbels und unberührt.

## Anker der 32x32-Kachel relativ zum Diamant-Mittelpunkt (cell_to_world):
## der Top-Diamant füllt die obere Hälfte, sein Mittelpunkt liegt auf y=8.
const TILE_TOPLEFT := Vector2(-16, -8)
## Wie weit nach vorne/zur Seite nach verdeckenden Kacheln gesucht wird.
const AHEAD := 4

var world: IsoWorld
var source: Sprite2D          ## das Möbel (Maske + Fußpunkt)
var get_cells: Callable

var _atlas: TileSetAtlasSource
var _tex: Texture2D
var _occ: Array = []          ## [ [Vector2 welt_pos, Rect2 region], ... ]
var _redraw: _Redraw


static func create(p_world: IsoWorld, p_source: Sprite2D, p_get_cells: Callable) -> TerrainOcclusion:
	var t := TerrainOcclusion.new()
	t.world = p_world
	t.source = p_source
	t.get_cells = p_get_cells
	return t


func _ready() -> void:
	# Maske = exakte Kopie des Möbel-Sprites (Textur, Anker, Skalierung,
	# Spiegelung, Position). clip_children macht sie unsichtbar und nutzt ihre
	# Deckkraft als Schablone für das Kind.
	texture = source.texture
	centered = source.centered
	offset = source.offset
	scale = source.scale
	flip_h = source.flip_h
	global_position = source.global_position
	z_index = 1                       # knapp über dem Möbel (Props-Container trägt z16)
	clip_children = CLIP_CHILDREN_ONLY

	var ts := world.tile_set_res
	if ts != null:
		_atlas = ts.get_source(IsoWorld.SOURCE_ID) as TileSetAtlasSource
		if _atlas != null:
			_tex = _atlas.texture

	_redraw = _Redraw.new()
	_redraw.occ = self
	add_child(_redraw)
	_rebuild()


## Sucht Kacheln, die höher als das Möbel und vor ihm liegen.
func _rebuild() -> void:
	if not is_instance_valid(source) or _atlas == null:
		return
	var cells: Array = get_cells.call()
	if cells.is_empty():
		return
	var base_level: int = world.top_level_at(cells[0])
	var foot_y := source.global_position.y

	var seen := {}
	var found: Array = []
	for c in cells:
		for dy in range(-1, AHEAD):
			for dx in range(-AHEAD, AHEAD + 1):
				var cell := Vector2i(c.x + dx, c.y + dy)
				if seen.has(cell):
					continue
				seen[cell] = true
				_collect(cell, base_level, foot_y, found)
	_occ = found
	if _redraw != null:
		_redraw.queue_redraw()


## Liegt die Zelle vor dem Möbel (auf dessen Ebene projiziert weiter unten)
## und ist sie höher? Dann alle Blöcke oberhalb der Möbel-Ebene vormerken.
func _collect(cell: Vector2i, base_level: int, foot_y: float, out: Array) -> void:
	var top: int = world.top_level_at(cell)
	if top <= base_level:
		return
	if world.cell_to_world(cell, base_level).y <= foot_y:
		return
	for m in range(base_level + 1, top + 1):
		var atlas := world.layer(m).get_cell_atlas_coords(cell)
		if atlas == Vector2i(-1, -1):
			continue
		out.append([world.cell_to_world(cell, m) + TILE_TOPLEFT,
			_atlas.get_tile_texture_region(atlas)])


## Das Kind: zeichnet die Kacheln, geклippt auf die Maske (den Elternsprite).
class _Redraw extends Node2D:
	var occ: TerrainOcclusion

	func _draw() -> void:
		if occ == null or occ._tex == null:
			return
		# Weltkoordinaten in den (skalierten) lokalen Raum der Maske umrechnen,
		# damit die Kacheln nach dem Zurückskalieren wieder pixelgenau auf dem
		# echten Terrain liegen.
		var inv := occ.global_transform.affine_inverse()
		for entry in occ._occ:
			var pos: Vector2 = entry[0]
			var region: Rect2 = entry[1]
			draw_texture_rect_region(occ._tex,
				Rect2(inv * pos, inv.basis_xform(region.size)), region)
