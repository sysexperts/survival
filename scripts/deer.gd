extends Node2D

## Ein umherstreifendes Reh (PixelLab-Character "deer").
##
## ERSTE VERSION: rein clientseitig/ambient - jeder Spieler sieht seine eigenen
## Rehe, es gibt noch keinen Netzwerk-Sync und keine Jagd. Beides ist der
## naechste Schritt (braucht eine Autoritaet, die das Reh simuliert; der
## dedizierte Server ist bisher nur ein Relay ohne Terrain).
##
## Bewegt sich frei im Bildschirmraum (Y gestaucht wie beim Spieler), laeuft von
## begehbarer Zelle zu begehbarer Zelle und legt zwischendurch Pausen ein - so
## entsteht das "hin und her". Haengt im y-sortierten Props-Container.

const FRAMES := preload("res://resources/deer_frames.tres")
const DIRS := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]
const DIR_VECTORS: Array[Vector2] = [
	Vector2(0, 1), Vector2(0.7071, 0.7071), Vector2(1, 0), Vector2(0.7071, -0.7071),
	Vector2(0, -1), Vector2(-0.7071, -0.7071), Vector2(-1, 0), Vector2(-0.7071, 0.7071),
]
## Rehe sind etwas kleiner als die 64er-Zelle gezeichnet - leicht verkleinern.
const ART_SCALE := 0.8
const SPRITE_OFFSET := Vector2(0, -20)   ## Fuesse auf den Node-Ursprung
const SPEED := 26.0
const FLEE_SPEED := 58.0
const Y_SQUASH := 0.5
const ARRIVE_PX := 2.0
## Scheu: kommt ein Spieler naeher als das (Bildpixel), flieht das Reh.
const FLEE_RADIUS := 95.0
## So lange laeuft es nach dem Erschrecken noch weg.
const FLEE_TIME := 2.6
## Beim Ausruhen: Chance, sich hinzulegen, und wie lange es liegen bleibt.
const LAY_CHANCE := 0.4
const LAY_MIN := 4.0
const LAY_MAX := 9.0
## Dauer der Hinlegen-/Aufsteh-Animation (9 Frames bei 10 fps).
const GETUP_TIME := 0.9

## wander | idle | laying | getup | flee
var _state := "wander"
var _flee_time := 0.0
var _lay_time := 0.0
var _getup_time := 0.0
var _got_up_scared := false
var spawner: Node                        ## liefert die Spielerpositionen (Flucht)

## Ueberschreibbar je Tierart - dasselbe Skript treibt auch das Kamel, nur mit
## anderen Frames/Werten (siehe camel_spawner.gd). Standard = Reh.
var frames: SpriteFrames = FRAMES
var art_scale := ART_SCALE
var move_speed := SPEED
var flee_speed := FLEE_SPEED
var flee_radius := FLEE_RADIUS
var sprite_offset := SPRITE_OFFSET
var avoid_water := false                  ## true = geht nicht ins Wasser (Kamel)
## true = blockiert seine aktuelle Zelle (mitwandernde Hitbox, z. B. Kamel).
var solid := false
var _blk := Vector2i(2147483647, 2147483647)

var world: IsoWorld
var level := 0
var facing := "south"
## Baby-Reh: halb so gross.
var is_baby := false
## Remote-Reh (Mitspieler-Sicht): keine eigene KI, folgt nur den ueber das Netz
## empfangenen Zustaenden.
var remote := false
var _rt := Vector2.ZERO
var _has_rt := false

var _sprite: AnimatedSprite2D
var _target := Vector2.ZERO
var _has_target := false
var _idle_left := 0.0
## Wie viele Schritte in dieselbe Richtung noch bevorzugt werden (ergibt ein
## ruhiges "hin und her" statt Gezappel).
var _run_len := 0
var _run_dir := 4                        ## Index in DIRS


func setup(p_world: IsoWorld, cell: Vector2i) -> void:
	world = p_world
	level = maxi(world.top_level_at(cell), 0)
	position = world.cell_to_world(cell, level)


