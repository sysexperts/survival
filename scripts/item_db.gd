extends RefCounted
class_name ItemDB

## Was es an Gegenständen gibt.
##
## Icons werden aus den vorhandenen Sheets geschnitten, damit keine
## zusätzlichen Grafiken nötig sind. `sheet` ist der Pfad, `cell` die
## Spalte/Zeile im jeweiligen Raster.

const SHEET_TILES := "res://assets/RPG-isometric-free.png"
const SHEET_CAMP := "res://assets/props/camp.png"
const SHEET_ITEMS := "res://assets/props/prop1.png"
const SHEET_FURNITURE := "res://assets/props/basic furniture.png"

## Raster des Item-Sheets: 32x32-Zellen, kein Rand, kein Abstand.
## `item_cell` sticht `cell` und `region` aus.
const ITEM_CELL := Vector2i(32, 32)
## Die Moebel sind doppelt so gross gezeichnet - ein Stueck belegt eine
## 64x64-Zelle. Ueber `cell_size` am Item einstellbar.
const FURNITURE_CELL := Vector2i(64, 64)

## Raster des Block-Sheets: 32x32-Zellen, links 2 px Rand, 2 px Abstand.
const TILE_MARGIN := Vector2i(2, 0)
const TILE_SEP := Vector2i(2, 0)
const TILE_SIZE := Vector2i(32, 32)

## `region` sticht `cell` aus, wenn ein Sheet ein anderes Raster hat.
static var ITEMS := {
	"gebratenes_fleisch": {
		"name": "Gebratenes Fleisch",
		"max_stack": 16,
		"sheet": SHEET_CAMP,
		"cell": Vector2i(0, 0),
		"region": Rect2i(428, 154, 34, 26),   # Fleisch aus Frame 11
	},
	"lagerfeuer": {
		"name": "Lagerfeuer",
		"max_stack": 16,
		"sheet": SHEET_CAMP,
		"cell": Vector2i(0, 0),
		"region": Rect2i(128, 0, 128, 128),   # brennendes Feuer ohne Fleisch
	},
	"stein": {
		"name": "Stein",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(10, 2),
	},
	"holz": {
		"name": "Holz",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(9, 13),   # gebuendelte Aeste
	},
	"pflanzenfaser": {
		"name": "Pflanzenfaser",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(5, 1),
	},
	"seil": {
		"name": "Seil",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(1, 4),
	},
	"schnur": {
		"name": "Schnur",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(7, 11),   # Garnknaeuel mit Faden
	},
	"stoff": {
		"name": "Stoff",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(15, 3),   # gerollter Stoffballen
	},
	"axt": {
		"name": "Axt",
		"max_stack": 1,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(15, 5),
	},
	"holzbrett": {
		"name": "Holzbrett",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(9, 14),
	},
}

## Die Einrichtung aus `basic furniture.png`, als {id: [Name, Zelle]}.
## Steht getrennt, weil alle dasselbe Sheet und dasselbe 64er-Raster
## benutzen - so muss das nicht siebzehnmal danebenstehen.
const FURNITURE := {
	"hobelbank": ["Hobelbank", Vector2i(0, 0)],
	"kiste": ["Kiste", Vector2i(1, 0)],
	"generator": ["Generator", Vector2i(2, 0)],
	"werkzeugstaender": ["Werkzeugständer", Vector2i(3, 0)],
	"gerbgestell": ["Gerbgestell", Vector2i(4, 0)],
	"spind": ["Spind", Vector2i(5, 0)],
	"werkbank": ["Werkbank", Vector2i(0, 1)],
	"kochstelle": ["Kochstelle", Vector2i(1, 1)],
	"amboss": ["Amboss", Vector2i(2, 1)],
	"webetisch": ["Webetisch", Vector2i(3, 1)],
	"schmelzofen": ["Schmelzofen", Vector2i(4, 1)],
	"bett": ["Bett", Vector2i(5, 1)],
	"feldbett": ["Feldbett", Vector2i(0, 2)],
	"alchemietisch": ["Alchemietisch", Vector2i(1, 2)],
	"wasserfass": ["Wasserfass", Vector2i(2, 2)],
	"hocker": ["Hocker", Vector2i(3, 2)],
	"hochbeet": ["Hochbeet", Vector2i(4, 2)],
}


## Moebel sind gewoehnliche Items - sie werden hier einmalig in die
## gemeinsame Liste geschrieben, damit Inventar und Handwerk nichts von
## der Trennung wissen muessen.
static func _fold_in_furniture() -> void:
	for id in FURNITURE:
		var entry: Array = FURNITURE[id]
		ITEMS[id] = {
			"name": entry[0],
			"max_stack": 16,
			"sheet": SHEET_FURNITURE,
			"item_cell": entry[1],
			"cell_size": FURNITURE_CELL,
		}


static var _folded := false


## Wird von jedem Zugriff angestossen. Ein `static func _static_init()`
## waere kuerzer, laeuft aber vor den Konstanten-Auswertungen.
static func _ensure() -> void:
	if not _folded:
		_folded = true
		_fold_in_furniture()

static var _icons: Dictionary = {}


static func has(id: String) -> bool:
	_ensure()
	return ITEMS.has(id)


## Ist das ein Moebel? Moebel werden ueber die 1x1-Vorschau aufgestellt.
static func is_furniture(id: String) -> bool:
	return FURNITURE.has(id)


## Alle bekannten Item-Ids.
static func ids() -> Array:
	_ensure()
	return ITEMS.keys()


static func display_name(id: String) -> String:
	_ensure()
	return ITEMS[id]["name"] if ITEMS.has(id) else id


static func max_stack(id: String) -> int:
	_ensure()
	return ITEMS[id]["max_stack"] if ITEMS.has(id) else 1


## Icon als AtlasTexture, einmal pro Item erzeugt und gemerkt.
static func icon(id: String) -> Texture2D:
	_ensure()
	if _icons.has(id):
		return _icons[id]
	if not ITEMS.has(id):
		return null
	var info: Dictionary = ITEMS[id]
	var tex := AtlasTexture.new()
	tex.atlas = load(info["sheet"])
	if info.has("item_cell"):
		var ic: Vector2i = info["item_cell"]
		var cs: Vector2i = info.get("cell_size", ITEM_CELL)
		tex.region = Rect2(ic.x * cs.x, ic.y * cs.y, cs.x, cs.y)
		tex.filter_clip = true
		_icons[id] = tex
		return tex
	if info.has("region"):
		tex.region = Rect2(info["region"])
		tex.filter_clip = true
		_icons[id] = tex
		return tex
	var cell: Vector2i = info["cell"]
	tex.region = Rect2(
		TILE_MARGIN.x + cell.x * (TILE_SIZE.x + TILE_SEP.x),
		TILE_MARGIN.y + cell.y * (TILE_SIZE.y + TILE_SEP.y),
		TILE_SIZE.x, TILE_SIZE.y)
	tex.filter_clip = true
	_icons[id] = tex
	return tex
