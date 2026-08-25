extends Sprite2D

## Zeigt das aktuell gehaltene Werkzeug an Jacks Hand.
##
## Bewusst OHNE class_name (Auto-Updater-Regel: neue class_name werden beim
## pck-Overlay nicht registriert) - wird per preload aus player.gd eingehaengt.
##
## Das Tool ist ein eigenes Sprite ueber/hinter dem Koerper. Pro Richtung ein
## Hand-Anker (Position + davor/dahinter + gespiegelt). Ein Icon reicht fuer
## alle Richtungen - das spart die Tool-mal-Richtungen-Explosion im Sheet.
##
## Live justieren: Numpad. 4/6 = x, 8/2 = y (der gerade sichtbaren Richtung),
## 7 = davor/dahinter, 9 = spiegeln. Die Werte werden ins Log gedruckt - so
## koennen wir die Tabelle danach fest eintragen.

var player: Node2D
var _sprite: AnimatedSprite2D
var _tool_id := "balta"

const HELD_SCALE := 0.7

## Startwerte je Richtung. pos = Versatz vom Spieler-Ursprung (Fuesse),
## front = vor dem Koerper zeichnen, flip = Icon spiegeln.
var hand := {
	"south":      {"pos": Vector2(7, -20), "front": true,  "flip": false},
	"south-east": {"pos": Vector2(9, -21), "front": true,  "flip": false},
	"east":       {"pos": Vector2(10, -23), "front": true,  "flip": false},
	"north-east": {"pos": Vector2(9, -25), "front": false, "flip": false},
	"north":      {"pos": Vector2(-7, -26), "front": false, "flip": true},
	"north-west": {"pos": Vector2(-9, -25), "front": false, "flip": true},
	"west":       {"pos": Vector2(-10, -23), "front": true, "flip": true},
	"south-west": {"pos": Vector2(-9, -21), "front": true,  "flip": true},
}


func setup(p_player: Node2D, p_sprite: AnimatedSprite2D) -> void:
	player = p_player
	_sprite = p_sprite
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(HELD_SCALE, HELD_SCALE)
	visible = false


func _process(_dt: float) -> void:
	# Nur zeigen, wenn die Axt in der Hand ist und nicht gerade der gebackene
	# Schlag laeuft (sonst haette Jack zwei Aexte).
	var swinging := String(_sprite.animation).begins_with("axe_")
	if player == null or not player.has_axe or swinging:
		visible = false
		return
	var f: String = player.facing
	var a: Dictionary = hand.get(f, hand["south"])
	texture = ItemDB.icon(_tool_id)
	position = a["pos"]
	flip_h = bool(a["flip"])
	z_index = 1 if a["front"] else -1
	visible = true


## Live-Justierung der aktuell sichtbaren Richtung ueber den Numpad.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var f: String = player.facing
	var a: Dictionary = hand[f]
	match event.keycode:
		KEY_KP_4: a["pos"].x -= 1
		KEY_KP_6: a["pos"].x += 1
		KEY_KP_8: a["pos"].y -= 1
		KEY_KP_2: a["pos"].y += 1
		KEY_KP_7: a["front"] = not a["front"]
		KEY_KP_9: a["flip"] = not a["flip"]
		_: return
	hand[f] = a
	print('\t"%s": {"pos": Vector2(%d, %d), "front": %s, "flip": %s},' % [
		f, int(a["pos"].x), int(a["pos"].y),
		str(a["front"]).to_lower(), str(a["flip"]).to_lower()])
	get_viewport().set_input_as_handled()
