extends Node2D

## XP-Effekt: leuchtende gelbe Kugeln fliegen in einem Bogen von einer
## Weltposition (z. B. dem gefaellten Baum) zu EINEM bestimmten Spieler und
## verblassen. Das Ziel wird waehrend des Flugs LIVE verfolgt - so landet die
## Erfahrung immer bei dem Spieler, dem sie gehoert (wichtig fuer spaeteres
## Gruppen-XP: dann bekommt jedes Gruppenmitglied seinen eigenen Zufluss).
##
## Preload-Muster (kein class_name, Auto-Updater-Regel):
##   const XpParticles := preload("res://scripts/xp_particles.gd")
##   XpParticles.spawn(welt_node, baum_pos, spieler_node)

const COUNT := 10

static var _tex: Texture2D = null


## Weiche, leuchtende Kreis-Textur (einmal erzeugt): weisser Kern -> warmes Gelb.
static func _glow() -> Texture2D:
	if _tex != null:
		return _tex
	var s := 20
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	var r := s * 0.5
	for y in s:
		for x in s:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a                              # weicher Randabfall
			var col := Color(1, 1, 0.75).lerp(Color(1.0, 0.78, 0.12), clampf(d, 0.0, 1.0))
			col.a = a
			img.set_pixel(x, y, col)
	_tex = ImageTexture.create_from_image(img)
	return _tex


## Erzeugt den Effekt als Kind von `parent` (Weltraum). `from_global` = Start
## (Weltkoordinaten), `target` = Spieler-Node2D, dem die XP gehoert.
static func spawn(parent: Node, from_global: Vector2, target: Node2D, count := COUNT) -> void:
	if parent == null or target == null or not is_instance_valid(target):
		return
	var root := Node2D.new()
	root.set_script(load("res://scripts/xp_particles.gd"))
	root.z_index = 400
	parent.add_child(root)
	root._burst(from_global, target, count)


func _burst(from_global: Vector2, target: Node2D, count: int) -> void:
	var slowest := 0.0
	for i in count:
		var s := Sprite2D.new()
		s.texture = _glow()
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.scale = Vector2(0.15, 0.15)
		add_child(s)
		var start := from_global + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		s.global_position = start
		# Kontrollpunkt fuer den Bogen: Richtung Ziel, leicht seitlich + nach oben.
		var mid := start.lerp(target.global_position, 0.5)
		var ctrl := mid + Vector2(randf_range(-30, 30), randf_range(-55, -20))
		var dur := randf_range(0.55, 0.9)
		var delay := randf_range(0.0, 0.18)
		slowest = maxf(slowest, delay + dur)
		var tw := create_tween().set_parallel(true)
		# Position entlang eines quadratischen Bogens, Ziel LIVE verfolgt.
		tw.tween_method(_fly.bind(s, start, ctrl, target), 0.0, 1.0, dur) \
			.set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		# Aufploppen, dann zum Ende hin schrumpfen + verblassen.
		tw.tween_property(s, "scale", Vector2(0.9, 0.9), 0.16).set_delay(delay)
		tw.tween_property(s, "scale", Vector2(0.35, 0.35), dur * 0.55).set_delay(delay + dur * 0.45)
		tw.tween_property(s, "modulate:a", 0.0, dur * 0.35).set_delay(delay + dur * 0.65)
	get_tree().create_timer(slowest + 0.3).timeout.connect(queue_free)


## Ein Teilchen entlang der Bezier-Kurve setzen; Endpunkt = aktuelle
## Spielerposition (verfolgt einen laufenden Spieler).
func _fly(t: float, s: Sprite2D, start: Vector2, ctrl: Vector2, target: Node2D) -> void:
	if not is_instance_valid(s):
		return
	var end := (target.global_position + Vector2(0, -10)) if is_instance_valid(target) else ctrl
	var a := start.lerp(ctrl, t)
	var b := ctrl.lerp(end, t)
	s.global_position = a.lerp(b, t)
