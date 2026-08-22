extends Node2D
class_name PlacementPreview

## Vorschau beim Platzieren: das Objekt klebt halbdurchsichtig am Cursor,
## umrandet in Weiss. Passt es an der Stelle nicht, wird der Rand rot.
##
## Der Umriss-Shader kann beides in einem Durchgang: `fill_alpha` regelt
## die Deckkraft des Koerpers, `outline_color` den Rand.
##
## Zwei Sorten teilen sich dieselbe Vorschau:
##   - das Lagerfeuer belegt ein 2x2-Feld (animiertes Sheet),
##   - ein Moebel belegt eine einzelne Zelle (Standbild) und laesst sich
##     spiegeln.
## Was gesetzt werden soll, verraet `kind` dem Empfaenger des `confirmed`.

signal confirmed(top_cell: Vector2i)
## Wird immer gefeuert, wenn die Vorschau endet - gesetzt oder abgebrochen.
signal ended

enum Kind { CAMPFIRE, FURNITURE }

@export var ok_color := Color(1, 1, 1, 0.95)
@export var blocked_color := Color(1, 0.28, 0.28, 0.95)
@export var body_alpha := 0.5

var world: IsoWorld
var active := false
var valid := false
var top_cell := Vector2i.ZERO
var kind := Kind.CAMPFIRE
## Bei Moebeln: welches Item gesetzt wird und ob gespiegelt.
var item_id := ""
var flipped := false
var _long := false                ## Moebel belegt 1x2 statt 1x1

var _anim: AnimatedSprite2D       ## Lagerfeuer
var _still: Sprite2D              ## Moebel
var _mat: ShaderMaterial


func _ready() -> void:
	z_index = IsoWorld.TALL_Z_INDEX + 2      # ueber Props, damit immer sichtbar
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/outline.gdshader")
	_mat.set_shader_parameter("thickness", 1.0)
	_mat.set_shader_parameter("fill_alpha", body_alpha)
	# Beide teilen sich das Material: Rand- und Koerperdeckkraft sind
	# fuer Lagerfeuer und Moebel gleich, es ist ja immer nur eines sichtbar.
	_anim = AnimatedSprite2D.new()
	_anim.material = _mat
	_anim.centered = false
	add_child(_anim)
	_still = Sprite2D.new()
	_still.material = _mat
	_still.centered = false
	add_child(_still)
	visible = false


## Startet die Vorschau fuer ein Lagerfeuer (2x2).
func begin_campfire() -> void:
	kind = Kind.CAMPFIRE
	item_id = "lagerfeuer"
	_anim.sprite_frames = preload("res://resources/campfire_frames.tres")
	_anim.animation = "brennt"
	_anim.play("brennt")
	_anim.offset = Campfire.ART_OFFSET
	_anim.scale = Vector2(Campfire.ART_SCALE, Campfire.ART_SCALE)
	_anim.visible = true
	_still.visible = false
	active = true
	visible = true


## Startet die Vorschau fuer ein Moebel (1x1). `id` ist das Item.
func begin_furniture(id: String) -> void:
	kind = Kind.FURNITURE
	item_id = id
	flipped = false
	_long = Furniture.is_long(id)
	_still.texture = ItemDB.icon(id)
	_still.offset = Furniture.offset_of(id)
	var s := Furniture.scale_of(id)
	_still.scale = Vector2(s, s)
	_still.flip_h = false
	_still.visible = true
	_anim.visible = false
	active = true
	visible = true


## Dreht das Moebel (spiegeln). Beim Lagerfeuer wirkungslos.
func flip() -> void:
	if not active or kind != Kind.FURNITURE:
		return
	flipped = not flipped
	_still.flip_h = flipped


func cancel() -> void:
	if not active:
		return
	active = false
	visible = false
	ended.emit()


func _process(_delta: float) -> void:
	if not active or world == null:
		return
	if kind == Kind.CAMPFIRE:
		_track_campfire()
	else:
		_track_furniture()
	_mat.set_shader_parameter("outline_color", ok_color if valid else blocked_color)


func _track_campfire() -> void:
	# Die Maus soll in der MITTE des 2x2-Feldes liegen, nicht auf dessen
	# oberer Zelle - deshalb vor dem Umrechnen eine halbe Feldhoehe abziehen.
	var probe := get_global_mouse_position() - Vector2(0, 16)
	var hit := world.pick_block(probe)
	var level: int = hit[1] if not hit.is_empty() else 0
	top_cell = world.world_to_cell(probe, level)
	valid = world.can_place_2x2(top_cell)
	var lvl := maxi(world.top_level_at(top_cell), 0)
	global_position = world.footprint_center(top_cell, lvl)


func _track_furniture() -> void:
	var mouse := get_global_mouse_position()
	var hit := world.pick_block(mouse)
	var level: int = hit[1] if not hit.is_empty() else 0
	top_cell = world.world_to_cell(mouse, level)
	var lvl := maxi(world.top_level_at(top_cell), 0)
	if _long:
		valid = world.can_place_long(top_cell)
		global_position = world.footprint_long_center(top_cell, lvl)
	else:
		valid = world.can_place_1x1(top_cell)
		global_position = world.cell_to_world(top_cell, lvl)


## Linksklick: setzen, wenn gueltig. Gibt true zurueck, wenn der Klick
## verbraucht wurde.
func try_confirm() -> bool:
	if not active:
		return false
	if valid:
		confirmed.emit(top_cell)
		cancel()
	return true
