extends Sprite2D
class_name CastShadow

## Geworfener Schatten eines Sprites.
##
## Statt Godots 2D-Schattensystem (das Occluder-Polygone braucht und im
## Bildschirmraum arbeitet) wird die Grafik selbst ein zweites Mal
## gezeichnet: schwarz, am Fusspunkt verankert und passend zum Sonnenstand
## geschert und gestreckt.
##
## Die Scherung bildet ab, was physikalisch passiert: ein Punkt in Hoehe h
## ueber dem Boden landet im Schatten bei fuss + richtung * h * laenge.
## Als Transform2D heisst das: die x-Achse bleibt, die y-Achse wird auf
## -richtung * laenge gelegt.

## Zeichnet unter allen Props, aber ueber dem Boden.
const Z_BELOW_PROPS := -1

@export var extra_alpha := 1.0

var source: Node2D                 ## Sprite2D oder AnimatedSprite2D
var _day: Node


static func create(p_source: Node2D) -> CastShadow:
	var sh := CastShadow.new()
	sh.name = "CastShadow"
	sh.source = p_source
	sh.z_index = Z_BELOW_PROPS
	sh.centered = p_source.get("centered")
	sh.offset = p_source.get("offset")
	# Gespiegelte Quelle (z. B. ein gedrehtes Moebel): Godots flip_h kippt das
	# Zeichenrechteck um den Ursprung. Wer das nicht mitmacht, wirft den
	# Schatten daneben - genau um die Sprite-Breite versetzt.
	sh.flip_h = bool(p_source.get("flip_h"))
	return sh


func _ready() -> void:
	_day = get_tree().get_first_node_in_group("day_night")
	light_mask = 0                 # Schatten sollen nicht mitleuchten
	_update(true)


func _process(_delta: float) -> void:
	_update(false)


func _update(force: bool) -> void:
	if not is_instance_valid(source):
		queue_free()
		return
	var strength := 0.0
	var dir := Vector2(-0.9, 0.45)
	var length := 2.0
	if _day != null:
		strength = _day.shadow_strength() * extra_alpha
		dir = _day.shadow_dir()
		length = _day.shadow_length()
	visible = strength > 0.003
	if not visible and not force:
		return
	texture = _source_texture()
	offset = source.get("offset")
	flip_h = bool(source.get("flip_h"))     # dem Moebel folgen, falls es gedreht ist
	modulate = Color(0, 0, 0, strength)
	# Um den FUSS scheren (opake Unterkante), nicht um den Node-Ursprung. Sonst
	# "schweben" Objekte, deren Fuss nicht zufaellig auf y=0 liegt.
	var foot_y := _foot_y_local()
	transform = Transform2D(Vector2(1, 0), -dir * length,
		Vector2(dir.x * length * foot_y, foot_y * (1.0 + dir.y * length)))


## Lokale y-Koordinate des Fusses (opake Unterkante, mittig) im Sprite-Raum -
## inklusive offset/centered. Nur y noetig, weil die Scherung nur von y abhaengt.
func _foot_y_local() -> float:
	if texture == null:
		return 0.0
	var maxy := _foot_tex_y(texture)
	var fy := float(offset.y) + float(maxy)
	if centered:
		fy -= texture.get_size().y * 0.5
	return fy


## Unterste opake Bildzeile einer Textur (Cache je Textur - Frames aendern sich,
## aber jede Textur wird nur einmal gescannt).
static var _foot_cache: Dictionary = {}
static func _foot_tex_y(tex: Texture2D) -> int:
	if _foot_cache.has(tex):
		return _foot_cache[tex]
	var img := tex.get_image()
	var maxy := int(tex.get_size().y)
	if img != null:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		for y in range(img.get_height() - 1, -1, -1):
			var found := false
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a > 0.3:
					found = true
					break
			if found:
				maxy = y
				break
	_foot_cache[tex] = maxy
	return maxy


## Bei AnimatedSprite2D das aktuelle Einzelbild holen, sonst die Textur.
func _source_texture() -> Texture2D:
	if source is AnimatedSprite2D:
		var a: AnimatedSprite2D = source
		if a.sprite_frames == null or not a.sprite_frames.has_animation(a.animation):
			return null
		return a.sprite_frames.get_frame_texture(a.animation, a.frame)
	return source.get("texture")
