extends CanvasLayer

## Ofen-Fenster (Cooking Campfire), Minecraft-Ofen-Layout:
##   [Input]                 (oben links)  -> kochbares (roher Fisch)
##   [Brennstoff]            (unten links) -> Kohle (komur)
##            =Fortschritt=> [Output]      (rechts)      -> fertig gekocht
## Darunter das Spieler-Inventar zum Umlegen. Inhalt + Fortschritt kommen
## server-autoritativ von furnace_sync. Beim Rausnehmen aus dem Output gibt es
## Koch-EXP.
##
## KEIN class_name (Auto-Updater) - per preload eingebunden.

const ChestSlot := preload("res://scripts/chest_slot.gd")
const SkillsXP := preload("res://scripts/skills_xp.gd")
const XpParticles := preload("res://scripts/xp_particles.gd")
const COOK_TIME := 30.0
const XP_PER_COOK := 6.0
const PCOLS := 10

## Slot-Indizes im Ofen-Inventar.
const S_IN := 0
const S_FUEL := 1
const S_OUT := 2

var player_inv: Inventory
var furnace_inv: Inventory
var furnace_sync
var player
var cell := Vector2i.ZERO
var _open := false

var _dim: ColorRect
var _panel: PanelContainer
var _fslots: Array = []
var _pslots: Array = []
var _bar: ColorRect
var _bar_bg: Panel
var _fire: Label


func setup(p_player_inv: Inventory, p_sync, p_player) -> void:
	player_inv = p_player_inv
	furnace_sync = p_sync
	player = p_player
	furnace_inv = Inventory.new(0, 0, 3)
	layer = 112
	_build()
	furnace_inv.changed.connect(_refresh)
	player_inv.changed.connect(_refresh)
	if furnace_sync != null and furnace_sync.has_signal("furnace_updated"):
		furnace_sync.furnace_updated.connect(_on_updated)


func is_open() -> bool:
	return _open


func inv_of(src: String) -> Inventory:
	return furnace_inv if src == "furnace" else player_inv


func open(p_cell: Vector2i) -> void:
	cell = p_cell
	_open = true
	visible = true
	_dim.visible = true
	_panel.visible = true
	for i in furnace_inv.slots.size():
		furnace_inv.slots[i] = {}
	if furnace_sync != null:
		furnace_sync.request(cell)
	_refresh()


func set_open(o: bool) -> void:
	_open = o
	visible = o
	_dim.visible = o
	_panel.visible = o


# --- Umlegen Ofen <-> Spieler ------------------------------------------

func transfer(from_src: String, from_i: int, to_src: String, to_i: int) -> void:
	var a := inv_of(from_src)
	var b := inv_of(to_src)
	# Regeln fuers Einlegen in Ofen-Slots.
	if to_src == "furnace":
		var moving: Dictionary = a.slots[from_i]
		if moving.is_empty():
			return
		var mid := String(moving.get("id", ""))
		if to_i == S_IN and not ItemDB.is_raw_fish(mid):
			return                              # Input nur kochbares
		if to_i == S_FUEL and mid != "komur":
			return                              # Brennstoff nur Kohle
		if to_i == S_OUT:
			return                              # Output: nichts einlegen
	# Menge im Output vor dem Zug (fuer EXP beim Rausnehmen).
	var out_before := 0
	if from_src == "furnace" and from_i == S_OUT and to_src == "player":
		out_before = int(furnace_inv.slots[S_OUT].get("count", 0)) if not furnace_inv.slots[S_OUT].is_empty() else 0
	# Zug ausfuehren (wie in der Truhe).
	if a == b:
		a.move(from_i, to_i)
	else:
		var stack: Dictionary = a.take(from_i)
		if stack.is_empty():
			return
		var back: Dictionary = b.put(to_i, stack)
		if not back.is_empty():
			a.put(from_i, back)
	# EXP fuer entnommene gekochte Stuecke.
	if from_src == "furnace" and from_i == S_OUT and to_src == "player":
		var out_after := int(furnace_inv.slots[S_OUT].get("count", 0)) if not furnace_inv.slots[S_OUT].is_empty() else 0
		var took := out_before - out_after
		if took > 0:
			_award_cook_xp(took)
	# Ofen-Aenderung an den Server (der verteilt + kocht weiter).
	if (from_src == "furnace" or to_src == "furnace") and furnace_sync != null:
		furnace_sync.push(cell, furnace_inv.slots)


## Shift-Klick: Ofen<->Inventar schnell umlegen. Aus dem Ofen -> ins Inventar
## (frei/merge); aus dem Inventar -> ins passende Ofen-Slot (Fisch=Input,
## Kohle=Brennstoff). Aus dem Output gibt es Koch-EXP.
func quick_move(src: String, i: int) -> void:
	if src == "furnace":
		var before := 0
		if i == S_OUT and not furnace_inv.slots[S_OUT].is_empty():
			before = int(furnace_inv.slots[S_OUT].get("count", 0))
		var moved := _to_inventory(furnace_inv, i)
		if i == S_OUT and moved > 0:
			_award_cook_xp(moved)
	else:
		var s: Dictionary = player_inv.slots[i]
		if s.is_empty():
			return
		var mid := String(s.get("id", ""))
		var target := -1
		if ItemDB.is_raw_fish(mid):
			target = S_IN
		elif mid == "komur":
			target = S_FUEL
		if target < 0:
			return
		var back: Dictionary = furnace_inv.put(target, player_inv.take(i))
		if not back.is_empty():
			player_inv.put(i, back)
	if furnace_sync != null:
		furnace_sync.push(cell, furnace_inv.slots)


