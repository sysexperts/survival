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
const Y_SQUASH := 0.5
const ARRIVE_PX := 2.0

var world: IsoWorld
var level := 0
var facing := "south"

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
	_sprite.sprite_frames = FRAMES
	_sprite.offset = SPRITE_OFFSET
	_sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	add_child(_sprite)
	_play("idle")
	_idle_left = randf_range(0.5, 1.5)


func _process(delta: float) -> void:
	if world == null:
		return
	if _idle_left > 0.0:
		_idle_left -= delta
		return
	if not _has_target:
		_pick_target()
		return
	var to := _target - global_position
	if to.length() <= ARRIVE_PX:
		global_position = _target
		_has_target = false
		# Ab und zu grasen (Pause), sonst gleich weiter.
		if randf() < 0.35:
			_idle_left = randf_range(1.0, 3.0)
			_play("idle")
		return
	facing = DIRS[_dir_index(Vector2(to.x, to.y / Y_SQUASH))]
	_play("walk")
	var step := to.normalized() * SPEED * delta
	if step.length() > to.length():
		step = to
	global_position += step


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
