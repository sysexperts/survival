extends CanvasLayer
class_name InventoryHUD

## Hotbar unten, Tasche (Buch) auf Tastendruck.
##
## SEIT DEM SZENEN-UMBAU: Der Aufbau steht in scenes/inventory_hud.tscn als
## editierbare Knoten (Buchbild, Kopfzeilen, Stat-Icons, die 4x5-Tasche und die
## Hotbar) - so laesst sich das Layout im Godot-Editor mit der Maus schieben.
## setup() bindet die Knoten (_bind) und haengt die dynamischen Teile an, die
## sich schlecht klicken lassen: +/- Buttons, Tabs/Lesezeichen, Scrollleiste,
## Punkte-Anzeige. Die Logik (Fenster-Scrolling, Drag & Drop, Stat-Vergabe)
## ist unveraendert.

const UiAtlas := preload("res://scripts/ui_atlas.gd")
const CharStats := preload("res://scripts/char_stats.gd")
const SkillsXP := preload("res://scripts/skills_xp.gd")
const RecipeDB := preload("res://scripts/recipe_db.gd")

## Buch-Hintergruende je Seite.
const BOOK_IMG := "res://assets/UI/Cute_Fantasy_UI/UI/inventar1.png"
const CRAFT_IMG := "res://assets/UI/Cute_Fantasy_UI/UI/basic_craft.png"

## Referenzen für die verstellbaren Stats (linke Buchseite).
var _stat_value_labels: Dictionary = {}
## Alle +/- Buttons (zum Ausblenden, sobald keine Punkte mehr uebrig sind).
var _stat_buttons: Array[Button] = []
var _points_label: Label = null

const SLOT := 46
const PAD := 4

## --- Buch-Layout ---
## Alle Knoten liegen in der Szene bereits x3 skaliert (Buchbild 230x138 -> 690x414).
const BOOK_SCALE := 3
## ENVANTER-Vertiefung (rechte Seite) - Ankerbereich der Scrollleiste (Quell-px).
const WELL := Rect2i(120, 30, 100, 98)
## Das gezeichnete Raster ist 4 Spalten x 5 Reihen sichtbar.
const VIEW_COLS := 4
const VIEW_ROWS := 5
## STATS (links): y-Mitte der 4 Zeilen (Quell-px) - fuer die +/- Buttons.
const ICON_BOX := [Vector2(21, 20.5), Vector2(21, 33.5), Vector2(21, 46.5), Vector2(21, 59.5)]
## +/- Buttons je Zeile (Quell-x) und Punkte-Anzeige (Quell-Mitte).
const MINUS_X := 90
const PLUS_X := 99
const POINTS_CENTER := Vector2(58, 116)
## Rastergroesse des Pixel-Fonts (kleiner Begleittext).
const INFO_FONT := 11

## Pack-Grafiken für Tabs/Lesezeichen (aus Book_UI) und Icons (aus UI_Icons).
const TAB_BG := Rect2i(590, 78, 20, 18)          ## tan Top-Tab (inaktiv)
const TAB_BG_ACTIVE := Rect2i(623, 76, 20, 21)   ## laengerer Reiter (aktiv, ragt oben raus)
const TAB_SCALE := 3
const RIBBON_BG := [                               ## farbige Lesezeichen (rechts)
	Rect2i(750, 79, 28, 18),   # rot
	Rect2i(798, 79, 28, 18),   # blau
	Rect2i(846, 79, 28, 18),   # grün
	Rect2i(894, 79, 28, 18),   # gelb
	Rect2i(990, 79, 28, 18),   # braun
]
## Obere Reiter: [Icon-Zelle, Name]. Rucksack / Basic Crafts / Einstellungen.
const TOP_TABS := [
	[Vector2i(9, 2), "Rucksack"],       # Rucksack-Icon
	[Vector2i(3, 1), "Basic Crafts"],   # Schraubenschlüssel
	[Vector2i(2, 1), "Einstellungen"],  # Zahnrad
]
const RIBBON_ICONS := [Vector2i(14, 1), Vector2i(0, 1), Vector2i(8, 1), Vector2i(3, 0), Vector2i(9, 2)]  # Mail/Chat/Gift/Star/Bag

