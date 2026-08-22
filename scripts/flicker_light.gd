@tool
extends PointLight2D

## Unruhiges Licht (Fackel, Laterne, Lagerfeuer).
## Energie und Radius schwanken leicht, damit es lebendig wirkt.

@export var base_energy := 1.0
@export var flicker_amount := 0.18   ## Ausschlag der Energie
@export var flicker_speed := 7.0
@export var scale_amount := 0.05     ## Ausschlag des Radius

var _noise := FastNoiseLite.new()
var _t := 0.0
var _base_scale := 1.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.4
	_noise.seed = randi()
	_base_scale = texture_scale
	energy = base_energy


func _process(delta: float) -> void:
	_t += delta * flicker_speed
	var n := _noise.get_noise_1d(_t)                    # -1 .. 1
	energy = base_energy * (1.0 + n * flicker_amount)
	texture_scale = _base_scale * (1.0 + n * scale_amount)
