extends Node2D

## Level-Designer (EIGENE Szene, NICHT im Spiel). Mit F6 starten.
##
## Links eine Palette mit Spiel-Assets (Boden/Moebel/Deko/Gebaeude/Pflanzen/
## Baeume), rechts ein Iso-Raster. Damit baust du eine Vorlage (z. B. das Magier-
## Gelaende) und speicherst sie als JSON. Ich lese die Datei und setze sie exakt
## ins Spiel um.
##
## Steuerung:
##   Palette anklicken -> Asset waehlen. Linksklick aufs Raster = setzen,
##   Rechtsklick = entfernen (erst Objekt, sonst Bodenkachel).
##   WASD/Pfeile = Kamera, Mausrad = Zoom.
##   S = speichern (user://mage_design.json), L = laden, C = alles loeschen.
##
## Boden nutzt das echte iso_tileset (Quelle 0). Objekte sind Sprites aus den
## Original-Sheets. Die Zeichen-Offsets sind nur eine Vorschau - beim Umsetzen ins
## Spiel nehme ich die exakten Spiel-Offsets; entscheidend sind Zelle + Asset-Id.

const TILESET := "res://tilesets/iso_tileset.tres"
const SHEET_GROUND := "res://assets/RPG-isometric-free.png"
const SHEET_FURN := "res://assets/props/basic furniture.png"
const SHEET_PLANTS := "res://assets/game_assets/items/plants_and_seeds.png"
const SHEET_TREES := "res://assets/props/baeume.png"
const SHEET_CAMP := "res://assets/props/camp.png"

## Boden-Atlas im iso_tileset (margins 2,0 / sep 2,0 / 32er).
const G_MX := 2
const G_SEP := 2
const G_CELL := 32

var _ground: TileMapLayer
var _objroot: Node2D
var _cam: Camera2D
var _sel := {}                    ## aktuell gewaehltes Palette-Item
var _sel_label: Label
var _objects := {}                ## "x,y" -> {"id": String, "node": Sprite2D}
var _hover: Sprite2D              ## Vorschau am Cursor

## --- Asset-Katalog ------------------------------------------------------
## Jeder Eintrag: {cat, id, kind, ...}. kind "ground": atlas=Vector2i (Quelle 0).
## kind "object": sheet, region:Rect2i, off:Vector2, scale:float.
var CATALOG: Array = []


func _ready() -> void:
	_build_catalog()
	RenderingServer.set_default_clear_color(Color(0.12, 0.13, 0.16))
	_ground = TileMapLayer.new()
	_ground.tile_set = load(TILESET)
	add_child(_ground)
	_objroot = Node2D.new()
	_objroot.y_sort_enabled = true
	add_child(_objroot)
	_hover = Sprite2D.new()
	_hover.modulate = Color(1, 1, 1, 0.55)
	_hover.z_index = 4000
	add_child(_hover)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(2, 2)
	add_child(_cam)
	_cam.make_current()
	_build_ui()
	queue_redraw()   # Iso-Gitter zeichnen (siehe _draw)


## Sichtbares Iso-Gitter (Rauten) ueber einen Bereich, damit man die Zellen auf
## leerem Grund sieht. Als _draw des Designer-Nodes (liegt HINTER Boden/Objekten,
## scheint also nur auf freien Zellen durch).
const GRID_RANGE := 26
func _draw() -> void:
	var line := Color(0.4, 0.55, 0.7, 0.5)
	for x in range(-GRID_RANGE, GRID_RANGE + 1):
		for y in range(-GRID_RANGE, GRID_RANGE + 1):
			var c: Vector2 = _ground.map_to_local(Vector2i(x, y))
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -8), c + Vector2(16, 0),
				c + Vector2(0, 8), c + Vector2(-16, 0), c + Vector2(0, -8)]),
				line, 1.0)


# --- Katalog ------------------------------------------------------------

func _g(cat: String, id: String, atlas: Vector2i) -> Dictionary:
	return {"cat": cat, "id": id, "kind": "ground", "atlas": atlas}


func _o(cat: String, id: String, sheet: String, region: Rect2i, off: Vector2, scl: float) -> Dictionary:
	return {"cat": cat, "id": id, "kind": "object", "sheet": sheet, "region": region, "off": off, "scale": scl}


func _fcell(id: String, c: int, r: int) -> Dictionary:
	# Basic-Furniture: 64er-Zellen. Vorschau-Offset foot-zentriert.
	return _o("Moebel", id, SHEET_FURN, Rect2i(c * 64, r * 64, 64, 64), Vector2(-32, -50), 0.7)


func _plant(id: String, c: int, r: int) -> Dictionary:
	return _o("Pflanzen", id, SHEET_PLANTS, Rect2i(c * 32, r * 32, 32, 32), Vector2(-16, -28), 1.0)


