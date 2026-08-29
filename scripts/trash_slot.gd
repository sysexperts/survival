extends Control

## Papierkorb im Buch (Istatik-Seite): zieht man einen Stapel darauf, wird er
## geloescht. Ein Drop-Ziel fuer Godots Drag & Drop - deshalb ein eigenes Script
## mit _can_drop_data / _drop_data (die lassen sich nicht von aussen anhaengen).
##
## KEIN class_name (Auto-Updater) - per preload einbinden.

const UiAtlas := preload("res://scripts/ui_atlas.gd")

var hud                       ## InventoryHUD (fuer inventory.take)
var _icon: TextureRect
var _hot := false             ## liegt gerade ein gueltiger Zug darueber?
var _hot_age := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Sil (buraya birak)"
	_icon = TextureRect.new()
	_icon.texture = UiAtlas.cell("icons", 14, 3)     # Muelleimer-Icon
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.pivot_offset = size * 0.5
	add_child(_icon)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and data.has("slot_from")
	if ok:
		_hot = true
		_hot_age = 0.0
	return ok


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if hud != null:
		hud.inventory.take(int(data["slot_from"]))   # Stapel entfernen (weg)
	_hot = false


## Rote Hervorhebung + kleiner Puls, solange ein Zug darueber liegt.
func _process(delta: float) -> void:
	if _hot:
		_hot_age += delta
		if _hot_age > 0.08:          # _can_drop_data feuert nicht mehr -> nicht mehr drueber
			_hot = false
	if _icon != null:
		_icon.pivot_offset = _icon.size * 0.5
		_icon.modulate = Color(1.4, 0.55, 0.5) if _hot else Color(1, 1, 1)
		_icon.scale = Vector2(1.18, 1.18) if _hot else Vector2.ONE
