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
## Fisch-Sheet (96x64): 3 Spalten x 2 Zeilen, je 32x32. Oben roh, unten gebraten.
const SHEET_FISH := "res://assets/game_assets/items/fish.png"
const SHEET_FURNITURE := "res://assets/props/basic furniture.png"
const SHEET_PLANTS := "res://assets/game_assets/items/plants_and_seeds.png"

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
		"texture": "res://assets/props/cooking_campfire_off.png",
	},
	"tas": {
		"name": "Tas",
		"max_stack": 64,
		"texture": "res://assets/game_assets/items/stone.png",
	},
	# Angeln: Olta (Angel) craftbar, Balik (roh, NICHT essbar), Pismis Balik
	# (gebraten, essbar). Icons per PixelLab generiert (pixflux).
	"olta": {
		"name": "Olta",
		"max_stack": 1,
		"durability": 40,               # ~40 Faenge, dann zerbricht sie
		"texture": "res://assets/game_assets/items/olta.png",
	},
	# Drei Fischarten aus fish.png (roh oben, gebraten unten). Region je 32x32.
	"balik_1": {"name": "Sazan", "max_stack": 16,
		"sheet": SHEET_FISH, "region": Rect2i(0, 0, 32, 32)},
	"balik_2": {"name": "Levrek", "max_stack": 16,
		"sheet": SHEET_FISH, "region": Rect2i(32, 0, 32, 32)},
	"balik_3": {"name": "Turna", "max_stack": 16,
		"sheet": SHEET_FISH, "region": Rect2i(64, 0, 32, 32)},
	"pismis_balik_1": {"name": "Pismis Sazan", "max_stack": 16,
		"sheet": SHEET_FISH, "region": Rect2i(0, 32, 32, 32)},
	"pismis_balik_2": {"name": "Pismis Levrek", "max_stack": 16,
		"sheet": SHEET_FISH, "region": Rect2i(32, 32, 32, 32)},
	"pismis_balik_3": {"name": "Pismis Turna", "max_stack": 16,
		"sheet": SHEET_FISH, "region": Rect2i(64, 32, 32, 32)},
	# Cakmaktasi (Flint): selten (1%) beim Abbauen von normalem Stein. Icon
	# vorerst eine Stein-Zelle aus prop1 (Platzhalter, leicht ersetzbar).
	"cakmaktasi": {
		"name": "Cakmaktasi", "max_stack": 64,
		"sheet": SHEET_ITEMS, "item_cell": Vector2i(10, 0),
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
		"name": "Tas Balta",
		"max_stack": 1,
		"texture": "res://assets/game_assets/tools/axe_stone.png",
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

	# --- Neue Materialien (Icons als Einzel-PNG unter assets/game_assets) ----
	# Kil und Demir sind Rohstoffe fuer Ofen bzw. Eisenwerkzeuge. Sammel-/
	# Schmelzkette steht noch aus (siehe Outline-Notizen).
	"kil": {
		"name": "Kil", "max_stack": 64,
		"texture": "res://assets/game_assets/items/clay.png",
	},
	"demir": {
		"name": "Demir", "max_stack": 64,
		"texture": "res://assets/game_assets/items/iron.png",
	},
	# Toprak = Dirt-Block vom Buddeln (Schaufel). Icon = die Dirt-Wuerfelkachel
	# aus dem Boden-Sheet. Zum Aufschuetten (Terraforming) wieder platzierbar.
	"toprak": {
		"name": "Toprak", "max_stack": 64,
		"sheet": SHEET_TILES, "cell": Vector2i(3, 1),
	},
	# --- Erze (aus Felsen abgebaut, spaeter im Ofen zu Barren) --------------
	"demir_cevheri": {
		"name": "Demir Cevheri", "max_stack": 64,
		"texture": "res://assets/game_assets/items/iron_ore.png",
	},
	"altin_cevheri": {
		"name": "Altin Cevheri", "max_stack": 64,
		"texture": "res://assets/game_assets/items/gold_ore.png",
	},
	"ham_elmas": {
		"name": "Ham Elmas", "max_stack": 64,
		"texture": "res://assets/game_assets/items/diamond_ore.png",
	},
	# Kohle: Icon vorerst die Coal-Fels-Zelle aus rocks.png (Reihe 4).
	"komur": {
		"name": "Kömür", "max_stack": 64,
		"sheet": "res://assets/props/rocks.png", "region": Rect2i(0, 192, 48, 48),
	},
	# Islenmis Sopa = bearbeiteter Griff, Zutat der Eisenwerkzeuge.
	"islenmis_sopa": {
		"name": "Islenmis Sopa", "max_stack": 64,
		"texture": "res://assets/game_assets/items/wooden_handle.png",
	},

	# --- Ackerbau (Ernte + Samen), Icons aus plants_and_seeds.png -----------
	# Mais: Produkt (fertiger Kolben) und Samen (Korn). Der Samen wird auf einer
	# gehackten Ackerzelle gepflanzt (siehe crop_db.gd / crop.gd).
	"misir": {
		"name": "Misir", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(5, 5), "cell_size": Vector2i(32, 32),
	},
	"misir_tohumu": {
		"name": "Misir Tohumu", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(0, 1), "cell_size": Vector2i(32, 32),
	},
	# Havuc (Karotte)
	"havuc": {"name": "Havuc", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(1, 4), "cell_size": Vector2i(32, 32)},
	"havuc_tohumu": {"name": "Havuc Tohumu", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(0, 3), "cell_size": Vector2i(32, 32)},
	# Domates (Tomate)
	"domates": {"name": "Domates", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(2, 4), "cell_size": Vector2i(32, 32)},
	"domates_tohumu": {"name": "Domates Tohumu", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(0, 4), "cell_size": Vector2i(32, 32)},
	# Kabak (Kuerbis)
	"kabak": {"name": "Kabak", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(3, 3), "cell_size": Vector2i(32, 32)},
	"kabak_tohumu": {"name": "Kabak Tohumu", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(0, 2), "cell_size": Vector2i(32, 32)},
	# Bugday (Weizen)
	"bugday": {"name": "Bugday", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(0, 0), "cell_size": Vector2i(32, 32)},
	"bugday_tohumu": {"name": "Bugday Tohumu", "max_stack": 64,
		"sheet": SHEET_PLANTS, "item_cell": Vector2i(0, 5), "cell_size": Vector2i(32, 32)},

	# Sulama Kabi (Giesskanne): Ladungen ueber die Dayaniklilik (10). Am Wasser
	# auffuellen (Dayaniklilik = voll), pro Giessen 1 verbrauchen. Zerbricht NICHT
	# bei 0 - dann nur leer (siehe player_inventory, kein _wear_selected). Icon
	# vorerst das Wasserfass als Platzhalter (leicht ersetzbar).
	"sulama_kabi": {
		"name": "Sulama Kabi", "max_stack": 1, "durability": 10,
		"sheet": SHEET_FURNITURE, "item_cell": Vector2i(2, 2), "cell_size": Vector2i(64, 64),
	},

	# --- Steinwerkzeuge (Basit Üretim Masasi) -------------------------------
	# Dayaniklilik wie die Steinaxt (200). Funktion (Abbau) folgt spaeter -
	# vorerst nur craftbar, siehe Outline.
	"kazma": {
		"name": "Tas Kazma", "max_stack": 1, "durability": 200,
		"texture": "res://assets/game_assets/tools/pickaxe_stone.png",
	},
	"kurek": {
		"name": "Tas Kürek", "max_stack": 1, "durability": 200,
		"texture": "res://assets/game_assets/tools/shovel_stone.png",
	},
	"cekic": {
		"name": "Tas Cekic", "max_stack": 1, "durability": 200,
		"texture": "res://assets/game_assets/tools/stone_hammer.png",
	},
	"capa": {
		"name": "Tas Capa", "max_stack": 1, "durability": 200,
		"texture": "res://assets/game_assets/tools/hoe_stone.png",
	},
	"bicak": {
		"name": "Tas Bicak", "max_stack": 1, "durability": 200,
		"texture": "res://assets/game_assets/tools/knife_stone.png",
	},

	# --- Eisenwerkzeuge (Ileri Üretim Masasi) -------------------------------
	# Haerter als Stein -> mehr Dayaniklilik (500). Zutat Islenmis Sopa + Demir
	# hat noch keine Herstellkette (Outline-Notiz).
	"demir_balta": {
		"name": "Demir Balta", "max_stack": 1, "durability": 500,
		"texture": "res://assets/game_assets/tools/axe_iron.png",
	},
	"demir_kazma": {
		"name": "Demir Kazma", "max_stack": 1, "durability": 500,
		"texture": "res://assets/game_assets/tools/pickaxe_iron.png",
	},
	"demir_kurek": {
		"name": "Demir Kürek", "max_stack": 1, "durability": 500,
		"texture": "res://assets/game_assets/tools/shovel_iron.png",
	},
	"demir_cekic": {
		"name": "Demir Cekic", "max_stack": 1, "durability": 500,
		"texture": "res://assets/game_assets/items/iron_hammer.png",
	},
	"demir_capa": {
		"name": "Demir Capa", "max_stack": 1, "durability": 500,
		"texture": "res://assets/game_assets/tools/hoe_iron.png",
	},
	"demir_bicak": {
		"name": "Demir Bicak", "max_stack": 1, "durability": 500,
		"texture": "res://assets/game_assets/tools/knife_iron.png",
	},

	# --- Materialien: Gold (fuer Goldwerkzeuge, Üstün Üretim Masasi) ---------
	# Barren wie "demir": aus altin_cevheri im Schmelzofen (SMELT_OF). Zusammen
	# mit islenmis_sopa an der Üstün-Bank zu Goldwerkzeugen - Kette ist komplett.
	"altin": {
		"name": "Altin", "max_stack": 64,
		"texture": "res://assets/game_assets/items/gold.png",
	},

	# --- Goldwerkzeuge (Üstün Üretim Masasi) --------------------------------
	# Haerter als Eisen -> mehr Dayaniklilik (800). Icons aus PixelLab
	# (assets/game_assets/tools/*_gold.png). Kein Hammer (nicht angefragt).
	"altin_balta": {
		"name": "Altin Balta", "max_stack": 1, "durability": 800,
		"texture": "res://assets/game_assets/tools/axe_gold.png",
	},
	"altin_kazma": {
		"name": "Altin Kazma", "max_stack": 1, "durability": 800,
		"texture": "res://assets/game_assets/tools/pickaxe_gold.png",
	},
	"altin_kurek": {
		"name": "Altin Kürek", "max_stack": 1, "durability": 800,
		"texture": "res://assets/game_assets/tools/shovel_gold.png",
	},
	"altin_capa": {
		"name": "Altin Capa", "max_stack": 1, "durability": 800,
		"texture": "res://assets/game_assets/tools/hoe_gold.png",
	},
	"altin_bicak": {
		"name": "Altin Bicak", "max_stack": 1, "durability": 800,
		"texture": "res://assets/game_assets/tools/knife_gold.png",
	},
}

