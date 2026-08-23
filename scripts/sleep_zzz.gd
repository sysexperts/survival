extends Node2D

## Aufsteigende "Z"-Zeichen ueber einer schlafenden Figur.
##
## KEIN class_name: wird nur per preload eingebunden (player.gd,
## remote_player.gd) - so haengt nichts an der Klassen-Registrierung, die der
## Auto-Updater nicht auffrischt (siehe chunk_manager.gd/WorldGen).
##
## Bewusst selbst gezeichnet (wie das Namensschild) statt Partikel: die
## Glyphen kommen aus demselben Bitmap-Font wie die restliche Oberflaeche,
## bleiben also pixelscharf, und ein Node2D laesst sich sauber ueber die
## Props heben - ein CPUParticles2D mit Buchstaben-Textur waere mehr Aufwand
## fuer dasselbe Bild.
##
## Wird von player.gd (eigene Figur) und remote_player.gd (Mitspieler) beim
## Einschlafen erzeugt und beim Aufwachen wieder entfernt. Lokaler Effekt -
## er braucht keinen Netzwerk-Sync, weil die Schlaf-Animation selbst schon
## synchron ist und jede Seite ihr eigenes Zzz zeichnet.

const FONT := "res://assets/fonts/pixel_bold.fnt"
const FONT_SIZE := 9
## Sekunden zwischen zwei Buchstaben.
const SPAWN_INTERVAL := 0.5
## Lebensdauer eines Buchstabens in Sekunden.
const LIFE := 1.5
## Startpunkt direkt am Kopf (Liege-Pose: Kopf oben-links).
const ORIGIN := Vector2(-14, -40)
## Aufstiegsgeschwindigkeit und seitliche Drift (Bildpixel/s) - klein halten,
## damit die Z dicht ueber dem Kopf bleiben und nicht wegfliegen.
const RISE := 5.0
const DRIFT := 3.0
const COLOR := Color(0.85, 0.9, 1.0)
const SHADOW := Color(0, 0, 0, 0.9)

var _font: Font
var _t := SPAWN_INTERVAL     ## sofort beim ersten Frame einen Buchstaben
## Jeder Eintrag: {"age": float, "scale": float}. Position folgt aus dem Alter,
## damit der Aufstieg deterministisch bleibt.
var _letters: Array = []


func _ready() -> void:
	_font = load(FONT)
	# Ueber allem in der Welt, nicht relativ zur Ebene der Figur - die haengt je
	# nach Hoehe an einem anderen Eltern-Node (siehe name_plate.gd).
	z_as_relative = false
	z_index = IsoWorld.TALL_Z_INDEX + 4


func _process(delta: float) -> void:
	_t += delta
	if _t >= SPAWN_INTERVAL:
		_t -= SPAWN_INTERVAL
		# Wechselnde Groesse ergibt das typische z-Z-z-Muster - klein gehalten.
		var s := 0.4 if _letters.size() % 2 == 0 else 0.55
		_letters.append({"age": 0.0, "scale": s})
	for l in _letters:
		l["age"] += delta
	_letters = _letters.filter(func(l): return l["age"] < LIFE)
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	for l in _letters:
		var age: float = l["age"]
		var f := age / LIFE                       # 0..1 ueber die Lebensdauer
		var pos := ORIGIN + Vector2(DRIFT * f, -RISE * age)
		# Sanft ein- und wieder ausblenden statt hart erscheinen.
		var a: float = clampf(sin(f * PI) * 1.4, 0.0, 1.0)
		var sc: float = l["scale"]
		# Font in Originalgroesse zeichnen und den Node-Zweig skalieren waere
		# global; hier stattdessen ueber einen Transform pro Buchstabe, damit
		# jeder seine eigene Groesse hat.
		draw_set_transform(pos, 0.0, Vector2(sc, sc))
		draw_string(_font, Vector2(1, 1), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_SIZE, Color(SHADOW.r, SHADOW.g, SHADOW.b, SHADOW.a * a))
		draw_string(_font, Vector2.ZERO, "Z", HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_SIZE, Color(COLOR.r, COLOR.g, COLOR.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
