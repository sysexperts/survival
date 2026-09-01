class_name WorldGen
extends RefCounted

## Prozeduraler Weltgenerator für das chunk-basierte Streaming.
##
## Reine, deterministische Logik: gleiche Zelle + gleicher Welt-Seed -> immer
## dasselbe Ergebnis. Damit lassen sich Chunks beliebig laden/entladen, ohne
## dass sich die Welt ändert, und alles ist ohne Szene testbar. Gearbeitet
## wird im DURCHGEHENDEN Zellkoordinatensystem - nur so bleibt die
## Stacked-Parität des Rasters an den Chunk-Grenzen stimmig (siehe README).
##
## Was hier entschieden wird: Höhe der Säule, Boden-Kachel (grün mit Varianz,
## stellenweise Erdflächen) und ob ein Prop (Baum) oder Rohstoff (Holz,
## Pflanzenfaser, Stein) auf der Zelle liegt. Das Setzen in der Welt macht der
## ChunkManager - diese Klasse fasst die Welt nie an.

const MAX_LEVEL := 2          ## Höher stapeln wir nicht (niedrige Hügel).
## Ab diesem Noise-Wert (nach 0..1) beginnt ueberhaupt ein Huegel. Darunter ist
## alles FLACH (Hoehe 0). Hoch = mehr flaches Land, weniger stoerende Stufen.
const HILL_START := 0.55
const EDGE_RING := 3          ## Zellen, über die vom Handbau-Rand geblendet wird.

## Grüne Bodenkacheln (Quelle 0) für die Varianz. Ein einziges Grün wirkte
## brettflach - drei leicht verschiedene Töne geben der Wiese Leben.
const GRASS: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]

## Erd-/Lehmkacheln für die braunen Flecken, die sich stellenweise durch die
## Wiese ziehen.
const DIRT: Array[Vector2i] = [Vector2i(3, 1), Vector2i(3, 3)]

## Die Baumbilder aus Quelle 1 (baeume.png), die der Generator verwenden darf.
## Die zwei Schnee-Bäume (2,0) und (2,1) sind bewusst NICHT dabei - sie passen
## nicht zur schneefreien Landschaft (waren nur Test-Bäume).
const TREES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
]

## Ab diesem Wert der Erd-Noise wird eine Zelle zu Erde statt Gras. Höher =
## seltener und kleinere Flecken.
const DIRT_THRESHOLD := 0.33

## Baum-Wahrscheinlichkeit: in offener Wiese selten, in "Wald"-Zonen dicht.
## Die Wald-Noise entscheidet, wo Bäume klumpen, statt sie gleichmäßig zu
## streuen - das sieht nach echten Wäldern und Lichtungen aus.
const TREE_P_MEADOW := 0.01
const TREE_P_FOREST := 0.26

## Rohstoff-Wahrscheinlichkeiten pro Zelle (kumulativ ausgewertet).
const P_HOLZ := 0.020
const P_FASER := 0.018
## Felsen (abbaubar). Der Zustand (Stein/Eisen/Gold/Diamant) kommt aus RockDB.
## Bewusst sparsam - Felsen sollen etwas Besonderes sein, nicht ueberall liegen.
const P_ROCK := 0.005
## Wahrscheinlichkeit fuer Wuesten-Flora (Palmen/Kakteen) je Wuesten-Zelle.
const DESERT_FLORA_P := 0.022

const RockDB := preload("res://scripts/rock_db.gd")

var _seed: int
var _height := FastNoiseLite.new()
var _dirt := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _clay := FastNoiseLite.new()
var _water := FastNoiseLite.new()
var _biome := FastNoiseLite.new()   ## grosse Regionen: Gras vs. Wueste
var _sea := FastNoiseLite.new()     ## sehr grossflaechig: hier entstehen Meere
var _rock := FastNoiseLite.new()    ## kleine Fels-Formationen in der Wueste