## Welches Werkzeug die Figur beim Halten zeigt: item_id -> [Layer-Name, Metall].
## Layer-Namen sind die des Packs (siehe cc_frames.TOOL_LAYERS). Metall-Tiers auf
## Pack-Metalle gemappt (Stein/Eisen -> Iron, Gold -> Gold; das Item-Icon im
## Inventar unterscheidet die Stufen ohnehin klar). Hoe (capa) fehlt im Pack ->
## leere Hand ([]). Metall-Tiers so gewaehlt, dass die Stufen am Character
## unterscheidbar sind: Stein -> Iron (mattes Grau), Eisen -> Silver (heller
## Stahl), Gold -> Gold. (Ein echtes Stein-Material hat das Pack nicht.)
const TOOL_HOLD := {
	"balta": ["Axe", "Iron"], "demir_balta": ["Axe", "Silver"], "altin_balta": ["Axe", "Gold"],
	"kazma": ["PickAxe", "Iron"], "demir_kazma": ["PickAxe", "Silver"], "altin_kazma": ["PickAxe", "Gold"],
	"kurek": ["Showel", "Iron"], "demir_kurek": ["Showel", "Silver"], "altin_kurek": ["Showel", "Gold"],
	"bicak": ["Sword", "Iron"], "demir_bicak": ["Sword", "Silver"], "altin_bicak": ["Sword", "Gold"],
	"cekic": ["Hammer", "Iron"], "demir_cekic": ["Hammer", "Silver"],
	# capa/demir_capa/altin_capa (Hoe): kein Pack-Sprite -> leere Hand.
}