var inventory: Inventory
var selected := 0

## DropSync (im Multiplayer) - fuer "aus dem Inventar in die Welt werfen".
var drop_sync: Node
## Welches Feld gerade gezogen wird (fuer das Fallenlassen ausserhalb).
var drag_from := -1

var _slot_nodes: Array[InventorySlot] = []
## Die sichtbaren Taschen-Ansichten (Fenster-Scrolling) + aktueller Zeilen-Offset.
var _bag_views: Array[InventorySlot] = []
var _bag_offset := 0
var _bag_scroll: VScrollBar = null
var _bag: Control
var _dim: ColorRect
var _bar: HBoxContainer
var _name_label: Label
var _hint_label: Label

## Itemleisten-Extras: EXP-Leiste (links/rechts) + Level-Stern.
var _exp_left: TextureProgressBar
var _exp_right: TextureProgressBar
var _level_label: Label
var _level_star: TextureRect
## Level, bei dem die EXP-Leiste zuletzt gezeichnet wurde (Poll-Vergleich).
var _last_level := -1
var _poll := 0.0
## Laeuft, waehrend sich die EXP-Leiste animiert fuellt.
var _exp_tween: Tween = null

## Buch-Reiter (oben) und Seiten.
var _tab_bgs: Array[TextureRect] = []      ## Hintergrund je Reiter (fuer aktiv/inaktiv)
var _active_tab := 0
var _page_rucksack: Control = null         ## Rucksack-Seite (Container, ein Auge im Editor)
var _page_craft: Control = null            ## Basic-Crafts-Seite
var _page_settings: Control = null         ## Einstellungen-Seite (Platzhalter)
var _book_bg: TextureRect = null           ## Buch-Hintergrund (wechselt je Seite)

## Grundhandwerk auf der Basic-Crafts-Seite (Layout kommt aus der Szene,
## das Script fuellt nur Icons/Liste).
var craft_queue: CraftQueue = null
var _craft_selected: Dictionary = {}       ## aktuell gewaehltes Rezept
var _rows: Control = null                   ## Rezeptzeilen (Szenen-Knoten, im Editor anpassbar)
var _in0: TextureRect = null               ## Zutat 1 (obere Box)
var _in1: TextureRect = null               ## Zutat 2 (untere Box)
var _out: TextureRect = null               ## Ergebnis (grosse Box, erst nach dem Bauen)
var _craft_btn: Button = null
var _craft_progress: ProgressBar = null    ## zeigt, wie lange das Bauen noch dauert
var _craft_pending := ""                   ## Ergebnis-Id, das nach dem Bauen erscheinen soll


func setup(p_inventory: Inventory) -> void:
	inventory = p_inventory
	inventory.changed.connect(_refresh)
	_bind()
	# Tasche startet zu. Die Sichtbarkeit steuert das Skript (nicht die Szene),
	# damit das Buch im Editor sichtbar/editierbar bleibt.
	_bag.visible = false
	_dim.visible = false
	_refresh()


# --- Bindung der Szenen-Knoten -----------------------------------------

func _bind() -> void:
	# Hotbar-Felder (aus der Szene) mit Index/Logik versehen.
	_bar = $Root/Hotbar
	_slot_nodes.clear()
	var i := 0
	for slot in _bar.get_children():
		if slot is InventorySlot:
			_init_slot(slot, i, true)
			_slot_nodes.append(slot)
			i += 1

	_dim = $Root/Dim
	_name_label = $Root/NameLabel
	_hint_label = $Root/HintLabel
	_bag = $Root/Center/Book
	_book_bg = _bag.get_node("BookBg")
	_page_rucksack = _bag.get_node("RucksackPage")

	# Taschen-Felder (4x5) - transparent, Index wird beim Scrollen gesetzt.
	_bag_views.clear()
	for v in _page_rucksack.get_node("BagGrid").get_children():
		if v is InventorySlot:
			_init_slot(v, -1, false)
			_bag_views.append(v)

	# Kopfzeilen (İstatik/Envanter) - Schrift ebenfalls im Editor einstellbar,
	# darum hier keine Font-Overrides mehr.
	_wire_left_page()
	_wire_right_page()
	# Klickbare Reiter oben + Seiten-Umschaltung (Rucksack/Basic Crafts/Ayarlar).
	_build_tabs(_bag, int(_bag.custom_minimum_size.x))
	_setup_pages()
	_select_tab(0)

	# Itemleisten-Extras (EXP-Leiste + Stern).
	_exp_left = $Root/LevelBar/ExpLeft
	_exp_right = $Root/LevelBar/ExpRight
	_level_star = $Root/LevelBar/LevelStar
	_level_label = _level_star.get_node("LevelLabel")
	_start_shimmer()

	# Hotbar + LevelBar in der Zeichenreihenfolge nach oben - sonst laegen sie
	# unter der Sperrflaeche (Dim) und man koennte bei offener Tasche nichts
	# hineinziehen bzw. die EXP-Leiste waere verdeckt.
	$Root.move_child($Root/LevelBar, -1)
	$Root.move_child(_bar, -1)
	_refresh_stats()
	_refresh_level()
	set_process(true)


