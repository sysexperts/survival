extends CanvasLayer
class_name CraftingHUD

## Das Handwerk-Fenster.
##
## Zeigt die Rezepte einer Station - `RecipeDB.HAND` ist das Grundhandwerk,
## das ohne alles geht. Dieselbe Klasse bedient später die Werkbank, dann
## nur mit einer anderen Station.
##
## Gebaut wird nicht sofort, sondern über die Bauliste (`CraftQueue`): pro
## Zeile stellt man eine Stückzahl ein, "Bauen" gibt sie in Auftrag, und
## unten läuft ab, was daraus wird. Die Liste arbeitet weiter, auch wenn
## dieses Fenster zu ist.
##
## Wird wie das Inventar komplett im Code aufgebaut, damit die Spielszene
## dafür nicht angefasst werden muss.

const SLOT := 46
const PAD := 4
## Rastergroesse des Pixel-Fonts. Kleinere Zwischenwerte verwaschen.
const SMALL := 11
## Obergrenze des Stückzahl-Reglers.
const MAX_BATCH := 99

var inventory: Inventory
var queue: CraftQueue
var station := RecipeDB.HAND
var title := "Handwerk"

var _dim: ColorRect
var _panel: PanelContainer
var _rows: Array = []          ## je Rezept: siehe _make_row
var _queue_box: VBoxContainer
var _queue_empty: Label
var _bar: ProgressBar
var _bar_label: Label


func setup(p_inventory: Inventory, p_queue: CraftQueue,
		p_station := RecipeDB.HAND, p_title := "Handwerk") -> void:
	inventory = p_inventory
	queue = p_queue
	station = p_station
	title = p_title
	layer = 111                # über dem Inventar-HUD
	inventory.changed.connect(_refresh)
	queue.changed.connect(_refresh)
	_build()
	_refresh()


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	set_open(not _panel.visible)


func set_open(open: bool) -> void:
	_panel.visible = open
	_dim.visible = open
	if open:
		_refresh()


# --- Aufbau -------------------------------------------------------------

func _frame(bg := Color(0.06, 0.07, 0.10, 0.94)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.35, 0.37, 0.45, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(12)
	return sb


func _slot_frame() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.82)
	sb.border_color = Color(0.35, 0.37, 0.45, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return sb


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sperrflaeche: dunkelt ab UND schluckt Klicks, damit bei offenem
	# Fenster kein Laufbefehl in die Welt durchrutscht.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", _frame())
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(head)

	for recipe in RecipeDB.for_station(station):
		column.add_child(_make_row(recipe))

	column.add_child(HSeparator.new())
	column.add_child(_make_queue())


func _make_row(recipe: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _slot_frame())

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(recipe["out"])
	icon.custom_minimum_size = Vector2(SLOT, SLOT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = ItemDB.display_name(recipe["out"])
	box.add_child(icon)

	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.custom_minimum_size = Vector2(260, 0)
	box.add_child(texts)

	var name_label := Label.new()
	var amount := int(recipe["count"])
	name_label.text = ItemDB.display_name(recipe["out"])
	if amount > 1:
		name_label.text += "  ×%d" % amount
	name_label.text += "   (%s s)" % _seconds_text(RecipeDB.seconds(recipe))
	texts.add_child(name_label)

	# Je Zutat eine eigene Zeile: nur so lässt sich einzeln einfärben,
	# was fehlt - eine zusammengesetzte Zeile wäre entweder ganz rot oder
	# ganz grün.
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 12)
	texts.add_child(costs)
	var cost_labels := {}
	for id in recipe["cost"]:
		# Je Zutat ein kleines Icon plus Text - das Icon macht auf einen Blick
		# klar, was gemeint ist, ohne den Namen entziffern zu muessen.
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 3)
		costs.add_child(item)
		var ic := TextureRect.new()
		ic.texture = ItemDB.icon(id)
		ic.custom_minimum_size = Vector2(SMALL + 5, SMALL + 5)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item.add_child(ic)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", SMALL)
		item.add_child(l)
		cost_labels[id] = l

	var note := Label.new()
	note.add_theme_font_size_override("font_size", SMALL)
	note.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
	texts.add_child(note)

	# Stückzahl-Regler. Als eigene Zeile mit -/+ statt eines Eingabefelds:
	# mit der Maus in der einen Hand tippt niemand gern Zahlen.
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 2)
	box.add_child(stepper)

	var minus := Button.new()
	# Bewusst der gewoehnliche Bindestrich und kein Minuszeichen: der
	# Pixel-Font kennt nur ASCII plus Umlaute, alles andere gaebe ein
	# leeres Kaestchen.
	minus.text = "-"
	minus.custom_minimum_size = Vector2(30, SLOT)
	stepper.add_child(minus)

	var amount_label := Label.new()
	amount_label.custom_minimum_size = Vector2(38, SLOT)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stepper.add_child(amount_label)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(30, SLOT)
	stepper.add_child(plus)

	var button := Button.new()
	button.text = "Bauen"
	button.custom_minimum_size = Vector2(96, SLOT)
	box.add_child(button)

	var entry := {
		"recipe": recipe,
		"button": button,
		"costs": cost_labels,
		"note": note,
		"amount": 1,
		"amount_label": amount_label,
		"minus": minus,
		"plus": plus,
	}
	minus.pressed.connect(_on_step.bind(entry, -1))
	plus.pressed.connect(_on_step.bind(entry, 1))
	button.pressed.connect(_on_craft.bind(entry))
	_rows.append(entry)
	return row


