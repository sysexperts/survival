extends Node2D
class_name Player

## Jack: 8-Richtungs-Bewegung auf der gestapelten Isometrie-Map.
##
## Bewegt sich frei im Bildschirmraum (die Y-Achse wird gestaucht, damit
## das Tempo in der Iso-Perspektive gleichmässig wirkt) und rastet nicht
## auf Zellen ein. Die Höhe kommt aus IsoWorld: der Spieler steht immer
## auf dem obersten Block seiner Zelle, Stufen bis MAX_STEP sind begehbar.

const DIRS := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]

## Bildschirmvektor je Richtung, gleiche Reihenfolge wie DIRS.
## Y zeigt nach unten, Sueden ist also (0, 1).
const DIR_VECTORS: Array[Vector2] = [
	Vector2(0, 1), Vector2(0.7071, 0.7071), Vector2(1, 0), Vector2(0.7071, -0.7071),
	Vector2(0, -1), Vector2(-0.7071, -0.7071), Vector2(-1, 0), Vector2(-0.7071, 0.7071),
]

## Wird ausgelöst, wenn ein Baum gefällt ist. `atlas` sagt, welche Baumart
## es war - Anknüpfpunkt für Inventar und Ressourcen.
signal felled(cell: Vector2i, level: int, atlas: Vector2i)
## Ein Baumstumpf wurde endgueltig entfernt.
signal stump_cleared(cell: Vector2i)
## Es wurde versucht zu faellen, ohne die Axt in der Hand zu haben.
## Das Inventar haengt daran und sagt es dem Spieler - der Player selbst
## kennt weder HUD noch Hinweiszeile.
signal chop_refused
## Ein Axtschlag wurde ausgefuehrt (ein "Schlag"). Das Inventar haengt daran
## und zieht der Axt Dayaniklilik ab - der Player selbst kennt kein Inventar.
signal axe_swung

## Ein Stein wurde aufgehoben.
## `gather_id` sagt, WAS aufgehoben wurde (siehe GatherDB) - leer bei den
## alten, in die Karte gemalten Steinen.
signal stone_collected(cell: Vector2i, level: int, gather_id: String)

## Jack ist bei einer Handwerks-Station angekommen (nach Rechtsklick). Das
## Inventar oeffnet daraufhin ihr Fenster - der Player kennt kein HUD.
signal reached_station(station: String)

## Ein Objekt wurde gesetzt - fuer den Multiplayer-Sync (world_sync.gd), damit
## Lagerfeuer und Moebel bei allen erscheinen.
signal placed_campfire(top: Vector2i)
signal placed_furniture(id: String, cell: Vector2i, orient: int)
## Ein platziertes Objekt (Moebel/Lagerfeuer) wurde zerstoert. `cell` ist die
## Ankerzelle. world_sync entfernt es aus der Persistenz und bei allen anderen.
## Es kommt bewusst NICHT ins Inventar zurueck - Zerstoeren heisst weg.
signal destroyed_placed(cell: Vector2i)

@export var world_path: NodePath = ^"../World"
@export var walk_speed := 60.0
@export var run_speed := 110.0
@export var y_squash := 0.5      ## Iso-Stauchung der vertikalen Bewegung
@export var max_step := 1        ## max. begehbarer Höhenunterschied in Ebenen
@export var start_cell := Vector2i(0, 0)
## Verschiebung des Sprites, damit die Fuesse auf dem Node-Ursprung stehen.
## Die Frames sind 68x68 (die Axt-Animation braucht den Platz), der
## Fusspunkt liegt bei y=52, die Regionsmitte bei 34 -> -18.
## Wird hier gesetzt statt in der Szene, damit player.tscn unberuehrt bleibt.
@export var sprite_offset := Vector2(0, -18)
## Helligkeit der Laterne bei voller Dunkelheit.
@export var lantern_energy := 0.55
## Axtschläge, bis ein Baum fällt.
@export var chops_to_fell := 6
## Frame der Axt-Animation, in dem die Klinge trifft (0-8).
@export var axe_impact_frame := 4
## Stärke des Kamera-Rucks pro Treffer bzw. beim Fällen.
@export var hit_shake := 1.6
@export var fell_shake := 4.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var lantern: PointLight2D = $Lantern
@onready var _shadow: Node2D = $Shadow
@onready var _nameplate: Node2D = $NamePlate

## Wie schnell der Stufen-Versatz ausgeglichen wird (grösser = schneller).
const STEP_SMOOTH_SPEED := 14.0
## Visueller Rest-Versatz in px, der einen Höhensprung weich nachzieht,
## damit Jack beim Stufenwechsel nicht ruckartig 8 px hoch/runter springt.
## Der Node selbst sitzt logisch schon auf der neuen Höhe (Y-Sortierung und
## Kollision stimmen); nur die sichtbaren Kinder gleiten nach.
var _step_lag := 0.0
var _sprite_base_y := 0.0
var _shadow_base_y := 0.0
var _lantern_base_y := 0.0
var _nameplate_base_y := 0.0

var world: IsoWorld
## Haelt Jack gerade eine Axt? Wird vom Inventar gesetzt und richtet sich
## danach, was in der Hotbar ausgewaehlt ist. Ohne Axt kein Baum.
var has_axe := false
## Gewaehltes Aussehen (fuer Neuaufbau bei Axt-Wechsel).
var _look: Dictionary = {}
## Werden gerade die bewaffneten Frames (Axt in der Hand) gezeigt?
var _armed_shown := false
var level := 0                   ## Ebene des Blocks, auf dem Jack steht
var facing := "south"
var busy := false                ## blockierende Animation (Axt) laeuft
var _day_night: Node = null      ## optional, zum Dimmen der Laterne

