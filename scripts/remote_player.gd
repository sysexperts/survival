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

const CCFrames := preload("res://scripts/cc_frames.gd")
const CCCatalog := preload("res://scripts/cc_catalog.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")
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
var owner_id := 0       # Peer-ID dieses Mitspielers (von net_game gesetzt)


## Ist dieser Mitspieler laut downed_sync gerade bewusstlos?
func _owner_downed() -> bool:
	var ds := get_tree().get_first_node_in_group("downed_sync")
	return ds != null and ds.has_method("is_downed_owner") and ds.is_downed_owner(owner_id)


## Aktuelle Frame-Textur (fuer den Hover-Rand beim Aufhelfen).
func frame_texture() -> Texture2D:
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(_sprite.animation):
		return _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	return null


func sprite_flip() -> bool:
	return _sprite.flip_h


func sprite_offset() -> Vector2:
	return _sprite.offset
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
	_sprite.sprite_frames = CCFrames.build(_look)
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


## Aussehen dieses Mitspielers. Standard, bis das echte über das Netz kommt.
var _look: Dictionary = CCCatalog.default_look()
## Welches Werkzeug der Mitspieler hält (Pack-Layer + Metall), "" = leere Hand.
var _tool := ""
var _metal := ""


## Übernimmt ein über das Netz empfangenes Aussehen und baut die Figur neu.
func set_look(look: Dictionary) -> void:
	_look = AppearanceStore.sanitize(look)
	_rebuild()


## Baut die SpriteFrames aus Aussehen + Bewaffnung neu; laufende Animation bleibt.
func _rebuild() -> void:
	if _sprite == null:
		return
	var a := _sprite.animation
	_sprite.sprite_frames = CCFrames.build(_look, _tool, _metal)
	if _sprite.sprite_frames.has_animation(a):
		_sprite.play(a)


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
func apply_state(pos: Vector2, anim: StringName, frame: int, tool: String = "", metal: String = "") -> void:
	if not _has_target:
		global_position = pos        # erstes Paket: direkt hinsetzen
		_has_target = true
	_target = pos
	if _sprite == null:
		return
	# Werkzeug gewechselt/abgelegt? Frames umbauen (mit/ohne Werkzeug-Pose).
	if tool != _tool or metal != _metal:
		_tool = tool
		_metal = metal
		_rebuild()
	# Ost-Richtungen werden gespiegelt gezeichnet (siehe cc_frames.gd).
	_sprite.flip_h = String(anim).ends_with("east")
	if _sprite.animation != anim and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
	_sprite.frame = frame
	# Schlaeft der Mitspieler, denselben Zzz-Effekt zeigen wie bei der eigenen
	# Figur. Rein lokal gezeichnet - die Schlaf-Animation kommt ja schon
	# synchron ueber das Netz, jede Seite ergaenzt ihr eigenes Zzz.
	# Laeuft der Mitspieler? Dann Schrittgeraeusch an (die Animation kommt
	# synchron ueber das Netz - kein Positions-Vergleich noetig).
	var a := String(anim)
	_walking = a.begins_with("walk_") or a.begins_with("run_")
	# Liege-Pose UND nicht bewusstlos = echtes Schlafen -> Zzz. Bei Bewusstlosen
	# (downed_sync) KEIN Zzz, denn die nutzen dieselbe Liege-Pose.
	var sleeping := a.begins_with("sleep_") and not _owner_downed()
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
