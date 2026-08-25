extends Sprite2D

## Zeigt das aktuell gehaltene Werkzeug an Jacks Hand.
##
## Bewusst OHNE class_name (Auto-Updater-Regel: neue class_name werden beim
## pck-Overlay nicht registriert) - wird per preload aus player.gd eingehaengt.
##
## Das Tool ist ein eigenes Sprite ueber/hinter dem Koerper. Pro Richtung ein
## Hand-Anker (Position + davor/dahinter + gespiegelt). Ein Icon reicht fuer
## alle Richtungen.
##
## === Justier-Modus (Taste P) ===========================================
## P schaltet den Tuning-Modus an/aus. Dann:
##   - die Axt ist immer sichtbar,
##   - mit der LINKEN MAUSTASTE ziehst du sie an die richtige Stelle
##     (fuer die gerade angezeigte Laufrichtung),
##   - MAUSRAD = Groesse,
##   - Taste 7 (Numpad) = vor/hinter den Koerper, 9 = spiegeln.
## Zum Drehen einfach kurz in eine Richtung laufen. Jede Aenderung wird nach
## `user://held_tool_anchors.json` gespeichert - daraus backen wir die finalen
## Werte fest ein.

const SAVE_PATH := "user://held_tool_anchors.json"

var player: Node2D
var _sprite: AnimatedSprite2D
var _tool_id := "balta"
var _tuning := false
var _dragging := false

var held_scale := 0.64

## Im Justier-Modus (Taste P) eingestellt und fest eingebacken.
## pos = Versatz vom Spieler-Ursprung (Fuesse), front = vor dem Koerper
## zeichnen, flip = Icon spiegeln.
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
	_load_anchors()
	scale = Vector2(held_scale, held_scale)
	visible = false


func _process(_dt: float) -> void:
	if player == null:
		return
	# Im Tuning-Modus immer zeigen; sonst nur wenn die Axt gewaehlt ist und
	# nicht gerade der gebackene Schlag laeuft (kein Doppel-Axt-Effekt).
	var swinging := String(_sprite.animation).begins_with("axe_")
	if not _tuning and (not player.has_axe or swinging):
		visible = false
		return
	var a: Dictionary = hand.get(player.facing, hand["south"])
	texture = ItemDB.icon(_tool_id)
	scale = Vector2(held_scale, held_scale)
	# Koerper-Wippen mitnehmen: der Sprite hebt/senkt sich beim Laufen ueber
	# sprite.offset.y (Schritt-Versatz). Ohne das bleibt die Axt starr am Boden
	# haengen und "fliegt nur mit", statt an der Hand zu kleben.
	var bob := _sprite.offset.y - player.sprite_offset.y
	# Beim Ziehen folgt die Position der Maus, sonst dem Anker (+ Wippen).
	if not (_tuning and _dragging):
		position = a["pos"] + Vector2(0, bob)
	flip_h = bool(a["flip"])
	z_index = 1 if a["front"] else -1
	visible = true


func _input(event: InputEvent) -> void:
	# In _input (nicht _unhandled_input), damit die Maus im Tuning-Modus die
	# Lauf-/Interaktionslogik nicht ausloest.
	# P: Tuning-Modus umschalten.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_P:
		_tuning = not _tuning
		_dragging = false
		print("[HeldTool] Justier-Modus: %s" % ("AN" if _tuning else "aus"))
		if not _tuning:
			_save_anchors()
		get_viewport().set_input_as_handled()
		return
	if not _tuning:
		return

	var a: Dictionary = hand[player.facing]

	# Maus-Ziehen setzt die Position der aktuellen Richtung.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not event.pressed:
			a["pos"] = (get_global_mouse_position() - player.global_position).round()
			hand[player.facing] = a
			_report(); _save_anchors()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _dragging:
		position = (get_global_mouse_position() - player.global_position).round()
		a["pos"] = position
		hand[player.facing] = a
		get_viewport().set_input_as_handled()
		return

	# Mausrad = Groesse.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			held_scale = minf(held_scale + 0.02, 2.0); _report(); _save_anchors()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			held_scale = maxf(held_scale - 0.02, 0.1); _report(); _save_anchors()
			get_viewport().set_input_as_handled()

	# Feintuning per Numpad: 4/6 x, 8/2 y, 7 vor/hinter, 9 spiegeln.
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_KP_4: a["pos"].x -= 1
			KEY_KP_6: a["pos"].x += 1
			KEY_KP_8: a["pos"].y -= 1
			KEY_KP_2: a["pos"].y += 1
			KEY_KP_7: a["front"] = not a["front"]
			KEY_KP_9: a["flip"] = not a["flip"]
			_: return
		hand[player.facing] = a
		_report(); _save_anchors()
		get_viewport().set_input_as_handled()


## Aktuelle Zeile ins Log drucken (zum spaeteren Fest-Einbacken).
func _report() -> void:
	var a: Dictionary = hand[player.facing]
	print('[HeldTool] scale=%.2f  "%s": {"pos": Vector2(%d, %d), "front": %s, "flip": %s},' % [
		held_scale, player.facing, int(a["pos"].x), int(a["pos"].y),
		str(a["front"]).to_lower(), str(a["flip"]).to_lower()])


func _save_anchors() -> void:
	var out := {"held_scale": held_scale, "hand": {}}
	for k in hand:
		var a: Dictionary = hand[k]
		out["hand"][k] = {"x": int(a["pos"].x), "y": int(a["pos"].y),
			"front": bool(a["front"]), "flip": bool(a["flip"])}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))


func _load_anchors() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	held_scale = float(data.get("held_scale", held_scale))
	var h: Variant = data.get("hand", {})
	if typeof(h) == TYPE_DICTIONARY:
		for k in h:
			if hand.has(k):
				var e: Dictionary = h[k]
				hand[k] = {"pos": Vector2(float(e.get("x", 0)), float(e.get("y", 0))),
					"front": bool(e.get("front", true)), "flip": bool(e.get("flip", false))}