## Werkzeug-Halte-Sprite eines Items: [Layer, Metall] oder ["", ""] (leere Hand).
static func hold_of(id: String) -> Array:
	return TOOL_HOLD.get(id, ["", ""])


## Spitzhacken-Stufe eines Items (fuers Fels-Abbauen): 1=Stein, 2=Eisen, 3=Gold.
## 0 = keine Spitzhacke. Ein hoeheres Tier baut alles ab, was ein niedrigeres kann.
const PICK_TIER := {"kazma": 1, "demir_kazma": 2, "altin_kazma": 3}

static func pick_tier(id: String) -> int:
	return int(PICK_TIER.get(id, 0))


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
	# Ileri-Baenke: eigener Richtungs-Sprite (siehe DIRSPRITES). Die Zelle hier
	# ist nur Fallback und wird von has_dirs()/dir_texture() ueberstochen.
	"ileri_uretim_masasi": ["Ileri Üretim Masasi", Vector2i(0, 1)],
	"ileri_dokuma_tezgahi": ["Ileri Dokuma Tezgahi", Vector2i(3, 1)],
	# working_table2 - alternative Stile zum Vergleichen (Richtungs-Sprites).
	"uretim_masasi_v2": ["Üretim Masasi 2", Vector2i(0, 1)],
	"ileri_uretim_masasi_v2": ["Ileri Üretim Masasi 2", Vector2i(0, 1)],
	"ustun_uretim_masasi": ["Üstün Üretim Masasi", Vector2i(0, 1)],
	# Mesale (Fackel): eigenes 32er-Objekt-Sheet (nicht das 64er Moebel-Sheet),
	# Icon = statische Pose (Reihe 0). Zelle hier nur Platzhalter, wird von
	# OBJ_ICON ueberstochen. Beim Setzen animiert (Feuer) - siehe furniture.gd.
	"mesale": ["Mesale", Vector2i(0, 0)],
}

