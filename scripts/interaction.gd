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
var _ground_hl: Line2D             ## Diamant-Umriss fuer den Boden-Hover (Buddeln)
var _hovered: Array = []           ## [cell, level, atlas] oder leer
var _furn_hover: Array = []        ## [cell, Furniture] oder leer
var _furn_imgs: Dictionary = {}    ## Moebel-Sheets je Atlas, einmal geladen (Alpha-Test)
var _hovered_crop = null           ## Crop-Node unter der Maus (oder null)
var _inv: Node = null              ## player_inventory (fuer Giesskannen-Ladungen)
var _interior: Node = null         ## Huetten-Innenraum (betreten/verlassen)

## Aufhelfen eines bewusstlosen Mitspielers (10 Sek halten in Reichweite).
const REVIVE_SECONDS := 10.0
const REVIVE_RANGE := 72.0         ## max. Abstand Helfer <-> Ziel (px)
var _revive_owner := 0             ## Peer-ID des Ziels (0 = keins)
var _revive_t := 0.0
var _revive_anchor := Vector2.ZERO ## Helfer-Position bei Start (Bewegung bricht ab)
var preview: PlacementPreview
var _struct_imgs: Dictionary = {}  ## Bauwerk-Bilder je Textur (Alpha-Test)
var _sel_outline: Sprite2D         ## Dauerhafter weisser Rand am ausgewaehlten Bauwerk
var _sel_structure: Node2D = null  ## Aktuell ausgewaehltes Bauwerk (Gruppe "structure")


func _ready() -> void:
	add_to_group("interaction")
	world = get_node(world_path) as IsoWorld
	player = get_tree().get_first_node_in_group("player")
	_build_highlight()
	preview = PlacementPreview.new()
	preview.world = world
	add_child(preview)
	_inv = get_node_or_null(^"../Inventory")
	_interior = get_node_or_null(^"../Interior")


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
	# Dauerhafter Auswahl-Rand (Rechtsklick auf ein Bauwerk). Eigener Sprite,
	# damit er bleibt, waehrend der Hover-Rand woanders hinwandert.
	var mat2 := ShaderMaterial.new()
	mat2.shader = preload("res://scripts/outline.gdshader")
	mat2.set_shader_parameter("outline_color", Color(1, 1, 1, 1))
	mat2.set_shader_parameter("thickness", 1.0)
	_sel_outline = Sprite2D.new()
	_sel_outline.material = mat2
	_sel_outline.centered = false
	_sel_outline.visible = false
	_sel_outline.z_index = IsoWorld.TALL_Z_INDEX + 1
	add_child(_sel_outline)
	# Boden-Hover (Buddeln): flacher Diamant-Umriss der Top-Flaeche, exakt am
	# Standpunkt (cell_to_world). Eigener Node, weil die Wuerfel-Textur des Blocks
	# keinen sauberen texture_origin hat und sonst um eine Ebene versetzt liegt.
	_ground_hl = Line2D.new()
	_ground_hl.top_level = true            # Punkte in Weltkoordinaten
	_ground_hl.width = 1.5
	_ground_hl.default_color = outline_color
	_ground_hl.closed = true
	_ground_hl.antialiased = false
	_ground_hl.z_index = IsoWorld.TALL_Z_INDEX + 1
	_ground_hl.visible = false
	add_child(_ground_hl)


