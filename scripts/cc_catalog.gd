extends RefCounted

## Katalog des "Customaizable Character"-Packs: welche Slots es gibt, in welcher
## Reihenfolge sie übereinander gezeichnet werden und welche Varianten je Slot
## zur Wahl stehen. Reine Daten - die Grafik baut cc_frames.gd, die Auswahl-UI
## das Görünüm-Menü.
##
## Ein Aussehen ist ein Dictionary  slot -> token, wobei token der Dateiname
## (ohne .png) im jeweiligen cc_scaled/<state>/-Ordner ist, z. B.
## "Layer5_Shirt_Red". Leerer String = Slot aus.

const CELL := 48
const ROWS := 5   ## Süd, Südwest, West, Nordwest, Nord

## Spielzustand -> Spaltenzahl (= Frames) im gebauten Sheet.
## sleep ist ein einzelnes, ruhendes Liege-Bild (aus der "Die"-Animation, letztes
## Frame) - kein Zyklus, deshalb nur 1 Spalte.
const STATE_COLS := {
	"idle": 8, "walk": 6, "run": 4, "axe": 6, "sleep": 1, "dig": 6, "fish": 6,
}

## Zeichenreihenfolge von unten nach oben. Jeder Eintrag ist ein Slot-Schlüssel
## im Aussehen-Dictionary.
const DRAW_ORDER := [
	"body", "face", "bodysuit", "pants", "shoes", "top", "sleeves",
	"necklace", "bag", "scarf", "bowtie", "hair", "hat", "acc",
]

## Farbnamen der einfärbbaren Stoff-Slots (Reihenfolge = UI-Reihenfolge).
const CLOTH := ["Beige", "Black", "Blue", "Brown", "Cream", "Dark", "Green",
	"Grey", "Magenta", "Olive", "Orange", "Pink", "Purple", "Red", "Sky", "Yellow"]
const METAL := ["Copper", "Gold", "Iron", "Platinum", "Silver"]
const HAIR_COLORS := ["Color1", "Color2", "Color3", "Color4", "Color5",
	"Color6", "Color7", "Color8", "Color9", "Color10"]

## UI-Katalog: Slot -> { label, allow_none, options:[token,...] }. `token` ist
## der Dateistamm ohne .png. `options` ist flach; die Menü-UI gruppiert selbst.
static func slots() -> Array:
	return [
		{"id": "body", "label": "Ten", "allow_none": false,
			"options": _tokens("Layer0_Body", ["Skin1", "Skin2", "Skin3", "Skin4", "Skin5"])},
		{"id": "face", "label": "Yüz", "allow_none": false,
			"options": _tokens("Layer1_Face", ["Regular", "Happy", "Angry", "Tired", "Blink"])},
		{"id": "hair", "label": "Saç", "allow_none": true,
			"options": _hair()},
		{"id": "top", "label": "Üst", "allow_none": true,
			"options": _tops()},
		{"id": "pants", "label": "Pantolon", "allow_none": true,
			"options": _tokens("Layer3_Pants", ["Beige", "Black", "Blue", "Brown", "Cream", "Green", "Grey", "Sky"])},
		{"id": "shoes", "label": "Ayakkabı", "allow_none": true,
			"options": _tokens("Layer4_Shoes", ["Beige", "Blue", "Brown", "Red", "Yellow"])},
		{"id": "sleeves", "label": "Kollar", "allow_none": true,
			"options": _tokens("Layer6_Sleeves", CLOTH)},
		{"id": "bodysuit", "label": "Tulum", "allow_none": true,
			"options": _tokens("Layer2_BodySuit", CLOTH)},
		{"id": "hat", "label": "Şapka", "allow_none": true,
			"options": _hats()},
		{"id": "scarf", "label": "Atkı", "allow_none": true,
			"options": _tokens("Layer9_Scarf", ["Olive", "Orange", "Purple", "Sky", "Yellow"])},
		{"id": "necklace", "label": "Kolye", "allow_none": true,
			"options": _tokens("Layer7_Necklace", METAL)},
		{"id": "bag", "label": "Çanta", "allow_none": true,
			"options": _tokens("Layer8_Bag", ["Beige", "Blue", "Brown", "Red", "Yellow"])},
		{"id": "bowtie", "label": "Papyon", "allow_none": true,
			"options": _tokens("Layer10_Bowtie", ["Blue", "Green", "Red", "Yellow"])},
		{"id": "acc", "label": "Ekstra", "allow_none": true,
			"options": _acc()},
	]


## Standard-Aussehen (neuer Spieler).
static func default_look() -> Dictionary:
	return {
		"body": "Layer0_Body_Skin1",
		"face": "Layer1_Face_Regular",
		"hair": "Layer11_ShortHair_Color3",
		"top": "Layer5_Shirt_Blue",
		"pants": "Layer3_Pants_Brown",
		"shoes": "Layer4_Shoes_Brown",
		"sleeves": "",
		"bodysuit": "",
		"hat": "",
		"scarf": "",
		"necklace": "",
		"bag": "",
		"bowtie": "",
		"acc": "",
	}


static func _tokens(prefix: String, variants: Array) -> Array:
	var out: Array = []
	for v in variants:
		out.append("%s_%s" % [prefix, v])
	return out


static func _tops() -> Array:
	var out: Array = []
	out.append_array(_tokens("Layer5_Shirt", CLOTH))
	out.append_array(_tokens("Layer5_Dress", CLOTH))
	out.append_array(_tokens("Layer5_Armor", METAL))
	return out


static func _hair() -> Array:
	var out: Array = []
	for t in ["ShortHair", "LongHair", "CurlyHair", "WavesHair", "SpikesHair",
			"MohawkHair", "PonytailHair", "BunHair"]:
		out.append_array(_tokens("Layer11_" + t, HAIR_COLORS))
	return out


static func _hats() -> Array:
	var out: Array = []
	out.append_array(_tokens("Layer11_Beanie", ["Olive", "Orange", "Purple", "Sky", "Yellow"]))
	out.append("Layer11_BambooHat_Beige")
	out.append_array(_tokens("Layer11_Hemlet", METAL))
	return out


static func _acc() -> Array:
	var out: Array = []
	out.append_array(_tokens("Layer12_Horns", ["Cream", "Dark", "Red"]))
	out.append_array(_tokens("Layer12_Bow", ["Blue", "Green", "Red", "Yellow"]))
	return out
