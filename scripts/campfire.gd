extends AnimatedSprite2D
class_name Campfire

## Ein gesetztes Lagerfeuer.
##
## Ablauf, wie im markierten Sheet vorgegeben:
##   anzuenden -> "brennt" (Frames 5-10, mit Fleisch am Spiess)
##   nach cook_seconds -> "fertig" (Frame 11, Fleisch durchgebraten)
##   abgeholt -> "aus" (Frame 3, Feuer erloschen)
##
## Frame 4 liegt als "ohne_fleisch" bereit, falls spaeter ein Feuer ohne
## Spiessgut gebraucht wird.
##
## Haengt im y-sortierten Props-Container, sortiert sich also korrekt
## zwischen Baeume und Figuren ein.

signal meat_ready
signal collected

enum State { AUS, BRENNT, FERTIG }

## Verkleinerung des Camp-Sheets. An einer Stelle, damit die Vorschau
## dieselbe Groesse zeigt wie das gesetzte Feuer.
## Das Sheet ist groesser gezeichnet als Tiles und Figuren: 101 px breit
## gegenueber 32 px beim Baum.
const ART_SCALE := 0.5

## Ankerpunkt im 128er-Frame. Er landet auf der Mitte des 2x2-Feldes.
## x = 64 ist die waagerechte Mitte des gesamten Bildinhalts (13..113) -
## nicht die Mitte des Feuers, denn die rechte Spiessstange steht weiter
## raus als die linke und wuerde es sonst rechtslastig wirken lassen.
## y = 88 setzt die Aschflaeche so, dass sie das Feld ausfuellt.
const ART_OFFSET := Vector2(-64, -88)

## Sekunden, bis das Fleisch durchgebraten ist.
@export var cook_seconds := 30.0
## Verkleinerung: Das Camp-Sheet ist groesser gezeichnet als Tiles und Figuren.
@export var art_scale := ART_SCALE

var cell: Vector2i          ## oberste Zelle des 2x2-Feldes
var level: int
var cells: Array[Vector2i] = []   ## alle vier belegten Zellen
var state: State = State.AUS

var _left := 0.0
var _light: PointLight2D
var _embers: CPUParticles2D


static func create(p_cell: Vector2i, p_level: int) -> Campfire:
	var c := Campfire.new()
	c.cell = p_cell
	c.level = p_level
	c.sprite_frames = preload("res://resources/campfire_frames.tres")
	c.centered = false
	return c


func _ready() -> void:
	scale = Vector2(art_scale, art_scale)
	offset = ART_OFFSET
	# Etwas schwaecher: ein Feuer steht flach und wirft weniger Masse.
	var sh := CastShadow.create(self)
	sh.extra_alpha = 0.7
	add_child(sh)
	_build_light()
	_build_embers()
	light()


func _build_light() -> void:
	_light = PointLight2D.new()
	_light.texture = preload("res://resources/light_gradient.tres")
	_light.color = Color(1, 0.66, 0.30)
	_light.energy = 0.9
	_light.texture_scale = 2.2 / maxf(art_scale, 0.01)
	_light.position = Vector2(-6, -24)     # Flammenmitte, relativ zum Anker
	_light.set_script(preload("res://scripts/flicker_light.gd"))
	_light.base_energy = 0.9
	_light.flicker_amount = 0.26
	_light.flicker_speed = 9.0
	add_child(_light)


func _build_embers() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_embers = CPUParticles2D.new()
	_embers.texture = ImageTexture.create_from_image(img)
	_embers.amount = 12
	_embers.lifetime = 1.4
	_embers.position = Vector2(-6, -16)    # Flammenbasis
	_embers.direction = Vector2(0, -1)
	_embers.spread = 18.0
	_embers.initial_velocity_min = 12.0
	_embers.initial_velocity_max = 30.0
	_embers.gravity = Vector2(0, -6)
	_embers.scale_amount_min = 0.6
	_embers.scale_amount_max = 1.3
	_embers.color = Color(1, 0.62, 0.22, 0.9)
	_embers.z_index = 1
	add_child(_embers)


## Zuendet das Feuer an. Das Fleisch braet ab diesem Moment.
func light() -> void:
	state = State.BRENNT
	_left = cook_seconds
	play("brennt")
	_light.visible = true
	_embers.emitting = true


func _process(delta: float) -> void:
	if state != State.BRENNT:
		return
	_left -= delta
	if _left <= 0.0:
		state = State.FERTIG
		play("fertig")
		meat_ready.emit()


## Restzeit bis das Fleisch fertig ist, -1 wenn gerade nichts braet.
func time_left() -> float:
	return _left if state == State.BRENNT else -1.0


func is_ready() -> bool:
	return state == State.FERTIG


## Fleisch abholen: Feuer geht aus, Frame 3.
func collect() -> bool:
	if state != State.FERTIG:
		return false
	state = State.AUS
	play("aus")
	_light.visible = false
	_embers.emitting = false
	collected.emit()
	return true
