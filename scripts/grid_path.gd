extends RefCounted
class_name GridPath

## A* auf dem Isometrie-Grid.
##
## Wird bei jeder Anfrage frisch gerechnet statt vorberechnet: die Karte
## ändert sich, sobald ein Baum fällt, und die Wege sind kurz genug.
## `max_nodes` deckelt die Suche, damit ein unerreichbares Ziel nicht
## die ganze Karte durchkämmt.

## Weg von `start` nach `goal`, exklusive `start`.
## Leeres Array = kein Weg gefunden.
static func find(world: IsoWorld, start: Vector2i, goal: Vector2i,
		max_step: int = 1, max_nodes: int = 4000) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal or world.top_level_at(goal) < 0 or world.has_prop(goal):
		return result

	var came: Dictionary = {start: start}
	var cost: Dictionary = {start: 0.0}
	# Offene Liste als Array aus [prioritaet, zelle]; klein genug, dass ein
	# lineares Minimum billiger ist als eine echte Priority Queue.
	var open: Array = [[0.0, start]]
	var expanded := 0

	while not open.is_empty() and expanded < max_nodes:
		var best := 0
		for i in range(1, open.size()):
			if open[i][0] < open[best][0]:
				best = i
		var current: Vector2i = open[best][1]
		open.remove_at(best)
		expanded += 1

		if current == goal:
			var node := goal
			while node != start:
				result.push_front(node)
				node = came[node]
			return result

		for n in world.neighbors(current):
			if not world.can_step(current, n, max_step):
				continue
			var next_cost: float = cost[current] + 1.0
			if not cost.has(n) or next_cost < cost[n]:
				cost[n] = next_cost
				came[n] = current
				open.append([next_cost + _heuristic(world, n, goal), n])
	return result


## Luftlinie zwischen den Zellmittelpunkten, in Schritten.
static func _heuristic(world: IsoWorld, a: Vector2i, b: Vector2i) -> float:
	var pa := world.cell_to_world(a, 0)
	var pb := world.cell_to_world(b, 0)
	# Ein Schritt entspricht (16, 8) px - darauf normieren.
	return maxf(absf(pa.x - pb.x) / 16.0, absf(pa.y - pb.y) / 8.0)


## Begehbare Nachbarzelle eines Props, möglichst nah an `from`.
static func adjacent_to(world: IsoWorld, target: Vector2i, from: Vector2i,
		max_step: int = 1) -> Vector2i:
	var best := Vector2i(2147483647, 2147483647)
	var best_dist := INF
	for n in world.neighbors(target):
		if world.top_level_at(n) < 0 or world.has_prop(n):
			continue
		var d := world.cell_to_world(n, 0).distance_to(world.cell_to_world(from, 0))
		if d < best_dist:
			best_dist = d
			best = n
	return best
