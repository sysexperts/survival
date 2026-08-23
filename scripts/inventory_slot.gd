extends Panel
class_name InventorySlot

## Ein Feld im Inventar - Hotbar wie Tasche.
##
## Eigene Klasse nur wegen Drag & Drop: Godot fragt dafür drei Methoden am
## Control ab, und die lassen sich nicht von aussen anhängen.
##
## Der Ablauf ist Godots eigener: `_get_drag_data` startet den Zug und
## liefert die Vorschau am Mauszeiger, `_can_drop_data` entscheidet, ob das
## Feld unter der Maus etwas annimmt, `_drop_data` führt es aus. Ein
## einfacher Klick ohne Ziehen kommt weiterhin als `gui_input` an und wählt
## das Feld nur aus.

var hud: InventoryHUD
var index: int


func _get_drag_data(_at_position: Vector2) -> Variant:
	var stack: Dictionary = hud.inventory.slots[index]
	if stack.is_empty():
		return null
	set_drag_preview(hud.make_drag_preview(stack))
	hud.drag_from = index          # merken, falls ausserhalb losgelassen wird
	return {"slot_from": index}


## Endet der Zug NICHT auf einem gueltigen Feld (also draussen in der Welt),
## wird der Stapel fallen gelassen - "mit der Maus rauswerfen".
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and hud and hud.drag_from == index:
		if not is_drag_successful():
			hud.drop_to_world(index)
		hud.drag_from = -1


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("slot_from")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	hud.inventory.move(int(data["slot_from"]), index)