func _tree(id: String, c: int, r: int) -> Dictionary:
	return _o("Baeume", id, SHEET_TREES, Rect2i(c * 32, r * 32, 32, 32), Vector2(-24, -44), 1.6)


func _build_catalog() -> void:
	# Boden (Atlas-Koords wie im Spiel).
	for a in [["gras1", Vector2i(2,0)], ["gras2", Vector2i(2,1)], ["gras3", Vector2i(2,2)],
			["erde1", Vector2i(3,1)], ["erde2", Vector2i(3,2)], ["acker", Vector2i(3,3)],
			["stein1", Vector2i(3,0)], ["stein2", Vector2i(4,0)], ["stein3", Vector2i(5,0)],
			["wasser1", Vector2i(0,1)], ["wasser2", Vector2i(1,2)],
			["holz1", Vector2i(5,1)], ["holz2", Vector2i(6,1)]]:
		CATALOG.append(_g("Boden", a[0], a[1]))

	# Moebel (basic furniture.png, 6x3).
	var furn := [["planya_tezgahi",0,0],["sandik",1,0],["jenerator",2,0],["alet_standi",3,0],
		["tabaklama_sehpasi",4,0],["dolap",5,0],["calisma_tezgahi",0,1],["ocak",1,1],
		["ors",2,1],["dokuma_tezgahi",3,1],["eritme_firini",4,1],["yatak",5,1],
		["portatif_yatak",0,2],["simya_masasi",1,2],["su_ficisi",2,2],["tabure",3,2],
		["yukseltilmis_tarha",4,2]]
	for f in furn:
		CATALOG.append(_fcell(f[0], f[1], f[2]))

	# Gebaeude (eigene PNGs, 136er). Offset foot-zentriert.
	CATALOG.append(_o("Gebaeude", "mage_house", "res://assets/game_assets/enemies/mage_house.png", Rect2i(0,0,136,136), Vector2(-68,-104), 1.0))
	CATALOG.append(_o("Gebaeude", "baraka", "res://assets/game_assets/buildings/shelter_done_south.png", Rect2i(0,0,136,136), Vector2(-68,-104), 1.0))
	CATALOG.append(_o("Gebaeude", "baraka_geruest", "res://assets/game_assets/buildings/shelter_scaffold_south.png", Rect2i(0,0,136,136), Vector2(-68,-104), 1.0))

	# Deko: Lagerfeuer.
	CATALOG.append(_o("Deko", "kamp_atesi", SHEET_CAMP, Rect2i(128,0,128,128), Vector2(-40,-70), 0.55))
	# Magier (Vorschau).
	CATALOG.append(_o("Deko", "mage", "res://assets/game_assets/enemies/mage/idle_south.png", Rect2i(0,0,48,48), Vector2(-24,-42), 1.0))

	# Pflanzen/Deko aus plants_and_seeds (reife/dekorative).
	for p in [["misir",5,3],["havuc",6,3],["domates",8,2],["kabak",9,3],["bugday",4,3]]:
		CATALOG.append(_plant(p[0], p[1], p[2]))

	# Baeume (baeume.png, 6x3).
	for r in range(3):
		for c in range(6):
			CATALOG.append(_tree("baum_%d_%d" % [c, r], c, r))


# --- Boden-Thumbnail ----------------------------------------------------

func _thumb(entry: Dictionary) -> Texture2D:
	var t := AtlasTexture.new()
	if entry["kind"] == "ground":
		t.atlas = load(SHEET_GROUND)
		var a: Vector2i = entry["atlas"]
		t.region = Rect2(G_MX + a.x * (G_CELL + G_SEP), a.y * G_CELL, G_CELL, G_CELL)
	else:
		t.atlas = load(entry["sheet"])
		t.region = Rect2(entry["region"])
	t.filter_clip = true
	return t


