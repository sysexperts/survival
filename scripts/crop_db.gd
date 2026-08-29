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
}


static func has(crop_id: String) -> bool:
	return CROPS.has(crop_id)


## Zeit (Sekunden) bis die Pflanze reif ist.
static func ripe_seconds(crop_id: String) -> float:
	var total := 0.0
	for s in CROPS[crop_id]["stage_secs"]:
		total += float(s)
	return total