func _bar_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	return sb


func _make_queue() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(480, 0)

	var head := Label.new()
	head.text = "Bauliste"
	head.add_theme_font_size_override("font_size", SMALL)
	box.add_child(head)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 16)
	# Ohne das schrumpft der Balken in der Spalte auf seine Mindestbreite
	# zusammen und ist als Anzeige nutzlos.
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", _bar_style(
		Color(0.04, 0.05, 0.07, 0.9), Color(0.3, 0.32, 0.4, 0.9)))
	_bar.add_theme_stylebox_override("fill", _bar_style(
		Color(0.65, 0.55, 0.28, 1.0), Color(0.9, 0.8, 0.45, 1.0)))
	box.add_child(_bar)

	_bar_label = Label.new()
	_bar_label.add_theme_font_size_override("font_size", SMALL)
	box.add_child(_bar_label)

	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 2)
	box.add_child(_queue_box)

	_queue_empty = Label.new()
	_queue_empty.text = "leer"
	_queue_empty.add_theme_font_size_override("font_size", SMALL)
	_queue_empty.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	box.add_child(_queue_empty)
	return box


# --- Anzeige ------------------------------------------------------------

func _seconds_text(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _process(_delta: float) -> void:
	# Der Balken läuft weiter, ohne dass die Warteschlange jedes Bild ein
	# Signal wirft - deshalb hier abgefragt statt in _refresh gesetzt.
	if not _panel.visible:
		return
	_bar.value = queue.progress()


func _refresh() -> void:
	if inventory == null:
		return
	for row in _rows:
		var recipe: Dictionary = row["recipe"]
		var possible := RecipeDB.affordable(inventory, recipe, MAX_BATCH)
		# Der Regler darf nie mehr anbieten, als der Vorrat hergibt.
		row["amount"] = clampi(int(row["amount"]), 1, maxi(possible, 1))
		row["amount_label"].text = str(row["amount"])
		row["minus"].disabled = int(row["amount"]) <= 1
		row["plus"].disabled = int(row["amount"]) >= maxi(possible, 1)

		for id in recipe["cost"]:
			var need := int(recipe["cost"][id]) * int(row["amount"])
			var have := inventory.count_of(id)
			var label: Label = row["costs"][id]
			label.text = "%s %d/%d" % [ItemDB.display_name(id), have, need]
			label.add_theme_color_override("font_color",
				Color(0.65, 0.9, 0.6) if have >= need else Color(0.9, 0.55, 0.5))

		var why := "" if possible >= int(row["amount"]) else "Zutaten fehlen"
		row["note"].text = why
		row["button"].disabled = why != ""

	_refresh_queue()


func _refresh_queue() -> void:
	for child in _queue_box.get_children():
		child.queue_free()

	var jobs := queue.jobs
	_queue_empty.visible = jobs.is_empty()
	_bar.visible = not jobs.is_empty()
	_bar_label.visible = not jobs.is_empty()
	if jobs.is_empty():
		_bar_label.text = ""
		return

	var first: Dictionary = jobs[0]
	_bar_label.text = "%s  ×%d" % [
		ItemDB.display_name(first["recipe"]["out"]), int(first["left"])]

	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", SMALL)
		label.text = "%d. %s ×%d" % [
			i + 1, ItemDB.display_name(job["recipe"]["out"]), int(job["left"])]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)

		var stop := Button.new()
		stop.text = "Abbrechen"
		stop.add_theme_font_size_override("font_size", SMALL)
		stop.pressed.connect(_on_cancel.bind(job))
		line.add_child(stop)

		_queue_box.add_child(line)


# --- Eingabe ------------------------------------------------------------

func _on_step(entry: Dictionary, delta: int) -> void:
	entry["amount"] = int(entry["amount"]) + delta
	_refresh()


func _on_craft(entry: Dictionary) -> void:
	queue.enqueue(entry["recipe"], int(entry["amount"]))
	_refresh()


## Über den Auftrag selbst statt über den Index: zwischen Klick und
## Auswertung kann ein Auftrag fertig geworden und die Liste gerutscht
## sein - dann bräche der Index den falschen ab.
func _on_cancel(job: Dictionary) -> void:
	queue.cancel(queue.jobs.find(job))
	_refresh()