func _init(world_seed: int = 1337) -> void:
	_seed = world_seed
	_height.seed = world_seed
	_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height.frequency = 0.02            # breitere, sanftere Hügel (weniger Stufen)
	# Eigene Seeds (Offsets), damit Höhe, Erde und Wald nicht korrelieren.
	_dirt.seed = world_seed + 1000
	_dirt.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dirt.frequency = 0.05              # etwas kleinere Flecken als die Hügel
	_forest.seed = world_seed + 2000
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.02            # große, zusammenhängende Waldzonen
	_clay.seed = world_seed + 3000
	_clay.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clay.frequency = 0.06             # kleine, seltene Kil-Flecken
	_water.seed = world_seed + 4000
	_water.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_water.frequency = 0.028           # groessere, zusammenhaengende Seen/Teiche
	_biome.seed = world_seed + 5000
	_biome.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome.frequency = 0.0008          # RIESIGE Biome (~4-5 Min zum Durchqueren)
	# Domain-Warp -> organische, rundliche Blobs statt gerader Streifen/Kanten.
	_biome.domain_warp_enabled = true
	_biome.domain_warp_amplitude = 120.0
	_biome.domain_warp_frequency = 0.004
	_sea.seed = world_seed + 6000
	_sea.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_sea.frequency = 0.0015            # grosse Meere
	_rock.seed = world_seed + 7000
	_rock.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rock.frequency = 0.06             # kleine, kompakte Fels-Cluster


# --- Höhe ---------------------------------------------------------------

