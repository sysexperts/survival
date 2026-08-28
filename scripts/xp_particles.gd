extends Node2D

## Kleiner XP-Effekt: ein paar gelbe Teilchen fliegen von einer Weltposition
## (z. B. dem gefaellten Baum) zum Spieler und verblassen dabei - symbolisiert
## gewonnene Erfahrung. Preload-Muster (kein class_name, Auto-Updater-Regel):
##   const XpParticles := preload("res://scripts/xp_particles.gd")
##   XpParticles.spawn(welt_node, baum_pos, spieler_node)

const COLOR := Color(1.0, 0.86, 0.2)     ## warmes Gelb
const COUNT := 8


## Erzeugt den Effekt als Kind von `parent` (Weltraum). `from_global` = Start
## (Weltkoordinaten), `target` = Node2D (Spieler), an den die Teilchen fliegen.
static func spawn(parent: Node, from_global: Vector2, target: Node2D, count := COUNT) -> void:
	if parent == null or target == null or not is_instance_valid(target):
		return
	var root := Node2D.new()
	root.set_script(load("res://scripts/xp_particles.gd"))
	root.z_index = 200
	parent.add_child(root)
	root._burst(from_global, target, count)


func _burst(from_global: Vector2, target: Node2D, count: int) -> void:
	var to := target.global_position + Vector2(0, -10)
	var longest := 0.0
	for i in count:
		var p := Polygon2D.new()
		# kleine Raute (pixelig, passt zum Look)
		p.polygon = PackedVector2Array([Vector2(0, -3), Vector2(3, 0), Vector2(0, 3), Vector2(-3, 0)])
		p.color = COLOR
		add_child(p)
		p.global_position = from_global + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		var dur := randf_range(0.45, 0.8)
		longest = maxf(longest, dur)
		var delay := randf_range(0.0, 0.12)
		var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(p, "global_position", to, dur).set_delay(delay)
		tw.tween_property(p, "scale", Vector2(0.3, 0.3), dur).set_delay(delay)
		tw.tween_property(p, "modulate:a", 0.0, dur * 0.9).set_delay(delay + dur * 0.1)
	# Nach dem letzten Teilchen aufraeumen.
	get_tree().create_timer(longest + 0.3).timeout.connect(queue_free)
