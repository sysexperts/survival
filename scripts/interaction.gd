extends Node2D

## Maus-Steuerung: Linksklick laufen, Rechtsklick auf einen Baum fällen,
## auf einen Stein hinlaufen und aufheben. Zeigt ausserdem den weissen Rand an dem Prop
## unter dem Mauszeiger - Baum, Stumpf oder Stein.

@export var world_path: NodePath = ^"../World"
@export var outline_color := Color(1, 1, 1, 0.9)
## Nur Props in diesem Umkreis um die Maus werden geprüft (Pixel).
@export var hover_radius := 120.0

var world: IsoWorld
var player: Player
var highlight: Sprite2D
var _hovered: Array = []           ## [cell, level, atlas] oder leer
var _furn_hover: Array = []        ## [cell, Furniture] oder leer
var _furn_img: Image               ## Moebel-Sheet, einmal geladen (Alpha-Test)
var preview: PlacementPreview


func _ready() -> void:
	add_to_group("interaction")
	world = get_node(world_path) as IsoWorld
	player = get_tree().get_first_node_in_group("player")
	_build_highlight()
	preview = PlacementPreview.new()
	preview.world = world
	add_child(preview)


func _build_highlight() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/outline.gdshader")
	mat.set_shader_parameter("outline_color", outline_color)
	mat.set_shader_parameter("thickness", 1.0)
	highlight = Sprite2D.new()
	highlight.material = mat
	highlight.centered = false
	highlight.visible = false
	highlight.z_index = IsoWorld.TALL_Z_INDEX + 1
	add_child(highlight)


func _process(_delta: float) -> void:
	# Waehrend des Platzierens kein Hover - sonst leuchten beide.
	if preview.active:
		highlight.visible = false
		_hovered = []
		_furn_hover = []
		return
	_hovered = _prop_under_mouse()
	if not _hovered.is_empty():
		_furn_hover = []
		_highlight_prop()
		return
	# Kein Prop unter der Maus - vielleicht ein Moebel (Werkbank, Bett ...).
	_furn_hover = _furniture_under_mouse()
	if _furn_hover.is_empty():
		highlight.visible = false
		return
	_highlight_furniture(_furn_hover[1])


func _highlight_prop() -> void:
	# Die Welt liefert die fertige Textur des Props - egal aus welchem Sheet
	# sie stammt. Selbst zusammenbauen ging schief, sobald ein Prop nicht
	# aus dem TileSet kam.
	var cell: Vector2i = _hovered[0]
	var tex := world.prop_texture(cell)
	if tex == null:
		highlight.visible = false
		return
	highlight.texture = tex
	highlight.flip_h = false
	# Ein Bildpixel Rand reicht: die Kamera zoomt vierfach, das bleibt auch
	# bei einem halbierten Prop deutlich sichtbar. Dicker zu ziehen wuerde
	# duenne Sachen wie einen Ast komplett weiss uebermalen.
	highlight.scale = world.prop_scale(cell)
	highlight.global_position = world.prop_rect(cell, _hovered[1], _hovered[2], _hovered[3]).position
	highlight.visible = true


func _highlight_furniture(node: Furniture) -> void:
	highlight.texture = node.texture
	highlight.scale = node.scale
	highlight.flip_h = node.flip_h
	# Der Rand wird an derselben Stelle gezeichnet wie das Moebel. Bei
	# gespiegeltem Moebel bleibt der Bildausschnitt gleich gross, nur der
	# Inhalt kippt - die obere linke Ecke stimmt also weiterhin.
	highlight.global_position = node.global_position + node.offset * node.scale
	highlight.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and preview.active:
		if event.keycode == KEY_ESCAPE:
			preview.cancel()
			get_viewport().set_input_as_handled()
			return
		# R dreht das Moebel in der Vorschau (spiegeln).
		if event.keycode == KEY_R:
			preview.flip()
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton and event.pressed) or player == null:
		return
	if preview.active:
		# Im Platzieren-Modus schluckt die Vorschau die Klicks, damit kein
		# Laufbefehl oder Faellauftrag dazwischenfunkt.
		if event.button_index == MOUSE_BUTTON_LEFT:
			preview.try_confirm()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			preview.cancel()
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var hit := world.pick_block(get_global_mouse_position())
		if not hit.is_empty():
			player.walk_to(hit[0])
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		# Shift+Rechtsklick auf ein platziertes Objekt (Möbel/Lagerfeuer) reißt
		# es ab. Es kommt NICHT ins Inventar zurück.
		if event.shift_pressed:
			var target := _placed_under_mouse()
			if target != Player.INVALID_CELL:
				_ask_destroy(target)
			get_viewport().set_input_as_handled()
			return
		if _hovered.is_empty():
			# Kein Prop, aber vielleicht ein Moebel: hinlaufen (und wenn es
			# eine Station ist, oeffnet sie sich bei Ankunft von selbst).
			var furn := _furniture_under_mouse()
			if not furn.is_empty():
				# Bett: hinlaufen und hineinlegen. Sonst: Station (oeffnet bei
				# Ankunft) bzw. gar nichts.
				if not player.walk_to_bed(furn[0]):
					player.walk_to_station(furn[0])
			return
		# Stein: hinlaufen und aufheben - E geht weiter zu Fuss.
		if int(_hovered[3]) == IsoWorld.STONE_SOURCE_ID:
			player.fetch_stone(_hovered[0])
		# Stumpf: ein Klick, endgueltig weg. Baum: normales Faellen.
		elif int(_hovered[3]) == IsoWorld.STUMP_SOURCE_ID:
			player.clear_stump(_hovered[0], _hovered[1])
		else:
			player.chop(_hovered[0], _hovered[1])