func _process(_delta: float) -> void:
	_tick_revive(_delta)
	# Boden-Hover standardmaessig aus; nur _highlight_ground schaltet ihn ein.
	_ground_hl.visible = false
	# Waehrend des Platzierens kein Hover - sonst leuchten beide.
	if preview.active:
		highlight.visible = false
		_hovered = []
		_furn_hover = []
		_set_crop_hover(null)
		return
	# Pflanzen zuerst: zeigt Restzeit/Status ueber der Pflanze.
	_set_crop_hover(_crop_under_mouse())
	if _hovered_crop != null:
		_highlight_crop(_hovered_crop)
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
	# Bauwerk (mage_house etc., Gruppe "structure"): weisser Rand beim Ueberfahren.
	var st := _structure_under_mouse()
	if st != null:
		_highlight_structure(st)
		return
	# Fertige Baraka unter der Maus: weisser Rand - Zeichen, dass man
	# reingehen kann (Rechtsklick oeffnet den Innenraum).
	var bhit := world.pick_block(get_global_mouse_position())
	if not bhit.is_empty():
		var bnode = world.blocker_at(bhit[0])
		if bnode != null and bnode.has_method("is_done") and bnode.is_done():
			_highlight_structure(bnode)
			return
	# Ofen (Campfire) unter der Maus: weisser Rand wie bei Moebeln.
	var cfhit := world.pick_block(get_global_mouse_position())
	if not cfhit.is_empty() and world.blocker_at(cfhit[0]) is Campfire:
		_highlight_campfire(world.blocker_at(cfhit[0]))
		return
	# Bewusstloser Mitspieler unter der Maus: weisser Rand (Rechtsklick hilft auf).
	var doid := _downed_under_mouse()
	if doid != 0:
		var dav = _net_game().avatar_node(doid)
		if dav != null and dav.has_method("frame_texture"):
			_highlight_avatar(dav)
			return
	# Sonst: mit Schaufel/Dirt die Bodenzelle unter der Maus hervorheben,
	# damit man sieht, was man abbaut/aufschuettet.
	if player != null and (player.held_tool == "Showel" or player.held_is_dirt):
		_highlight_ground()
		return
	# Hacke: zeigt die Zelle, die zu Acker wird (gruen = geht). Samen: zeigt die
	# gehackte Zelle, auf die gepflanzt wird.
	if player != null and ItemDB.is_hoe(player.held_item_id):
		_highlight_farm_cell(true)
		return
	if player != null and ItemDB.is_seed(player.held_item_id):
		_highlight_farm_cell(false)
		return
	highlight.visible = false


## Diamant-Umriss der Zielzelle beim Hacken/Pflanzen. `till_mode`: hackbar?
## sonst pflanzbar (gehackt, frei). Gruen = geht, Rot = nicht.
func _highlight_farm_cell(till_mode: bool) -> void:
	highlight.visible = false
	var hit := world.pick_block(get_global_mouse_position())
	if hit.is_empty():
		return
	var cell: Vector2i = hit[0]
	var ok := world.can_till(cell) if till_mode else \
		(world.is_tilled(cell) and not world.has_crop(cell))
	_ground_hl.default_color = Color(0.45, 1.0, 0.45, 0.95) if ok else Color(1.0, 0.4, 0.4, 0.9)
	var c := world.cell_to_world(cell, int(hit[1]))
	_ground_hl.points = PackedVector2Array([
		c + Vector2(0, -8), c + Vector2(16, 0),
		c + Vector2(0, 8), c + Vector2(-16, 0)])
	_ground_hl.visible = true


## Diamant-Umriss der Top-Flaeche des Bodenblocks unter der Maus. Beim BUDDELN
## (Schaufel) die angeklickte Zelle. Beim AUFSCHUETTEN (Dirt) die Stelle, wo der
## neue Block LANDET: Top-Flaeche -> oben drauf; Seitenflaeche -> Nachbar davor
## (Wand bauen). So sieht man, ob man drauf oder daneben platziert.
func _highlight_ground() -> void:
	highlight.visible = false
	_ground_hl.default_color = outline_color   # nach Hacke/Samen (gruen/rot) zuruecksetzen
	var hit := world.pick_block(get_global_mouse_position())
	if hit.is_empty():
		return
	# Buddeln: die getroffene Zelle markieren. Aufschuetten: die Ebene DRUEBER
	# (dort landet der neue Block) - so sieht man vorab, ob es oben drauf oder
	# (bei Seiten-Hover, den pick_block auf die vordere Zelle aufloest) daneben landet.
	var mark_level := int(hit[1]) + (1 if player.held_is_dirt else 0)
	var c := world.cell_to_world(hit[0], mark_level)
	_ground_hl.points = PackedVector2Array([
		c + Vector2(0, -8), c + Vector2(16, 0),
		c + Vector2(0, 8), c + Vector2(-16, 0)])
	_ground_hl.visible = true


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


## Vorderste Pflanze unter der Maus - PIXELGENAU (Alpha), damit die Nachbarzellen
## frei anklickbar bleiben (sonst deckt das 32er-Rechteck die Nachbarn ab und man
## koennte nicht direkt daneben pflanzen).
func _crop_under_mouse():
	var mouse := get_global_mouse_position()
	var best = null
	var best_y := -INF
	for node in get_tree().get_nodes_in_group("crop"):
		var tex := node.texture as AtlasTexture
		if tex == null:
			continue
		var rect := Rect2(node.global_position + node.offset, tex.get_size())
		if not rect.has_point(mouse):
			continue
		var local := mouse - rect.position
		if _furn_alpha(tex, local) > 0.1 and node.global_position.y > best_y:
			best_y = node.global_position.y
			best = node
	return best


