extends RefCounted
class_name RecipeDB

## Was sich woraus bauen lässt.
##
## Es gibt zwei Arten von Handwerk. Das Grundhandwerk (`HAND`) geht überall
## und jederzeit - dafür nur die einfachsten Sachen. Alles Weitere braucht
## eine Station, an der man stehen muss.
##
## Die Station steht am Rezept, nicht am Fenster: so kann dasselbe Fenster
## beide Fälle anzeigen, und ein Rezept wandert später mit einer Zeile von
## der Hand an die Werkbank.
##
## `seconds` ist die Bauzeit für EIN Stück. Gebaut wird über die
## Warteschlange (`CraftQueue`), nicht hier - diese Klasse kennt nur die
## Daten und die Prüfungen.

const HAND := ""                     ## überall, ohne Station
const WERKBANK := "calisma_tezgahi"          ## Basit Üretim Masasi
const WEBETISCH := "dokuma_tezgahi"          ## Dokuma Tezgahi
const ILERI_WERKBANK := "ileri_uretim_masasi"  ## Ileri Üretim Masasi
const USTUN_WERKBANK := "ustun_uretim_masasi"  ## Üstün Üretim Masasi (Gold)

## Die Stationen, an denen man craften kann. Die Ids sind bewusst dieselben
## wie die Moebel-Ids (ItemDB.FURNITURE) - ein gesetztes Moebel "calisma_tezgahi"
## IST damit die Station WERKBANK, ohne dass es eine zweite Zuordnung braucht.
const STATIONS := [WERKBANK, WEBETISCH, ILERI_WERKBANK, USTUN_WERKBANK]


## Ist `id` eine Handwerks-Station? (Der leere HAND-String ist keine.)
static func is_station(id: String) -> bool:
	return id in STATIONS


# --- Kategorien (Tabs im Handwerk-Fenster) ------------------------------ #
# Reihenfolge der Tabs von oben nach unten. Jede Kategorie hat einen Namen
# und ein stellvertretendes Icon (ein Item, dessen Grafik den Tab schmueckt).
const CAT_ORDER := ["masa", "alet", "malzeme", "mobilya", "yapi"]
const CATEGORIES := {
	"masa": {"name": "Masalar", "icon": "calisma_tezgahi"},
	"alet": {"name": "Aletler", "icon": "balta"},
	"malzeme": {"name": "Malzemeler", "icon": "tahta"},
	"mobilya": {"name": "Mobilya", "icon": "yatak"},
	"yapi": {"name": "Yapilar", "icon": "baraka"},
}
## Kategorie je Ergebnis-Item. Was hier fehlt, gilt als "malzeme".
const CAT_OF := {
	"calisma_tezgahi": "masa", "dokuma_tezgahi": "masa",
	"ileri_uretim_masasi": "masa", "ileri_dokuma_tezgahi": "masa",
	"ustun_uretim_masasi": "masa",
	"eritme_firini": "masa", "kamp_atesi": "masa",
	"balta": "alet", "kazma": "alet", "kurek": "alet", "cekic": "alet",
	"capa": "alet", "bicak": "alet",
	"demir_balta": "alet", "demir_kazma": "alet", "demir_kurek": "alet",
	"demir_cekic": "alet", "demir_capa": "alet", "demir_bicak": "alet",
	"altin_balta": "alet", "altin_kazma": "alet", "altin_kurek": "alet",
	"altin_capa": "alet", "altin_bicak": "alet",
	"sulama_kabi": "alet",
	"tahta": "malzeme", "halat": "malzeme", "ip": "malzeme", "kumas": "malzeme",
	"kil": "malzeme", "demir": "malzeme", "islenmis_sopa": "malzeme",
	"yatak": "mobilya", "portatif_yatak": "mobilya", "su_ficisi": "mobilya",
	"sandik": "mobilya",
	"baraka": "yapi",
}


## Kategorie eines Rezepts.
static func cat_of(recipe: Dictionary) -> String:
	return CAT_OF.get(recipe["out"], "malzeme")


