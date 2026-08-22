extends Node2D

## Weicher Schlagschatten unter einer Figur. Zeichnet eine gestauchte
## Ellipse in mehreren Ringen, damit die Kante nicht hart wirkt.

@export var radius := 7.0
@export var squash := 0.45        ## vertikale Stauchung (Iso-Perspektive)
## Bleibt als Kontaktschatten direkt unter der Figur, jetzt dezenter -
## den Rest uebernimmt der geworfene Schatten (cast_shadow.gd).
@export var color := Color(0, 0, 0, 0.16)
@export var rings := 4


func _ready() -> void:
	# Der Schatten liegt auf dem Boden und darf nicht mitleuchten.
	light_mask = 0
	z_index = -1


func _draw() -> void:
	for i in range(rings, 0, -1):
		var t := float(i) / float(rings)
		var c := Color(color.r, color.g, color.b, color.a / float(rings))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, squash))
		draw_circle(Vector2.ZERO, radius * t, c)