## --- Abriss-Rückfrage ---------------------------------------------------

## Nachfrage vor dem Abreißen, damit man nicht aus Versehen ein Möbel verliert.
var _confirm: ConfirmationDialog
var _pending_destroy := Vector2i(2147483647, 2147483647)


## Fragt "«Name» yıkılsın mı?" und reißt erst nach Bestätigung ab.
func _ask_destroy(cell: Vector2i) -> void:
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.title = "Yikim"
		_confirm.get_ok_button().text = "Evet"
		_confirm.get_cancel_button().text = "Hayir"
		_confirm.confirmed.connect(_on_destroy_confirmed)
		# Bei Abbruch/Schließen den gemerkten Auftrag verwerfen.
		_confirm.canceled.connect(func(): _pending_destroy = Player.INVALID_CELL)
		add_child(_confirm)
	_pending_destroy = cell
	_confirm.dialog_text = "%s yikilsin mi?" % _placed_name(cell)
	_confirm.popup_centered()


func _on_destroy_confirmed() -> void:
	if _pending_destroy != Player.INVALID_CELL:
		player.walk_to_destroy(_pending_destroy)
	_pending_destroy = Player.INVALID_CELL


## Anzeigename des platzierten Objekts an `cell` (für die Rückfrage).
func _placed_name(cell: Vector2i) -> String:
	var node := world.blocker_at(cell)
	if node is Furniture:
		return ItemDB.display_name(node.id)
	if node is Campfire:
		return ItemDB.display_name("kamp_atesi")
	return "Bu"


## Ankerzelle des platzierten Objekts unter der Maus (Möbel pixelgenau,
## Lagerfeuer über die getroffene Bodenzelle), oder INVALID_CELL.
func _placed_under_mouse() -> Vector2i:
	var furn := _furniture_under_mouse()
	if not furn.is_empty():
		return (furn[1] as Furniture).cell
	var hit := world.pick_block(get_global_mouse_position())
	if not hit.is_empty():
		var node := world.blocker_at(hit[0])
		if node is Campfire:
			return node.cell
	return Player.INVALID_CELL


## Vorderstes Moebel unter dem Mauszeiger, pixelgenau. [cell, Furniture] oder [].
## Sortiert nach Fusspunkt-Y: das weiter unten stehende liegt vorn.
func _furniture_under_mouse() -> Array:
	var mouse := get_global_mouse_position()
	var best: Array = []
	var best_y := -INF
	for entry in world.furniture_cells():
		var node: Furniture = entry[1]
		var tex := node.texture as AtlasTexture
		if tex == null:
			continue
		var size := tex.get_size()
		var rect := Rect2(node.global_position + node.offset * node.scale, size * node.scale)
		if not rect.has_point(mouse):
			continue
		var local := (mouse - rect.position) / node.scale
		# Gespiegeltes Moebel: die x-Koordinate im Bild kippt mit.
		if node.flip_h:
			local.x = size.x - 1.0 - local.x
		if _furn_alpha(tex, local) > 0.1 and node.global_position.y > best_y:
			best_y = node.global_position.y
			best = [entry[0], node]
	return best


## Deckkraft an einer Stelle im Moebel-Bild, in unskalierten Bildpixeln.
func _furn_alpha(tex: AtlasTexture, local: Vector2) -> float:
	if _furn_img == null:
		_furn_img = tex.atlas.get_image()
	var px := Vector2i(tex.region.position) + Vector2i(local.floor())
	if px.x < 0 or px.y < 0 or px.x >= _furn_img.get_width() or px.y >= _furn_img.get_height():
		return 0.0
	return _furn_img.get_pixelv(px).a


## Vorderstes Prop unter dem Mauszeiger, pixelgenau.
## Sortiert wie gezeichnet: erst Ebene, dann Bildschirm-Y - das oberste
## Ergebnis ist das, was der Spieler tatsächlich sieht.
func _prop_under_mouse() -> Array:
	var mouse := get_global_mouse_position()
	var hits: Array = []
	for entry in world.prop_placements():
		var pos := world.cell_to_world(entry[0], entry[1])
		if pos.distance_to(mouse) > hover_radius:
			continue
		var rect := world.prop_rect(entry[0], entry[1], entry[2], entry[3])
		if not rect.has_point(mouse):
			continue
		# Zurueck in Bildpixel rechnen: das Rechteck ist skaliert, das Bild
		# dahinter nicht.
		var sc := world.prop_scale(entry[0])
		var local := ((mouse - rect.position) / sc).floor()
		if world.prop_alpha_at(entry[0], Vector2i(local)) > 0.1:
			hits.append([entry, pos.y])
	if hits.is_empty():
		return []
	hits.sort_custom(func(a, b):
		if a[0][1] != b[0][1]:
			return a[0][1] > b[0][1]
		return a[1] > b[1])
	return hits[0][0]