## Die an dieser Station vorhandenen Kategorien, in fester Reihenfolge.
static func categories_for(station: String) -> Array:
	var present := {}
	for r in for_station(station):
		present[cat_of(r)] = true
	var out: Array = []
	for c in CAT_ORDER:
		if present.has(c):
			out.append(c)
	return out


## Rezepte einer Station, gefiltert auf eine Kategorie.
static func for_station_cat(station: String, cat: String) -> Array:
	var out: Array = []
	for r in for_station(station):
		if cat_of(r) == cat:
			out.append(r)
	return out

const RECIPES := [
	{
		"out": "tahta", "count": 1, "station": HAND, "seconds": 1.0,
		"cost": {"odun": 8},
	},
	{
		"out": "halat", "count": 1, "station": HAND, "seconds": 1.0,
		"cost": {"bitki_lifi": 8},
	},
	{
		"out": "calisma_tezgahi", "count": 1, "station": HAND, "seconds": 5.0,
		"cost": {"tahta": 16},
	},
	# Lagertruhe (Sandik): 3x10 Online-Lager. Ueberall craftbar - im Grundhandwerk
	# UND an jeder Üretim Masasi. Deshalb ein HAND-Eintrag (Basic Crafts) und ein
	# WERKBANK-Eintrag (Basit + geerbt an Ileri/Üstün, siehe for_station).
	{
		"out": "sandik", "count": 1, "station": HAND, "seconds": 3.0,
		"cost": {"tahta": 8},
	},
	{
		"out": "sandik", "count": 1, "station": WERKBANK, "seconds": 3.0,
		"cost": {"tahta": 8},
	},
	{
		"out": "dokuma_tezgahi", "count": 1, "station": HAND, "seconds": 8.0,
		"cost": {"tahta": 16, "halat": 16},
	},
	# Tas Balta (Steinaxt): wie die anderen Steinwerkzeuge aus Ast + Stein.
	# Erst damit lassen sich Baeume faellen - Player.chop() verlangt eine Axt
	# in der Hand.
	{
		"out": "balta", "count": 1, "station": WERKBANK, "seconds": 4.0,
		"cost": {"odun": 2, "tas": 3},
	},
	# Weberei: aus Pflanzenfaser wird Schnur, aus Schnur wird Stoff. Der
	# Stoff ist die Grundlage fuer Betten und spaeter Kleidung.
	{
		"out": "ip", "count": 1, "station": WEBETISCH, "seconds": 1.5,
		"cost": {"bitki_lifi": 4},
	},
	{
		"out": "kumas", "count": 1, "station": WEBETISCH, "seconds": 2.5,
		"cost": {"ip": 4},
	},
	# Zwei Betten an der Werkbank. Das Feldbett ist das einfache (weniger
	# Zutaten), das Bett das bequeme. Beide sind Moebel und lassen sich wie
	# jedes platzierbare Item drehen.
	{
		"out": "portatif_yatak", "count": 1, "station": WERKBANK, "seconds": 6.0,
		"cost": {"tahta": 4, "kumas": 2},
	},
	{
		"out": "yatak", "count": 1, "station": WERKBANK, "seconds": 12.0,
		"cost": {"tahta": 10, "kumas": 5},
	},
	# Su Ficisi (Wasserfass): Wasserquelle zum Auffuellen der Giesskanne.
	{
		"out": "su_ficisi", "count": 1, "station": WERKBANK, "seconds": 8.0,
		"cost": {"tahta": 8, "tas": 4},
	},

	# --- Gebaeude (eigener Tab "Yapilar") --------------------------------
	# Die Baraka wird ganz normal gefertigt und landet als Item im Inventar
	# (kurze Craft-Zeit). Platziert wird sie dann wie ein Moebel auf einem
	# ebenen 4x4-Feld und baut sich VOR ORT in 10 Minuten in drei Phasen selbst
	# (der 10-Minuten-Countdown steht dann ueber dem Bau, siehe building.gd).
	{
		"out": "baraka", "count": 1, "station": WERKBANK, "seconds": 4.0,
		"cost": {"tahta": 64},
	},

	# ------------------------------------------------------------------ #
	# Aus den Outline-Rezepten (Item Crafts) uebernommen. Mengen/Zeiten
	# sind erste Vorschlaege - in Outline als Notiz vermerkt, dort leicht
	# nachzujustieren. Icons kommen aus assets/game_assets (siehe ItemDB).
	# ------------------------------------------------------------------ #

	# Kamp Atesi: per Hand, aus Stein und Aesten.
	{
		"out": "kamp_atesi", "count": 1, "station": HAND, "seconds": 4.0,
		"cost": {"tas": 8, "odun": 8},
	},

	# --- Steinwerkzeuge an der Basit Üretim Masasi (Ast + Stein) ---------
	{"out": "kazma", "count": 1, "station": WERKBANK, "seconds": 4.0,
		"cost": {"odun": 2, "tas": 3}},
	{"out": "kurek", "count": 1, "station": WERKBANK, "seconds": 4.0,
		"cost": {"odun": 2, "tas": 3}},
	{"out": "cekic", "count": 1, "station": WERKBANK, "seconds": 4.0,
		"cost": {"odun": 2, "tas": 3}},
	{"out": "capa", "count": 1, "station": WERKBANK, "seconds": 4.0,
		"cost": {"odun": 2, "tas": 3}},
	{"out": "bicak", "count": 1, "station": WERKBANK, "seconds": 4.0,
		"cost": {"odun": 2, "tas": 3}},

	# Sulama Kabi (Giesskanne) fuer den Ackerbau - am Wasser auffuellen.
	# Aus Holz + Stein, damit sie ohne die (noch fehlende) Eisenkette craftbar ist.
	{"out": "sulama_kabi", "count": 1, "station": WERKBANK, "seconds": 5.0,
		"cost": {"tahta": 4, "tas": 4}},

	# Eritme Firini (Schmelzofen): Stein + Ton. Ton (kil) ist noch nicht
	# sammelbar - Rezept steht, ist aber vorerst nicht erreichbar.
	{"out": "eritme_firini", "count": 1, "station": WERKBANK, "seconds": 10.0,
		"cost": {"tas": 16, "kil": 32}},

	# Ausbauten der Werkbank/Weberei zur Ileri-Stufe (Brett + Eisen/Garn).
	{"out": "ileri_uretim_masasi", "count": 1, "station": WERKBANK, "seconds": 12.0,
		"cost": {"tahta": 16, "demir": 4}},
	{"out": "ileri_dokuma_tezgahi", "count": 1, "station": WERKBANK, "seconds": 12.0,
		"cost": {"tahta": 16, "ip": 8}},
	# Üstün Üretim Masasi (Goldwerkzeug-Station): Ausbau ueber der Ileri-Bank.
	{"out": "ustun_uretim_masasi", "count": 1, "station": ILERI_WERKBANK, "seconds": 15.0,
		"cost": {"tahta": 24, "demir": 8}},

	# --- Eisenwerkzeuge an der Ileri Üretim Masasi (Griff + Eisen) -------
	# Islenmis Sopa und Demir haben noch keine Herstellkette (Outline-Notiz),
	# daher aktuell nicht craftbar. Die Ileri-Bank kann zusaetzlich alles,
	# was die einfache Werkbank kann (siehe for_station()).
	{"out": "demir_balta", "count": 1, "station": ILERI_WERKBANK, "seconds": 6.0,
		"cost": {"islenmis_sopa": 1, "demir": 4}},
	{"out": "demir_kazma", "count": 1, "station": ILERI_WERKBANK, "seconds": 6.0,
		"cost": {"islenmis_sopa": 1, "demir": 4}},
	{"out": "demir_kurek", "count": 1, "station": ILERI_WERKBANK, "seconds": 6.0,
		"cost": {"islenmis_sopa": 1, "demir": 4}},
	{"out": "demir_cekic", "count": 1, "station": ILERI_WERKBANK, "seconds": 6.0,
		"cost": {"islenmis_sopa": 1, "demir": 4}},
	{"out": "demir_capa", "count": 1, "station": ILERI_WERKBANK, "seconds": 6.0,
		"cost": {"islenmis_sopa": 1, "demir": 4}},
	{"out": "demir_bicak", "count": 1, "station": ILERI_WERKBANK, "seconds": 6.0,
		"cost": {"islenmis_sopa": 1, "demir": 4}},

	# --- Goldwerkzeuge an der Üstün Üretim Masasi (Griff + Gold) ----------
	# Wie die Eisenwerkzeuge, nur mit Gold (altin). Altin hat noch keine
	# Sammel-/Schmelzkette (wie demir) - vorerst also noch nicht craftbar.
	# Kein Hammer (nicht angefragt). Die Üstün-Bank kann zusaetzlich alles,
	# was Ileri- und Basit-Bank koennen (siehe for_station()).
	{"out": "altin_balta", "count": 1, "station": USTUN_WERKBANK, "seconds": 8.0,
		"cost": {"islenmis_sopa": 1, "altin": 4}},
	{"out": "altin_kazma", "count": 1, "station": USTUN_WERKBANK, "seconds": 8.0,
		"cost": {"islenmis_sopa": 1, "altin": 4}},
	{"out": "altin_kurek", "count": 1, "station": USTUN_WERKBANK, "seconds": 8.0,
		"cost": {"islenmis_sopa": 1, "altin": 4}},
	{"out": "altin_capa", "count": 1, "station": USTUN_WERKBANK, "seconds": 8.0,
		"cost": {"islenmis_sopa": 1, "altin": 4}},
	{"out": "altin_bicak", "count": 1, "station": USTUN_WERKBANK, "seconds": 8.0,
		"cost": {"islenmis_sopa": 1, "altin": 4}},
]