## Gegner (Magier) unter der Maus - ueber den Body-Sprite (48er), oder null.
func _mage_under_mouse():
	var mouse := get_global_mouse_position()
	var best = null
	var best_y := -INF
	for m in get_tree().get_nodes_in_group("mage"):
		if not is_instance_valid(m) or m._body == null or m._body.texture == null:
			continue
		var sz: Vector2 = m._body.texture.get_size()
		var rect := Rect2(m.global_position + m._body.offset, sz)
		if rect.has_point(mouse) and m.global_position.y > best_y:
			best_y = m.global_position.y
			best = m
	return best


## Setzt/loescht die Restzeit-Anzeige ueber der zuletzt ueberfahrenen Pflanze.
func _set_crop_hover(crop) -> void:
	if crop == _hovered_crop:
		return
	if _hovered_crop != null and is_instance_valid(_hovered_crop):
		_hovered_crop.set_hovered(false)
	_hovered_crop = crop
	if crop != null:
		crop.set_hovered(true)


func _highlight_crop(node) -> void:
	highlight.texture = node.texture
	highlight.scale = node.scale
	highlight.flip_h = false
	highlight.global_position = node.global_position + node.offset
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
		# Huetten: im Innenraum aufs Tuerfeld -> raus; draussen auf eine FERTIGE
		# Baraka -> rein. Hat Vorrang (Schwarzblende + Teleport in interior.gd).
		if _interior != null:
			var here := world.pick_block(get_global_mouse_position())
			if _interior.is_inside():
				if not here.is_empty() and here[0] == _interior.exit_world_cell():
					_interior.leave()
					get_viewport().set_input_as_handled()
					return
			elif not here.is_empty():
				var bn = world.blocker_at(here[0])
				if bn != null and bn.has_method("is_done") and bn.is_done():
					_interior.enter()
					get_viewport().set_input_as_handled()
					return
		# Bewusstlosen Mitspieler aufhelfen: Rechtsklick fragt erst nach.
		if _try_ask_revive():
			get_viewport().set_input_as_handled()
			return
		# Shift+Rechtsklick auf ein platziertes Objekt (Möbel/Lagerfeuer) reißt
		# es ab. Es kommt NICHT ins Inventar zurück.
		if event.shift_pressed:
			var target := _placed_under_mouse()
			if target != Player.INVALID_CELL:
				_ask_destroy(target)
			get_viewport().set_input_as_handled()
			return
		# Bauwerk (mage_house etc.) auswaehlen: weisser Rand bleibt stehen.
		# Ins Leere/auf etwas anderes geklickt -> Auswahl aufheben.
		var struct := _structure_under_mouse()
		if struct != null:
			_select_structure(struct)
			get_viewport().set_input_as_handled()
			return
		_select_structure(null)
		# Gegner (Magier) mit Messer/Schwert angreifen - hat Vorrang.
		if ItemDB.is_knife(player.held_item_id):
			var mage = _mage_under_mouse()
			if mage != null:
				player.attack_mage(mage, ItemDB.melee_damage(player.held_item_id))
				get_viewport().set_input_as_handled()
				return
		# Giesskanne: auf Pflanze giessen, auf Wasser auffuellen (vor dem Ernten,
		# damit man eine Pflanze mit der Kanne giesst statt sie zu ernten).
		if ItemDB.is_watering_can(player.held_item_id) and _inv != null:
			if _hovered_crop != null:
				_inv.try_water(_hovered_crop.cell)
				get_viewport().set_input_as_handled()
				return
			# Am Su Ficisi (Wasserfass) auffuellen.
			var f := _furniture_under_mouse()
			if not f.is_empty() and String((f[1] as Furniture).id) == "su_ficisi":
				_inv.try_fill(f[0])
				get_viewport().set_input_as_handled()
				return
		# Ackerbau: reife/tote Pflanze ernten (Vorrang vor allem anderen).
		if _hovered_crop != null:
			player.harvest(_hovered_crop.cell)
			get_viewport().set_input_as_handled()
			return
		if _hovered.is_empty():
			# Ofen (Campfire) anklicken -> hinlaufen und Ofen-Fenster oeffnen.
			var cf := world.pick_block(get_global_mouse_position())
			if not cf.is_empty() and world.blocker_at(cf[0]) is Campfire:
				player.walk_to_furnace(cf[0])
				return
			# Hacke: Boden zu Acker. Samen: auf gehackten Acker pflanzen.
			var g := world.pick_block(get_global_mouse_position())
			if not g.is_empty():
				var gc: Vector2i = g[0]
				if ItemDB.is_hoe(player.held_item_id):
					if player.till(gc):
						return
				elif ItemDB.is_seed(player.held_item_id) and world.is_tilled(gc) and not world.has_crop(gc):
					if player.plant(gc, ItemDB.crop_of_seed(player.held_item_id)):
						return
			# Kein Prop, aber vielleicht ein Moebel: hinlaufen (und wenn es
			# eine Station ist, oeffnet sie sich bei Ankunft von selbst).
			var furn := _furniture_under_mouse()
			if not furn.is_empty():
				# Bett: hineinlegen. Truhe/Schmelzofen: oeffnen. Sonst: Station.
				if not player.walk_to_bed(furn[0]):
					if String((furn[1] as Furniture).id) == "eritme_firini":
						player.walk_to_furnace(furn[0])
					elif not player.walk_to_chest(furn[0]):
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
		elif int(_hovered[3]) == IsoWorld.ROCK_SOURCE_ID:
			player.mine(_hovered[0])
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
var _confirm_yes := Callable()      ## was "Evet" ausloest (generisch)


