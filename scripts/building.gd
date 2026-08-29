extends Sprite2D

## Ein vor Ort errichtetes Gebaeude (Baraka).
##
## Anders als ein Moebel ist ein Gebaeude nicht sofort fertig: es belegt ein
## 4x4-Feld auf ebenem Boden und baut sich ueber `TOTAL_SECONDS` in drei Phasen
## selbst. Welche Phase gerade zu sehen ist, ergibt sich allein aus der
## verstrichenen Zeit seit `started` (einem Unix-Zeitstempel) - so zeigen alle
## Clients und ein neu geladener Spielstand dieselbe Phase, ohne dass ein
## Fortschritt mitsynchronisiert werden muss. Ueber dem Bau laeuft bis zur
## Fertigstellung ein Countdown.
##
## Wie ein Richtungs-Moebel hat das Gebaeude acht Ansichten (orient 0..7); die
## Drehung waehlt beim Platzieren die passende.
##
## KEIN `class_name`: neue benannte Klassen werden vom Auto-Updater (game.pck
## ueber die Basis-.exe) nicht registriert. Ueberall per preload einbinden.

## Gesamtbauzeit und die zwei Phasengrenzen (Sekunden). 0-300 Geruest,
## 300-600 halbfertig, ab 600 fertig.
const TOTAL_SECONDS := 600.0
const PHASE1_AT := 300.0

## Phasen-Ordner-Praefix und die acht Richtungsdateien (im Uhrzeigersinn ab
## Sued - dieselbe Reihenfolge wie ItemDB.DIR_FILE).
const PHASE_NAME := ["scaffold", "half", "done"]
const DIR_FILE := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]

## Die 136er-Sprites auf dem 4x4-Feld: waagerecht mittig (offset.x = -68),
## der Fuss des Hauses knapp unter die Rautenmitte gelegt.
const ART_OFFSET := Vector2(-68, -104)

static var _cache: Dictionary = {}

## Textur fuer Phase (0..2) und Ausrichtung (0..7), einmal geladen und gemerkt.
static func tex(phase: int, orient: int) -> Texture2D:
	var key := "%d#%d" % [phase, orient % 8]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = load("res://assets/game_assets/buildings/shelter_%s_%s.png"
		% [PHASE_NAME[phase], DIR_FILE[orient % 8]])
	_cache[key] = t
	return t

var id := "baraka"
var cell: Vector2i                 ## oberste Zelle der 4x4-Raute
var level: int
var orient := 0                    ## 0..7 (S, SO, O, NO, N, NW, W, SW)
var cells: Array[Vector2i] = []
var started := 0.0                 ## Unix-Zeit des Baubeginns
var world = null

var _phase := -1
var _timer: Label


static func create(p_world, p_id: String, p_top: Vector2i, p_level: int, p_orient: int, p_started: float):
	var b = new()
	b.world = p_world
	b.id = p_id
	b.cell = p_top
	b.level = p_level
	b.orient = p_orient
	b.started = p_started
	b.centered = false
	b.offset = ART_OFFSET
	return b


func _ready() -> void:
	# Countdown-Label ueber dem Dach. Als eigenes Control-Kind; top_level, damit
	# es die Sprite-Groesse/Position nicht erbt und immer waagerecht bleibt.
	_timer = Label.new()
	_timer.add_theme_font_size_override("font_size", 11)
	_timer.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	_timer.add_theme_constant_override("outline_size", 4)
	_timer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.z_index = 100
	add_child(_timer)
	_update_phase()
	_update_timer()


## Wie viele Sekunden laeuft der Bau schon?
func _elapsed() -> float:
	return Time.get_unix_time_from_system() - started


func _phase_for(elapsed: float) -> int:
	if elapsed < PHASE1_AT:
		return 0
	elif elapsed < TOTAL_SECONDS:
		return 1
	return 2


func is_done() -> bool:
	return _elapsed() >= TOTAL_SECONDS


func _update_phase() -> void:
	var p := _phase_for(_elapsed())
	if p == _phase:
		return
	_phase = p
	texture = tex(p, orient)


## Countdown "M:SS" mittig ueber dem Dach, oder verstecken wenn fertig.
func _update_timer() -> void:
	if _timer == null:
		return
	var rest := TOTAL_SECONDS - _elapsed()
	if rest <= 0.0:
		_timer.visible = false
		return
	_timer.text = "%d:%02d" % [int(rest) / 60, int(rest) % 60]
	# Nach dem Setzen des Textes die Groesse kennen, um mittig ueber der
	# Bild-Mitte (offset.x + 68) und knapp ueber dem Sprite (offset.y) zu sitzen.
	_timer.reset_size()
	_timer.position = Vector2(-_timer.size.x * 0.5, ART_OFFSET.y - 14)


func _process(_delta: float) -> void:
	_update_timer()
	# Fertig gebaut: Phase feststehen lassen, Prozess einstellen.
	if _phase >= 2:
		set_process(false)
		return
	_update_phase()
