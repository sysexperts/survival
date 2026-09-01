extends CanvasLayer

## Das Lagertruhen-Fenster: oben 3x10 Truhen-Felder, unten das Spieler-Inventar
## (Hotbar + Tasche) zum Umlegen. Der Inhalt ist online (chest_sync): aendert ein
## anderer Spieler die Truhe, sehe ich es sofort.
##
## KEIN class_name (Auto-Updater) - per preload eingebunden.

const ChestSlot := preload("res://scripts/chest_slot.gd")
const COLS := 10
const ROWS := 3

var player_inv: Inventory
var chest_inv: Inventory
var chest_sync                    ## Node fuer Online-Sync
var cell := Vector2i.ZERO
var _open := false
var _awaiting := false            ## MP: auf Server-Freigabe (Lock) wartend
var _loading := false             ## gerade Server-Inhalt geladen -> nicht zuruecksenden

## Bittet um eine kurze Bildschirm-Notiz (player_inventory zeigt sie an).
signal wants_notice(text: String)

var _dim: ColorRect
var _panel: PanelContainer
var _chest_slots: Array = []
var _player_slots: Array = []


func setup(p_player_inv: Inventory, p_chest_sync) -> void:
	player_inv = p_player_inv
	chest_sync = p_chest_sync
	chest_inv = Inventory.new(0, 0, ROWS * COLS)   # 30 Felder
	layer = 112
	_build()
	chest_inv.changed.connect(_refresh)
	player_inv.changed.connect(_refresh)
	if chest_sync != null and chest_sync.has_signal("chest_updated"):
		chest_sync.chest_updated.connect(_on_chest_updated)
	if chest_sync != null and chest_sync.has_signal("chest_denied"):
		chest_sync.chest_denied.connect(_on_chest_denied)


func is_open() -> bool:
	return _open


func inv_of(src: String) -> Inventory:
	return chest_inv if src == "chest" else player_inv


func open(p_cell: Vector2i) -> void:
	cell = p_cell
	# Truhe leeren.
	_loading = true
	for i in chest_inv.slots.size():
		chest_inv.slots[i] = {}
	_loading = false
	var mp: bool = chest_sync != null and chest_sync.has_method("is_mp") and chest_sync.is_mp()
	if mp:
		# Erst Lock anfordern; das Fenster geht erst bei Freigabe (_recv) auf,
		# oder es kommt eine Absage (_on_chest_denied). Kein Dupe mehr.
		_awaiting = true
		chest_sync.request(cell)
	else:
		# Einzelspieler: sofort oeffnen (kein Lock noetig).
		_open = true
		_show_panel(true)
		_refresh()


func _show_panel(o: bool) -> void:
	visible = o
	_dim.visible = o
	_panel.visible = o


func set_open(o: bool) -> void:
	# Beim Schliessen im MP den Lock wieder freigeben (server ignoriert Fremde).
	if not o and chest_sync != null and chest_sync.has_method("release") \
			and chest_sync.has_method("is_mp") and chest_sync.is_mp():
		chest_sync.release(cell)
	_open = o
	_awaiting = false
	_show_panel(o)


# --- Umlegen zwischen Truhe und Spieler --------------------------------

func transfer(from_src: String, from_i: int, to_src: String, to_i: int) -> void:
	var a := inv_of(from_src)
	var b := inv_of(to_src)
	if a == b:
		a.move(from_i, to_i)
	else:
		var stack: Dictionary = a.take(from_i)
		if stack.is_empty():
			return
		var back: Dictionary = b.put(to_i, stack)   # Rest/Tausch zurueck
		if not back.is_empty():
			a.put(from_i, back)
	# Truhe hat sich evtl. geaendert -> an den Server (der verteilt an andere).
	if (from_src == "chest" or to_src == "chest") and chest_sync != null:
		chest_sync.push(cell, chest_inv.slots)


## Shift-Klick: Stapel sofort ins andere Inventar (Truhe<->Spieler).
func quick_move(src: String, i: int) -> void:
	var from_inv := inv_of(src)
	var to_inv := player_inv if src == "chest" else chest_inv
	var s: Dictionary = from_inv.slots[i]
	if s.is_empty():
		return
	if s.has("dur"):
		# Haltbarkeits-Item (stapelt nicht): ganzer Eintrag in ersten freien Slot.
		for j in to_inv.slots.size():
			if to_inv.slots[j].is_empty():
				to_inv.slots[j] = s.duplicate()
				from_inv.slots[i] = {}
				break
	else:
		var left := to_inv.add(String(s["id"]), int(s["count"]))
		if left <= 0:
			from_inv.slots[i] = {}
		else:
			s["count"] = left
	from_inv.changed.emit()
	to_inv.changed.emit()
	if chest_sync != null:
		chest_sync.push(cell, chest_inv.slots)


# --- Online-Aktualisierung ---------------------------------------------

func _on_chest_updated(p_cell: Vector2i, slots: Array) -> void:
	if p_cell != cell or (not _open and not _awaiting):
		return
	# Freigabe im MP: jetzt erst das Fenster zeigen.
	if _awaiting:
		_awaiting = false
		_open = true
		_show_panel(true)
	_loading = true
	for i in chest_inv.slots.size():
		chest_inv.slots[i] = slots[i].duplicate() if i < slots.size() and slots[i] is Dictionary else {}
	_loading = false
	_refresh()


## Truhe ist von jemand anderem offen -> nicht oeffnen, kurze Notiz.
func _on_chest_denied(p_cell: Vector2i) -> void:
	if p_cell != cell:
		return
	_awaiting = false
	_open = false
	_show_panel(false)
	wants_notice.emit("Sandik su an kullaniliyor")


# --- Aufbau/Anzeige ----------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	# Klick auf den abgedunkelten Hintergrund schliesst die Truhe.
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			set_open(false))
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	sb.border_color = Color(0.4, 0.42, 0.5, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)

	var head := Label.new()
	head.text = "Sandik"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	var chest_grid := GridContainer.new()
	chest_grid.columns = COLS
	chest_grid.add_theme_constant_override("h_separation", 3)
	chest_grid.add_theme_constant_override("v_separation", 3)
	col.add_child(chest_grid)
	for i in ROWS * COLS:
		var s = ChestSlot.new()
		chest_grid.add_child(s)
		s.setup(self, "chest", i)
		_chest_slots.append(s)

	col.add_child(HSeparator.new())
	var head2 := Label.new()
	head2.text = "Envanter"
	head2.add_theme_font_size_override("font_size", 11)
	col.add_child(head2)

	var pgrid := GridContainer.new()
	pgrid.columns = COLS
	pgrid.add_theme_constant_override("h_separation", 3)
	pgrid.add_theme_constant_override("v_separation", 3)
	col.add_child(pgrid)
	# Spieler-Slots kommen erst in open()/setup(), wenn player_inv steht.
	call_deferred("_build_player_slots", pgrid)


func _build_player_slots(grid: GridContainer) -> void:
	for i in player_inv.slots.size():
		var s = ChestSlot.new()
		grid.add_child(s)
		s.setup(self, "player", i)
		_player_slots.append(s)
	_refresh()


func _refresh() -> void:
	for s in _chest_slots:
		s.refresh()
	for s in _player_slots:
		s.refresh()


