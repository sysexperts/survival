extends Control

## Kleiner Fortschrittsring fuers Aufhelfen (selbst gezeichnet - kein Sprite-Sheet,
## damit nichts verrutscht). `progress` 0..1 fuellt den Ring im Uhrzeigersinn.
##
## KEIN class_name (Auto-Updater) - per preload eingebunden.

var progress := 0.0
var ring_color := Color(0.45, 0.85, 1.0)
var back_color := Color(0.0, 0.0, 0.0, 0.45)


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	var w := maxf(4.0, r * 0.22)
	# Hintergrundring (voll), dann der gefuellte Fortschritt oben drauf.
	draw_arc(c, r, 0.0, TAU, 48, back_color, w, true)
	if progress > 0.0:
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, ring_color, w, true)
