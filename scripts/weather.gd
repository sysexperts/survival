extends CanvasLayer

## Wetter (Regen), server-autoritativ und bei allen gleich.
##
## Rollen (wie bei time_sync.gd):
##   * Dedizierter Server: bestimmt, ob es regnet. Faengt von selbst ab und zu an
##     und hoert wieder auf; ausserdem per Admin-Befehl /rain umschaltbar. Schickt
##     den Zustand an alle Clients (und neuen Beitretenden sofort).
##   * Client: zeigt Regen-Tropfen (Bildschirm-Overlay) und laesst die Welt ueber
##     day_night.rain_dim etwas dunkler werden.
##   * Einzelspieler (Net.active == false): laeuft lokal, faengt auch ab und zu an.
##
## KEIN class_name / Autoload (Auto-Updater-Regel) - haengt als Node in main.tscn.

## Wie stark es beim Regnen schuettet (0..1) - steuert Tropfenzahl und Dunkelheit.
const RAIN_STRENGTH := 1.0
## Server: Grenzen fuer die zufaellige Dauer von Trocken- und Regenphasen (Sek.).
const DRY_MIN := 180.0
const DRY_MAX := 480.0
const WET_MIN := 60.0
const WET_MAX := 150.0
## Wahrscheinlichkeit, mit der eine automatische Phase ueberhaupt in Regen kippt.
## (Sonst bliebe es haeufiger einfach trocken.)
const AUTO_RAIN_CHANCE := 0.6

var _day: Node
var _raining := false
## Server/SP: Restzeit der aktuellen Phase.
var _phase_left := 0.0
## Vom Admin erzwungen? Dann keine automatische Umschaltung mehr, bis /rain erneut.
var _forced := false

var _drops: CPUParticles2D
var _overlay: ColorRect
## WorldEnvironment-Glow: das Softlight-Glow malt auf der abgedunkelten Welt sonst
## einen hellen Hof um JEDE Kachel (Diamant-Gitter). Bei Regen deshalb stark
## zuruecknehmen. Ausgangswert wird beim Aufbau gemerkt und beim Aufklaren
## wiederhergestellt.
var _env: Environment
var _glow_clear := 0.72
const GLOW_RAIN_MUL := 0.65


func _ready() -> void:
	add_to_group("weather")
	layer = 80                      # ueber der Welt, unter Menue/Chat (90+)
	_day = get_tree().get_first_node_in_group("day_night")
	if not Net.is_dedicated:
		_build_visuals()
		_apply_visuals()
	# Server UND Einzelspieler treiben den Zustand. Reiner Client (Net.active und
	# nicht dedicated) bekommt ihn nur zugeschickt.
	if Net.is_dedicated:
		multiplayer.peer_connected.connect(func(id): _set_rain.rpc_id(id, _raining))
		_phase_left = randf_range(DRY_MIN, DRY_MAX)
	elif not Net.active:
		_phase_left = randf_range(DRY_MIN, DRY_MAX)


func _process(delta: float) -> void:
	# Nur die "Uhr" (Server oder Einzelspieler) schaltet automatisch um.
	var drives := Net.is_dedicated or not Net.active
	if drives and not _forced:
		_phase_left -= delta
		if _phase_left <= 0.0:
			_advance_phase()


## Naechste Wetterphase wuerfeln (Server/Einzelspieler).
func _advance_phase() -> void:
	if _raining:
		_set_state(false)
		_phase_left = randf_range(DRY_MIN, DRY_MAX)
	else:
		var wet := randf() < AUTO_RAIN_CHANCE
		_set_state(wet)
		_phase_left = randf_range(WET_MIN, WET_MAX) if wet else randf_range(DRY_MIN, DRY_MAX)


## Admin-Befehl /rain: Regen erzwingen/beenden. `on` true = Regen an. Bleibt so,
## bis erneut per Befehl umgeschaltet wird (kein Auto-Wechsel mehr).
func set_rain_forced(on: bool) -> void:
	_forced = true
	_set_state(on)


