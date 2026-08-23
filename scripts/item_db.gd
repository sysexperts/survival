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
	"kizarmis_et": {
		"name": "Kizarmis Et",
		"max_stack": 16,
		"sheet": SHEET_CAMP,
		"cell": Vector2i(0, 0),
		"region": Rect2i(428, 154, 34, 26),   # Fleisch aus Frame 11
	},
	"kamp_atesi": {
		"name": "Kamp Atesi",
		"max_stack": 16,
		"sheet": SHEET_CAMP,
		"cell": Vector2i(0, 0),
		"region": Rect2i(128, 0, 128, 128),   # brennendes Feuer ohne Fleisch
	},
	"tas": {
		"name": "Tas",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(10, 2),
	},
	"odun": {
		"name": "Odun",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(9, 13),   # gebuendelte Aeste
	},
	"bitki_lifi": {
		"name": "Bitki Lifi",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(5, 1),
	},
	"halat": {
		"name": "Halat",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(1, 4),
	},
	"ip": {
		"name": "Ip",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(7, 11),   # Garnknaeuel mit Faden
	},
	"kumas": {
		"name": "Kumas",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(15, 3),   # gerollter Stoffballen
	},
	"balta": {
		"name": "Balta",
		"max_stack": 1,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(15, 5),
		# Dayaniklilik: her balta darbesi 1 harcar, 0'da kirilir. Kural: malzeme
		# ne kadar sertse o kadar cok darbe. Tas balta = 200 (en dusuk seviye);
		# demir/celik baltalar geldiginde bu deger artacak.
		"durability": 200,
	},
	"tahta": {
		"name": "Tahta",
		"max_stack": 64,
		"sheet": SHEET_ITEMS,
		"item_cell": Vector2i(9, 14),
	},
}

## Die Einrichtung aus `basic furniture.png`, als {id: [Name, Zelle]}.
## Steht getrennt, weil alle dasselbe Sheet und dasselbe 64er-Raster
## benutzen - so muss das nicht siebzehnmal danebenstehen.
const FURNITURE := {
	"planya_tezgahi": ["Planya Tezgahi", Vector2i(0, 0)],
	"sandik": ["Sandik", Vector2i(1, 0)],
	"jenerator": ["Jeneratör", Vector2i(2, 0)],
	"alet_standi": ["Alet Standi", Vector2i(3, 0)],
	"tabaklama_sehpasi": ["Tabaklama Sehpasi", Vector2i(4, 0)],
	"dolap": ["Dolap", Vector2i(5, 0)],
	"calisma_tezgahi": ["Calisma Tezgahi", Vector2i(0, 1)],
	"ocak": ["Ocak", Vector2i(1, 1)],
	"ors": ["Örs", Vector2i(2, 1)],
	"dokuma_tezgahi": ["Dokuma Tezgahi", Vector2i(3, 1)],
	"eritme_firini": ["Eritme Firini", Vector2i(4, 1)],
	"yatak": ["Yatak", Vector2i(5, 1)],
	"portatif_yatak": ["Portatif Yatak", Vector2i(0, 2)],
	"simya_masasi": ["Simya Masasi", Vector2i(1, 2)],
	"su_ficisi": ["Su Ficisi", Vector2i(2, 2)],
	"tabure": ["Tabure", Vector2i(3, 2)],
	"yukseltilmis_tarha": ["Yükseltilmis Tarha", Vector2i(4, 2)],
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


## Alte deutsche Ids -> neue tuerkische. Gespeicherte Spielstaende, build.json
## usw. tragen noch die alten Namen; `canonical()` hebt sie beim Laden an, und
## beim naechsten Speichern stehen die neuen drin. Nach ein paar Wochen kann
## diese Tabelle raus (dann gibt es keine alten Daten mehr).
const MIGRATE := {
	"gebratenes_fleisch": "kizarmis_et", "lagerfeuer": "kamp_atesi",
	"stein": "tas", "holz": "odun", "pflanzenfaser": "bitki_lifi",
	"seil": "halat", "schnur": "ip", "stoff": "kumas", "axt": "balta",
	"holzbrett": "tahta", "hobelbank": "planya_tezgahi", "kiste": "sandik",
	"generator": "jenerator", "werkzeugstaender": "alet_standi",
	"gerbgestell": "tabaklama_sehpasi", "spind": "dolap",
	"werkbank": "calisma_tezgahi", "kochstelle": "ocak", "amboss": "ors",
	"webetisch": "dokuma_tezgahi", "schmelzofen": "eritme_firini",
	"bett": "yatak", "feldbett": "portatif_yatak",
	"alchemietisch": "simya_masasi", "wasserfass": "su_ficisi",
	"hocker": "tabure", "hochbeet": "yukseltilmis_tarha",
}


## Bringt eine (evtl. alte) Id auf ihren aktuellen Namen. Unbekannte/schon
## aktuelle Ids kommen unveraendert zurueck.
static func canonical(id: String) -> String:
	return MIGRATE.get(id, id)


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


## Tam dayaniklilik (alet ise), yoksa 0. Dur alani olan her esya bir alet
## sayilir - darbe basina 1 harcanir ve slot uzerinde bir cubuk gosterilir.
static func max_durability(id: String) -> int:
	_ensure()
	return int(ITEMS[id].get("durability", 0)) if ITEMS.has(id) else 0


## Bu esya dayanikliligi olan bir alet mi?
static func has_durability(id: String) -> bool:
	return max_durability(id) > 0


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