## Versieht ein Szenen-Slotfeld mit Index, Stil, Hover und Klick-Logik. Die
## inneren Knoten (Icon/Count/DurBg) bringt die Slot-Szene bereits mit.
func _init_slot(panel: InventorySlot, index: int, boxed: bool) -> void:
	panel.hud = self
	panel.index = index
	var sz: float = panel.custom_minimum_size.x
	if boxed:
		panel.add_theme_stylebox_override("panel", _style(false))
	else:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Aktuellen Index zur Ereigniszeit lesen (Fenster-Scrolling ändert ihn).
	panel.gui_input.connect(func(e): _on_slot_input(e, panel.index))
	panel.pivot_offset = Vector2(sz, sz) * 0.5
	panel.mouse_entered.connect(func():
		panel.modulate = Color(1.22, 1.22, 1.22)
		panel.scale = Vector2(1.07, 1.07)
		panel.z_index = 1)
	panel.mouse_exited.connect(func():
		panel.modulate = Color(1, 1, 1)
		panel.scale = Vector2.ONE
		panel.z_index = 0)


## Linke Seite: Kopfzeile/Werte formatieren (Knoten aus der Szene) und die
## +/- Buttons sowie die Punkte-Anzeige anhaengen.
func _wire_left_page() -> void:
	for i in range(CharStats.ORDER.size()):
		if i >= ICON_BOX.size():
			break
		var key := String(CharStats.ORDER[i])
		var lbl: Label = _page_rucksack.get_node("StatValue%d" % i)
		# Schrift/Groesse/Farbe NICHT mehr im Code setzen - so laesst sich die
		# Textart der Stat-Werte im Editor (Inspector -> Theme Overrides) aendern.
		_stat_value_labels[key] = lbl
		# +/- Buttons liegen jetzt als Knoten in der Szene (im Editor schiebbar) -
		# hier nur noch die Aktion verdrahten und fuer das spaetere Ausblenden merken.
		var plus: Button = _page_rucksack.get_node("Plus%d" % i)
		var minus: Button = _page_rucksack.get_node("Minus%d" % i)
		plus.pressed.connect(_on_stat.bind(key, 1))
		minus.pressed.connect(_on_stat.bind(key, -1))
		_stat_buttons.append(plus)
		_stat_buttons.append(minus)

	# Restpunkte-Anzeige (unterer Balken).
	_points_label = Label.new()
	_points_label.add_theme_font_override("font", UiAtlas.font())
	_points_label.add_theme_font_size_override("font_size", 14)
	_points_label.add_theme_color_override("font_color", Color("2a1a10"))
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_points_label.size = Vector2(200, 24)
	_points_label.position = POINTS_CENTER * BOOK_SCALE - Vector2(100, 12)
	_points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_rucksack.add_child(_points_label)