var path: Array[Vector2i] = []   ## laufender Klick-Weg, leer = kein Auftrag
var _chop_cell := Vector2i.ZERO  ## Baum, der nach dem Laufen dran ist
var _chop_level := -1
var _chops_left := 0
var _clearing_stump := false     ## Auftrag ist "Stumpf weg", nicht "Baum faellen"
var _pickup_cell := Vector2i(2147483647, 2147483647)  ## Stein, der nach dem Laufen dran ist
var _reach_station := ""          ## Station, die nach dem Laufen geoeffnet wird
var _reach_destroy := Vector2i(2147483647, 2147483647)  ## Objekt, das nach dem Laufen zerstoert wird
var _tree: TreeActor = null      ## Baum als Node, solange gefällt wird
var _camera: Camera2D = null
## WorldSync-Node (Multiplayer): geteilte Baum-HP. Im Einzelspieler null bzw.
## inaktiv - dann zaehlt der Baum lokal herunter.
var _ws: Node = null

## Schlafen im Bett. `_sleeping` = Jack liegt gerade; `_reach_bed` = er laeuft
## noch zum Bett und legt sich bei Ankunft hin. `_sleep_return_pos`/`_level`
## merken, wo er vorm Hinlegen stand, damit er beim Aufwachen dorthin zurueck-
## springt (das Bett selbst ist belegt, dort kann er nicht stehen).
var _sleeping := false
var _reach_bed := false
var _bed_cell := Vector2i.ZERO
var _sleep_return_pos := Vector2.ZERO
var _sleep_return_level := 0
## Der aufsteigende Zzz-Effekt, solange Jack liegt (rein optisch, siehe
## sleep_zzz.gd). Haengt an der Figur und wandert beim Ebenenwechsel mit.
## Per preload statt ueber den class_name SleepZzz - sonst kennt der
## Auto-Updater die neue Klasse nicht (die Basis-.exe registriert sie beim
## Start nicht, siehe chunk_manager.gd/WorldGen).
const SleepZzzScript := preload("res://scripts/sleep_zzz.gd")
var _zzz: Node = null

## Laufgeraeusch (Effekt auf dem "Efektler"-Bus, spaeter in den Einstellungen
## regelbar). Stream + Lautstaerke liegen zentral in audio.gd, damit Mitspieler
## (remote_player.gd) dieselbe Quelle nutzen.
const AudioHelper := preload("res://scripts/audio.gd")
## Eigene Schritte etwas leiser als die der Mitspieler (die man ohnehin nur aus
## der Naehe hoert). Separat von AudioHelper.FOOTSTEP_DB, das die Remote-Basis ist.
const OWN_FOOTSTEP_DB := -22.0
## Ab so viel Bewegung pro Frame (px) gilt Jack als laufend. Die Obergrenze
## faengt Spruenge (Teleport, Aufwachen) ab, die kurz "Bewegung" vortaeuschen.
const FOOTSTEP_MIN_MOVE := 0.1
const FOOTSTEP_MAX_MOVE := 20.0
## Nachlauf: so lange nach der letzten Bewegung bleibt der Loop noch an. Federt
## das Timing zwischen _process und _physics_process ab, sonst stottert der Ton.
const FOOTSTEP_COOLDOWN := 0.12
var _footsteps: AudioStreamPlayer = null
var _last_pos := Vector2.ZERO
var _move_cooldown := 0.0


## Aussehen zur Laufzeit aus den Layer-Sheets (Customaizable Character). Preload
## statt class_name wegen der Auto-Updater-Regel.
const CCFrames := preload("res://scripts/cc_frames.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")
const UIState := preload("res://scripts/ui_state.gd")


func _ready() -> void:
	# Jack haengt sich zur Laufzeit in die TileMapLayer um, deshalb ist er
	# ueber den festen Szenenpfad nicht mehr auffindbar -> Gruppe.
	add_to_group("player")
	z_index = 0        # den z_index bringt der Props-Container mit
	_day_night = get_tree().get_first_node_in_group("day_night")
	world = get_node(world_path) as IsoWorld
	# Figur aus dem gewaehlten Aussehen bauen (statt festem jack_frames.tres).
	_look = AppearanceStore.local()
	sprite.sprite_frames = CCFrames.build(_look, has_axe)
	sprite.offset = sprite_offset
	# Ruhelagen der sichtbaren Kinder merken - darauf wird der Stufen-Versatz
	# addiert (siehe _step_lag).
	_sprite_base_y = sprite.offset.y
	_shadow_base_y = _shadow.position.y
	_lantern_base_y = lantern.position.y
	_nameplate_base_y = _nameplate.position.y
	sprite.animation_finished.connect(_on_animation_finished)
	# Umriss-Anzeige zur Laufzeit anhaengen - so bleibt player.tscn unberuehrt.
	add_child(OcclusionOutline.create(self, sprite, world))
	add_child(CastShadow.create(sprite))
	# Die Axt ist Teil des Charakters (Pack-Layer), kein Overlay mehr - siehe
	# _sync_armed(): bei has_axe werden die "_hold"-Frames mit Axt gezeigt.
	sprite.frame_changed.connect(_on_frame_changed)
	_setup_footsteps()
	# WorldSync fuer die geteilte Baum-HP (Multiplayer). Einmal cachen - der
	# Player haengt sich zur Laufzeit um, ein NodePath wuerde danach brechen.
	_ws = get_parent().get_node_or_null(^"WorldSync")
	# Umhaengen ist waehrend _ready nicht erlaubt -> auf den naechsten Frame legen
	_snap_to_cell.call_deferred(start_cell)
	_play("idle")


