extends Node2D
class_name DroppedItem

## Ein auf dem Boden liegendes Item: Bodenschatten, schwebendes Icon und eine
## enge, zentrierte Beschriftung ("Name xN"). Alles selbst gezeichnet, damit
## der Text-Hintergrund genau am Text klebt und der Schatten sicher sichtbar
## ist (ein Bitmap-Font macht bei Label + StyleBox beides schwer).

const FONT := "res://assets/fonts/pixel.fnt"
const FONT_SIZE := 9
## Verkleinerung der Schrift (Bitmap-Font sieht bei kleinen font_size unscharf
## aus, deshalb lieber in nativer Groesse zeichnen und herunterskalieren).
const TEXT_SCALE := 0.6

var item_id := ""
var count := 1

var _font: Font
var _spr: Sprite2D
var _t := 0.0


func setup(p_id: String, p_count: int) -> void:
	item_id = p_id
	count = p_count


func _ready() -> void:
	_font = load(FONT)
	# Normale y-Sortierung im Props-Container (wie ein Baum/Stein), damit das
	# Item korrekt zwischen den Props einsortiert und sicher sichtbar ist.
	_spr = Sprite2D.new()
	_spr.texture = ItemDB.icon(item_id)
	_spr.scale = Vector2(0.55, 0.55)
	_spr.position = Vector2(0, -9)
	add_child(_spr)
	queue_redraw()


func _process(delta: float) -> void:
	# Sanftes Auf- und Abschweben - nur das Icon, Schatten bleibt am Boden.
	_t += delta
	_spr.position.y = -9.0 + sin(_t * 2.4) * 2.5


func _draw() -> void:
	# Bodenschatten (gestauchte Ellipse) direkt unter dem Item.
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _font == null:
		return
	# Beschriftung: enger schwarzer Kasten, exakt um den Text, zentriert.
	var text := "%s x%d" % [ItemDB.display_name(item_id), count]
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var asc := _font.get_ascent(FONT_SIZE)
	var desc := _font.get_descent(FONT_SIZE)
	var pad := 1.5
	draw_set_transform(Vector2(0, 10), 0.0, Vector2(TEXT_SCALE, TEXT_SCALE))
	draw_rect(Rect2(-w * 0.5 - pad, -asc - pad, w + pad * 2, asc + desc + pad * 2),
		Color(0, 0, 0, 0.5))
	draw_string(_font, Vector2(-w * 0.5, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