## Ganzen Stapel aus from_inv[i] ins Spieler-Inventar (merge + freier Slot).
func _to_inventory(from_inv: Inventory, i: int) -> int:
	var s: Dictionary = from_inv.slots[i]
	if s.is_empty():
		return 0
	var id := String(s["id"])
	var cnt := int(s["count"])
	var left := player_inv.add(id, cnt)
	var moved := cnt - left
	if left <= 0:
		from_inv.slots[i] = {}
	else:
		s["count"] = left
	from_inv.changed.emit()
	return moved


func _award_cook_xp(n: int) -> void:
	SkillsXP.xp["cooking"] = float(SkillsXP.xp.get("cooking", 0.0)) + XP_PER_COOK * n
	if player != null and is_instance_valid(player) and player.world != null:
		var lvl: int = maxi(player.world.top_level_at(cell), 0)
		var from: Vector2 = player.world.cell_to_world(cell, lvl)
		XpParticles.spawn(player.get_parent(), from, player, 6)


# --- Server-Update -----------------------------------------------------

func _on_updated(p_cell: Vector2i, state: Dictionary) -> void:
	if not _open or p_cell != cell:
		return
	var slots: Array = state.get("slots", [{}, {}, {}])
	for i in furnace_inv.slots.size():
		furnace_inv.slots[i] = slots[i].duplicate() if i < slots.size() and slots[i] is Dictionary else {}
	var prog := float(state.get("progress", 0.0))
	var lit := bool(state.get("lit", false))
	_set_progress(prog, lit)
	_refresh()


func _set_progress(prog: float, lit: bool) -> void:
	if _bar == null:
		return
	var full := float(_bar_bg.size.x - 2)
	_bar.size.x = maxf(0.0, full * clampf(prog / COOK_TIME, 0.0, 1.0))
	_fire.text = "Atesli" if lit else "Sonuk"
	_fire.add_theme_color_override("font_color", Color(1, 0.7, 0.3) if lit else Color(0.6, 0.62, 0.68))


# --- Aufbau ------------------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
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
	head.text = "Ocak"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	# Kochbereich: [Input/Fuel] --Fortschritt--> [Output]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	_fslots.resize(3)
	_fslots[S_IN] = _make_fslot(S_IN, "Malzeme")
	left.add_child(_fslots[S_IN].get_parent())
	_fslots[S_FUEL] = _make_fslot(S_FUEL, "Komur")
	left.add_child(_fslots[S_FUEL].get_parent())

	# Mitte: Feuer-Status + Fortschrittsbalken.
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(mid)
	_fire = Label.new()
	_fire.text = "Sonuk"
	_fire.add_theme_font_size_override("font_size", 11)
	_fire.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_fire)
	_bar_bg = Panel.new()
	_bar_bg.custom_minimum_size = Vector2(90, 12)
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = Color(0.05, 0.05, 0.07, 0.9)
	bgsb.set_corner_radius_all(3)
	_bar_bg.add_theme_stylebox_override("panel", bgsb)
	mid.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Color(1, 0.6, 0.2)
	_bar.position = Vector2(1, 1)
	_bar.size = Vector2(0, 10)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar)

	# Rechts: Output.
	_fslots[S_OUT] = _make_fslot(S_OUT, "Cikti")
	row.add_child(_fslots[S_OUT].get_parent())

	col.add_child(HSeparator.new())
	var head2 := Label.new()
	head2.text = "Envanter"
	head2.add_theme_font_size_override("font_size", 11)
	col.add_child(head2)

	var pgrid := GridContainer.new()
	pgrid.columns = PCOLS
	pgrid.add_theme_constant_override("h_separation", 3)
	pgrid.add_theme_constant_override("v_separation", 3)
	col.add_child(pgrid)
	call_deferred("_build_player_slots", pgrid)


## Ein Ofen-Slot mit Beschriftung darueber (in einem VBox verpackt).
func _make_fslot(index: int, label: String):
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var lab := Label.new()
	lab.text = label
	lab.add_theme_font_size_override("font_size", 10)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lab)
	var s = ChestSlot.new()
	box.add_child(s)
	s.setup(self, "furnace", index)
	return s


func _build_player_slots(grid: GridContainer) -> void:
	for i in player_inv.slots.size():
		var s = ChestSlot.new()
		grid.add_child(s)
		s.setup(self, "player", i)
		_pslots.append(s)
	_refresh()


func _refresh() -> void:
	for s in _fslots:
		if s != null:
			s.refresh()
	for s in _pslots:
		s.refresh()