## Baut die Figur aus einem neuen Aussehen neu auf (Görünüm-Editor). Die
## laufende Animation wird beibehalten.
func apply_look(look: Dictionary) -> void:
	_look = look
	var a := sprite.animation
	sprite.sprite_frames = CCFrames.build(_look, has_axe)
	_armed_shown = has_axe
	if sprite.sprite_frames.has_animation(a):
		sprite.play(a)
	else:
		_play("idle")


## Wechselt zwischen unbewaffneten und bewaffneten Frames, sobald sich has_axe
## ändert. Die laufende Animation (gleicher Name in beiden Sätzen) läuft weiter.
func _sync_armed() -> void:
	if _armed_shown == has_axe:
		return
	_armed_shown = has_axe
	var a := sprite.animation
	sprite.sprite_frames = CCFrames.build(_look, has_axe)
	if sprite.sprite_frames.has_animation(a):
		sprite.play(a)


## Setzt Jack auf den obersten Block einer Zelle.
func _snap_to_cell(cell: Vector2i) -> void:
	level = maxi(world.top_level_at(cell), 0)
	global_position = world.cell_to_world(cell, level)
	_reparent_to_level()


## Die Laterne brennt nur, wenn es dunkel genug ist.
func _process(delta: float) -> void:
	if _day_night and lantern.visible:
		lantern.base_energy = lerpf(0.0, lantern_energy, _day_night.darkness())
	_ease_step_lag(delta)
	_update_footsteps(delta)


## Laufgeraeusch an die tatsaechliche Bewegung koppeln - so deckt es Tastatur
## UND Klick-Laufen ab und schweigt bei Idle, Faellen und Schlafen (dort steht
## Jack still). Ueber die Positions-Differenz, nicht ueber die Animation, damit
## keine Sonderfaelle vergessen werden.
func _update_footsteps(delta: float) -> void:
	if _footsteps == null:
		return
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	# Bewegung erneuert den Nachlauf; ohne aktuelle Bewegung laeuft er ab.
	if moved > FOOTSTEP_MIN_MOVE and moved < FOOTSTEP_MAX_MOVE and not _sleeping:
		_move_cooldown = FOOTSTEP_COOLDOWN
	else:
		_move_cooldown = maxf(_move_cooldown - delta, 0.0)
	var walking := _move_cooldown > 0.0
	if walking and not _footsteps.playing:
		_footsteps.play()
	elif not walking and _footsteps.playing:
		_footsteps.stop()


## Baut den Laufgeraeusch-Player. Nur der LOKALE Spieler ist ein Player (andere
## sind remote_player.gd), deshalb reicht ein einfacher AudioStreamPlayer -
## unabhaengig von Kamera/Listener, immer voll hoerbar. Der Stream ist als
## unkomprimiertes PCM mit eingebackenem Loop importiert (WICHTIG: QOA lief auf
## dem ausgelieferten Client nicht) und laeuft auf dem Efektler-Bus. Den Bus VOR
## dem Zuweisen anlegen, sonst verstummt der Player.
func _setup_footsteps() -> void:
	AudioHelper.ensure_effects_bus()
	_footsteps = AudioStreamPlayer.new()
	_footsteps.bus = AudioHelper.EFFECTS_BUS
	_footsteps.volume_db = OWN_FOOTSTEP_DB
	_footsteps.stream = AudioHelper.FOOTSTEP_STREAM
	add_child(_footsteps)
	_last_pos = global_position
	# Audio-Hoerpunkt an die eigene Figur binden, damit 2D-Klaenge (z. B. die
	# Schritte anderer Spieler) korrekt mit der Entfernung leiser werden. Ohne
	# expliziten Listener nimmt Godot den Bildschirmmittelpunkt - das daempft hier
	# nicht zuverlaessig. Der Listener wandert als Kind beim Ebenenwechsel mit.
	var listener := AudioListener2D.new()
	add_child(listener)
	listener.make_current()


## Zieht den Stufen-Versatz Frame für Frame gegen null und legt ihn auf die
## sichtbaren Kinder. So gleitet Jack über ~0,1 s auf die neue Höhe, statt zu
## springen. Der geworfene Schatten (CastShadow) folgt automatisch, weil er
## sprite.offset jeden Frame kopiert.
func _ease_step_lag(delta: float) -> void:
	if is_zero_approx(_step_lag):
		return
	_step_lag = lerpf(_step_lag, 0.0, 1.0 - exp(-STEP_SMOOTH_SPEED * delta))
	if absf(_step_lag) < 0.05:
		_step_lag = 0.0
	sprite.offset.y = _sprite_base_y + _step_lag
	_shadow.position.y = _shadow_base_y + _step_lag
	lantern.position.y = _lantern_base_y + _step_lag
	_nameplate.position.y = _nameplate_base_y + _step_lag


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			lantern.visible = not lantern.visible


