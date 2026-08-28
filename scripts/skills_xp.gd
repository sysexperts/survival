extends Node

## DORMANT bis Features.on("skills_xp"). Vergibt Erfahrung für Tätigkeiten
## (Fällen, Handwerk, Bauen) und rechnet daraus Level - passt zum Skills-Tab im
## Buch. Solange das Flag aus ist, wird keine XP vergeben (Handler früher return).
##
## Aktivieren: features.gd -> "skills_xp" = true. Danach zeigt eine kleine
## Anzeige das Fäll-Level; die Anbindung an den Skills-Tab folgt beim Aktivieren.

const Features := preload("res://scripts/features.gd")

## Skill-Schlüssel -> XP (roh). Level = floor(sqrt(xp / 10)).
static var xp := {"woodcutting": 0.0, "crafting": 0.0, "building": 0.0}

const XP_PER_CHOP := 5.0
const XP_PER_CRAFT := 8.0
const XP_PER_BUILD := 10.0
## Kleiner XP-Gewinn pro GEFAELLTEM Baum - fuellt die EXP-Leiste in der
## Itemleiste. Bewusst NICHT ans Feature-Flag gebunden (Test/Grundfortschritt).
const XP_PER_FELL := 4.0

var _player: Node = null
var _label: Label = null


func _ready() -> void:
	# Der Spieler joint die Gruppe erst spaeter (Parent-Wechsel, Netzwerk) -
	# darum das Verbinden wiederholen, bis er da ist. Sonst kommt nie XP an.
	_hook_player.call_deferred()


func _hook_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		get_tree().create_timer(1.0).timeout.connect(_hook_player)
		return
	if _player.has_signal("axe_swung") and not _player.axe_swung.is_connected(_on_chop):
		_player.axe_swung.connect(_on_chop)
	# Pro gefaelltem Baum ein bisschen XP - immer aktiv (speist die EXP-Leiste).
	if _player.has_signal("felled") and not _player.felled.is_connected(_on_felled):
		_player.felled.connect(_on_felled)


func _on_felled(_cell: Vector2i, _level: int, _atlas: Vector2i) -> void:
	xp["woodcutting"] += XP_PER_FELL


func _on_chop() -> void:
	if not Features.on("skills_xp"):
		return
	xp["woodcutting"] += XP_PER_CHOP
	_show()


static func award(skill: String, amount: float) -> void:
	if not Features.on("skills_xp"):
		return
	if xp.has(skill):
		xp[skill] += amount


static func level_of(skill: String) -> int:
	return int(floor(sqrt(xp.get(skill, 0.0) / 10.0)))


## Gesamt-XP ueber alle Skills - Grundlage fuer das Spieler-Level (EXP-Leiste
## + Stern in der Itemleiste). level = floor(sqrt(gesamt/10)); xp_fuer(L)=10*L^2.
static func total_xp() -> float:
	var sum := 0.0
	for v in xp.values():
		sum += v
	return sum


static func player_level() -> int:
	return int(floor(sqrt(total_xp() / 10.0)))


## Fortschritt zum naechsten Level, 0..1 (fuer die Fuellung der EXP-Leiste).
static func level_progress() -> float:
	var lvl := player_level()
	var base := 10.0 * lvl * lvl
	var next := 10.0 * (lvl + 1) * (lvl + 1)
	var span := next - base
	if span <= 0.0:
		return 0.0
	return clampf((total_xp() - base) / span, 0.0, 1.0)


func _show() -> void:
	if _label == null:
		var layer := CanvasLayer.new()
		layer.layer = 90
		add_child(layer)
		_label = Label.new()
		_label.position = Vector2(12, 112)
		_label.add_theme_font_size_override("font_size", 11)
		_label.add_theme_color_override("font_color", Color(0.8, 1, 0.85))
		layer.add_child(_label)
	_label.text = "Oduncu Sv %d" % level_of("woodcutting")