## Moebel-Ids mit EIGENEM Sheet statt dem 64er-Sheet (Icon-Override nach dem Fold).
const OBJ_ICON := {
	"mesale": {"sheet": "res://assets/game_assets/objects/torch.png", "region": Rect2i(0, 0, 32, 32)},
}


## Gebaeude (Baraka ...). Anders als Moebel belegen sie ein 4x4-Feld, brauchen
## ebenen Boden und werden vor Ort ueber mehrere Minuten in drei Phasen gebaut
## (siehe scripts/building.gd). Als Item registriert (fuer Rezept-/Inventar-Icon);
## das Icon ist das fertige Haus. Die Phasen-Sprites liegen daneben und werden
## direkt in building.gd geladen.
const BUILDINGS := {
	"baraka": {
		"name": "Baraka",
		"texture": "res://assets/game_assets/buildings/shelter_done_south-east.png",
	},
}


## Ist das ein Gebaeude? Gebaeude werden ueber die 4x4-Vorschau aufgestellt und
## bauen sich vor Ort selbst (Phasen-Sprites, 10 Minuten).
static func is_building(id: String) -> bool:
	return BUILDINGS.has(id)


## Hacken (Capa/Hoe): wandelt Boden zu Acker. Alle drei Stufen taugen dazu.
const HOES := ["capa", "demir_capa", "altin_capa"]
static func is_hoe(id: String) -> bool:
	return id in HOES


