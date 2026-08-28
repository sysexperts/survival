extends Node

## DORMANT bis Features.on("survival_needs"). Lässt Hunger/Durst/Stamina über
## die Zeit sinken; sind sie leer, sinkt Leben. Optional (eigene Flags) regeneriert
## Leben und wirkt Temperatur/Ermüdung. Solange die Flags aus sind, tut dieser
## Node nichts (früher return in _process).
##
## Aktivieren: features.gd -> "survival_needs" (und optional health_regen,
## temperature, fatigue) auf true. Zum Auffüllen: eat()/drink() aufrufen.

const Features := preload("res://scripts/features.gd")
const PlayerStats := preload("res://scripts/player_stats.gd")

## Verlust pro Sekunde.
const HUNGER_RATE := 0.15
const THIRST_RATE := 0.22
## Leben sinkt so schnell, wenn Hunger ODER Durst bei 0 ist.
const STARVE_DMG := 1.0
## Leben-Regeneration pro Sekunde (nur wenn health_regen an und satt/getränkt).
const REGEN_RATE := 0.5
## Stamina regeneriert im Stehen, sinkt beim Rennen (an die Bewegung gekoppelt).
const STAMINA_REGEN := 8.0

var _debug_label: Label = null
var _player: Node = null


func _process(delta: float) -> void:
	if not Features.on("survival_needs"):
		if _debug_label:
			_debug_label.visible = false
		return
	_ensure_debug()

	PlayerStats.hunger = maxf(0.0, PlayerStats.hunger - HUNGER_RATE * delta)
	PlayerStats.thirst = maxf(0.0, PlayerStats.thirst - THIRST_RATE * delta)

	if PlayerStats.hunger <= 0.0 or PlayerStats.thirst <= 0.0:
		PlayerStats.health = maxf(0.0, PlayerStats.health - STARVE_DMG * delta)
	elif Features.on("health_regen") and PlayerStats.health < PlayerStats.health_max:
		PlayerStats.health = minf(PlayerStats.health_max, PlayerStats.health + REGEN_RATE * delta)

	# Stamina füllt sich im Ruhezustand wieder.
	if PlayerStats.stamina < PlayerStats.stamina_max:
		PlayerStats.stamina = minf(PlayerStats.stamina_max, PlayerStats.stamina + STAMINA_REGEN * delta)

	if Features.on("death_respawn") and PlayerStats.health <= 0.0:
		_respawn()

	_update_debug()


func eat(amount: float) -> void:
	PlayerStats.hunger = clampf(PlayerStats.hunger + amount, 0.0, PlayerStats.hunger_max)


func drink(amount: float) -> void:
	PlayerStats.thirst = clampf(PlayerStats.thirst + amount, 0.0, PlayerStats.thirst_max)


func _respawn() -> void:
	# Werte zurücksetzen; die eigentliche Positions-Logik übernähme der Player
	# beim Aktivieren (hier bewusst schlicht gehalten).
	PlayerStats.health = PlayerStats.health_max
	PlayerStats.hunger = PlayerStats.hunger_max
	PlayerStats.thirst = PlayerStats.thirst_max


## Kleine Text-Anzeige, damit man das System beim Aktivieren sofort sieht.
func _ensure_debug() -> void:
	if _debug_label != null:
		_debug_label.visible = true
		return
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_debug_label = Label.new()
	_debug_label.position = Vector2(12, 96)
	_debug_label.add_theme_font_size_override("font_size", 11)
	_debug_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	layer.add_child(_debug_label)


func _update_debug() -> void:
	if _debug_label:
		_debug_label.text = "Aclik %d  Susuzluk %d  Can %d" % [
			int(PlayerStats.hunger), int(PlayerStats.thirst), int(PlayerStats.health)]