## Setzt den Zustand lokal und - wenn wir die Autoritaet sind - verteilt ihn.
func _set_state(on: bool) -> void:
	_raining = on
	if Net.is_dedicated:
		_set_rain.rpc(on)
	if not Net.is_dedicated:
		_apply_visuals()


@rpc("authority", "call_remote", "reliable")
func _set_rain(on: bool) -> void:
	# Nur echte Clients empfangen (Server sendet, Einzelspieler ist nie im Netz).
	if Net.is_dedicated:
		return
	_raining = on
	_apply_visuals()


func is_raining() -> bool:
	return _raining


# --- Optik (nur Client / Einzelspieler) ----------------------------------

func _apply_visuals() -> void:
	if _day:
		_day.rain_dim = RAIN_STRENGTH if _raining else 0.0
	if _drops:
		_drops.emitting = _raining
	if _overlay:
		# Sanft ein-/ausblenden.
		create_tween().tween_property(_overlay, "color:a", 0.14 if _raining else 0.0, 0.8)
	if _env:
		# Glow bei Regen etwas zuruecknehmen (bewoelkt = weniger Nachglueh). Das
		# Diamant-Gitter kam aber NICHT vom Glow, sondern von der durchscheinenden
		# Hintergrundfarbe - das behebt der Kamera-Hintergrund (follow_camera.gd).
		var target: float = _glow_clear * GLOW_RAIN_MUL if _raining else _glow_clear
		create_tween().tween_property(_env, "glow_intensity", target, 0.8)


func _build_visuals() -> void:
	# WorldEnvironment-Glow merken (fuer die Regen-Daempfung).
	var we := get_node_or_null(^"../WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		_env = we.environment
		_glow_clear = _env.glow_intensity
	# Halbtransparenter, kuehler Schleier zusaetzlich zur Welt-Abdunklung.
	_overlay = ColorRect.new()
	_overlay.color = Color(0.10, 0.13, 0.20, 0.0)   # Alpha kommt aus dem Regen
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	var vp := get_viewport().get_visible_rect().size
	_drops = CPUParticles2D.new()
	_drops.texture = _streak_texture()
	_drops.amount = 320
	_drops.lifetime = 0.7
	_drops.preprocess = 0.7
	_drops.local_coords = false
	# Emitter als breite Linie ueber dem oberen Bildrand (etwas Rand fuer den Wind).
	_drops.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drops.emission_rect_extents = Vector2(vp.x * 0.75, 2)
	_drops.position = Vector2(vp.x * 0.5, -20)
	_drops.direction = Vector2(-0.25, 1)      # leicht schraeg (Wind)
	_drops.spread = 4.0
	_drops.gravity = Vector2(0, 1400)
	_drops.initial_velocity_min = 900.0
	_drops.initial_velocity_max = 1200.0
	_drops.scale_amount_min = 0.7
	_drops.scale_amount_max = 1.3
	_drops.color = Color(0.75, 0.82, 0.95, 0.55)
	_drops.emitting = false
	add_child(_drops)
	# Bei Fenstergroesse-Aenderung den Emitter neu spannen.
	get_viewport().size_changed.connect(_resize_emitter)


func _resize_emitter() -> void:
	if _drops == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_drops.emission_rect_extents = Vector2(vp.x * 0.75, 2)
	_drops.position = Vector2(vp.x * 0.5, -20)


## Kleine senkrechte Regenstreifen-Textur (ohne externe Datei).
func _streak_texture() -> Texture2D:
	var img := Image.create(2, 14, false, Image.FORMAT_RGBA8)
	for y in range(14):
		var a: float = 0.9 * (1.0 - absf(float(y) / 13.0 - 0.5) * 1.4)
		var col := Color(1, 1, 1, clampf(a, 0.0, 1.0))
		img.set_pixel(0, y, col)
		img.set_pixel(1, y, col)
	return ImageTexture.create_from_image(img)
