class_name WorldGen
extends RefCounted

## Prozedurale Höhenkarte für den chunk-basierten Weltgenerator.
##
## Reine Logik, kein Node-Zustand: eine Zellkoordinate rein, eine Höhe raus.
## Damit ist die Erzeugung deterministisch (gleicher Welt-Seed -> gleiche
## Welt) und lässt sich ohne Szene testen. Gearbeitet wird immer im
## DURCHGEHENDEN Zellkoordinatensystem - nur so bleibt die Stacked-Parität
## des Rasters an den Chunk-Grenzen stimmig (siehe README/neighbors).

## Höher stapeln wir nicht: die Optik ist auf niedrige Hügel ausgelegt, und
## der Handbau-Bereich reicht selten über Layer 03 hinaus.
const MAX_LEVEL := 3

## Basishöhe direkt am Handbau-Rand. Der authored Bereich liegt auf Level00,
## deshalb 0 - so entsteht am Übergang keine Kante.
const BASE_HEIGHT := 0

## Über so viele Zellen wird vom Handbau-Rand (BASE_HEIGHT) in die volle
## Noise-Höhe überblendet. Ohne diese Rampe stünde direkt neben der gemalten
## Map eine harte Stufe.
const EDGE_RING := 3

var _noise := FastNoiseLite.new()


func _init(world_seed: int = 1337) -> void:
	_noise.seed = world_seed
	# Weiches Simplex, damit die Hügel zusammenhängen statt zu rauschen.
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Grob eine Hügelkuppe alle ~30 Zellen - eng genug, dass man beim Laufen
	# ständig Neues sieht, weit genug, dass Hügel begehbar bleiben.
	_noise.frequency = 0.03


## Rohe Noise-Höhe einer Zelle, 0..MAX_LEVEL. Ohne Rand-Rücksicht.
func noise_height(cell: Vector2i) -> int:
	var t := (_noise.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5   # -1..1 -> 0..1
	return clampi(int(floor(t * float(MAX_LEVEL + 1))), 0, MAX_LEVEL)


## Endgültige Höhe der Säule an dieser Zelle.
##
## `dist_to_authored` ist der Zellabstand zum gemalten Bereich (0 = direkt am
## Rand). Innerhalb von EDGE_RING wird von BASE_HEIGHT in die Noise-Höhe
## überblendet, damit der Übergang weich bleibt.
func height_at(cell: Vector2i, dist_to_authored: int) -> int:
	var h := noise_height(cell)
	if dist_to_authored >= EDGE_RING:
		return h
	var t := float(dist_to_authored) / float(EDGE_RING)
	return int(round(lerp(float(BASE_HEIGHT), float(h), t)))