func _physics_process(delta: float) -> void:
	if world == null:
		return
	# Waehrend ein Textfeld (z. B. die Chat-Eingabe) den Fokus hat, keine
	# Steuerung annehmen. Ueber den Fokus statt ein Flag - so kann nichts
	# "haengen bleiben" und die Steuerung dauerhaft blockieren.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	# ESC-Menü offen? Keine Steuerung annehmen.
	if UIState.pause_open:
		return
	var input := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	input = input.limit_length(1.0)

	# Schlafen: Jack liegt still im Bett, bis eine Bewegungstaste kommt. Erst
	# aufstehen (zurueck auf die Standfläche), dann normal weiter - so laeuft er
	# im selben Tastendruck los, statt einen Frame zu verschlucken.
	if _sleeping:
		if input == Vector2.ZERO:
			return
		_wake_up()

	# Tastatur bricht einen laufenden Auftrag ab - und zwar VOR dem
	# busy-Guard, sonst käme man während der Axt-Animation nie durch und
	# der gefällte Baum bliebe als Node hängen.
	if input != Vector2.ZERO and (busy or not path.is_empty() or _chop_level >= 0
			or _pickup_cell != INVALID_CELL or _reach_station != "" or _reach_bed
			or _reach_destroy != INVALID_CELL):
		_cancel_task()

	if busy:
		return

	# Axt auf Leertaste. (Enter ist jetzt fuer den Chat reserviert.)
	if Input.is_key_pressed(KEY_SPACE):
		_start_axe()
		return

	if input == Vector2.ZERO:
		if not path.is_empty():
			_follow_path(delta)
			return
		if _chop_level >= 0:
			_begin_chopping()
			return
		if _pickup_cell != INVALID_CELL:
			var target := _pickup_cell
			_pickup_cell = INVALID_CELL
			collect_stone(target)
			return
		if _reach_station != "":
			var s := _reach_station
			_reach_station = ""
			reached_station.emit(s)
			_play("idle")
			return
		if _reach_bed:
			_reach_bed = false
			_lie_down(_bed_cell)
			return
		if _reach_destroy != INVALID_CELL:
			var dcell := _reach_destroy
			_reach_destroy = INVALID_CELL
			_do_destroy(dcell)
			_play("idle")
			return
		_play("idle")
		return

	var running := Input.is_key_pressed(KEY_SHIFT)
	facing = DIRS[_dir_index(input)]
	_play("run" if running else "walk")

	var speed := run_speed if running else walk_speed
	var step := Vector2(input.x, input.y * y_squash) * speed * delta
	# Achsen getrennt bewegen, damit man an Kanten entlanggleitet
	_try_move(Vector2(step.x, 0.0))
	_try_move(Vector2(0.0, step.y))


## Richtungsindex aus dem Eingabevektor.
## Bildschirmwinkel (Y zeigt nach unten): Süden = 90°, Osten = 0°,
## Norden = -90°. DIRS laufen im 45°-Raster von Süden aus.
func _dir_index(v: Vector2) -> int:
	var a := rad_to_deg(atan2(v.y, v.x))
	return wrapi(int(round((90.0 - a) / 45.0)), 0, 8)


## Verschiebt Jack, wenn das Ziel begehbar ist, und passt die Höhe an.
func _try_move(delta_pos: Vector2) -> void:
	if delta_pos == Vector2.ZERO:
		return
	var target := global_position + delta_pos
	var cell := world.world_to_cell(target, level)
	if world.has_prop(cell):
		return                                  # Baum o. ae. im Weg
	var top := world.top_level_at(cell)
	if top < 0 or absi(top - level) > max_step:
		return                                  # Loch oder zu hohe Stufe
	if top != level:
		# Höhe wechseln: die Standfläche liegt (top - level) * 8 px höher
		var dy := float(top - level) * IsoWorld.LEVEL_STEP_PX
		target.y -= dy
		# Der Node springt sofort auf die neue Höhe (Y-Sortierung/Kollision),
		# aber optisch fangen wir den Sprung ab und lassen ihn ausgleiten.
		_step_lag += dy
		level = top
		_reparent_to_level()
	global_position = target


## Jack gehoert in denselben y-sortierten Container wie die Props. Nur so
## entscheidet zwischen ihm und einem Baum die Bildschirmposition statt des
## Ebenen-z_index. Der Container traegt den z_index, Jack selbst bleibt 0.
func _reparent_to_level() -> void:
	if not is_inside_tree() or world.props_root == null:
		return
	if get_parent() != world.props_root:
		reparent(world.props_root, true)


# --- Animation ---------------------------------------------------------

func _play(state: String) -> void:
	_sync_armed()
	# Die Sheets zeigen nur die Westseite - Osten wird gespiegelt gezeichnet.
	sprite.flip_h = CCFrames.flipped(facing)
	var anim := "%s_%s" % [state, facing.replace("-", "_")]
	if sprite.animation == anim and sprite.is_playing():
		return
	# Beim reinen Richtungswechsel den Zyklus weiterlaufen lassen,
	# statt den Schritt neu zu starten.
	var same_state := String(sprite.animation).begins_with(state + "_")
	var f := sprite.frame
	var progress := sprite.frame_progress
	sprite.play(anim)
	if same_state:
		sprite.set_frame_and_progress(f, progress)


func _start_axe() -> void:
	busy = true
	_sync_armed()
	sprite.flip_h = CCFrames.flipped(facing)
	sprite.play("axe_%s" % facing.replace("-", "_"))
	# Ein Schlag = ein Dayaniklilik-Punkt. Das Inventar bucht ihn ab und
	# setzt has_axe auf false, sobald die Axt zerbricht (siehe unten).
	axe_swung.emit()


## Die Klinge trifft mitten in der Animation, nicht am Ende - sonst wirkt
## der Ruck versetzt zum Bild.
func _on_frame_changed() -> void:
	if not String(sprite.animation).begins_with("axe_"):
		return
	if sprite.frame != axe_impact_frame or not is_instance_valid(_tree):
		return
	# Wackeln bei jedem Schlag, solange der Baum noch steht (bei geteilter HP
	# weiss der Client die Restschlaege nicht - der Fall ersetzt den Node eh).
	if world.prop_node(_chop_cell) != null:
		var away := (_tree.global_position - global_position).normalized()
		_tree.hit(away)
		_shake(hit_shake)