## Rechte Seite: Scrollleiste anhaengen, wenn es mehr Taschen-Reihen als
## sichtbare gibt, dann das Fenster einmal anwenden.
func _wire_right_page() -> void:
	var bag_count := inventory.slots.size() - inventory.hotbar_size
	var total_rows := int(ceil(float(bag_count) / VIEW_COLS))
	if total_rows > VIEW_ROWS:
		var bar := VScrollBar.new()
		bar.min_value = 0
		bar.max_value = total_rows - VIEW_ROWS
		bar.step = 1
		bar.page = 1
		bar.position = Vector2((WELL.position.x + WELL.size.x - 1) * BOOK_SCALE, WELL.position.y * BOOK_SCALE)
		bar.custom_minimum_size = Vector2(12, WELL.size.y * BOOK_SCALE)
		bar.size = Vector2(12, WELL.size.y * BOOK_SCALE)
		bar.value_changed.connect(func(val): _bag_offset = int(val); _apply_window())
		_page_rucksack.add_child(bar)
		_bag_scroll = bar
	_apply_window()


# --- Stil-Bausteine -----------------------------------------------------

func _style(bright: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.82)
	sb.border_color = Color(0.95, 0.85, 0.55, 0.95) if bright else Color(0.35, 0.37, 0.45, 0.9)
	sb.set_border_width_all(2 if bright else 1)
	sb.set_corner_radius_all(3)
	return sb


## Brauner Slot-Stil fürs Buch (Pack-Look).
func _book_slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("8a5a3c")
	sb.border_color = Color("5a3826")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


## Passenden Slot-Stil je Index: Hotbar dunkel (ausgewaehlt heller), Tasche leer.
func _slot_style(i: int) -> StyleBox:
	if i >= inventory.hotbar_size or i < 0:
		return StyleBoxEmpty.new()
	return _style(i == selected)


# --- Tabs/Lesezeichen (Code, an das Buch gehaengt) ----------------------

## Klickbare Icon-Reiter oben. Der aktive nutzt das laengere Bookmark-Asset und
## ragt oben raus; ein Klick schaltet die Seite um (_select_tab).
func _build_tabs(book: Control, book_w: int) -> void:
	_tab_bgs.clear()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	# Ueber dem Buch; Zeilenhoehe = aktive (hoehere) Variante, damit alle sitzen.
	# +16 px nach unten, damit die Reiter buendig am Buch sitzen (kleiner Ueber-
	# lapp wie eingesteckte Lesezeichen) statt darueber zu schweben.
	tabs.position = Vector2(18 * BOOK_SCALE, -21 * TAB_SCALE + 16)
	book.add_child(tabs)
	for i in TOP_TABS.size():
		tabs.add_child(_make_tab(TOP_TABS[i][0], String(TOP_TABS[i][1]), i))


## Ein anklickbarer Reiter: Hintergrund (aktiv/inaktiv) + zentriertes Icon.
func _make_tab(icon_cell: Vector2i, tip: String, index: int) -> Control:
	var tab := Control.new()
	tab.custom_minimum_size = Vector2(20 * TAB_SCALE, 21 * TAB_SCALE)
	tab.tooltip_text = tip
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select_tab(index))
	var bg := TextureRect.new()
	bg.name = "Bg"
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(bg)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = UiAtlas.cell("icons", icon_cell.x, icon_cell.y)
	icon.size = Vector2(32, 32)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(icon)
	_tab_bgs.append(bg)
	return tab


## Reiter-Optik setzen: aktiv = laengeres Bookmark (ragt oben raus), inaktiv =
## kuerzeres, unten buendig. Icon jeweils in der sichtbaren Flaeche zentrieren.
func _update_tab_visual(bg: TextureRect, active: bool) -> void:
	var icon: TextureRect = bg.get_parent().get_node("Icon")
	if active:
		bg.texture = UiAtlas.tex("book", TAB_BG_ACTIVE)
		bg.size = Vector2(20 * TAB_SCALE, 21 * TAB_SCALE)
		bg.position = Vector2.ZERO
	else:
		bg.texture = UiAtlas.tex("book", TAB_BG)
		bg.size = Vector2(20 * TAB_SCALE, 18 * TAB_SCALE)
		bg.position = Vector2(0, 3 * TAB_SCALE)
	icon.position = Vector2((bg.size.x - icon.size.x) * 0.5,
		bg.position.y + (bg.size.y - icon.size.y) * 0.5)


