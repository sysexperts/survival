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
	# Wuesten-Flora (col = coel/Wueste): Palmen, Saguaro-, Feigen-, Fasskakteen aus
	# desert_trees.png. EIGENES Sheet + explizite Pixel-Regionen (kein 32er-Raster).
	# Steht aufrecht (foot), gibt beim Aufsammeln Holz (drop_item). Nur in der
	# Wueste - resource_scatter ueberspringt es (biome), gesetzt via world_gen.
	"col": {
		"name": "Col Bitkisi",
		"sheet": "res://assets/game_assets/tiles/desert_trees.png",
		"regions": [
			Rect2i(1, 4, 29, 51), Rect2i(35, 4, 26, 52), Rect2i(100, 5, 23, 51),
			Rect2i(65, 8, 29, 49), Rect2i(129, 13, 30, 44), Rect2i(161, 16, 30, 41),
			Rect2i(197, 36, 22, 23), Rect2i(101, 68, 24, 52), Rect2i(33, 69, 29, 51),
			Rect2i(2, 70, 29, 49), Rect2i(129, 70, 29, 51), Rect2i(65, 71, 30, 50),
			Rect2i(166, 102, 20, 20), Rect2i(2, 132, 30, 51), Rect2i(34, 133, 29, 51),
			Rect2i(102, 135, 24, 49), Rect2i(67, 138, 23, 46), Rect2i(130, 145, 29, 40),
			Rect2i(166, 166, 19, 21),
		],
		"icon": Vector2i(0, 0),
		"yield": [1, 4],
		"density": 0.035,
		"scale": 1.5,
		"anchor": "foot",
		"drop_item": "odun",
		"biome": "desert",
		"harvestable": false,          # vorerst reine Deko: nur Hover, kein Ernten
		"hint": "",
	},
}


## Kann diese Sorte aufgesammelt/abgebaut werden? (Wuesten-Flora: nein = Deko.)
static func harvestable(id: String) -> bool:
	return not (KINDS.has(id) and KINDS[id].get("harvestable", true) == false)


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


## Kind-aware: Region fuer eine Sorte. Bei Regionen-Sorten (Wueste) ist
## sheet_cell.x der Index in die explizite Rect-Liste; sonst 32er-Zelle.
static func region_for(id: String, sheet_cell: Vector2i) -> Rect2i:
	if KINDS.has(id) and KINDS[id].has("regions"):
		var rs: Array = KINDS[id]["regions"]
		return rs[clampi(sheet_cell.x, 0, rs.size() - 1)]
	return region(sheet_cell)


## Ein zufälliges Prop-Bild dieser Sorte. Bei Regionen-Sorten: Index in x.
static func random_prop(id: String, rng: RandomNumberGenerator) -> Vector2i:
	if KINDS.has(id) and KINDS[id].has("regions"):
		return Vector2i(rng.randi() % int(KINDS[id]["regions"].size()), 0)
	var list: Array = KINDS[id]["props"]
	return list[rng.randi() % list.size()]


static func sheet() -> Texture2D:
	return load(SHEET)


## Sheet einer Sorte (eigenes Sheet moeglich, sonst Standard prop1.png).
static func sheet_of(id: String) -> Texture2D:
	if KINDS.has(id) and KINDS[id].has("sheet"):
		return load(KINDS[id]["sheet"])
	return load(SHEET)


static var _images: Dictionary = {}   ## sheet-Pfad -> Image (Alpha-Test-Cache)


## Bild einer Sorte (fuer den Alpha-Treffertest), je Sheet einmal geladen.
static func image_of(id: String) -> Image:
	var path := String(KINDS[id]["sheet"]) if (KINDS.has(id) and KINDS[id].has("sheet")) else SHEET
	if not _images.has(path):
		_images[path] = load(path).get_image()
	return _images[path]


## Welches Item ein Aufsammeln gibt (Standard: die Sorte selbst).
static func drop_item(id: String) -> String:
	if KINDS.has(id) and KINDS[id].has("drop_item"):
		return String(KINDS[id]["drop_item"])
	return id


## Nur in diesem Biom streuen (leer = ueberall). resource_scatter respektiert das.
static func biome_of(id: String) -> String:
	return String(KINDS[id].get("biome", "")) if KINDS.has(id) else ""


static var _bounds: Dictionary = {}
static var _image: Image = null


## Der tatsächlich sichtbare Bereich einer Sheet-Zelle, relativ zur Zellecke.
##
## Die Icons sitzen unterschiedlich in ihren 32x32 - mal links, mal mittig.
## Wer die Kachel als Ganzes aufs Feld setzt, bekommt Props, die neben ihrer
## Zelle zu stehen scheinen. Darum wird hier der echte Umriss gesucht.
## Kind-aware Umriss. Regionen-Sorten (Wueste) sind bereits eng zugeschnitten,
## der sichtbare Bereich ist also die ganze Region.
static func content_bounds_for(id: String, sheet_cell: Vector2i) -> Rect2:
	if KINDS.has(id) and KINDS[id].has("regions"):
		var r: Rect2i = region_for(id, sheet_cell)
		return Rect2(0, 0, r.size.x, r.size.y)
	return content_bounds(sheet_cell)


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