## Rohe Noise-Höhe einer Zelle, 0..MAX_LEVEL, ohne Rand-Rücksicht.
func noise_height(cell: Vector2i) -> int:
	var t := (_height.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5   # 0..1
	# Der Grossteil der Karte bleibt FLACH (Hoehe 0); nur oberhalb HILL_START
	# steigt sanft ein Huegel an. So gibt es kaum noch einzelne Stufen im Weg.
	if t < HILL_START:
		return 0
	var h := (t - HILL_START) / (1.0 - HILL_START)               # 0..1 im Huegel
	return clampi(int(round(h * float(MAX_LEVEL))), 0, MAX_LEVEL)


## Endgültige Höhe der Säule.
##
## `edge_dist`/`edge_height` beschreiben den nächsten Handbau-Nachbarn:
## edge_dist < 0 heißt "kein gemalter Rand in der Nähe" -> volle Noise-Höhe.
## Sonst wird von der tatsächlichen Randhöhe (edge_height) über EDGE_RING
## Zellen in die Noise-Höhe geblendet - direkt am Rand (edge_dist 0) exakt
## bündig, damit dort weder eine Stufe noch eine Lücke entsteht.
func height_at(cell: Vector2i, edge_dist: int, edge_height: int) -> int:
	# REGEL: Wasser ist IMMER Ebene 0 und nie gestapelt (Einzel-Block auf Level 0).
	if is_water(cell):
		return 0
	# Direktes Ufer ebenfalls flach auf Hoehe 0 (nur fern der gemalten Karte,
	# damit der Rand-Uebergang dort nicht bricht).
	if edge_dist < 0 and near_water(cell):
		return 0
	var h := noise_height(cell)
	# Wuestenfelsen ragen als kleine Formationen aus dem flachen Sand.
	var rb := desert_rock(cell)
	if rb > h:
		h = rb
	if edge_dist < 0 or edge_dist >= EDGE_RING:
		return h
	var t := float(edge_dist) / float(EDGE_RING)
	return int(round(lerp(float(edge_height), float(h), t)))


# --- Boden --------------------------------------------------------------

## Ist diese Zelle Erde (brauner Fleck) statt Gras?
func is_dirt(cell: Vector2i) -> bool:
	return _dirt.get_noise_2d(cell.x, cell.y) > DIRT_THRESHOLD


## Bodenkachel (Quelle-0-Atlas) für die oberste Ebene dieser Zelle.
## Ab diesem Kil-Noise-Wert wird eine Zelle zum Kil-Block. Hoeher = seltener.
const CLAY_THRESHOLD := 0.6

func is_clay(cell: Vector2i) -> bool:
	return _clay.get_noise_2d(cell.x, cell.y) > CLAY_THRESHOLD


## Wasser: ab diesem Noise-Wert wird eine Zelle zu (flachem) Wasser. Seen liegen
## flach auf Hoehe 0 (siehe height_at), am Ufer sammelt sich Kil.
const WATER_THRESHOLD := 0.22
const WATER_FILL: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
## Wahrscheinlichkeit, dass eine Ufer-Landzelle Kil wird (Prozent).
const SHORE_CLAY_PCT := 55
const NB4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## --- Biome ---------------------------------------------------------------
## Grosse, zusammenhaengende Regionen (nicht staendig wechselnd, siehe _biome-freq).
const BIOME_GRASS := "grass"
const BIOME_DESERT := "desert"
const BIOME_STEPPE := "steppe"
## _biome-Noise ueber diesem Wert -> Wueste. Hoeher = seltener/kleiner.
const DESERT_THRESHOLD := 0.12
## _biome-Noise UNTER diesem Wert -> Steppe/Oedland (gegenueberliegendes Ende).
const STEPPE_THRESHOLD := -0.15
## Sehr wenige Baeume in der Steppe.
const STEPPE_TREE_P := 0.004
## Wuestenboden + Straende: nur die zwei mittleren Sand-Toene (Sheet-Reihe 6,
## Zellen 1 beige + 2 gelblich). (0,6) ganz-gelb bleibt vorerst weg, (3,6) dunkel
## ist nur fuer Felsen.
const SAND: Array[Vector2i] = [Vector2i(1, 6), Vector2i(2, 6)]
## Wie oft ein Ufer AUSSERHALB der Wueste Sand statt Gras/Kil wird (Prozent).
const BEACH_SAND_PCT := 60
## Meer: ab diesem _sea-Wert wird die Wasser-Schwelle stark gesenkt -> grosse Flaeche.
const SEA_THRESHOLD := 0.35
const WATER_THRESHOLD_SEA := -0.15
## Fels-Wahrscheinlichkeit in der Wueste ("ab und zu kleine Felsen").
const P_ROCK_DESERT := 0.02


func biome_at(cell: Vector2i) -> String:
	var n := _biome.get_noise_2d(cell.x, cell.y)
	if n > DESERT_THRESHOLD:
		return BIOME_DESERT
	if n < STEPPE_THRESHOLD:
		return BIOME_STEPPE
	return BIOME_GRASS


## Wuestenfelsen: kleine, aufgestapelte Formationen aus der dunklen Kachel (3,6).
const DARK_ROCK := Vector2i(3, 6)
const ROCK_THRESHOLD := 0.7    ## _rock-Noise darueber -> Fels (klein/selten, "ab und zu")
const ROCK_MAX := 2            ## bis 2 Ebenen hoch (Huegel-Form: Rand 1, Mitte 2)

## Fels-Bump-Hoehe in der Wueste: 0 = kein Fels, 1-2 = Formationshoehe.
func desert_rock(cell: Vector2i) -> int:
	if biome_at(cell) != BIOME_DESERT:
		return 0
	var rn := _rock.get_noise_2d(cell.x, cell.y)
	if rn < ROCK_THRESHOLD:
		return 0
	var t := (rn - ROCK_THRESHOLD) / (1.0 - ROCK_THRESHOLD)   # 0..1 im Cluster
	return clampi(int(ceil(t * float(ROCK_MAX))), 1, ROCK_MAX)


## Kachel fuer die UNTEREN Bloecke einer Saeule (die Seitenflaechen der Wuerfel).
## Wueste: Fels-Formation -> dunkle Kachel, sonst Sand. Grasland: Gras.
func fill_atlas(cell: Vector2i) -> Vector2i:
	var b := biome_at(cell)
	if b == BIOME_DESERT:
		if desert_rock(cell) > 0:
			return DARK_ROCK
		return SAND[_hash(cell, 41) % SAND.size()]
	if b == BIOME_STEPPE:
		return DIRT[0]                 # trockene Erd-Seiten statt gruen
	return GRASS[0]


func is_water(cell: Vector2i) -> bool:
	var thr := WATER_THRESHOLD
	if _sea.get_noise_2d(cell.x, cell.y) > SEA_THRESHOLD:
		thr = WATER_THRESHOLD_SEA        # Meer-Region: viel mehr Wasser
	return _water.get_noise_2d(cell.x, cell.y) > thr


## Zelle ODER ein 4er-Nachbar ist Wasser (fuer flaches Ufer).
func near_water(cell: Vector2i) -> bool:
	if is_water(cell):
		return true
	for d in NB4:
		if is_water(cell + d):
			return true
	return false


## Landzelle direkt an Wasser (fuer Ufer-Kil).
func is_shore(cell: Vector2i) -> bool:
	if is_water(cell):
		return false
	for d in NB4:
		if is_water(cell + d):
			return true
	return false


func ground_atlas(cell: Vector2i) -> Vector2i:
	if is_water(cell):
		return WATER_FILL[_hash(cell, 23) % WATER_FILL.size()]
	var b := biome_at(cell)
	# Ufer: in der Wueste immer Sand; sonst OFT (BEACH_SAND_PCT) Sandstrand,
	# ansonsten wie bisher etwas Kil.
	if is_shore(cell):
		if b == BIOME_DESERT or _hash(cell, 29) % 100 < BEACH_SAND_PCT:
			return SAND[_hash(cell, 31) % SAND.size()]
		if _hash(cell, 17) % 100 < SHORE_CLAY_PCT:
			return IsoWorld.CLAY_ATLAS
	# Wueste: Fels-Formation (dunkle Kachel) oder Sandboden.
	if b == BIOME_DESERT:
		if desert_rock(cell) > 0:
			return DARK_ROCK
		return SAND[_hash(cell, 31) % SAND.size()]
	# Steppe/Oedland: ueberwiegend trockene Erde, etwas Kil/Lehm, vereinzelt Gras.
	if b == BIOME_STEPPE:
		var sr := _hash(cell, 51) % 100
		if sr < 15:
			return GRASS[_hash(cell, 11) % GRASS.size()]
		if sr < 32:
			return IsoWorld.CLAY_ATLAS
		return DIRT[_hash(cell, 7) % DIRT.size()]
	# Grasland: Kil-Fleck, Erde, sonst Gras.
	if is_clay(cell):
		return IsoWorld.CLAY_ATLAS
	if is_dirt(cell):
		return DIRT[_hash(cell, 7) % DIRT.size()]
	return GRASS[_hash(cell, 11) % GRASS.size()]


# --- Props / Rohstoffe --------------------------------------------------

## Was liegt auf dieser Zelle? Leeres Dictionary = nichts. Sonst:
##   {"kind": "tree", "atlas": Vector2i}   - blockierender Baum
##   {"kind": "odun" | "bitki_lifi" | "tas"}  - Rohstoff zum Aufsammeln
##
## Bäume nur auf Gras (auf einer Erdfläche wirkt ein Wald deplatziert),
## Rohstoffe überall. Pro Zelle höchstens eine Sache.
func prop_at(cell: Vector2i) -> Dictionary:
	if is_water(cell):
		return {}                      # nichts waechst/liegt auf Wasser
	# Wueste: KEINE Baeume/Props. Die "Felsen" sind aufgestapelte Dark-Tile-
	# Formationen im Terrain (siehe desert_rock / height_at / ground_atlas).
	var bm := biome_at(cell)
	if bm == BIOME_DESERT:
		# Auf erhoehten Felsformationen nichts; sonst vereinzelt Palmen/Kakteen
		# (eigenes Sheet, gerendert ueber den Gather-Pfad, mit Hover + F-Ernte).
		if desert_rock(cell) > 0:
			return {}
		if _rand(cell, 7) < DESERT_FLORA_P:
			return {"kind": "col"}
		return {}
	# Baeume: Steppe nur ganz vereinzelt, Grasland ueber die Wald-Noise (Klumpen).
	if bm == BIOME_STEPPE:
		if _rand(cell, 1) < STEPPE_TREE_P:
			return {"kind": "tree", "atlas": TREES[_hash(cell, 2) % TREES.size()]}
	elif not is_dirt(cell):
		var forest := (_forest.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5   # 0..1
		var tree_p := lerpf(TREE_P_MEADOW, TREE_P_FOREST, forest)
		if _rand(cell, 1) < tree_p:
			return {"kind": "tree", "atlas": TREES[_hash(cell, 2) % TREES.size()]}

	var r := _rand(cell, 3)
	if r < P_HOLZ:
		return {"kind": "odun"}
	if r < P_HOLZ + P_FASER:
		return {"kind": "bitki_lifi"}
	if r < P_HOLZ + P_FASER + P_ROCK:
		# Fels: Zustand nach Seltenheit, Variante zufaellig (8 Formen).
		var state := RockDB.pick_state(_rand(cell, 5))
		var variant := _hash(cell, 6) % RockDB.VARIANTS
		return {"kind": "rock", "state": state, "variant": variant}
	return {}


# --- Deterministischer Zell-Zufall --------------------------------------
#
# Kein RandomNumberGenerator, sondern ein reiner Hash aus Koordinate + Seed:
# so ist jede Zelle für sich reproduzierbar, unabhängig von der Reihenfolge,
# in der Chunks geladen werden.

func _hash(cell: Vector2i, salt: int) -> int:
	var n := cell.x * 374761393 + cell.y * 668265263 + salt * 1274126177 + _seed * 2246822519
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return n & 0x7fffffff


## Hash als Float in [0, 1).
func _rand(cell: Vector2i, salt: int) -> float:
	return float(_hash(cell, salt) & 0xffffff) / float(0x1000000)
