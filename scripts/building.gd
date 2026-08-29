extends Sprite2D

## Ein vor Ort errichtetes Gebaeude (Baraka).
##
## Anders als ein Moebel ist ein Gebaeude nicht sofort fertig: es belegt ein
## 4x4-Feld auf ebenem Boden und baut sich ueber `TOTAL_SECONDS` in drei Phasen
## selbst. Welche Phase gerade zu sehen ist, ergibt sich allein aus der
## verstrichenen Zeit seit `started` (einem Unix-Zeitstempel) - so zeigen alle
## Clients und ein neu geladener Spielstand dieselbe Phase, ohne dass ein
## Fortschritt mitsynchronisiert werden muss.
##
## KEIN `class_name`: neue benannte Klassen werden vom Auto-Updater (game.pck
## ueber die Basis-.exe) nicht registriert. Ueberall per preload einbinden.

## Gesamtbauzeit und die zwei Phasengrenzen (Sekunden). 0-300 Geruest,
## 300-600 halbfertig, ab 600 fertig.
const TOTAL_SECONDS := 600.0
const PHASE1_AT := 300.0

## Die drei Phasen-Sprites. Reihenfolge: Geruest -> halbfertig -> fertig.
const TEX := [
	preload("res://assets/game_assets/buildings/shelter_scaffold.png"),
	preload("res://assets/game_assets/buildings/shelter_half.png"),
	preload("res://assets/game_assets/buildings/shelter_done.png"),
]

## Die 136er-Sprites auf dem 4x4-Feld: waagerecht mittig (offset.x = -68),
## der Fuss des Hauses knapp unter die Rautenmitte gelegt.
const ART_OFFSET := Vector2(-68, -104)

var id := "baraka"
var cell: Vector2i                 ## oberste Zelle der 4x4-Raute
var level: int
var cells: Array[Vector2i] = []
var started := 0.0                 ## Unix-Zeit des Baubeginns
var world = null

var _phase := -1


static func create(p_world, p_id: String, p_top: Vector2i, p_level: int, p_started: float):
	var b = new()
	b.world = p_world
	b.id = p_id
	b.cell = p_top
	b.level = p_level
	b.started = p_started
	b.centered = false
	b.offset = ART_OFFSET
	return b


func _ready() -> void:
	_update_phase()


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
	texture = TEX[p]


func _process(_delta: float) -> void:
	# Fertig gebaut: nichts mehr zu tun, Prozess einstellen.
	if _phase >= 2:
		set_process(false)
		return
	_update_phase()