## Samen -> Pflanzen-Id (crop_db). {} bei Nicht-Samen.
const SEED_CROP := {
	"misir_tohumu": "misir", "havuc_tohumu": "havuc", "domates_tohumu": "domates",
	"kabak_tohumu": "kabak", "bugday_tohumu": "bugday",
}
static func is_seed(id: String) -> bool:
	return SEED_CROP.has(id)
static func crop_of_seed(id: String) -> String:
	return SEED_CROP.get(id, "")


## Essbares -> wie viel Hunger es fuellt.
const FOOD := {
	"misir": 25, "kizarmis_et": 40,
	"havuc": 20, "domates": 15, "kabak": 40, "bugday": 10,
	"pismis_balik_1": 30, "pismis_balik_2": 35, "pismis_balik_3": 40,
}

## Fisch-Arten (roh) und ihre gebratene Version. Angeln liefert eine zufaellige
## rohe Art; Kochen macht daraus die passende gebratene.
const RAW_FISH := ["balik_1", "balik_2", "balik_3"]
const COOKED_OF := {
	"balik_1": "pismis_balik_1",
	"balik_2": "pismis_balik_2",
	"balik_3": "pismis_balik_3",
}
static func is_raw_fish(id: String) -> bool:
	return COOKED_OF.has(id)
static func cooked_of(id: String) -> String:
	return String(COOKED_OF.get(id, ""))
static func random_raw_fish() -> String:
	return RAW_FISH[randi() % RAW_FISH.size()]


## Schmelzen im Schmelzofen (Eritme Firini): Erz -> Barren. Analog zu COOKED_OF.
const SMELT_OF := {
	"demir_cevheri": "demir",
	"altin_cevheri": "altin",
}
static func is_ore(id: String) -> bool:
	return SMELT_OF.has(id)
static func bar_of(id: String) -> String:
	return String(SMELT_OF.get(id, ""))
static func is_food(id: String) -> bool:
	return FOOD.has(id)
static func food_value(id: String) -> int:
	return int(FOOD.get(id, 0))


## Giesskanne? (zum Pflanzen-Bewaessern; Ladungen ueber die Dayaniklilik.)
static func is_watering_can(id: String) -> bool:
	return id == "sulama_kabi"


## Nahkampfwaffe (Messer/Schwert) -> Schaden pro Treffer. 0 = keine Waffe.
const MELEE_DMG := {"bicak": 10, "demir_bicak": 18, "altin_bicak": 28}
static func is_knife(id: String) -> bool:
	return MELEE_DMG.has(id)
static func melee_damage(id: String) -> int:
	return int(MELEE_DMG.get(id, 0))


