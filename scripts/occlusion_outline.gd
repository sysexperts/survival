extends AnimatedSprite2D
class_name OcclusionOutline

## Weisser Umriss der Figur, sobald ein Prop sie verdeckt.
##
## Spiegelt Bild für Bild die Animation des Spieler-Sprites und zeichnet sie
## mit `fill_alpha = 0` - also nur den Rand - über allem anderen. Dadurch
## sieht man durch einen Baum hindurch, wo Jack steht.
##
## Wird von `player.gd` zur Laufzeit erzeugt, damit die Spielerszene dafür
## nicht angefasst werden muss.

## z_index über dem Props-Container, damit der Rand nie verdeckt wird.
const OVER_PROPS_Z := 50

@export var color := Color(1, 1, 1, 0.85)
## Wie weit der Körper für den Verdeckungstest eingeschnürt wird. Der
## 48x48-Frame ist grösstenteils leer; ohne das Einschnüren würde schon ein
## Baum weit daneben als "verdeckend" gelten.
@export var core_size := Vector2(20, 38)
## Props weiter weg als das werden gar nicht erst geprüft (Pixel).
@export var check_radius := 90.0
## Wie viel vom Körper mindestens verdeckt sein muss, damit der Umriss
## erscheint. Ohne diese Schwelle genügte schon eine Ecke einer weit
## entfernten Baumkrone, die Jacks Füsse streift.
@export_range(0.0, 1.0) var min_cover := 0.28

var player: Node2D
var source: AnimatedSprite2D
var world: IsoWorld


static func create(p_player: Node2D, p_source: AnimatedSprite2D, p_world: IsoWorld) -> OcclusionOutline:
	var o := OcclusionOutline.new()
	o.name = "OcclusionOutline"
	o.player = p_player
	o.source = p_source
	o.world = p_world
	o.sprite_frames = p_source.sprite_frames
	o.offset = p_source.offset
	o.centered = p_source.centered
	o.z_index = OVER_PROPS_Z
	o.visible = false
	return o


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/outline.gdshader")
	mat.set_shader_parameter("outline_color", color)
	mat.set_shader_parameter("thickness", 1.0)
	mat.set_shader_parameter("fill_alpha", 0.0)     # nur der Rand
	material = mat


func _process(_delta: float) -> void:
	if source == null or world == null:
		return
	var hidden := _is_occluded()
	visible = hidden
	if not hidden:
		return
	# Erst synchronisieren, wenn tatsächlich gezeichnet wird.
	if animation != source.animation:
		animation = source.animation
	set_frame_and_progress(source.frame, source.frame_progress)


## Verdeckt ein Prop die Figur gerade?
##
## Beide hängen im selben y-sortierten Container, deshalb reicht der
## Vergleich der Fusspunkt-Y: was weiter unten steht, wird später gezeichnet
## und liegt damit vorn.
func _is_occluded() -> bool:
	var core := Rect2(player.global_position + offset - core_size * 0.5, core_size)
	var needed := core.get_area() * min_cover
	for entry in world.prop_placements():
		var cell: Vector2i = entry[0]
		var node := world.prop_node(cell)
		if node == null:
			continue
		# Nur Baeume verdecken. Ein Stumpf ist 14 px hoch, sein Tile-Rechteck
		# aber 64 - ohne diesen Filter loeste er den Umriss faelschlich aus.
		if node.source_id != IsoWorld.PROP_SOURCE_ID:
			continue
		if node.global_position.y <= player.global_position.y:
			continue                                  # steht hinter Jack
		if node.global_position.distance_to(player.global_position) > check_radius:
			continue
		# Gegen den tatsaechlich sichtbaren Teil pruefen, nicht gegen das
		# 32x64-Tile-Rechteck - und erst ab spuerbarer Ueberdeckung melden.
		if world.prop_content_rect(cell).intersection(core).get_area() >= needed:
			return true
	return false
