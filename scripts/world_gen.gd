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

const MAX_LEVEL := 3          ## Höher stapeln wir nicht (niedrige Hügel).
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

const RockDB := preload("res://scripts/rock_db.gd")

var _seed: int
var _height := FastNoiseLite.new()
var _dirt := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _clay := FastNoiseLite.new()


func _init(world_seed: int = 1337) -> void:
	_seed = world_seed
	_height.seed = world_seed
	_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height.frequency = 0.03            # ~Hügelkuppe alle 30 Zellen
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


# --- Höhe ---------------------------------------------------------------

## Rohe Noise-Höhe einer Zelle, 0..MAX_LEVEL, ohne Rand-Rücksicht.
func noise_height(cell: Vector2i) -> int:
	var t := (_height.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5
	return clampi(int(floor(t * float(MAX_LEVEL + 1))), 0, MAX_LEVEL)


## Endgültige Höhe der Säule.
##
## `edge_dist`/`edge_height` beschreiben den nächsten Handbau-Nachbarn:
## edge_dist < 0 heißt "kein gemalter Rand in der Nähe" -> volle Noise-Höhe.
## Sonst wird von der tatsächlichen Randhöhe (edge_height) über EDGE_RING
## Zellen in die Noise-Höhe geblendet - direkt am Rand (edge_dist 0) exakt
## bündig, damit dort weder eine Stufe noch eine Lücke entsteht.
func height_at(cell: Vector2i, edge_dist: int, edge_height: int) -> int:
	var h := noise_height(cell)
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


func ground_atlas(cell: Vector2i) -> Vector2i:
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
	var dirt := is_dirt(cell)

	if not dirt:
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