func _ready() -> void:
	z_index = 0
	var shadow := Node2D.new()
	shadow.position = Vector2(0, 1)
	shadow.set_script(preload("res://scripts/blob_shadow.gd"))
	add_child(shadow)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.offset = sprite_offset
	var s := art_scale * (0.5 if is_baby else 1.0)
	_sprite.scale = Vector2(s, s)
	add_child(_sprite)
	_play("idle")
	_idle_left = randf_range(0.5, 1.5)
	if solid:
		tree_exiting.connect(func():
			if _blk.x != 2147483647 and world != null:
				world.unblock_cell(_blk))


## Remote-Reh: einen ueber das Netz empfangenen Zustand uebernehmen.
func apply_state(pos: Vector2, anim: StringName, lvl: int) -> void:
	remote = true
	level = lvl
	if not _has_rt:
		global_position = pos
		_has_rt = true
	_rt = pos
	if _sprite and _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)


## Fuer den Host: aktuelle Animation zum Verschicken.
func anim_name() -> StringName:
	return _sprite.animation if _sprite else &"idle_south"


## Mitwandernde Hitbox: die aktuelle Zelle blockieren, beim Zellwechsel umziehen.
func _update_block() -> void:
	if not solid or world == null:
		return
	var cell := world.world_to_cell(global_position, level)
	if cell == _blk:
		return
	if _blk.x != 2147483647:
		world.unblock_cell(_blk)
	# Nur blocken, wenn dort nicht schon etwas anderes sitzt.
	if world.blocker_at(cell) == null:
		world.block_cell(cell, self)
		_blk = cell
	else:
		_blk = Vector2i(2147483647, 2147483647)


func _process(delta: float) -> void:
	_update_block()
	if remote:
		# Nur weich zur empfangenen Zielposition gleiten - keine eigene KI.
		if _has_rt:
			global_position = global_position.lerp(_rt, 1.0 - exp(-16.0 * delta))
		return
	if world == null:
		return

	var np: Dictionary = spawner.nearest_player(global_position) if spawner else {"found": false, "dist": INF, "pos": Vector2.ZERO}
	var scared: bool = flee_radius > 0.0 and bool(np["found"]) and float(np["dist"]) < flee_radius

	match _state:
		"laying":
			if scared:
				_begin_getup(true)
			else:
				_lay_time -= delta
				if _lay_time <= 0.0:
					_begin_getup(false)
		"getup":
			_getup_time -= delta
			if _getup_time <= 0.0:
				if _got_up_scared:
					_state = "flee"; _flee_time = FLEE_TIME
				else:
					_state = "wander"
				_has_target = false
		"flee":
			_flee_time -= delta
			if not scared and _flee_time <= 0.0:
				_state = "wander"; _has_target = false
			else:
				_flee_step(delta, np["pos"] if np["found"] else global_position)
		"idle":
			if scared:
				_state = "flee"; _flee_time = FLEE_TIME; _has_target = false
				return
			_idle_left -= delta
			if _idle_left <= 0.0:
				if randf() < LAY_CHANCE:
					_begin_lay()
				else:
					_state = "wander"; _has_target = false
		_:  # wander
			if scared:
				_state = "flee"; _flee_time = FLEE_TIME; _has_target = false
				return
			_wander(delta)


## Normales Umherstreifen: zur naechsten begehbaren Zelle laufen, ab und zu
## eine Pause (idle) - dort kann sich das Reh dann auch hinlegen.
func _wander(delta: float) -> void:
	if not _has_target:
		_pick_target()
		return
	var to := _target - global_position
	if to.length() <= ARRIVE_PX:
		global_position = _target
		_has_target = false
		if randf() < 0.4:
			_state = "idle"
			_idle_left = randf_range(1.5, 3.5)
			_play("idle")
		return
	facing = DIRS[_dir_index(Vector2(to.x, to.y / Y_SQUASH))]
	_play("walk")
	var step := to.normalized() * move_speed * delta
	if step.length() > to.length():
		step = to
	global_position += step