## Die Seiten sind jetzt je EIN Container (im Editor ein Auge-Klick pro Seite):
## RucksackPage + CraftPage liegen in der Szene, Ayarlar ist ein Platzhalter.
func _setup_pages() -> void:
	_page_craft = _bag.get_node("CraftPage")
	_page_settings = _placeholder_page("Ayarlar")


## Leere Seite mit Titel (bis die echten Grafiken kommen).
func _placeholder_page(title: String) -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.visible = false
	_bag.add_child(page)
	var lbl := Label.new()
	lbl.text = "%s — yakında" % title
	lbl.add_theme_font_override("font", UiAtlas.font())
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color("4a2f1c"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(lbl)
	return page


## Reiter/Seite wechseln.
func _select_tab(index: int) -> void:
	_active_tab = index
	# Buch-Hintergrund je Seite (Basic Crafts hat ein eigenes Bild).
	if _book_bg:
		_book_bg.texture = load(CRAFT_IMG) if index == 1 else load(BOOK_IMG)
	if _page_rucksack:
		_page_rucksack.visible = index == 0
	if _page_craft:
		_page_craft.visible = index == 1
	if _page_settings:
		_page_settings.visible = index == 2
	for t in range(_tab_bgs.size()):
		_update_tab_visual(_tab_bgs[t], t == index)


# --- Basic Crafts (Grundhandwerk im Buch, loest die C-Taste ab) ---------

## Verdrahtet die Basic-Crafts-Knoten aus der Szene (CraftPage). Das Layout
## (Boxen/Liste/Yap) liegt in der Szene und ist im Editor schiebbar - hier wird
## nur die Liste gefuellt und die Icons gesetzt.
func attach_crafting(q: CraftQueue) -> void:
	craft_queue = q
	_in0 = _page_craft.get_node("Input0")
	_in1 = _page_craft.get_node("Input1")
	_out = _page_craft.get_node("Output")
	_craft_btn = _page_craft.get_node("CraftBtn")
	_craft_progress = _page_craft.get_node_or_null("CraftProgress")
	_rows = _page_craft.get_node("Rows")
	if not _craft_btn.pressed.is_connected(_on_craft_pressed):
		_craft_btn.pressed.connect(_on_craft_pressed)
	_add_hover(_craft_btn)
	if craft_queue and not craft_queue.changed.is_connected(_on_craft_queue):
		craft_queue.changed.connect(_on_craft_queue)
	# Jede (Szenen-)Zeile einmal verdrahten + Hover; welches Rezept sie zeigt,
	# kommt aus den Metadaten und wird in _fill_craft_list gesetzt.
	for row in _rows.get_children():
		if row is Button and not row.pressed.is_connected(_on_row_pressed):
			row.pressed.connect(_on_row_pressed.bind(row))
			_add_hover(row)
	if _craft_progress:
		_craft_progress.visible = false
	_fill_craft_list()
	_show_recipe({})


## Sanfter Hover: aufhellen + leicht vergroessern. Nur Verhalten (kein Layout).
func _add_hover(c: Control) -> void:
	c.mouse_entered.connect(func():
		c.pivot_offset = c.size * 0.5
		c.modulate = Color(1.18, 1.18, 1.18)
		c.scale = Vector2(1.04, 1.04))
	c.mouse_exited.connect(func():
		c.modulate = Color(1, 1, 1)
		c.scale = Vector2.ONE)


## Oeffnet das Buch direkt auf der Basic-Crafts-Seite (fuer die C-Taste).
func open_craft_page() -> void:
	if not bag_open():
		toggle_bag()
	_select_tab(1)


## Setzt in jede vorhandene Szenen-Zeile (CraftRow0..N) ein Rezept: Name + Icon.
## Ueberzaehlige Zeilen werden ausgeblendet. Das Layout der Zeilen (Position,
## Groesse von Zeile/Icon/Name) machst du komplett im Editor.
func _fill_craft_list() -> void:
	var recipes: Array = []
	for r in RecipeDB.RECIPES:
		if String(r.get("station", "")) == RecipeDB.HAND:
			recipes.append(r)
	var rows := _rows.get_children()
	for i in rows.size():
		var row: Control = rows[i]
		if i < recipes.size():
			row.visible = true
			row.set_meta("recipe", recipes[i])
			(row.get_node("Icon") as TextureRect).texture = ItemDB.icon(recipes[i]["out"])
			(row.get_node("Name") as Label).text = ItemDB.display_name(recipes[i]["out"])
		else:
			row.visible = false


## Klick auf eine Rezeptzeile -> zugehoeriges Rezept anzeigen.
func _on_row_pressed(row: Control) -> void:
	if row.has_meta("recipe"):
		_show_recipe(row.get_meta("recipe"))


## Zeigt ein Rezept: die zwei Zutaten in die Eingabe-Boxen; die Ergebnis-Box
## bleibt leer, bis wirklich gebaut wurde. Leeres Rezept leert alles.
func _show_recipe(recipe: Dictionary) -> void:
	_craft_selected = recipe
	_craft_pending = ""
	_out.texture = null
	(_out.get_node("Count") as Label).text = ""
	if recipe.is_empty():
		_in0.texture = null
		_in1.texture = null
		_ing_count(_in0, [], {}, 0)
		_ing_count(_in1, [], {}, 1)
		_craft_btn.disabled = true
		return
	var cost: Dictionary = recipe.get("cost", {})
	var ings: Array = cost.keys()
	_in0.texture = ItemDB.icon(String(ings[0])) if ings.size() > 0 else null
	_in1.texture = ItemDB.icon(String(ings[1])) if ings.size() > 1 else null
	_ing_count(_in0, ings, cost, 0)
	_ing_count(_in1, ings, cost, 1)
	# Ergebnis-Menge (wie viel man rausbekommt).
	(_out.get_node("Count") as Label).text = "x%d" % int(recipe.get("count", 1))
	_craft_btn.disabled = not _can_afford(recipe)


## Setzt die benoetigte Menge unter eine Zutat-Box (rot, wenn man zu wenig hat).
func _ing_count(box: TextureRect, ings: Array, cost: Dictionary, idx: int) -> void:
	var lbl: Label = box.get_node("Count")
	if idx >= ings.size():
		lbl.text = ""
		return
	var ing := String(ings[idx])
	var need := int(cost[ing])
	var have := inventory.count_of(ing)
	lbl.text = "x%d" % need
	lbl.add_theme_color_override("font_color", Color("b03030") if have < need else Color(0.23, 0.16, 0.1))


func _can_afford(recipe: Dictionary) -> bool:
	var cost: Dictionary = recipe.get("cost", {})
	for ing in cost:
		if inventory.count_of(String(ing)) < int(cost[ing]):
			return false
	return true


func _on_craft_pressed() -> void:
	if craft_queue == null or _craft_selected.is_empty() or not _can_afford(_craft_selected):
		return
	craft_queue.enqueue(_craft_selected, 1)
	_craft_pending = String(_craft_selected["out"])


## Nach jeder Queue-Aenderung: Knopf-Status; das Ergebnis erscheint in der
## grossen Box erst, wenn nichts mehr in Arbeit ist (also fertig gebaut).
func _on_craft_queue() -> void:
	if not _craft_selected.is_empty():
		_craft_btn.disabled = not _can_afford(_craft_selected)
	if _craft_pending != "" and not craft_queue.is_busy():
		_out.texture = ItemDB.icon(_craft_pending)
		_craft_pending = ""


## Ein Tab/Lesezeichen: Pack-Hintergrund + zentriertes Icon.
func _icon_tab(bg_region: Rect2i, icon_cell: Vector2i, bg_scale: int, icon_scale: int) -> Control:
	var tab := Control.new()
	tab.custom_minimum_size = Vector2(bg_region.size * bg_scale)
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	bg.texture = UiAtlas.tex("book", bg_region)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(bg)
	var icon := TextureRect.new()
	icon.texture = UiAtlas.cell("icons", icon_cell.x, icon_cell.y)
	icon.custom_minimum_size = Vector2(16 * icon_scale, 16 * icon_scale)
	icon.size = Vector2(16 * icon_scale, 16 * icon_scale)
	icon.position = (tab.custom_minimum_size - icon.size) * 0.5
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(icon)
	return tab


func _on_stat(key: String, delta: int) -> void:
	CharStats.adjust(key, delta)
	_refresh_stats()


func _refresh_stats() -> void:
	for key in _stat_value_labels:
		_stat_value_labels[key].text = "%s: %02d" % [
			CharStats.LABELS.get(key, key), int(CharStats.values.get(key, 0))]
	if _points_label:
		_points_label.text = "Kalan Puan: %d" % CharStats.points
	# +/- verschwinden, sobald alle Punkte verteilt sind - und nur auf der
	# Rucksack-Seite (sonst wuerden sie auf anderen Reitern auftauchen).
	var show_btns := CharStats.points > 0 and _active_tab == 0
	for b in _stat_buttons:
		b.visible = show_btns


## Stern-Grafik je Level-Stufe (alle 5 Level eine andere). Leicht erweiterbar:
## weitere Zellen aus UI_Icons anhaengen. Aktuell blau -> gelb.
const STAR_CELLS := [Vector2i(9, 3), Vector2i(3, 0)]


## EXP-Leiste + Level-Stern aus skills_xp aktualisieren.
func _refresh_level() -> void:
	if _exp_left == null:
		return
	var lvl := SkillsXP.player_level()
	var prog := SkillsXP.level_progress()
	# EINE durchgehende Leiste: erst fuellt sich die linke Haelfte (0..0.5),
	# dann laeuft es rechts weiter (0.5..1). Sanft animiert.
	var left_t := clampf(prog * 2.0, 0.0, 1.0) * 100.0
	var right_t := clampf((prog - 0.5) * 2.0, 0.0, 1.0) * 100.0
	_animate_exp(left_t, right_t)
	_level_label.text = str(lvl)
	# Stern-Grafik nur bei Levelwechsel neu setzen (spart Arbeit).
	if lvl != _last_level:
		var tier: int = clampi(lvl / 5, 0, STAR_CELLS.size() - 1)
		_level_star.texture = UiAtlas.cell("icons", STAR_CELLS[tier].x, STAR_CELLS[tier].y)
		_last_level = lvl


## Leichtes, endloses Schimmern der gefuellten Leiste (heller/dunkler pulsen).
func _start_shimmer() -> void:
	var bright := Color(1.35, 1.3, 1.05)
	var base := Color(1, 1, 1)
	_exp_left.tint_progress = base
	_exp_right.tint_progress = base
	var sh := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Aufhellen (beide zugleich), dann wieder zurueck - endlos.
	sh.tween_property(_exp_left, "tint_progress", bright, 0.9)
	sh.parallel().tween_property(_exp_right, "tint_progress", bright, 0.9)
	sh.tween_property(_exp_left, "tint_progress", base, 0.9)
	sh.parallel().tween_property(_exp_right, "tint_progress", base, 0.9)


## Animiert beide Leisten-Haelften auf ihre Zielwerte (0..100).
func _animate_exp(left_t: float, right_t: float) -> void:
	if is_equal_approx(_exp_left.value, left_t) and is_equal_approx(_exp_right.value, right_t):
		return
	if _exp_tween != null and _exp_tween.is_valid():
		_exp_tween.kill()
	_exp_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_exp_tween.tween_property(_exp_left, "value", left_t, 0.35)
	_exp_tween.tween_property(_exp_right, "value", right_t, 0.35)


func _process(delta: float) -> void:
	# Craft-Fortschritt jeden Frame (fluessige Leiste); nur sichtbar, waehrend
	# wirklich etwas gebaut wird.
	if _craft_progress and craft_queue:
		var busy := craft_queue.is_busy()
		_craft_progress.visible = busy
		if busy:
			_craft_progress.value = craft_queue.progress() * 100.0
	# XP aendert sich ohne Signal - dafuer reicht ein leichter Poll.
	_poll += delta
	if _poll < 0.4:
		return
	_poll = 0.0
	_refresh_level()


# --- Fenster-Scrolling der Tasche ---------------------------------------

## Verschiebt das sichtbare Fenster (Mausrad); hält die Scrollleiste im Gleichlauf.
func _scroll_bag(delta: int) -> void:
	if _bag_scroll == null:
		return
	_bag_scroll.value = clampf(_bag_scroll.value + delta, _bag_scroll.min_value, _bag_scroll.max_value)


## Ordnet den Ansichten die aktuellen Taschen-Slots zu (nach Scroll-Offset).
func _apply_window() -> void:
	for r in range(VIEW_ROWS):
		for c in range(VIEW_COLS):
			var view: InventorySlot = _bag_views[r * VIEW_COLS + c]
			var data_idx := inventory.hotbar_size + (_bag_offset + r) * VIEW_COLS + c
			if data_idx < inventory.slots.size():
				view.index = data_idx
				view.visible = true
			else:
				view.index = -1
				view.visible = false
			_refresh_slot(view)


# --- Anzeige ------------------------------------------------------------

func _refresh() -> void:
	for panel in _slot_nodes:
		_refresh_slot(panel)
		panel.add_theme_stylebox_override("panel", _slot_style(panel.index))
	for view in _bag_views:
		_refresh_slot(view)
	var sel: Dictionary = inventory.slots[selected]
	_name_label.text = ItemDB.display_name(sel["id"]) if not sel.is_empty() else ""


## Aktualisiert Icon/Anzahl/Dauerhaftigkeit eines Slots aus seinem aktuellen
## Index (bei den Taschen-Ansichten ändert er sich beim Scrollen).
func _refresh_slot(panel: InventorySlot) -> void:
	var icon: TextureRect = panel.get_node("Icon")
	var label: Label = panel.get_node("Count")
	var dur_bg: ColorRect = panel.get_node("DurBg")
	if panel.index < 0 or panel.index >= inventory.slots.size() or inventory.slots[panel.index].is_empty():
		icon.texture = null
		label.text = ""
		panel.tooltip_text = ""
		dur_bg.visible = false
		return
	var slot: Dictionary = inventory.slots[panel.index]
	icon.texture = ItemDB.icon(slot["id"])
	label.text = str(slot["count"]) if int(slot["count"]) > 1 else ""
	panel.tooltip_text = ItemDB.display_name(slot["id"])
	_refresh_durability(dur_bg, slot)


## Stellt den Dayaniklilik-Cubugu eines Slots ein: sichtbar nur bei Aleten,
## Breite = Restanteil, Farbe von gruen (voll) ueber gelb nach rot (leer).
func _refresh_durability(dur_bg: ColorRect, slot: Dictionary) -> void:
	if not ItemDB.has_durability(slot["id"]):
		dur_bg.visible = false
		return
	var maxd := ItemDB.max_durability(slot["id"])
	var cur := int(slot.get("dur", maxd))
	var r := clampf(float(cur) / float(maxd), 0.0, 1.0)
	dur_bg.visible = true
	var fill: ColorRect = dur_bg.get_node("Fill")
	fill.anchor_right = r
	fill.offset_right = 0
	fill.color = Color.from_hsv(0.33 * r, 0.85, 0.9)


## Das Bild, das beim Ziehen am Mauszeiger hängt.
func make_drag_preview(stack: Dictionary) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(stack["id"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(SLOT - 8, SLOT - 8)
	icon.position = -icon.size * 0.5
	icon.modulate = Color(1, 1, 1, 0.85)
	wrap.add_child(icon)
	var count := int(stack["count"])
	if count > 1:
		var label := Label.new()
		label.text = str(count)
		label.add_theme_font_size_override("font_size", INFO_FONT)
		label.position = Vector2(6, 2)
		wrap.add_child(label)
	return wrap


# --- Eingabe ------------------------------------------------------------

func toggle_bag() -> void:
	_bag.visible = not _bag.visible
	_dim.visible = _bag.visible


func bag_open() -> bool:
	return _bag.visible


func select(index: int) -> void:
	selected = clampi(index, 0, inventory.hotbar_size - 1)
	_refresh()


func _on_slot_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	# Mausrad über den Taschen-Feldern scrollt das Fenster.
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_bag(-1)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_bag(1)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Ein Klick waehlt nur aus. Das Umlegen laeuft ueber Drag & Drop.
	if index >= 0 and index < inventory.hotbar_size:
		select(index)


## Wird vom Slot aufgerufen, wenn ein Zug ausserhalb der Felder endet.
func drop_to_world(index: int) -> void:
	if drop_sync:
		drop_sync.drop_index(index)


func set_hint(text: String) -> void:
	_hint_label.text = text
