extends Node2D
class_name NamePlate

## Der Spielername über der Figur, so wie man es aus Online-Spielen kennt.
##
## Bewusst kein Label, sondern selbst gezeichnet: ein Control müsste erst
## ausgemessen und ausgerichtet werden, und die Zeichenreihenfolge liesse
## sich nicht sauber über die Props heben. Ein Node2D kann beides.
##
## Zur Schriftgrösse: der Font ist ein Bitmap-Font mit fester Rasterhöhe
## und wird genau in dieser Grösse gezeichnet, damit ein Schriftpixel ein
## Bildpixel bleibt. Die Verkleinerung auf `text_scale` und der vierfache
## Kamerazoom ergeben zusammen eine glatte Verdopplung - also scharf.

## Fette Variante, und kleiner gerastert als die Oberflächenschrift: über
## einer Figur soll der Name lesbar sein, ohne sich in den Vordergrund zu
## drängen.
const FONT := "res://assets/fonts/pixel_bold.fnt"
## Rasterhöhe der Vorlage. Andere Werte verwaschen die Glyphen.
const FONT_SIZE := 9
## Gamemaster-Abzeichen (64x64) und die zentrale Admin-Pruefung. Beides per
## preload, damit es auch ueber den Auto-Updater greift (siehe admins.gd).
const GM_TEX := preload("res://assets/gamemaster.png")
const AdminsScript := preload("res://scripts/admins.gd")
## Anzeigegroesse des Abzeichens ueber dem Namen (lokale Pixel, vor node scale).
const GM_SIZE := 30.0

## Laufzeit fuer die GM-Animation (Float, Glow-Puls, Funken).
var _t := 0.0

@export var player_name := "dodominati":
	set(v):
		player_name = v
		queue_redraw()
## Höhe über dem Fusspunkt der Figur, in Weltpixeln.
@export var height := 40.0:
	set(v):
		height = v
		position = Vector2(0, -height)
@export var text_scale := 0.5
@export var color := Color(1, 0.97, 0.88)
## Voller Umriss (rundum), damit der Name auf jedem Untergrund lesbar bleibt.
## Ein Bitmap-Font hat keine Umrissdaten, also zeichnen wir den Text selbst
## mehrfach versetzt in Schwarz und legen die helle Schrift darueber.
@export var shadow := Color(0, 0, 0, 1)

var _font: Font


func _ready() -> void:
	_font = load(FONT)
	# Über allem, was in der Welt steht. Nicht relativ: die Figur hängt je
	# nach Höhenebene an einem anderen Eltern-Node, sonst würde der Name
	# mit ihr nach oben und unten wandern.
	z_as_relative = false
	z_index = IsoWorld.TALL_Z_INDEX + 4
	position = Vector2(0, -height)
	scale = Vector2(text_scale, text_scale)


func _draw() -> void:
	if _font == null or player_name.is_empty():
		return
	var w := _font.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var at := Vector2(-roundf(w * 0.5), 0.0)
	# Rundum-Umriss: den Text achtfach versetzt in Schwarz zeichnen ...
	for oy in [-1, 0, 1]:
		for ox in [-1, 0, 1]:
			if ox == 0 and oy == 0:
				continue
			draw_string(_font, at + Vector2(ox, oy), player_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, shadow)
	# ... und die helle Schrift oben drauf.
	draw_string(_font, at, player_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)

	# Gamemaster-Abzeichen direkt ueber dem Namen, wenn dieser Spieler Admin ist.
	if AdminsScript.is_admin(player_name):
		var bob := sin(_t * 3.0) * 2.0                 # sanftes Auf und Ab
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)         # 0..1 fuer den Glow
		var half := GM_SIZE * 0.5
		# Zentrum: direkt ueber der Schrift (Namenskante liegt bei ~ -FONT_SIZE).
		var c := Vector2(0.0, -FONT_SIZE + 1 - half + bob)
		# Pulsierender Glow: groesseres, halbdurchsichtiges Abzeichen dahinter.
		var gsize := GM_SIZE * (1.3 + 0.12 * pulse)
		draw_texture_rect(GM_TEX, Rect2(c.x - gsize * 0.5, c.y - gsize * 0.5, gsize, gsize),
			false, Color(1.0, 0.85, 0.35, 0.10 + 0.12 * pulse))
		# Kleine funkelnde Sparks, die um das Abzeichen kreisen und blinken.
		for i in 4:
			var a := _t * 2.0 + i * (TAU / 4.0)
			var sp := c + Vector2(cos(a) * (half + 3.0) * 1.1, sin(a) * (half + 2.0) * 0.6)
			var sa: float = clampf(sin(_t * 4.0 + i * 1.7) * 0.5 + 0.5, 0.0, 1.0)
			draw_circle(sp, 0.9, Color(1.0, 0.96, 0.7, sa * 0.9))
		# Das eigentliche Abzeichen.
		draw_texture_rect(GM_TEX, Rect2(c.x - half, c.y - half, GM_SIZE, GM_SIZE), false)


## Die GM-Animation (Float/Glow/Funken) laeuft nur fuer Admins - sonst kein
## Dauer-Redraw.
func _process(delta: float) -> void:
	if AdminsScript.is_admin(player_name):
		_t += delta
		queue_redraw()
