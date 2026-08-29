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
var _furn_imgs: Dictionary = {}    ## Moebel-Sheets je Atlas, einmal geladen (Alpha-Test)
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
	if not _furn_hover.is_empty():
		_highlight_furniture(_furn_hover[1])
		return
	# Sonst: mit Schaufel/Dirt die Bodenzelle unter der Maus hervorheben,
	# damit man sieht, was man abbaut/aufschuettet.
	if player != null and (player.held_tool == "Showel" or player.held_is_dirt):
		_highlight_ground()
		return
	highlight.visible = false


## Weisser Rand um den obersten Bodenblock unter der Maus (Buddeln/Aufschuetten).
func _highlight_ground() -> void:
	var hit := world.pick_block(get_global_mouse_position())
	if hit.is_empty():
		highlight.visible = false
		return
	var tex := world.block_texture(hit[0])
	if tex == null:
		highlight.visible = false
		return
	highlight.texture = tex
	highlight.flip_h = false
	highlight.scale = Vector2.ONE
	highlight.global_position = world.block_top_left(hit[0])
	highlight.visible = true


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
	# Offene Abriss-Rückfrage: Esc bricht ab, sonst schluckt sie ohnehin die Klicks.
	if _confirm != null and _confirm.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_confirm()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and preview.active:
		if event.keycode == KEY_ESCAPE:
			preview.cancel()
			get_viewport().set_input_as_handled()
			return
		# R dreht das Moebel in der Vorschau (N/O/S/W).
		if event.keycode == KEY_R:
			preview.rotate_step()
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
			# Blanker Boden: Schaufel buddelt eine Ebene ab, ein Dirt-Block
			# schuettet eine Ebene auf (Terraforming). Sonst passiert nichts.
			var ground_hit := world.pick_block(get_global_mouse_position())
			if not ground_hit.is_empty():
				if player.held_tool == "Showel":
					player.dig(ground_hit[0])
				elif player.held_is_dirt:
					player.raise_ground(ground_hit[0])
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
## Selbst gebaut statt ConfirmationDialog: dessen Fenster ist zu groß und die
## Default-Schriftgröße verwäscht den Bitmap-Font (nur 11/22 px bleiben scharf).
const CONFIRM_FONT := 11
var _confirm: CanvasLayer
var _confirm_label: Label
var _pending_destroy := Vector2i(2147483647, 2147483647)


## Fragt "Name yikilsin mi?" und reißt erst nach Bestätigung ab.
func _ask_destroy(cell: Vector2i) -> void:
	if _confirm == null:
		_build_confirm()
	_pending_destroy = cell
	_confirm_label.text = "%s yikilsin mi?" % _placed_name(cell)
	_confirm.visible = true


func _build_confirm() -> void:
	_confirm = CanvasLayer.new()
	_confirm.layer = 120                 # über der Hotbar (110)
	add_child(_confirm)

	# Sperrfläche: dunkelt ab und schluckt Klicks dahinter.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.96)
	sb.border_color = Color(0.35, 0.37, 0.45, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	_confirm_label = Label.new()
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.add_theme_font_size_override("font_size", CONFIRM_FONT)
	col.add_child(_confirm_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(_confirm_button("Evet", _on_destroy_confirmed))
	row.add_child(_confirm_button("Hayir", _close_confirm))


func _confirm_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", CONFIRM_FONT)
	b.custom_minimum_size = Vector2(64, 0)
	b.pressed.connect(on_press)
	return b


func _close_confirm() -> void:
	_pending_destroy = Player.INVALID_CELL
	if _confirm != null:
		_confirm.visible = false


func _on_destroy_confirmed() -> void:
	if _pending_destroy != Player.INVALID_CELL:
		player.walk_to_destroy(_pending_destroy)
	_close_confirm()


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
	# Je Atlas ein eigenes Bild merken - seit den Richtungs-Tischen gibt es
	# mehrere Sheets, ein einzelner Cache wuerde die falsche Grafik testen.
	var atlas: Texture2D = tex.atlas
	if not _furn_imgs.has(atlas):
		_furn_imgs[atlas] = tex.atlas.get_image()
	var img: Image = _furn_imgs[atlas]
	var px := Vector2i(tex.region.position) + Vector2i(local.floor())
	if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
		return 0.0
	return img.get_pixelv(px).a


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
