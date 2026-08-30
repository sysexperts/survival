extends PathFollow2D

## Friedlicher Lauf-NPC: geht endlos den Eltern-Pfad (Path2D) ab und zeigt je
## nach Laufrichtung das passende Richtungs-Idle. KEIN Angriff, kein Verhalten
## ausser Laufen. Die FORM des Wegs bearbeitet man im Editor am Path2D - hier
## steht bewusst nur das Minimum an Script.
##
## KEIN class_name (Auto-Updater) - haengt als Node in der Szene.

## Tempo entlang des Pfads (px/s).
@export var speed := 24.0
## Sprite-Satz aus assets/.../mage/ (z. B. "idle").
@export var kind := "idle"
## Kind-Sprite, das umgefaerbt/gedreht wird (relativ zu diesem Node).
@export var body_path := NodePath("Body")

const DIR_FILE := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]
const BASE := "res://assets/game_assets/enemies/mage/"

var _body: Sprite2D
var _last := Vector2.ZERO
var _switch_cd := 0.0

func _ready() -> void:
	loop = true
	rotates = false
	_body = get_node_or_null(body_path) as Sprite2D
	_last = global_position
	# Der dedizierte Server rendert nichts - dort keine Bewegung simulieren.
	if Net.is_dedicated:
		set_process(false)

func _process(delta: float) -> void:
	progress += speed * delta
	var v := global_position - _last
	_last = global_position
	_switch_cd -= delta
	if _body != null and v.length() > 0.4 and _switch_cd <= 0.0:
		_switch_cd = 0.15   # nicht in jedem Frame die Textur wechseln
		_body.texture = load(BASE + kind + "_" + DIR_FILE[_dir_index(v)] + ".png")

## 0=Sued, im Uhrzeigersinn - wie mage.gd (atan2(x, y*2)).
func _dir_index(v: Vector2) -> int:
	var a := atan2(v.x, v.y * 2.0)
	return posmod(int(round(a / (PI / 4.0))), 8)
