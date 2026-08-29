extends Sprite2D

## Magier-Haus in Spawn-Naehe. Naehert sich der Spieler, tritt ein Magier heraus
## (mage.gd) und beschiesst ihn. Stirbt der Magier, kommt nach RESPAWN ein neuer.
## Rein lokal (pro Client). Die "Tuer auf"-Animation ist angedeutet (der Magier
## blendet aus der Tuer heraus) - PixelLab liefert kein eigenes Offen-Tuer-Bild.
##
## KEIN class_name (Auto-Updater) - per preload einbinden.

const MageScript := preload("res://scripts/mage.gd")

## 136er-Bild: waagerecht mittig, Fuss knapp unter die Zellmitte.
const ART_OFFSET := Vector2(-68, -104)
const TRIGGER := 190.0            ## Spieler naeher -> Magier kommt heraus
const RESPAWN := 12.0             ## Sekunden bis ein neuer Magier kommt

var world = null
var player = null
var cell: Vector2i
var level: int
var cells: Array[Vector2i] = []
var _mage = null
var _respawn_cd := 0.0


static func create(p_world, p_player, p_cell: Vector2i):
	var h = new()
	h.world = p_world
	h.player = p_player
	h.cell = p_cell
	return h


func _ready() -> void:
	texture = load("res://assets/game_assets/enemies/mage_house.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	offset = ART_OFFSET
	z_index = IsoWorld.TALL_Z_INDEX
	level = maxi(world.top_level_at(cell), 0)
	global_position = world.cell_to_world(cell, level)
	# Ein kleines Feld unter dem Haus sperren, damit man nicht hindurchlaeuft.
	cells = world.footprint_2x2(cell)
	for c in cells:
		world.block_cell(c, self)


func _exit_tree() -> void:
	for c in cells:
		if world != null:
			world.unblock_cell(c)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if _mage != null and is_instance_valid(_mage):
		return
	_mage = null
	if _respawn_cd > 0.0:
		_respawn_cd -= delta
		return
	if global_position.distance_to(player.global_position) <= TRIGGER:
		_spawn_mage()


func _spawn_mage() -> void:
	var door := global_position + Vector2(0, 26)   # vorn an der Tuer (Fuss des Hauses)
	_mage = MageScript.create(world, player, door)
	get_parent().add_child(_mage)
	_mage.died.connect(func(): _respawn_cd = RESPAWN)