## Fragt "Name yikilsin mi?" und reißt erst nach Bestätigung ab.
func _ask_destroy(cell: Vector2i) -> void:
	if _confirm == null:
		_build_confirm()
	_pending_destroy = cell
	_confirm_yes = _on_destroy_confirmed
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
	row.add_child(_confirm_button("Evet", _confirm_accept))
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
	_confirm_yes = Callable()
	if _confirm != null:
		_confirm.visible = false


## "Evet" gedrueckt: Dialog schliessen und die hinterlegte Aktion ausfuehren.
func _confirm_accept() -> void:
	var cb := _confirm_yes
	if _confirm != null:
		_confirm.visible = false
	if cb.is_valid():
		cb.call()


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


## --- Bauwerke (Gruppe "structure", z. B. mage_house) ---------------------

## Bildschirm-Rechteck eines Bauwerk-Sprites (beachtet centered/offset/scale).
func _structure_rect(n: Node2D) -> Rect2:
	var sp := n as Sprite2D
	var size: Vector2 = sp.texture.get_size()
	var tl: Vector2 = sp.global_position + sp.offset * sp.scale
	if sp.centered:
		tl -= size * sp.scale * 0.5
	return Rect2(tl, size * sp.scale)


## Deckkraft eines Bauwerk-Bildes an lokaler (unskalierter) Pixelstelle.
func _structure_alpha(tex: Texture2D, local: Vector2) -> float:
	if not _struct_imgs.has(tex):
		_struct_imgs[tex] = tex.get_image()
	var img: Image = _struct_imgs[tex]
	var px := Vector2i(local.floor())
	if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
		return 0.0
	return img.get_pixelv(px).a


## Bauwerk unter der Maus (pixelgenau, vorderstes zuerst).
func _structure_under_mouse() -> Node2D:
	var mouse := get_global_mouse_position()
	var best: Node2D = null
	var best_y := -INF
	for n in get_tree().get_nodes_in_group("structure"):
		var sp := n as Sprite2D
		if sp == null or sp.texture == null:
			continue
		var rect := _structure_rect(sp)
		if not rect.has_point(mouse):
			continue
		var local := (mouse - rect.position) / sp.scale
		if sp.flip_h:
			local.x = sp.texture.get_size().x - 1.0 - local.x
		if _structure_alpha(sp.texture, local) > 0.1 and sp.global_position.y > best_y:
			best_y = sp.global_position.y
			best = sp
	return best


func _highlight_structure(n: Node2D) -> void:
	var sp := n as Sprite2D
	highlight.region_enabled = false
	highlight.texture = sp.texture
	highlight.flip_h = sp.flip_h
	highlight.scale = sp.scale
	highlight.global_position = _structure_rect(sp).position
	highlight.visible = true


## Weisser Rand am Ofen (Campfire, AnimatedSprite2D) beim Ueberfahren.
func _highlight_campfire(n) -> void:
	var tex: Texture2D = null
	if n.sprite_frames != null and n.sprite_frames.has_animation(n.animation):
		tex = n.sprite_frames.get_frame_texture(n.animation, n.frame)
	if tex == null:
		highlight.visible = false
		return
	highlight.region_enabled = false
	highlight.texture = tex
	highlight.flip_h = false
	highlight.scale = n.scale
	highlight.global_position = n.global_position + n.offset * n.scale
	highlight.visible = true