# --- UI (Palette) -------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size = Vector2(240, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.96)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Level-Designer"
	title.add_theme_font_size_override("font_size", 18)
	col.add_child(title)
	var help := Label.new()
	help.text = "Links=setzen  Rechts=weg\nPfeiltasten=Kamera  Rad=Zoom\nS=Speichern  L=Laden  C=Leeren"
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	col.add_child(help)
	_sel_label = Label.new()
	_sel_label.text = "Gewaehlt: (nichts)"
	_sel_label.add_theme_font_size_override("font_size", 12)
	_sel_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	col.add_child(_sel_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	# Nach Kategorie gruppieren.
	var cats: Array = []
	for e in CATALOG:
		if not cats.has(e["cat"]):
			cats.append(e["cat"])
	for cat in cats:
		var head := Label.new()
		head.text = cat
		head.add_theme_font_size_override("font_size", 13)
		head.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		inner.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		inner.add_child(grid)
		for e in CATALOG:
			if e["cat"] != cat:
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(40, 40)
			b.icon = _thumb(e)
			b.expand_icon = true
			b.tooltip_text = e["id"]
			b.pressed.connect(_select.bind(e))
			grid.add_child(b)


func _select(entry: Dictionary) -> void:
	_sel = entry
	_sel_label.text = "Gewaehlt: %s" % entry["id"]
	if entry["kind"] == "object":
		_hover.texture = _thumb(entry)
		_hover.centered = false
		_hover.offset = entry["off"]
		_hover.scale = Vector2(entry["scale"], entry["scale"])
		_hover.visible = true
	else:
		_hover.visible = false


# --- Platzieren / Entfernen --------------------------------------------

func _cell_at_mouse() -> Vector2i:
	return _ground.local_to_map(_ground.to_local(get_global_mouse_position()))


func _place(cell: Vector2i) -> void:
	if _sel.is_empty():
		return
	if _sel["kind"] == "ground":
		_ground.set_cell(cell, 0, _sel["atlas"])
		return
	# Objekt: vorhandenes an der Zelle ersetzen.
	_erase_object(cell)
	var s := Sprite2D.new()
	s.texture = _thumb(_sel)
	s.centered = false
	s.offset = _sel["off"]
	s.scale = Vector2(_sel["scale"], _sel["scale"])
	s.position = _ground.map_to_local(cell)
	_objroot.add_child(s)
	_objects["%d,%d" % [cell.x, cell.y]] = {"id": _sel["id"], "node": s}


func _erase_object(cell: Vector2i) -> bool:
	var key := "%d,%d" % [cell.x, cell.y]
	if _objects.has(key):
		_objects[key]["node"].queue_free()
		_objects.erase(key)
		return true
	return false


func _erase(cell: Vector2i) -> void:
	if not _erase_object(cell):
		_ground.erase_cell(cell)


# --- Eingabe ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place(_cell_at_mouse())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_erase(_cell_at_mouse())
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.zoom *= 1.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.zoom *= 0.9
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_place(_cell_at_mouse())   # ziehen zum Malen
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S:
			_save()
		elif event.keycode == KEY_L:
			_load()
		elif event.keycode == KEY_C:
			_clear()


func _process(delta: float) -> void:
	# Kamera nur mit Pfeiltasten (S/L/C bleiben fuer Speichern/Laden/Leeren frei).
	var v := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	_cam.position += v * 400.0 * delta / _cam.zoom.x
	if _hover.visible and not _sel.is_empty():
		_hover.position = _ground.map_to_local(_cell_at_mouse())


# --- Speichern / Laden --------------------------------------------------

const SAVE_PATH := "user://mage_design.json"

func _save() -> void:
	var data := {"ground": [], "objects": []}
	for cell in _ground.get_used_cells():
		var a := _ground.get_cell_atlas_coords(cell)
		data["ground"].append({"cell": [cell.x, cell.y], "atlas": [a.x, a.y]})
	for key in _objects:
		var parts: PackedStringArray = key.split(",")
		data["objects"].append({"cell": [int(parts[0]), int(parts[1])], "id": _objects[key]["id"]})
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("GESPEICHERT: %s  (%d Boden, %d Objekte)" % [ProjectSettings.globalize_path(SAVE_PATH), data["ground"].size(), data["objects"].size()])
	_flash("Gespeichert: %s" % ProjectSettings.globalize_path(SAVE_PATH))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_flash("Keine Datei zum Laden")
		return
	_clear()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for g in data.get("ground", []):
		_ground.set_cell(Vector2i(int(g["cell"][0]), int(g["cell"][1])), 0, Vector2i(int(g["atlas"][0]), int(g["atlas"][1])))
	for o in data.get("objects", []):
		var e := _find(String(o["id"]))
		if not e.is_empty():
			var save_sel := _sel
			_sel = e
			_place(Vector2i(int(o["cell"][0]), int(o["cell"][1])))
			_sel = save_sel
	_flash("Geladen")


func _find(id: String) -> Dictionary:
	for e in CATALOG:
		if e["id"] == id:
			return e
	return {}


func _clear() -> void:
	_ground.clear()
	for key in _objects:
		_objects[key]["node"].queue_free()
	_objects.clear()


var _flash_label: Label
func _flash(msg: String) -> void:
	if _flash_label == null:
		var cl := CanvasLayer.new()
		add_child(cl)
		_flash_label = Label.new()
		_flash_label.position = Vector2(250, 12)
		_flash_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
		cl.add_child(_flash_label)
	_flash_label.text = msg
