extends Sprite2D

## Zeigt das aktuell gehaltene Werkzeug an Jacks Hand.
##
## Bewusst OHNE class_name (Auto-Updater-Regel: neue class_name werden beim
## pck-Overlay nicht registriert) - wird per preload aus player.gd eingehaengt.
##
## Das Tool ist ein eigenes Sprite ueber/hinter dem Koerper. Pro Richtung ein
## Hand-Anker (Position + davor/dahinter + gespiegelt). Ein Icon reicht fuer
## alle Richtungen.

var player: Node2D
var _sprite: AnimatedSprite2D
var _tool_id := "balta"

var held_scale := 0.64

## Hand-Anker je Richtung. pos = Versatz vom Spieler-Ursprung (Fuesse),
## front = vor dem Koerper zeichnen, flip = Icon spiegeln.
var hand := {
	"south":      {"pos": Vector2(-3, -15), "front": true,  "flip": false},
	"south-east": {"pos": Vector2(1, -12),  "front": true,  "flip": false},
	"east":       {"pos": Vector2(5, -15),  "front": true,  "flip": false},
	"north-east": {"pos": Vector2(13, -15), "front": false, "flip": false},
	"north":      {"pos": Vector2(2, -16),  "front": false, "flip": true},
	"north-west": {"pos": Vector2(-11, -15), "front": false, "flip": true},
	"west":       {"pos": Vector2(-26, 7),  "front": false, "flip": true},
	"south-west": {"pos": Vector2(-3, -14), "front": true,  "flip": true},
}


func setup(p_player: Node2D, p_sprite: AnimatedSprite2D) -> void:
	player = p_player
	_sprite = p_sprite
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(held_scale, held_scale)
	visible = false


func _process(_dt: float) -> void:
	if player == null:
		return
	# Nur zeigen, wenn die Axt gewaehlt ist und nicht gerade der gebackene
	# Schlag laeuft (sonst haette Jack zwei Aexte).
	var swinging := String(_sprite.animation).begins_with("axe_")
	if not player.has_axe or swinging:
		visible = false
		return
	var a: Dictionary = hand.get(player.facing, hand["south"])
	texture = ItemDB.icon(_tool_id)
	# Koerper-Wippen beim Laufen (sprite.offset.y) mitnehmen.
	var base_y: float = player.sprite_offset.y
	var bob: float = _sprite.offset.y - base_y
	position = a["pos"] + Vector2(0, bob)
	flip_h = bool(a["flip"])
	z_index = 1 if a["front"] else -1
	visible = true
