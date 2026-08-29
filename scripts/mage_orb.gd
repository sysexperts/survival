extends Node2D

## Blaue Lichtkugel, die der Magier auf den Spieler schiesst. Fliegt geradlinig
## zur Zielposition (Spieler beim Abschuss), leuchtet (PointLight2D, gut sichtbar
## nachts) und macht bei Treffer Schaden.
##
## KEIN class_name (Auto-Updater) - per preload einbinden.

const SPEED := 150.0
const DAMAGE := 8.0
const HIT_DIST := 14.0
const LIFE := 5.0

var _vel := Vector2.ZERO
var _target                       ## Player-Node (Ziel/Trefferpruefung)
var _life := LIFE

static var _glow: Texture2D


## Radiale Glut-Textur (weiss -> transparent), einmal erzeugt.
static func _glow_tex() -> Texture2D:
	if _glow != null:
		return _glow
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_glow = ImageTexture.create_from_image(img)
	return _glow


func setup(from: Vector2, target) -> void:
	global_position = from
	_target = target
	if is_instance_valid(target):
		_vel = (target.global_position - from).normalized() * SPEED
	z_index = IsoWorld.TALL_Z_INDEX + 3


func _ready() -> void:
	var light := PointLight2D.new()
	light.texture = _glow_tex()
	light.color = Color(0.4, 0.7, 1.0)
	light.energy = 1.6
	light.texture_scale = 1.6
	add_child(light)


func _draw() -> void:
	# Heller Kern + weicher Hof, additiv wirkend durch helle Farben.
	draw_circle(Vector2.ZERO, 7.0, Color(0.35, 0.6, 1.0, 0.35))
	draw_circle(Vector2.ZERO, 4.0, Color(0.6, 0.85, 1.0, 0.9))
	draw_circle(Vector2.ZERO, 2.0, Color(0.9, 0.97, 1.0, 1.0))


func _process(delta: float) -> void:
	global_position += _vel * delta
	_life -= delta
	if not is_instance_valid(_target) or _life <= 0.0:
		queue_free()
		return
	if global_position.distance_to(_target.global_position) <= HIT_DIST:
		if _target.has_method("take_damage"):
			_target.take_damage(DAMAGE)
		queue_free()
