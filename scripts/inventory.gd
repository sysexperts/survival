extends RefCounted
class_name Inventory

## Reines Datenmodell: eine Liste von Slots, keine Oberfläche.
##
## Die ersten `hotbar_size` Slots sind die Hotbar, der Rest die Tasche.
## Ein Slot ist entweder `{}` (leer) oder `{"id": String, "count": int}`.

signal changed

var hotbar_size: int
var slots: Array = []


func _init(p_hotbar := 9, p_bag_rows := 3) -> void:
	hotbar_size = p_hotbar
	slots.resize(p_hotbar + p_hotbar * p_bag_rows)
	for i in slots.size():
		slots[i] = {}


func is_empty_slot(i: int) -> bool:
	return slots[i].is_empty()


func count_of(id: String) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and slot["id"] == id:
			total += int(slot["count"])
	return total


## Legt `count` Stück ab. Gibt zurück, was keinen Platz mehr fand.
## Füllt erst angebrochene Stapel auf, dann leere Slots - so landet
## Nachschub dort, wo der Spieler ihn erwartet.
func add(id: String, count: int) -> int:
	if count <= 0 or not ItemDB.has(id):
		return count
	var left := count
	var cap := ItemDB.max_stack(id)
	for i in slots.size():
		if left <= 0:
			break
		var slot: Dictionary = slots[i]
		if slot.is_empty() or slot["id"] != id:
			continue
		var room: int = cap - int(slot["count"])
		var moved: int = mini(room, left)
		slot["count"] = int(slot["count"]) + moved
		left -= moved
	for i in slots.size():
		if left <= 0:
			break
		if slots[i].is_empty():
			var moved: int = mini(cap, left)
			slots[i] = {"id": id, "count": moved}
			left -= moved
	if left != count:
		changed.emit()
	return left


## Passen `count` Stück dieser Sorte noch hinein?
##
## Wird vor dem Handwerk gefragt: erst prüfen, dann Zutaten verbrauchen -
## sonst wären sie weg und das Ergebnis fiele auf den Boden.
func room_for(id: String, count: int) -> bool:
	var cap := ItemDB.max_stack(id)
	var room := 0
	for slot in slots:
		if slot.is_empty():
			room += cap
		elif slot["id"] == id:
			room += cap - int(slot["count"])
		if room >= count:
			return true
	return room >= count


## Nimmt bis zu `count` Stück heraus. Gibt zurück, wie viel es wirklich war.
func remove(id: String, count: int) -> int:
	var left := count
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var slot: Dictionary = slots[i]
		if slot.is_empty() or slot["id"] != id:
			continue
		var taken: int = mini(int(slot["count"]), left)
		slot["count"] = int(slot["count"]) - taken
		left -= taken
		if int(slot["count"]) <= 0:
			slots[i] = {}
	if left != count:
		changed.emit()
	return count - left


## Nimmt den kompletten Stapel aus einem Slot heraus.
func take(i: int) -> Dictionary:
	var stack: Dictionary = slots[i]
	slots[i] = {}
	if not stack.is_empty():
		changed.emit()
	return stack


## Legt einen Stapel in einen Slot. Gleiche Sorte wird zusammengeführt,
## sonst getauscht. Zurück kommt, was der Spieler danach in der Hand hält.
func put(i: int, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	var slot: Dictionary = slots[i]
	if not slot.is_empty() and slot["id"] == stack["id"]:
		var cap := ItemDB.max_stack(stack["id"])
		var room: int = cap - int(slot["count"])
		var moved: int = mini(room, int(stack["count"]))
		slot["count"] = int(slot["count"]) + moved
		var rest: int = int(stack["count"]) - moved
		changed.emit()
		return {} if rest <= 0 else {"id": stack["id"], "count": rest}
	slots[i] = stack
	changed.emit()
	return slot


## Schiebt den Stapel aus `from` auf `to` - das Ziel von Drag & Drop.
##
## Gleiche Sorte wird zusammengeführt, sonst getauscht. Was nicht ins Ziel
## passt (voller Stapel), bleibt im Ausgangsfeld liegen; nichts geht
## verloren, auch wenn der Spieler auf ein volles Feld zieht.
func move(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0:
		return
	if from >= slots.size() or to >= slots.size():
		return
	var stack: Dictionary = slots[from]
	if stack.is_empty():
		return
	slots[from] = {}
	# `put` liefert entweder den Rest eines zu grossen Stapels oder den
	# Inhalt, der im Ziel lag - beides gehört zurück ins Ausgangsfeld.
	slots[from] = put(to, stack)
	changed.emit()