func _select_structure(n: Node2D) -> void:
	_sel_structure = n
	if n == null:
		_sel_outline.visible = false
		return
	var sp := n as Sprite2D
	_sel_outline.region_enabled = false
	_sel_outline.texture = sp.texture
	_sel_outline.flip_h = sp.flip_h
	_sel_outline.scale = sp.scale
	_sel_outline.global_position = _structure_rect(sp).position
	_sel_outline.visible = true


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


# --- Aufhelfen eines bewusstlosen Mitspielers --------------------------

func _net_game() -> Node:
	return get_tree().get_first_node_in_group("net_game")


func _downed_sync() -> Node:
	return get_tree().get_first_node_in_group("downed_sync")


func _downed_hud() -> Node:
	return get_tree().get_first_node_in_group("downed_hud")


## Owner-ID des bewusstlosen Mitspielers unter der Maus (oder 0).
func _downed_under_mouse() -> int:
	var net := _net_game()
	var ds := _downed_sync()
	if net == null or ds == null or not net.has_method("avatar_owner_near"):
		return 0
	var oid: int = net.avatar_owner_near(get_global_mouse_position(), 42.0)
	if oid != 0 and ds.is_downed_owner(oid):
		return oid
	return 0


## Rechtsklick auf einen bewusstlosen Mitspieler -> Rueckfrage "aufhelfen?".
## Gibt true zurueck, wenn der Klick verbraucht wurde.
func _try_ask_revive() -> bool:
	var oid := _downed_under_mouse()
	if oid == 0 or player == null:
		return false
	var av = _net_game().avatar_node(oid)
	if av == null:
		return false
	if player.global_position.distance_to(av.global_position) > REVIVE_RANGE:
		if _inv != null and _inv.has_method("_notice"):
			_inv._notice("Once yaklas")
		return true
	_ask_revive(oid)
	return true


## Rueckfrage-Dialog fuers Aufhelfen (nutzt den generischen Confirm).
func _ask_revive(owner_id: int) -> void:
	if _confirm == null:
		_build_confirm()
	_confirm_yes = func(): _begin_revive(owner_id)
	_confirm_label.text = "Oyuncuyu kaldirmak istiyor musun?"
	_confirm.visible = true


## Aufhelfen-Kanal starten (nach Bestaetigung).
func _begin_revive(owner_id: int) -> void:
	if player == null:
		return
	_revive_owner = owner_id
	_revive_t = 0.0
	_revive_anchor = player.global_position
	var h := _downed_hud()
	if h != null and h.has_method("show_revive"):
		h.show_revive("arkadas")


## Weisser Rand um einen (bewusstlosen) Mitspieler-Avatar beim Ueberfahren.
func _highlight_avatar(av) -> void:
	var tex: Texture2D = av.frame_texture()
	if tex == null:
		highlight.visible = false
		return
	highlight.region_enabled = false
	highlight.texture = tex
	highlight.flip_h = av.sprite_flip()
	highlight.scale = Vector2.ONE
	# _sprite ist zentriert -> Oben-Links = Pos + Offset - halbe Texturgroesse.
	highlight.global_position = av.global_position + av.sprite_offset() - tex.get_size() * 0.5
	highlight.visible = true


## Laeuft der Aufhelfen-Kanal, Fortschritt zaehlen und Abbruchgruende pruefen.
func _tick_revive(delta: float) -> void:
	if _revive_owner == 0:
		return
	var net := _net_game()
	var ds := _downed_sync()
	if net == null or ds == null or player == null:
		_cancel_revive()
		return
	var av = net.avatar_node(_revive_owner)
	# Abbruch: Ziel weg/wach, Helfer bewegt sich, oder zu weit entfernt.
	if av == null or not ds.is_downed_owner(_revive_owner) \
			or player.global_position.distance_to(_revive_anchor) > 12.0 \
			or player.global_position.distance_to(av.global_position) > REVIVE_RANGE + 12.0:
		_cancel_revive()
		return
	_revive_t += delta
	var h := _downed_hud()
	if h != null and h.has_method("update_revive"):
		h.update_revive(_revive_t / REVIVE_SECONDS)
	if _revive_t >= REVIVE_SECONDS:
		if ds.has_method("request_revive"):
			ds.request_revive(_revive_owner)
		_cancel_revive()


func _cancel_revive() -> void:
	_revive_owner = 0
	_revive_t = 0.0
	var h := _downed_hud()
	if h != null and h.has_method("hide_revive"):
		h.hide_revive()
