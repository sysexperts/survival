extends PathFollow2D

## Friedlicher Lauf-NPC: geht endlos den Eltern-Pfad (Path2D) ab und spielt je
## nach Laufrichtung die passende Walk-Animation (steht -> Idle). KEIN Angriff,
## kein Verhalten ausser Laufen. Die FORM des Wegs bearbeitet man im Editor am
## Path2D - hier steht bewusst nur das Minimum an Script; die Animation laeuft
## von selbst (AnimatedSprite2D + SpriteFrames).
##
## KEIN class_name (Auto-Updater) - haengt als Node in der Szene.

## Tempo entlang des Pfads (px/s).
@export var speed := 24.0
## Kind-AnimatedSprite2D mit walk_<dir>/idle_<dir>-Animationen.
@export var body_path := NodePath("Body")

const DIR_FILE := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]

var _body: AnimatedSprite2D
var _last := Vector2.ZERO
var _facing := 0

func _ready() -> void:
	loop = true
	rotates = false
	_body = get_node_or_null(body_path) as AnimatedSprite2D
	_last = global_position
	# Der dedizierte Server rendert nichts - dort keine Bewegung simulieren.
	if Net.is_dedicated:
		set_process(false)

func _process(delta: float) -> void:
	progress += speed * delta
	var v := global_position - _last
	_last = global_position
	if _body == null:
		return
	var want: StringName
	if v.length() > 0.4:
		_facing = _dir_index(v)
		want = StringName("walk_" + DIR_FILE[_facing])
	else:
		want = StringName("idle_" + DIR_FILE[_facing])
	if _body.animation != want or not _body.is_playing():
		_body.play(want)

## 0=Sued, im Uhrzeigersinn - wie mage.gd (atan2(x, y*2)).
func _dir_index(v: Vector2) -> int:
	var a := atan2(v.x, v.y * 2.0)
	return posmod(int(round(a / (PI / 4.0))), 8)
