extends Node
class_name CraftQueue

## Die Bauliste: was gerade gefertigt wird und was noch ansteht.
##
## Bauen dauert. Der Spieler gibt eine Stückzahl auf, die Zutaten sind
## sofort weg, und danach fällt im Takt der Bauzeit ein Stück nach dem
## anderen ins Inventar.
##
## Warum die Zutaten sofort abgebucht werden: sonst könnte man denselben
## Vorrat mehrfach verplanen oder ihn zwischendurch verbauen, und die
## Liste stünde da mit Aufträgen, die nicht mehr gedeckt sind. Bricht man
## einen Auftrag ab, kommt der Rest vollständig zurück.
##
## Läuft weiter, während das Fenster zu ist - der Node hängt am Inventar,
## nicht an der Oberfläche.

signal changed

var inventory: Inventory
## Je Auftrag: {"recipe": Dictionary, "left": int, "elapsed": float}
var jobs: Array = []


func setup(p_inventory: Inventory) -> void:
	inventory = p_inventory


func is_busy() -> bool:
	return not jobs.is_empty()


## Der Auftrag, an dem gerade gearbeitet wird - oder {}.
func current() -> Dictionary:
	return jobs[0] if not jobs.is_empty() else {}


## Fortschritt des laufenden Stücks, 0..1.
func progress() -> float:
	if jobs.is_empty():
		return 0.0
	var secs := RecipeDB.seconds(jobs[0]["recipe"])
	return clampf(float(jobs[0]["elapsed"]) / maxf(secs, 0.001), 0.0, 1.0)


## Nimmt bis zu `count` Stück in die Liste auf und bucht die Zutaten ab.
## Gibt zurück, wie viele es wirklich wurden.
func enqueue(recipe: Dictionary, count: int) -> int:
	if inventory == null or count <= 0:
		return 0
	var n := RecipeDB.affordable(inventory, recipe, count)
	if n <= 0:
		return 0
	for id in recipe["cost"]:
		inventory.remove(id, int(recipe["cost"][id]) * n)
	# Gleiches Rezept anhängen statt einen zweiten Auftrag aufmachen -
	# sonst wächst die Liste bei jedem Klick um eine Zeile.
	for job in jobs:
		if job["recipe"] == recipe:
			job["left"] = int(job["left"]) + n
			changed.emit()
			return n
	jobs.append({"recipe": recipe, "left": n, "elapsed": 0.0})
	changed.emit()
	return n


## Bricht einen Auftrag ab und gibt die Zutaten der offenen Stücke zurück.
func cancel(index: int) -> void:
	if index < 0 or index >= jobs.size():
		return
	var job: Dictionary = jobs[index]
	var left := int(job["left"])
	for id in job["recipe"]["cost"]:
		inventory.add(id, int(job["recipe"]["cost"][id]) * left)
	jobs.remove_at(index)
	changed.emit()


func cancel_all() -> void:
	while not jobs.is_empty():
		cancel(0)


func _process(delta: float) -> void:
	if jobs.is_empty() or inventory == null:
		return
	var job: Dictionary = jobs[0]
	var recipe: Dictionary = job["recipe"]
	var secs := RecipeDB.seconds(recipe)
	var amount := int(recipe["count"])
	job["elapsed"] = float(job["elapsed"]) + delta
	var done := 0
	# Schleife statt if: bei sehr kurzer Bauzeit oder einem Ruckler können
	# in einem Bild mehrere Stücke fertig werden.
	while float(job["elapsed"]) >= secs and int(job["left"]) > 0:
		if not inventory.room_for(recipe["out"], amount):
			# Kein Platz: die Uhr bleibt stehen, bis wieder welcher da ist.
			# Das Stück ist bezahlt und geht nicht verloren.
			job["elapsed"] = secs
			break
		job["elapsed"] = float(job["elapsed"]) - secs
		job["left"] = int(job["left"]) - 1
		inventory.add(recipe["out"], amount)
		done += 1
	if int(job["left"]) <= 0:
		jobs.pop_front()
		done += 1
	# Nur melden, wenn sich wirklich etwas geändert hat. Der laufende
	# Balken fragt `progress()` selbst ab - dafür jedes Bild ein Signal zu
	# werfen, würde die halbe Oberfläche neu aufbauen.
	if done > 0:
		changed.emit()