## Flucht: weg vom Spieler, schneller. Zielzelle in Gegenrichtung suchen.
func _flee_step(delta: float, from_player: Vector2) -> void:
	var away := (global_position - from_player)
	away = Vector2(away.x, away.y / Y_SQUASH)
	if away.length() < 0.01:
		away = Vector2(1, 0)
	away = away.normalized()
	if not _has_target or (_target - global_position).length() <= ARRIVE_PX:
		var here := world.world_to_cell(global_position, level)
		var di := _dir_index(away)
		var n := _cell_towards(here, di)
		if n == here or not _walkable(here, n):
			# Ausweichen: irgendeine begehbare Nachbarzelle.
			for nb in world.neighbors(here):
				if _walkable(here, nb):
					n = nb; break
		level = maxi(world.top_level_at(n), 0)
		_target = world.cell_to_world(n, level)
		_has_target = true
	var to := _target - global_position
	facing = DIRS[_dir_index(Vector2(to.x, to.y / Y_SQUASH))]
	_play("walk")
	var step := to.normalized() * flee_speed * delta
	if step.length() > to.length():
		step = to
	global_position += step


func _begin_lay() -> void:
	_state = "laying"
	_lay_time = randf_range(LAY_MIN, LAY_MAX)
	_has_target = false
	var anim := "laydown_%s" % facing.replace("-", "_")
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)          # vorwaerts = hinlegen, bleibt am letzten Frame


## Aufstehen = Hinlegen rueckwaerts. `scared` merkt, ob danach geflohen wird.
func _begin_getup(scared: bool) -> void:
	_state = "getup"
	_getup_time = GETUP_TIME
	_got_up_scared = scared
	var anim := "laydown_%s" % facing.replace("-", "_")
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.play_backwards(anim)


## Sucht die naechste begehbare Zelle. Bevorzugt die bisherige Laufrichtung
## (kurze "Laeufe"), damit das Reh eine Strecke geht und dann wendet.
func _pick_target() -> void:
	var here := world.world_to_cell(global_position, level)
	if _run_len <= 0:
		_run_dir = randi() % 8
		_run_len = randi_range(2, 5)
	# Kandidaten in Vorzugsrichtung, sonst irgendeine begehbare Nachbarzelle.
	var order := [_run_dir, (_run_dir + 1) % 8, (_run_dir + 7) % 8,
		(_run_dir + 4) % 8, randi() % 8]
	for di in order:
		var n := _cell_towards(here, di)
		if n != here and _walkable(here, n):
			_run_dir = di
			_run_len -= 1
			level = maxi(world.top_level_at(n), 0)
			_target = world.cell_to_world(n, level)
			_has_target = true
			facing = DIRS[di]
			return
	# Nirgends hin: kurz stehen, dann neue Richtung.
	_run_len = 0
	_idle_left = randf_range(0.6, 1.4)
	_play("idle")


## Nachbarzelle in Richtung di (ueber den Bildschirmvektor, wegen der
## Stacked-Paritaet nicht per festem Offset).
func _cell_towards(cell: Vector2i, di: int) -> Vector2i:
	var v := DIR_VECTORS[di]
	var best := cell
	var best_dot := 0.35                 # Mindest-Uebereinstimmung
	for nb in world.neighbors(cell):
		var d := (world.cell_to_world(nb, 0) - world.cell_to_world(cell, 0))
		d = Vector2(d.x, d.y / Y_SQUASH).normalized()
		var dot := d.dot(v)
		if dot > best_dot:
			best_dot = dot
			best = nb
	return best


func _walkable(from: Vector2i, to: Vector2i) -> bool:
	if avoid_water and world.is_water(to):
		return false
	return world.top_level_at(to) >= 0 and not world.has_prop(to) \
		and world.blocker_at(to) == null and world.can_step(from, to, 1)


func _dir_index(v: Vector2) -> int:
	var a := rad_to_deg(atan2(v.y, v.x))
	return wrapi(int(round((90.0 - a) / 45.0)), 0, 8)


func _play(state: String) -> void:
	var anim := "%s_%s" % [state, facing.replace("-", "_")]
	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)
	elif not _sprite.is_playing():
		_sprite.play(anim)
