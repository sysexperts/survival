extends RefCounted
class_name GatherDB

## Die Rohstoffe, die frei auf der Karte herumliegen.
##
## Hier steht alles an einer Stelle: welche Bilder aus `prop1.png` als Prop
## in der Welt liegen, welches Bild im Inventar erscheint, welches Item es
## gibt und wie dicht das Zeug gesät wird.
##
## Alle Angaben sind Zellen im 32x32-Raster von `prop1.png` (704x480 =
## 22 Spalten x 15 Zeilen, kein Rand, kein Abstand). Spalte/Zeile ab 0.
## Willst du andere Grafiken, änderst du nur die Vector2i hier drin.

const SHEET := "res://assets/props/prop1.png"
const CELL := Vector2i(32, 32)

## Die Icons sind 32x32 gezeichnet, ein Boden-Diamant ist nur 32x16 gross -
## unskaliert wirkt ein Faserbuendel wie ein Baum. Pro Sorte ueber "scale"
## feinjustierbar.
const DEFAULT_SCALE := 0.5

## Wie kraeftig der geworfene Schatten eines Fundstuecks ist, im Verhaeltnis
## zu dem eines Baumes. Deutlich schwaecher: ein Aestchen am Boden wirft
## keinen Schatten wie eine Fichte.
const SHADOW_ALPHA := 0.55

## Bodenkacheln aus `RPG-isometric-free.png`, auf denen bereits etwas steht.
## Sie sind zwar begehbar, aber optisch besetzt - ein Faserbüschel mitten im
## Busch sieht aus wie ein Zeichenfehler. Die kleinen Steinhaufen fehlen
## hier bewusst: die werden beim Start ohnehin zu eigenen Props.
const BLOCKED_GROUND: Array[Vector2i] = [
	Vector2i(5, 4),   # Busch
	Vector2i(6, 4),   # Busch
	Vector2i(2, 4),   # Schädel
]


## `props`    - Zufallsauswahl für das, was in der Welt liegt.
## `icon`     - das Bild im Inventar.
## `yield`    - wie viele Items ein Aufsammeln bringt. Zwei Zahlen sind
##              eine Spanne, aus der gewürfelt wird.
## `density`  - Anteil der freien Bodenzellen, der damit belegt wird.
## `anchor`   - wie das Bild auf der Zelle sitzt:
##              "center" für alles, was flach am Boden LIEGT (Ast, Stein) -
##              die Bildmitte kommt auf die Mitte des Diamanten.
##              "foot" für alles, was aufrecht STEHT (Pflanze) - dann sitzt
##              der untere Rand auf der Mitte, wie bei einem Baum.
const KINDS := {
	"odun": {
		"name": "Odun",
		"props": [Vector2i(9, 9), Vector2i(9, 11)],
		"icon": Vector2i(9, 13),
		"yield": [1, 8],
		"density": 0.02,
		"scale": 0.5,
		"anchor": "center",
		"hint": "F  Odun topla",
	},
	"bitki_lifi": {
		"name": "Bitki Lifi",
		"props": [Vector2i(3, 0)],
		"icon": Vector2i(5, 1),
		"yield": [1, 8],
		"density": 0.025,
		"scale": 0.45,
		"anchor": "foot",
		"hint": "F  Bitki lifi topla",
	},
	"tas": {
		"name": "Tas",
		"props": [Vector2i(10, 0), Vector2i(10, 1), Vector2i(10, 3), Vector2i(10, 5)],
		"icon": Vector2i(10, 2),
		"yield": 1,
		"density": 0.018,
		"scale": 0.5,
		"anchor": "center",
		"hint": "F  Tas al",
	},
}


static func has(id: String) -> bool:
	return KINDS.has(id)


static func ids() -> Array:
	return KINDS.keys()


## Wie viel ein Aufsammeln bringt. Bei einer Spanne wird gewürfelt, sonst
## ist es jedes Mal derselbe Wert.
static func amount(id: String) -> int:
	if not KINDS.has(id):
		return 1
	var y = KINDS[id]["yield"]
	if y is Array:
		return randi_range(int(y[0]), int(y[1]))
	return int(y)


static func density(id: String) -> float:
	return float(KINDS[id]["density"]) if KINDS.has(id) else 0.0


static func scale_of(id: String) -> float:
	if KINDS.has(id) and KINDS[id].has("scale"):
		return float(KINDS[id]["scale"])
	return DEFAULT_SCALE


static func anchor_of(id: String) -> String:
	if KINDS.has(id) and KINDS[id].has("anchor"):
		return KINDS[id]["anchor"]
	return "center"


static func hint(id: String) -> String:
	return KINDS[id]["hint"] if KINDS.has(id) else ""


## Region einer Sheet-Zelle in Pixeln.
static func region(cell: Vector2i) -> Rect2i:
	return Rect2i(cell.x * CELL.x, cell.y * CELL.y, CELL.x, CELL.y)


## Ein zufälliges Prop-Bild dieser Sorte.
static func random_prop(id: String, rng: RandomNumberGenerator) -> Vector2i:
	var list: Array = KINDS[id]["props"]
	return list[rng.randi() % list.size()]


static func sheet() -> Texture2D:
	return load(SHEET)


static var _bounds: Dictionary = {}
static var _image: Image = null


## Der tatsächlich sichtbare Bereich einer Sheet-Zelle, relativ zur Zellecke.
##
## Die Icons sitzen unterschiedlich in ihren 32x32 - mal links, mal mittig.
## Wer die Kachel als Ganzes aufs Feld setzt, bekommt Props, die neben ihrer
## Zelle zu stehen scheinen. Darum wird hier der echte Umriss gesucht.
static func content_bounds(sheet_cell: Vector2i) -> Rect2:
	var key := "%d:%d" % [sheet_cell.x, sheet_cell.y]
	if _bounds.has(key):
		return _bounds[key]
	if _image == null:
		_image = sheet().get_image()
	var min_x := CELL.x
	var min_y := CELL.y
	var max_x := -1
	var max_y := -1
	for y in CELL.y:
		for x in CELL.x:
			if _image.get_pixel(sheet_cell.x * CELL.x + x, sheet_cell.y * CELL.y + y).a > 0.1:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	var rect := Rect2()
	if max_x >= 0:
		rect = Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	_bounds[key] = rect
	return rect
