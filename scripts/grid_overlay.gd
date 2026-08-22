@tool
extends Node2D

## Zeichnet das isometrische Grundraster (Ebene 0) als Orientierungshilfe
## beim Bauen im Editor. Im laufenden Spiel standardmässig aus.

@export var radius := 20:
	set(v):
		radius = v
		queue_redraw()
@export var color := Color(1, 1, 1, 0.12):
	set(v):
		color = v
		queue_redraw()
## Im laufenden Spiel anzeigen?
@export var show_in_game := false

const HW := 16.0  ## halbe Tile-Breite
const HH := 8.0   ## halbe Tile-Hoehe


func _ready() -> void:
	z_index = -1
	if not Engine.is_editor_hint() and not show_in_game:
		visible = false


func _draw() -> void:
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var c := Vector2((x - y) * HW, (x + y) * HH)
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -HH), c + Vector2(HW, 0),
				c + Vector2(0, HH), c + Vector2(-HW, 0),
				c + Vector2(0, -HH),
			]), color, 1.0)
