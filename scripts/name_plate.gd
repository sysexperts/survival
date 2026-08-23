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
