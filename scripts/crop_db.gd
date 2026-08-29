extends RefCounted

## Daten der anbaubaren Pflanzen (Ackerbau).
##
## KEIN `class_name`: neue benannte Klassen registriert der Auto-Updater
## (game.pck ueber die Basis-.exe) nicht. Ueberall per preload einbinden.
##
## Sprites kommen aus assets/game_assets/items/plants_and_seeds.png (32er-Raster,
## Spalte/Zeile). Jede Pflanze hat mehrere Wachstumsstufen (`stages`, letzte =
## reif/erntereif), ein Tot-Bild (`dead`) und Zeiten:
##   `stage_secs`  Sekunden pro Uebergang; es gibt (stages-1) Eintraege. Die
##                 Summe ist die Zeit bis reif.
##   `rot_after`   Sekunden nach dem Reifwerden, bis die Pflanze stirbt, wenn
##                 sie nicht geerntet wird (Nutzerwunsch: 30 min).
## Ertrag: `produce`/`produce_count` (Produkt-Item + Menge min..max),
##         `seed`/`seed_return` (Samen zurueck, damit sich der Anbau traegt).

const SHEET := "res://assets/game_assets/items/plants_and_seeds.png"
const CELL := 32

const CROPS := {
	"misir": {
		"name": "Misir",
		"seed": "misir_tohumu",
		"produce": "misir",
		"stages": [Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)],
		"dead": Vector2i(5, 4),
		"stage_secs": [180.0, 180.0, 180.0],   # 3x3 min -> reif nach 9 min
		"rot_after": 1800.0,                    # 30 min bis zum Absterben
		"produce_count": [2, 3],
		"seed_return": [1, 2],
	},
	# Havuc (Karotte): schnelle Wurzel, 4 Stufen bis zur vollen Ruebe.
	"havuc": {
		"name": "Havuc", "seed": "havuc_tohumu", "produce": "havuc",
		"stages": [Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3)],
		"dead": Vector2i(6, 4),
		"stage_secs": [120.0, 120.0, 120.0],   # 6 min bis reif
		"rot_after": 1800.0, "produce_count": [1, 2], "seed_return": [1, 2],
	},
	# Domates (Tomate): am Stab, 4 Stufen bis zu den roten Fruechten.
	"domates": {
		"name": "Domates", "seed": "domates_tohumu", "produce": "domates",
		"stages": [Vector2i(8, 4), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2)],
		"dead": Vector2i(8, 3),
		"stage_secs": [180.0, 180.0, 240.0],   # 10 min bis reif
		"rot_after": 1800.0, "produce_count": [2, 4], "seed_return": [1, 2],
	},
	# Kabak (Kuerbis): Sproessling -> gruener Kuerbis -> orange -> grosser Kuerbis.
	# (7,5) ist ein neutraler Keimling; (9,3) der grosse reife Kuerbis, (9,2) tot.
	"kabak": {
		"name": "Kabak", "seed": "kabak_tohumu", "produce": "kabak",
		"stages": [Vector2i(7, 5), Vector2i(9, 0), Vector2i(9, 1), Vector2i(9, 3)],
		"dead": Vector2i(9, 2),
		"stage_secs": [200.0, 200.0, 200.0],   # 10 min bis reif
		"rot_after": 1800.0, "produce_count": [1, 1], "seed_return": [1, 2],
	},
	# Bugday (Weizen): Getreide, 3 Stufen bis zur goldenen Aehre.
	"bugday": {
		"name": "Bugday", "seed": "bugday_tohumu", "produce": "bugday",
		"stages": [Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)],
		"dead": Vector2i(4, 4),
		"stage_secs": [180.0, 180.0],          # 6 min bis reif
		"rot_after": 1800.0, "produce_count": [2, 3], "seed_return": [1, 2],
	},
}


static func has(crop_id: String) -> bool:
	return CROPS.has(crop_id)


## Zeit (Sekunden) bis die Pflanze reif ist.
static func ripe_seconds(crop_id: String) -> float:
	var total := 0.0
	for s in CROPS[crop_id]["stage_secs"]:
		total += float(s)
	return total
