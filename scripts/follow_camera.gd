extends Camera2D

## Folgt Jack weich. Der Zoom ist fest (in der Szene gesetzt) - das Mausrad
## blaettert stattdessen durch die Hotbar (siehe player_inventory.gd).

@export var target_path: NodePath = ^"../Player"
@export var smoothing := 8.0

var target: Node2D
var _shake := 0.0          ## aktuelle Stärke in Pixeln
var _shake_decay := 1.0


func _ready() -> void:
	target = get_node_or_null(target_path) as Node2D
	if target:
		global_position = target.global_position


## Ab hier ist die Kamera "angekommen": statt weiter in Sub-Pixel-Schritten
## ans Ziel zu kriechen (was bei Nearest-Filter das ganze Bild flackern laesst),
## rastet sie exakt ein und steht still, bis sich das Ziel wieder bewegt.
const SETTLE_DIST := 0.5


func _process(delta: float) -> void:
	if target:
		var to := target.global_position
		if global_position.distance_to(to) <= SETTLE_DIST:
			global_position = to
		else:
			global_position = global_position.lerp(
				to, 1.0 - exp(-smoothing * delta))
	# Ruetteln liegt auf offset, damit es dem Folgen nicht in die Quere kommt.
	if _shake > 0.0:
		_shake = maxf(_shake - _shake_decay * delta, 0.0)
		offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
	# Kamera aufs BILDSCHIRM-Pixelraster einrasten. Bei nicht-ganzzahligem Zoom
	# (2.5) und Nearest-Filter flackert sonst das ganze Bild, weil dieselben
	# Texel je nach Sub-Pixel-Lage mal 2, mal 3 Bildschirmpixel breit werden.
	# So verschiebt sich die Welt immer um ganze Bildschirmpixel.
	_snap_to_pixel_grid()


## Rundet die effektive Zeichenposition (Position + Offset) so, dass sie auf
## dem Bildschirm-Pixelraster liegt: (pos * zoom) ganzzahlig, dann / zoom.
func _snap_to_pixel_grid() -> void:
	var eff := global_position + offset
	var snapped := Vector2(
		round(eff.x * zoom.x) / zoom.x,
		round(eff.y * zoom.y) / zoom.y)
	global_position += snapped - eff


## Kurzer Ruck, z. B. bei einem Axtschlag.
func shake(amount: float, duration := 0.18) -> void:
	_shake = maxf(_shake, amount)
	_shake_decay = amount / maxf(duration, 0.01)
