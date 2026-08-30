extends AnimatedSprite2D
class_name Campfire

## Ein gesetzter Ofen (Cooking Campfire, PixelLab). Zeigt "aus" bzw. "brennt"
## je nach Feuer-Status. Das Kochen laeuft server-autoritativ in furnace_sync;
## dieser Node ist nur Anzeige + Anker (seine Zelle = Ofen-Schluessel). Der
## Rechtsklick oeffnet das Ofen-Fenster (siehe interaction/player_inventory).
##
## Frueher hat das Lagerfeuer automatisch Fleisch gekocht - das ist entfernt.

## 68px-Grafik, ca. 2x2 Kacheln gross. Fuss auf die Feldmitte, waagerecht zentriert.
const ART_SCALE := 1.0
## Fuss (opake Unterkante y=56) auf den Node-Ursprung, damit der geworfene
## Schatten am Fuss ansetzt (sonst "schwebt" der Ofen). Mitte x=34.
const ART_OFFSET := Vector2(-34, -56)

@export var art_scale := ART_SCALE

var cell: Vector2i          ## oberste Zelle des 2x2-Feldes (Ofen-Schluessel)
var level: int
var cells: Array[Vector2i] = []
var _lit := false
var _light: PointLight2D
var _embers: CPUParticles2D
var _sync


static func create(p_cell: Vector2i, p_level: int) -> Campfire:
	var c := Campfire.new()
	c.cell = p_cell
	c.level = p_level
	c.sprite_frames = preload("res://resources/campfire_frames.tres")
	c.centered = false
	return c


func _ready() -> void:
	scale = Vector2(art_scale, art_scale)
	offset = ART_OFFSET
	var sh := CastShadow.create(self)
	sh.extra_alpha = 0.7
	add_child(sh)
	_build_light()
	_build_embers()
	_set_lit(false)
	# Ofen-Sync: Feuer an/aus + Anfangszustand vom Server holen.
	_sync = get_tree().get_first_node_in_group("furnace_sync")
	if _sync != null and _sync.has_signal("furnace_updated"):
		_sync.furnace_updated.connect(_on_furnace_updated)
		_sync.request(cell)


func _on_furnace_updated(p_cell: Vector2i, state: Dictionary) -> void:
	if p_cell != cell:
		return
	_set_lit(bool(state.get("lit", false)))


func _set_lit(lit: bool) -> void:
	_lit = lit
	play("brennt" if lit else "aus")
	if _light:
		_light.visible = lit
	if _embers:
		_embers.emitting = lit


## Kompatibilitaets-Stubs (frueheres Fleisch-Kochen wurde entfernt).
func is_ready() -> bool:
	return false


func collect() -> bool:
	return false


func _build_light() -> void:
	_light = PointLight2D.new()
	_light.texture = preload("res://resources/light_gradient.tres")
	_light.color = Color(1, 0.66, 0.30)
	_light.energy = 0.9
	_light.texture_scale = 2.0
	_light.position = Vector2(0, -20)      # Flammenmitte unterm Topf
	_light.set_script(preload("res://scripts/flicker_light.gd"))
	_light.base_energy = 0.9
	_light.flicker_amount = 0.26
	_light.flicker_speed = 9.0
	_light.visible = false
	add_child(_light)


func _build_embers() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_embers = CPUParticles2D.new()
	_embers.texture = ImageTexture.create_from_image(img)
	_embers.amount = 12
	_embers.lifetime = 1.4
	_embers.position = Vector2(0, -14)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 18.0
	_embers.initial_velocity_min = 12.0
	_embers.initial_velocity_max = 30.0
	_embers.gravity = Vector2(0, -6)
	_embers.scale_amount_min = 0.6
	_embers.scale_amount_max = 1.3
	_embers.color = Color(1, 0.62, 0.22, 0.9)
	_embers.z_index = 1
	_embers.emitting = false
	add_child(_embers)