func _shake(amount: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
	if _camera and _camera.has_method("shake"):
		_camera.shake(amount)


func _on_animation_finished() -> void:
	if not String(sprite.animation).begins_with("axe_"):
		return
	busy = false
	if _chop_level < 0:
		_play("idle")
		return

	# Axt zwischendurch zerbrochen (Dayaniklilik 0)? Nicht weiterschlagen.
	if not has_axe:
		_end_chop()
		_play("idle")
		return

	# Stumpf roden: ein Schlag, endgueltig (unveraendert).
	if _clearing_stump:
		var scell := _chop_cell
		world.remove_prop(scell, _chop_level)
		_shake(hit_shake)
		_end_chop()
		stump_cleared.emit(scell)
		_play("idle")
		return

	# Baum ist inzwischen gefaellt (von mir oder einem Mitspieler)? Aufhoeren.
	if not is_instance_valid(_tree) or world.prop_node(_chop_cell) == null:
		var fell_cell := _chop_cell
		var fell_lvl := _chop_level
		var fell_atlas: Vector2i = _tree.atlas if is_instance_valid(_tree) else Vector2i.ZERO
		var was_active := _chop_level >= 0
		_tree = null
		_end_chop()
		_play("idle")
		# Im MP faellt der Baum server-seitig - die normale felled-Zeile unten
		# wird nie erreicht. Wenn ich gerade an diesem Baum geschlagen habe und
		# er jetzt weg ist, das Signal hier nachziehen (fuer XP / EXP-Leiste).
		if Net.active and was_active:
			felled.emit(fell_cell, fell_lvl, fell_atlas)
		return

	if Net.active and _ws != null:
		# GETEILTE HP: Treffer an den Server melden und weiterschlagen. Der Baum
		# faellt, wenn der Server ihn (ueber _fell_now -> _apply_fell) entfernt;
		# der naechste Zyklus sieht dann prop_node == null und stoppt.
		_ws.report_tree_hit(_chop_cell, _chop_level, _tree.atlas)
		_start_axe()
		return

	# Einzelspieler: lokale HP herunterzaehlen.
	_chops_left -= 1
	print("[Baum] %s: %d/%d HP" % [_chop_cell, maxi(_chops_left, 0), chops_to_fell])
	if _chops_left > 0:
		_start_axe()
		return
	var cell := _chop_cell
	var lvl := _chop_level
	var atlas := _tree.atlas
	world.detach_prop(cell)
	_tree.fell((_tree.global_position - global_position).normalized())
	_shake(fell_shake)
	_tree = null
	_end_chop()
	felled.emit(cell, lvl, atlas)
	_play("idle")


## Beendet einen Fäll-/Rode-Auftrag (ohne den Baum-Node anzufassen).
func _end_chop() -> void:
	path.clear()
	_chop_level = -1
	_chops_left = 0
	_clearing_stump = false


# --- Klick-Aufträge -----------------------------------------------------

## Läuft zur angeklickten Zelle. Gibt false zurück, wenn es keinen Weg gibt.
func walk_to(cell: Vector2i) -> bool:
	_cancel_task()
	var here := world.world_to_cell(global_position, level)
	# Auf ein Prop kann man nicht treten - dann daneben stellen.
	if world.has_prop(cell):
		cell = GridPath.adjacent_to(world, cell, here, max_step)
		if cell.x == 2147483647:
			return false
	path = GridPath.find(world, here, cell, max_step)
	return not path.is_empty()


## Läuft zu einer Handwerks-Station und öffnet sie bei Ankunft (Rechtsklick).
## `cell` ist die belegte Zelle der Station. false, wenn dort keine steht
## oder kein Weg daneben führt.
func walk_to_station(cell: Vector2i) -> bool:
	var node := world.blocker_at(cell)
	if not (node is Furniture and RecipeDB.is_station(node.id)):
		return false
	_cancel_task()
	var here := world.world_to_cell(global_position, level)
	var stand := GridPath.adjacent_to(world, cell, here, max_step)
	if stand.x == 2147483647:
		return false            # kein begehbares Feld neben der Station
	if stand == here:
		reached_station.emit(node.id)   # steht schon daneben
		return true
	path = GridPath.find(world, here, stand, max_step)
	if path.is_empty():
		return false
	_reach_station = node.id
	return true


## Läuft zu einem platzierten Objekt (Möbel/Lagerfeuer) und zerstört es bei
## Ankunft (Shift+Rechtsklick). Steht Jack schon daneben, sofort. false, wenn
## dort nichts Zerstörbares steht oder kein Weg daneben führt.
func walk_to_destroy(cell: Vector2i) -> bool:
	var node := world.blocker_at(cell)
	if not (node is Furniture or node is Campfire):
		return false
	_cancel_task()
	# Die Ankerzelle des Objekts nehmen, nicht die evtl. angeklickte Randzelle -
	# darüber findet der Server den Bau-Eintrag wieder.
	var anchor: Vector2i = node.cell
	var here := world.world_to_cell(global_position, level)
	var stand := GridPath.adjacent_to(world, anchor, here, max_step)
	if stand.x == 2147483647:
		return false            # kein begehbares Feld daneben
	if stand == here:
		_do_destroy(anchor)     # steht schon daneben
		return true
	path = GridPath.find(world, here, stand, max_step)
	if path.is_empty():
		return false
	_reach_destroy = anchor
	return true


## Entfernt das platzierte Objekt an `cell` lokal und meldet es (für die
## Persistenz und die anderen Spieler). Das Item kehrt NICHT ins Inventar zurück.
func _do_destroy(cell: Vector2i) -> void:
	var node := world.blocker_at(cell)
	if not (node is Furniture or node is Campfire):
		return
	var anchor: Vector2i = node.cell
	# queue_free löst tree_exiting aus -> die belegten Zellen werden wieder frei.
	node.queue_free()
	destroyed_placed.emit(anchor)


## Betten, in die sich Jack legen kann.
const BED_IDS := ["yatak", "portatif_yatak"]
## Liege-Pose entlang der Bett-Diagonale (Kopf oben-links am Kissen, Füsse
## unten-rechts). Gespiegeltes Bett spiegelt die Richtung mit.
const BED_FACING := "south_east"
const BED_FACING_FLIPPED := "south_west"
## Feinjustierung der Liegeposition. y leicht positiv, damit Jack in der
## Y-Sortierung VOR dem Bettrahmen liegt (er wird also ganz auf dem Bett
## gezeichnet, nicht dahinter).
const BED_POS_NUDGE := Vector2(0, 3)
## Zusaetzlicher Bild-Versatz beim Liegen: hebt das Sprite mittig auf die
## Matratze, OHNE den Fusspunkt (und damit die Y-Sortierung) zu verschieben.
## x wird beim gespiegelten Bett mitgespiegelt.
##
## PRO BETT, weil das Feldbett tiefer aufgesetzt ist (siehe furniture.gd): sein
## Wert ist um denselben Betrag gesenkt, damit die Liegepose relativ gleich
## bleibt. Standard = Wert des hohen Betts.
const BED_SLEEP_OFFSET := Vector2(-1, -12)
const BED_SLEEP_OFFSETS := {
	"yatak": Vector2(-1, -12),
	"portatif_yatak": Vector2(-1, 0),
}


## Ist auf dieser Zelle ein Bett?
func _bed_at(cell: Vector2i) -> Furniture:
	var node := world.blocker_at(cell)
	if node is Furniture and BED_IDS.has(node.id):
		return node
	return null


## Läuft zum Bett und legt sich bei Ankunft hinein (Rechtsklick). false, wenn
## dort kein Bett steht oder kein Weg daneben führt.
func walk_to_bed(cell: Vector2i) -> bool:
	var bed := _bed_at(cell)
	if bed == null:
		return false
	_cancel_task()
	var here := world.world_to_cell(global_position, level)
	var stand := GridPath.adjacent_to(world, cell, here, max_step)
	if stand.x == 2147483647:
		return false            # kein begehbares Feld neben dem Bett
	_bed_cell = cell
	if stand == here:
		_lie_down(cell)         # steht schon daneben
		return true
	path = GridPath.find(world, here, stand, max_step)
	if path.is_empty():
		return false
	_reach_bed = true
	return true


## Legt Jack ins Bett: Position auf die Bett-Mitte, passende Liege-Pose. Die
## Standfläche wird gemerkt, damit er beim Aufwachen wieder daneben steht.
func _lie_down(cell: Vector2i) -> void:
	var bed := _bed_at(cell)
	if bed == null:
		_play("idle")
		return
	_sleep_return_pos = global_position
	_sleep_return_level = level
	var center := world.footprint_long_center(bed.cell, bed.level)
	global_position = center + BED_POS_NUDGE
	level = bed.level
	_reparent_to_level()
	_sleeping = true
	facing = BED_FACING_FLIPPED if bed.flip_h else BED_FACING
	sprite.flip_h = CCFrames.flipped(facing)
	sprite.play("sleep_%s" % facing.replace("-", "_"))
	# Bild auf die Matratze heben; beim gespiegelten Bett den x-Versatz spiegeln.
	var off: Vector2 = BED_SLEEP_OFFSETS.get(bed.id, BED_SLEEP_OFFSET)
	if bed.flip_h:
		off.x = -off.x
	sprite.offset = sprite_offset + off
	if _zzz == null:
		_zzz = SleepZzzScript.new()
		_zzz.mirror = bed.flip_h     # Kopf liegt beim gespiegelten Bett rechts
		add_child(_zzz)


## Weckt Jack: zurück auf die gemerkte Standfläche, normale Anzeige.
func _wake_up() -> void:
	_sleeping = false
	sprite.offset = sprite_offset      # Liege-Bildversatz zuruecknehmen
	if _zzz != null:
		_zzz.queue_free()
		_zzz = null
	global_position = _sleep_return_pos
	level = _sleep_return_level
	_reparent_to_level()
	_play("idle")


## Läuft zum Stumpf und entfernt ihn mit einem Schlag - endgültig, es
## wächst danach nichts mehr nach.
func clear_stump(cell: Vector2i, stump_level: int) -> bool:
	if not chop(cell, stump_level):
		return false
	_clearing_stump = true
	return true


## Läuft zum Baum und fällt ihn. Steht Jack schon daneben, schlägt er sofort.
func chop(cell: Vector2i, prop_level: int) -> bool:
	# Ohne Axt in der Hand faellt hier gar nichts. Bewusst vor dem
	# Wegwerfen des laufenden Auftrags: ein Klick ins Leere soll nicht den
	# Weg abbrechen, auf dem Jack gerade ist.
	if not has_axe:
		chop_refused.emit()
		return false
	_cancel_task()
	var here := world.world_to_cell(global_position, level)
	var stand := GridPath.adjacent_to(world, cell, here, max_step)
	if stand.x == 2147483647:
		return false            # kein begehbares Feld neben dem Baum
	_chop_cell = cell
	_chop_level = prop_level
	if stand != here:
		path = GridPath.find(world, here, stand, max_step)
		if path.is_empty():
			_cancel_task()
			return false
	return true


func _cancel_task() -> void:
	# Ein neuer Auftrag (Klick) weckt Jack zuerst - er steht auf und geht dann
	# von der Standfläche neben dem Bett aus weiter.
	if _sleeping:
		_wake_up()
	path.clear()
	_pickup_cell = INVALID_CELL
	_reach_station = ""
	_reach_bed = false
	_reach_destroy = INVALID_CELL
	_chop_level = -1
	_chops_left = 0
	_clearing_stump = false
	busy = false                 # einen laufenden Axtschlag mit abbrechen
	if is_instance_valid(_tree):
		_tree.reset()
	_tree = null


## Bewegt Jack zum nächsten Wegpunkt. Ein Punkt gilt als erreicht, sobald
## er näher als ARRIVE_PX dran ist - sonst zappelt er auf der Stelle.
const ARRIVE_PX := 2.0
## Abstand der Prüfpunkte auf der Sichtlinie beim Glätten.
const LOS_SAMPLE_PX := 3.0
## So viele Wegpunkte werden pro Frame höchstens übersprungen. Deckelt die
## Sichtlinien-Tests bei langen Wegen.
const SMOOTH_LOOKAHEAD := 12

func _follow_path(delta: float) -> void:
	_smooth_path()
	var target := world.cell_to_world(path[0], world.top_level_at(path[0]))
	var to_target := target - global_position
	if to_target.length() <= ARRIVE_PX:
		global_position = target
		level = world.top_level_at(path[0])
		_reparent_to_level()
		path.remove_at(0)
		if path.is_empty() and _chop_level < 0 and _pickup_cell == INVALID_CELL:
			_play("idle")
		return

	# Blickrichtung aus der Bildschirmrichtung, Y-Stauchung herausgerechnet,
	# damit dieselben 8 Sektoren gelten wie bei der Tastatur.
	facing = DIRS[_dir_index(Vector2(to_target.x, to_target.y / y_squash))]
	_play("walk")
	var step := to_target.normalized() * walk_speed * delta
	if step.length() > to_target.length():
		step = to_target
	_try_move(Vector2(step.x, 0.0))
	_try_move(Vector2(0.0, step.y))


## Zellweise A*-Wege sehen aus wie Treppen. Deshalb wird vor jedem Schritt
## der am weitesten entfernte Wegpunkt gesucht, zu dem die direkte Linie frei
## ist - dazwischenliegende Punkte fallen weg. Ergebnis: Jack läuft schnurgerade
## und schneidet Kurven, statt am Raster entlangzuknicken.
func _smooth_path() -> void:
	var last := mini(path.size() - 1, SMOOTH_LOOKAHEAD)
	for i in range(last, 0, -1):
		var lvl := world.top_level_at(path[i])
		if lvl != level:
			continue                 # Höhenwechsel: lieber am Raster bleiben
		if _line_is_walkable(global_position, world.cell_to_world(path[i], lvl)):
			for _n in range(i):
				path.remove_at(0)
			return


## Ist die gerade Linie zwischen zwei Weltpunkten auf der aktuellen Ebene frei?
func _line_is_walkable(from: Vector2, to: Vector2) -> bool:
	var delta := to - from
	# In Iso-Pixeln ist ein Schritt (16, 8) - die Y-Achse doppelt so fein
	# abtasten wäre unnötig, LOS_SAMPLE_PX ist klein genug für beide.
	var steps := int(ceilf(delta.length() / LOS_SAMPLE_PX))
	for i in range(1, steps + 1):
		var p := from + delta * (float(i) / float(steps))
		if not _point_is_walkable(p):
			return false
	return true


## Prüft die Zelle unter einem Weltpunkt - und die beiden seitlich versetzten
## Punkte dazu, damit Jack nicht mit der Schulter durch eine Ecke rutscht.
func _point_is_walkable(p: Vector2) -> bool:
	for offset in [Vector2.ZERO, Vector2(3.0, 0.0), Vector2(-3.0, 0.0)]:
		var cell := world.world_to_cell(p + offset, level)
		if world.has_prop(cell):
			return false
		if world.top_level_at(cell) != level:
			return false
	return true


func _begin_chopping() -> void:
	var exists := world.has_stump(_chop_cell) if _clearing_stump else world.has_prop(_chop_cell)
	if not exists:
		_cancel_task()                      # Ziel ist inzwischen weg
		_play("idle")
		return
	# Blickrichtung auf den BODEN unter dem Baum, nicht auf die Prop-Ebene:
	# die liegt 8 px höher und würde die Richtung verfälschen.
	var ground := maxi(world.top_level_at(_chop_cell), 0)
	var to_tree := world.cell_to_world(_chop_cell, ground) - global_position
	facing = DIRS[_dir_index(Vector2(to_tree.x, to_tree.y / y_squash))]
	# Das Prop-Tile weicht einem Node, damit der Baum wackeln und umkippen
	# kann. Bei Abbruch setzt _cancel_task() das Tile zurück.
	if _clearing_stump:
		# Ein Stumpf braucht keinen wackelnden Node - ein Schlag genuegt.
		_chops_left = 1
		_start_axe()
		return
	_tree = world.prop_node(_chop_cell)
	if _tree == null:
		_cancel_task()
		_play("idle")
		return
	_chops_left = chops_to_fell
	_start_axe()


# --- Objekte setzen -----------------------------------------------------

## Stellt ein Lagerfeuer auf ein 2x2-Feld. `top` ist dessen oberste Zelle.
## Gibt false zurueck, wenn dort kein Platz ist - dann wird auch kein Item
## verbraucht.
func place_campfire_at(top: Vector2i) -> bool:
	if not world.can_place_2x2(top):
		return false
	var lvl := maxi(world.top_level_at(top), 0)
	var fire := Campfire.create(top, lvl)
	fire.cells = world.footprint_2x2(top)
	world.props_root.add_child(fire)
	fire.global_position = world.footprint_center(top, lvl)
	for c in fire.cells:
		world.block_cell(c, fire)
	var taken := fire.cells.duplicate()
	fire.tree_exiting.connect(func():
		for c in taken:
			world.unblock_cell(c))
	placed_campfire.emit(top)
	return true


## Stellt ein Moebel auf eine einzelne Zelle. `flipped` spiegelt es.
## Gibt false zurueck, wenn dort kein Platz ist - dann wird auch kein Item
## verbraucht.
func place_furniture_at(id: String, cell: Vector2i, orient: int) -> bool:
	var long := Furniture.is_long(id)
	var cells: Array[Vector2i] = []
	if long:
		if not world.can_place_long(cell):
			return false
		cells = world.footprint_long(cell)
	else:
		if not world.can_place_1x1(cell, Furniture.tileable(id)):
			return false
		cells = [cell]
	var lvl := maxi(world.top_level_at(cell), 0)
	var f := Furniture.create(world, id, cell, lvl, orient)
	world.props_root.add_child(f)
	f.global_position = world.footprint_long_center(cell, lvl) if long else world.cell_to_world(cell, lvl)
	for c in cells:
		world.block_cell(c, f)
	var taken := cells.duplicate()
	f.tree_exiting.connect(func():
		for c in taken:
			world.unblock_cell(c))
	placed_furniture.emit(id, cell, orient)
	return true


## Stein in Reichweite, oder INVALID_CELL wenn keiner nah genug liegt.
##
## Bewusst ueber den Bildschirmabstand statt ueber Nachbarzellen: eine Zelle
## hat in diesem Halbversatz-Raster nur vier Nachbarn, die seitlich
## anliegenden Zellen gehoeren NICHT dazu. Wer von der Seite ankommt, stuende
## optisch direkt am Stein und waere trotzdem "nicht in Reichweite".
const INVALID_CELL := Vector2i(2147483647, 2147483647)
## Greifweite in Zellen. Gemessen wird im Zellmass (ein Diamant ist 32x16 px
## gross), sonst reicht Jack in der Iso-Sicht nach oben und unten nur halb so
## weit wie zur Seite.
@export var pickup_radius := 1.25

func stone_in_reach() -> Vector2i:
	var best := INVALID_CELL
	var best_dist := INF
	for entry in world.prop_placements():
		if int(entry[3]) != IsoWorld.STONE_SOURCE_ID:
			continue
		var to_stone := world.cell_to_world(entry[0], entry[1]) - global_position
		var d := Vector2(to_stone.x / IsoWorld.TILE_SIZE.x,
			to_stone.y / IsoWorld.TILE_SIZE.y).length()
		if d <= pickup_radius and d < best_dist:
			best_dist = d
			best = entry[0]
	return best


## Laeuft zum Stein und hebt ihn auf. Liegt er schon in Reichweite, wird
## sofort zugegriffen. false, wenn dort keiner liegt oder kein Weg hinfuehrt.
func fetch_stone(cell: Vector2i) -> bool:
	_cancel_task()
	if not world.has_stone(cell):
		return false
	if stone_in_reach() == cell:
		return collect_stone(cell)
	var here := world.world_to_cell(global_position, level)
	# Steine blockieren nicht - man kann direkt auf ihre Zelle laufen.
	path = GridPath.find(world, here, cell, max_step)
	if path.is_empty():
		return false
	_pickup_cell = cell
	return true


## Hebt den Stein auf dieser Zelle auf. false, wenn dort keiner (mehr) liegt.
func collect_stone(cell: Vector2i) -> bool:
	var lvl := world.stone_level(cell)
	if lvl < 0:
		return false
	# Kurz hinschauen, das reicht als Geste - eine Aufheb-Animation hat
	# Jack nicht.
	var to_stone := world.cell_to_world(cell, lvl) - global_position
	if to_stone.length() > 1.0:
		facing = DIRS[_dir_index(Vector2(to_stone.x, to_stone.y / y_squash))]
		_play("idle")
	# Vor dem Entfernen abfragen - danach ist der Node weg.
	var what := world.gather_id_at(cell)
	world.remove_prop(cell, lvl)
	stone_collected.emit(cell, lvl, what)
	return true


## Lagerfeuer in Reichweite: die eigene Zelle und ihre Nachbarn.
## `only_ready` liefert nur Feuer, deren Fleisch fertig ist.
func campfire_in_reach(only_ready := false) -> Campfire:
	var here := world.world_to_cell(global_position, level)
	var cells: Array[Vector2i] = [here]
	cells.append_array(world.neighbors(here))
	for c in cells:
		var node := world.blocker_at(c)
		if node is Campfire and (not only_ready or node.is_ready()):
			return node
	return null


## Handwerks-Station in Reichweite (eigene Zelle + Nachbarn), oder "".
## Gibt die Station-Id zurueck (= die Moebel-Id, z. B. "calisma_tezgahi").
func station_in_reach() -> String:
	var here := world.world_to_cell(global_position, level)
	var cells: Array[Vector2i] = [here]
	cells.append_array(world.neighbors(here))
	for c in cells:
		var node := world.blocker_at(c)
		if node is Furniture and RecipeDB.is_station(node.id):
			return node.id
	return ""
