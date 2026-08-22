@tool
extends CanvasModulate

## Tag/Nacht-Zyklus. Faerbt die gesamte 2D-Szene ein; alles, was heller
## werden soll, braucht ein Light2D.
##
## Als @tool laeuft die Vorschau auch im Editor: `time_of_day` schieben
## und die Stimmung direkt im Viewport sehen.

## 0.0 = Mitternacht, 0.25 = Sonnenaufgang, 0.5 = Mittag, 0.75 = Sonnenuntergang
@export_range(0.0, 1.0, 0.001) var time_of_day := 0.66:
	set(v):
		time_of_day = v
		_apply()

## Sekunden fuer einen vollen Tag. 0 = Zyklus steht still.
@export var day_length := 1200.0

## Farbverlauf ueber den Tag. Leer lassen -> Standardverlauf.
@export var sky_gradient: Gradient:
	set(v):
		sky_gradient = v
		_apply()


func _ready() -> void:
	add_to_group("day_night")
	if sky_gradient == null:
		sky_gradient = _default_gradient()
	_apply()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or day_length <= 0.0:
		return
	time_of_day = fposmod(time_of_day + delta / day_length, 1.0)


func _apply() -> void:
	var g := sky_gradient if sky_gradient != null else _default_gradient()
	color = g.sample(time_of_day)


## Nacht -> Daemmerung -> Tag -> Abendrot -> Nacht
func _default_gradient() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.00, 0.22, 0.30, 0.40, 0.60, 0.72, 0.84, 1.00])
	g.colors = PackedColorArray([
		Color(0.52, 0.58, 0.85),   # Mitternacht (kuehl, aber noch lesbar)
		Color(0.56, 0.61, 0.86),   # spaete Nacht
		Color(0.86, 0.78, 0.80),   # Sonnenaufgang
		Color(1.00, 0.99, 0.96),   # Vormittag
		Color(1.00, 0.97, 0.92),   # Nachmittag
		Color(1.00, 0.87, 0.74),   # goldene Stunde
		Color(0.74, 0.70, 0.86),   # Daemmerung
		Color(0.52, 0.58, 0.85),   # Mitternacht
	])
	return g


# --- Sonnenstand ---------------------------------------------------------
#
# Die Sonne wandert von Osten (Sonnenaufgang) nach Westen. Schatten zeigen
# entgegengesetzt: morgens nach Westen, mittags kurz nach vorn, abends nach
# Osten. Alles nur aus `time_of_day` abgeleitet, kein eigener Zustand.

## Beginn und Ende des Tages auf der 0..1-Skala.
@export var sunrise := 0.26
@export var sunset := 0.80
## Schattenlaenge bei tiefstehender bzw. hochstehender Sonne.
@export var shadow_length_low := 1.9
@export var shadow_length_high := 0.55
## Deckkraft des Schattens am hellen Tag.
@export var shadow_alpha := 0.34


## Wie hoch die Sonne steht: 0 bei Auf- und Untergang, 1 mittags.
func sun_elevation() -> float:
	var a := inverse_lerp(sunrise, sunset, time_of_day)
	if a <= 0.0 or a >= 1.0:
		return 0.0
	return sin(a * PI)


## Richtung, in die Schatten fallen - Bildschirmvektor, normalisiert.
## Das Y ist bewusst flach gehalten, damit der Schatten auf der
## Iso-Bodenebene liegt statt senkrecht nach unten zu kippen.
func shadow_dir() -> Vector2:
	var a := clampf(inverse_lerp(sunrise, sunset, time_of_day), 0.0, 1.0)
	return Vector2(lerpf(-1.0, 1.0, a), 0.5).normalized()


## Streckung: lang bei tiefer Sonne, kurz mittags.
func shadow_length() -> float:
	return lerpf(shadow_length_low, shadow_length_high, sun_elevation())


## Deckkraft. Nachts null, an den Raendern weich ein- und ausgeblendet.
func shadow_strength() -> float:
	var a := inverse_lerp(sunrise, sunset, time_of_day)
	if a <= 0.0 or a >= 1.0:
		return 0.0
	return shadow_alpha * smoothstep(0.0, 0.12, a) * smoothstep(0.0, 0.12, 1.0 - a)


## 0.0 = heller Tag, 1.0 = tiefe Nacht. Fuer Lichter, die nur nachts
## angehen sollen (Laterne, Strassenlaternen, Gegner-Spawns ...).
func darkness() -> float:
	return clampf((1.0 - color.get_luminance()) * 1.6, 0.0, 1.0)