## Bauzeit für ein Stück, in Sekunden.
static func seconds(recipe: Dictionary) -> float:
	return float(recipe.get("seconds", 1.0))


## Wie oft liesse sich das mit dem Vorrat bauen? Deckelt bei `wanted`.
static func affordable(inv: Inventory, recipe: Dictionary, wanted: int) -> int:
	var n := wanted
	for id in recipe["cost"]:
		n = mini(n, inv.count_of(id) / int(recipe["cost"][id]))
	return maxi(n, 0)


## Alle Rezepte, die an dieser Station gehen.
##
## Die Ileri Üretim Masasi ist ein Ausbau der einfachen Werkbank und kann
## deshalb alles, was diese kann, plus die eigenen (Eisen-)Rezepte.
static func for_station(station: String) -> Array:
	var out: Array = []
	for r in RECIPES:
		if r["station"] == station:
			out.append(r)
		# Ausbaustufen koennen alles der niedrigeren Baenke: Ileri kann Basit,
		# Üstün kann Basit UND Ileri.
		elif station == ILERI_WERKBANK and r["station"] == WERKBANK:
			out.append(r)
		elif station == USTUN_WERKBANK and (r["station"] == WERKBANK or r["station"] == ILERI_WERKBANK):
			out.append(r)
	return out


## Liegt genug im Inventar? Der Platz für das Ergebnis zählt mit - sonst
## wären die Zutaten weg und das Werkstück nirgends.
static func can_craft(inv: Inventory, recipe: Dictionary) -> bool:
	for id in recipe["cost"]:
		if inv.count_of(id) < int(recipe["cost"][id]):
			return false
	return inv.room_for(recipe["out"], int(recipe["count"]))


## Baut einmal. Gibt false zurück, wenn es nicht ging - dann ist auch
## nichts verbraucht worden.
static func craft(inv: Inventory, recipe: Dictionary) -> bool:
	if not can_craft(inv, recipe):
		return false
	for id in recipe["cost"]:
		inv.remove(id, int(recipe["cost"][id]))
	inv.add(recipe["out"], int(recipe["count"]))
	return true


## Warum es gerade nicht geht - für die Anzeige. "" heisst: es geht.
static func blocker(inv: Inventory, recipe: Dictionary) -> String:
	for id in recipe["cost"]:
		if inv.count_of(id) < int(recipe["cost"][id]):
			return "Malzeme eksik"
	if not inv.room_for(recipe["out"], int(recipe["count"])):
		return "Envanter dolu"
	return ""
