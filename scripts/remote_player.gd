extends Node2D
class_name RemotePlayer

## Die Figur EINES anderen Spielers auf diesem Bildschirm.
##
## Bewusst leichtgewichtig und getrennt vom echten Player: sie liest keine
## Eingabe, faellt keine Baeume und greift nicht in die Welt ein - sie zeigt
## nur, wo der andere steht und welche Animation er gerade spielt. Alles
## Weitere kommt ueber das Netzwerk von NetGame.
##
## Haengt im y-sortierten Props-Container der Welt, damit sie korrekt zwischen
## Baeumen ein- und ausgeblendet wird.

const FRAMES := preload("res://resources/jack_frames.tres")
## Gleicher Fusspunkt-Versatz wie beim echten Player (siehe player.gd).
const SPRITE_OFFSET := Vector2(0, -18)

const SleepZzzScript := preload("res://scripts/sleep_zzz.gd")
const AudioHelper := preload("res://scripts/audio.gd")

## Ab dieser Entfernung (px) ist der Mitspieler-Schritt nicht mehr zu hoeren.
## Der sichtbare Weltausschnitt ist bei Zoom 2.5 nur ~512x288 px (Halbbreite
## ~256), deshalb knapp an den Bildschirmrand gesetzt: wer aus dem Bild laeuft,
## ist still. `ATT` macht den Abfall steil, damit es schon vorher deutlich leiser
## wird (statt erst am Rand).
const FOOTSTEP_MAX_DISTANCE := 280.0
const FOOTSTEP_ATTENUATION := 3.0

var _sprite: AnimatedSprite2D
var _plate: NamePlate
var _zzz: Node = null   # SleepZzz - per preload, siehe player.gd
## Schrittgeraeusch dieses Mitspielers - positionsabhaengig (2D), damit es mit
## der Entfernung leiser wird. Laeuft, solange seine Animation "walk_/run_" ist.
var _footsteps: AudioStreamPlayer2D = null
var _walking := false


func _ready() -> void:
	z_index = 0

	var shadow := Node2D.new()
	shadow.position = Vector2(0, 1)
	shadow.set_script(preload("res://scripts/blob_shadow.gd"))
	add_child(shadow)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.animation = &"idle_south"
	_sprite.offset = SPRITE_OFFSET
	_sprite.play(&"idle_south")
	add_child(_sprite)

	_plate = NamePlate.new()
	add_child(_plate)

	# Schrittgeraeusch positionsabhaengig. Bus VOR dem Zuweisen anlegen.
	AudioHelper.ensure_effects_bus()
	_footsteps = AudioStreamPlayer2D.new()
	_footsteps.stream = AudioHelper.FOOTSTEP_STREAM
	_footsteps.bus = AudioHelper.EFFECTS_BUS
	_footsteps.volume_db = AudioHelper.FOOTSTEP_DB
	_footsteps.max_distance = FOOTSTEP_MAX_DISTANCE
	_footsteps.attenuation = FOOTSTEP_ATTENUATION
	add_child(_footsteps)


var pname := ""

func set_player_name(n: String) -> void:
	pname = n
	if _plate:
		_plate.player_name = n


var _target := Vector2.ZERO
var _has_target := false


## Uebernimmt eine ueber das Netz empfangene Momentaufnahme. Die Position wird
## nur als ZIEL gemerkt und in _process weich angefahren - sonst springt die
## Figur bei 15 Paketen/s sichtbar.
func apply_state(pos: Vector2, anim: StringName, frame: int) -> void:
	if not _has_target:
		global_position = pos        # erstes Paket: direkt hinsetzen
		_has_target = true
	_target = pos
	if _sprite == null:
		return
	if _sprite.animation != anim and FRAMES.has_animation(anim):
		_sprite.play(anim)
	_sprite.frame = frame
	# Schlaeft der Mitspieler, denselben Zzz-Effekt zeigen wie bei der eigenen
	# Figur. Rein lokal gezeichnet - die Schlaf-Animation kommt ja schon
	# synchron ueber das Netz, jede Seite ergaenzt ihr eigenes Zzz.
	# Laeuft der Mitspieler? Dann Schrittgeraeusch an (die Animation kommt
	# synchron ueber das Netz - kein Positions-Vergleich noetig).
	var a := String(anim)
	_walking = a.begins_with("walk_") or a.begins_with("run_")
	var sleeping := a.begins_with("sleep_")
	if sleeping and _zzz == null:
		_zzz = SleepZzzScript.new()
		add_child(_zzz)
	elif not sleeping and _zzz != null:
		_zzz.queue_free()
		_zzz = null


func _process(delta: float) -> void:
	if _has_target:
		# Exponentielles Glaetten - unabhaengig von der Bildrate.
		global_position = global_position.lerp(_target, 1.0 - exp(-16.0 * delta))
	if _footsteps != null:
		# Zusaetzlich an Restbewegung koppeln: bleibt das letzte Paket auf "walk"
		# stehen (kein Idle-Paket nachgekommen), stoppt der Sound trotzdem, sobald
		# die Figur ihr Ziel erreicht hat.
		var moving := global_position.distance_to(_target) > 1.0
		var run := _walking and moving
		if run and not _footsteps.playing:
			_footsteps.play()
		elif not run and _footsteps.playing:
			_footsteps.stop()