## Richtungs-Sprites: Stationen, die als 8-Richtungs-Satz (68x68) unter
## assets/game_assets/tool_tables liegen. Statt eines Sheet-Ausschnitts
## bekommt so ein Moebel je nach Ausrichtung (orient 0..3 = S/O/N/W) ein
## eigenes Bild. Ueberschreibt fuer diese Ids den Sheet-Eintrag aus FURNITURE.
const DIRSPRITES := {
	"calisma_tezgahi": "res://assets/game_assets/tool_tables/working_table/working_table/rotations",
	"ileri_uretim_masasi": "res://assets/game_assets/tool_tables/working_table/make_the_table_more/rotations",
	"dokuma_tezgahi": "res://assets/game_assets/tool_tables/loom_table/loom_table/rotations",
	"ileri_dokuma_tezgahi": "res://assets/game_assets/tool_tables/loom_table/make_a_advaned_loom/rotations",
	"eritme_firini": "res://assets/game_assets/tool_tables/melting_oven/isometric_pixelart/rotations",
	"uretim_masasi_v2": "res://assets/game_assets/tool_tables/working_table2/uretim_masasi/rotations",
	"ileri_uretim_masasi_v2": "res://assets/game_assets/tool_tables/working_table2/ileri_uretim_masasi_v2/rotations",
	"ustun_uretim_masasi": "res://assets/game_assets/tool_tables/working_table2/ustun_uretim_masasi/rotations",
}

## orient 0..7 -> Dateiname der Richtung, im Uhrzeigersinn ab Sued. Alle acht
## Richtungen sind drehbar - so laesst sich ein Tisch exakt buendig ausrichten.
const DIR_FILE := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]

## Ausrichtung fuers Inventar-/Vorschau-Icon (schraege Ansicht statt frontal).
const ICON_ORIENT := 1   # south-east


## Hat dieses Moebel einen Richtungs-Sprite-Satz?
static func has_dirs(id: String) -> bool:
	return DIRSPRITES.has(id)


## Textur fuer eine Ausrichtung (orient 0..3). Als AtlasTexture mit voller
## Region - so bleibt die Klick-/Abriss-Erkennung (die AtlasTexture erwartet)
## unveraendert nutzbar.
static func dir_texture(id: String, orient: int) -> Texture2D:
	var key := "%s#%d" % [id, orient]
	if _icons.has(key):
		return _icons[key]
	var img: Texture2D = load("%s/%s.png" % [DIRSPRITES[id], DIR_FILE[orient % 8]])
	var tex := AtlasTexture.new()
	tex.atlas = img
	tex.region = Rect2(Vector2.ZERO, img.get_size())
	tex.filter_clip = true
	_icons[key] = tex
	return tex


## Moebel sind gewoehnliche Items - sie werden hier einmalig in die
## gemeinsame Liste geschrieben, damit Inventar und Handwerk nichts von
## der Trennung wissen muessen.
static func _fold_in_furniture() -> void:
	for id in FURNITURE:
		var entry: Array = FURNITURE[id]
		if OBJ_ICON.has(id):
			# Objekt mit eigenem Sheet (z. B. Fackel) - Region statt Sheet-Zelle.
			var o: Dictionary = OBJ_ICON[id]
			ITEMS[id] = {"name": entry[0], "max_stack": 16,
				"sheet": o["sheet"], "region": o["region"]}
		else:
			ITEMS[id] = {
				"name": entry[0],
				"max_stack": 16,
				"sheet": SHEET_FURNITURE,
				"item_cell": entry[1],
				"cell_size": FURNITURE_CELL,
			}
	# Gebaeude als gewoehnliche Items einreihen (fuers Rezept-/Inventar-Icon).
	for id in BUILDINGS:
		var info: Dictionary = BUILDINGS[id]
		ITEMS[id] = {
			"name": info["name"],
			"max_stack": 1,
			"texture": info["texture"],
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
	# Richtungs-Moebel: als Inventar-Icon die schraege Ansicht (lebendiger als
	# frontal), bei allen dieselbe Richtung.
	if has_dirs(id):
		var t := dir_texture(id, ICON_ORIENT)
		_icons[id] = t
		return t
	if not ITEMS.has(id):
		return null
	var info: Dictionary = ITEMS[id]
	# Einzel-PNG (game_assets): das ganze Bild ist das Icon, kein Atlas noetig.
	if info.has("texture"):
		var whole: Texture2D = load(info["texture"])
		_icons[id] = whole
		return whole
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
