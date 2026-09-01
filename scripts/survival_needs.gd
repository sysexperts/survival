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
		return
	# Anzeige laeuft ueber die Balken oben links (stats_hud), keine Debug-Zeile mehr.

	PlayerStats.hunger = maxf(0.0, PlayerStats.hunger - HUNGER_RATE * delta)
	# Durst nur, wenn eigens aktiviert (sonst gaebe es ohne Trinkquelle keinen
	# Ausweg). Bleibt sonst voll und loest keinen Schaden aus.
	var thirst_on := Features.on("thirst")
	if thirst_on:
		PlayerStats.thirst = maxf(0.0, PlayerStats.thirst - THIRST_RATE * delta)

	# Verhungern/Verdursten zieht Leben ab; satt regeneriert Leben langsam.
	# Beides gehoert fest zum aktiven Survival-Loop (survival_needs an) - nicht
	# mehr an die getrennten Dormant-Flags gekoppelt, sonst blieb Leben bei 0
	# haengen bzw. erholte sich nie (Bugs B3/B4).
	if PlayerStats.hunger <= 0.0 or (thirst_on and PlayerStats.thirst <= 0.0):
		PlayerStats.health = maxf(0.0, PlayerStats.health - STARVE_DMG * delta)
	elif PlayerStats.health < PlayerStats.health_max:
		PlayerStats.health = minf(PlayerStats.health_max, PlayerStats.health + REGEN_RATE * delta)

	# Stamina füllt sich im Ruhezustand wieder.
	if PlayerStats.stamina < PlayerStats.stamina_max:
		PlayerStats.stamina = minf(PlayerStats.stamina_max, PlayerStats.stamina + STAMINA_REGEN * delta)

	if PlayerStats.health <= 0.0:
		_die()


func eat(amount: float) -> void:
	PlayerStats.hunger = clampf(PlayerStats.hunger + amount, 0.0, PlayerStats.hunger_max)


func drink(amount: float) -> void:
	PlayerStats.thirst = clampf(PlayerStats.thirst + amount, 0.0, PlayerStats.thirst_max)


## Tod durch Verhungern/Verdursten: Werte zuruecksetzen UND den Spieler an
## seinen Wiederbelebungspunkt (Bett/Start) versetzen - dieselbe respawn()-Logik
## wie beim Magier-Tod, damit Leben nicht bei 0 haengen bleibt (Bug B3).
func _die() -> void:
	PlayerStats.health = PlayerStats.health_max
	PlayerStats.hunger = PlayerStats.hunger_max
	PlayerStats.thirst = PlayerStats.thirst_max
	PlayerStats.stamina = PlayerStats.stamina_max
	var p := _get_player()
	if p != null and p.has_method("respawn"):
		p.respawn()


func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player


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
		if Features.on("thirst"):
			_debug_label.text = "Can %d  Aclik %d  Susuzluk %d" % [
				int(PlayerStats.health), int(PlayerStats.hunger), int(PlayerStats.thirst)]
		else:
			_debug_label.text = "Can %d  Aclik %d" % [int(PlayerStats.health), int(PlayerStats.hunger)]
