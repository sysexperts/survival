extends Node2D
class_name RemotePlayer

## Die Figur EINES anderen Spielers auf diesem Bildschirm.
##
## Bewusst leichtgewichtig und getrennt vom echten Player: sie liest keine
## Eingabe, faellt keine Baeume und greift nicht in die Welt ein - sie zeigt
## nur, wo der andere steht und welche Animation er gerade spielt. Alles
## Weitere kommt ueber das Netzwerk von NetGame.
##
## Haengt im y-sortierten Props-Container der Welt, damit sie korrekt zwischen
## Baeumen ein- und ausgeblendet wird.

const FRAMES := preload("res://resources/jack_frames.tres")
## Gleicher Fusspunkt-Versatz wie beim echten Player (siehe player.gd).
const SPRITE_OFFSET := Vector2(0, -18)

var _sprite: AnimatedSprite2D
var _plate: NamePlate


func _ready() -> void:
	z_index = 0

	var shadow := Node2D.new()
	shadow.position = Vector2(0, 1)
	shadow.set_script(preload("res://scripts/blob_shadow.gd"))
	add_child(shadow)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.animation = &"idle_south"
	_sprite.offset = SPRITE_OFFSET
	_sprite.play(&"idle_south")
	add_child(_sprite)

	_plate = NamePlate.new()
	add_child(_plate)


func set_player_name(n: String) -> void:
	if _plate:
		_plate.player_name = n


var _target := Vector2.ZERO
var _has_target := false


## Uebernimmt eine ueber das Netz empfangene Momentaufnahme. Die Position wird
## nur als ZIEL gemerkt und in _process weich angefahren - sonst springt die
## Figur bei 15 Paketen/s sichtbar.
func apply_state(pos: Vector2, anim: StringName, frame: int) -> void:
	if not _has_target:
		global_position = pos        # erstes Paket: direkt hinsetzen
		_has_target = true
	_target = pos
	if _sprite == null:
		return
	if _sprite.animation != anim and FRAMES.has_animation(anim):
		_sprite.play(anim)
	_sprite.frame = frame


func _process(delta: float) -> void:
	if _has_target:
		# Exponentielles Glaetten - unabhaengig von der Bildrate.
		global_position = global_position.lerp(_target, 1.0 - exp(-16.0 * delta))
