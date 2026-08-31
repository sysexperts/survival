extends CanvasLayer

## Skills-Fenster (Taste K). Zeigt die 7 Fertigkeiten mit Level + XP-Balken.
## Phase 1: reine Anzeige (Perks folgen in Phase 2). Bewusst im Code aufgebaut;
## spaeter kann das ins Buch als Reiter wandern.
##
## KEIN class_name (Auto-Updater) - per preload eingebunden.

const SkillsXP := preload("res://scripts/skills_xp.gd")

## [Anzeigename, xp-Key, Icon-Item, geplanter Perk-Text]
const SKILLS := [
	["Oduncu", "woodcutting", "balta", "schneller faellen"],
	["Madenci", "mining", "kazma", "Chance auf +1 Erz"],
	["Balikci", "fishing", "olta", "hoehere Fangchance"],
	["Asci", "cooking", "pismis_balik_1", "mehr Saettigung"],
	["Demirci", "smithing", "demir", "weniger Kohle"],
	["Zanaat", "crafting", "calisma_tezgahi", "spart Material"],
	["Insaat", "building", "baraka", "billiger bauen"],
]

var _open := false
var _dim: ColorRect
var _panel: PanelContainer
var _rows: Array = []          ## je Skill {level, bar, bar_bg}


func setup() -> void:
	layer = 112
	_build()


func is_open() -> bool:
	return _open


func toggle() -> void:
	set_open(not _open)


func set_open(o: bool) -> void:
	_open = o
	visible = o
	_dim.visible = o
	_panel.visible = o
	if o:
		_refresh()


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
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	sb.border_color = Color(0.4, 0.42, 0.5, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(360, 0)
	_panel.add_child(col)

	var head := Label.new()
	head.text = "Yetenekler"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 16)
	col.add_child(head)
	col.add_child(HSeparator.new())

	for s in SKILLS:
		col.add_child(_skill_row(s))


func _skill_row(s: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 34)

	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(String(s[2]))
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)

	var name_box := VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(110, 0)
	var nl := Label.new()
	nl.text = String(s[0])
	nl.add_theme_font_size_override("font_size", 13)
	name_box.add_child(nl)
	var pl := Label.new()
	pl.text = String(s[3])
	pl.add_theme_font_size_override("font_size", 10)
	pl.add_theme_color_override("font_color", Color(0.6, 0.63, 0.72))
	name_box.add_child(pl)
	row.add_child(name_box)

	var lvl := Label.new()
	lvl.custom_minimum_size = Vector2(46, 0)
	lvl.add_theme_font_size_override("font_size", 12)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(lvl)

	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(120, 10)
	bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = Color(0.05, 0.05, 0.07, 0.9)
	bgsb.set_corner_radius_all(3)
	bar_bg.add_theme_stylebox_override("panel", bgsb)
	var bar := ColorRect.new()
	bar.color = Color(0.37, 0.66, 1.0)
	bar.position = Vector2(1, 1)
	bar.size = Vector2(0, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar)
	row.add_child(bar_bg)

	_rows.append({"level": lvl, "bar": bar, "bar_bg": bar_bg})
	return row


func _refresh() -> void:
	for i in SKILLS.size():
		var key := String(SKILLS[i][1])
		var r: Dictionary = _rows[i]
		r["level"].text = "Sv %d" % SkillsXP.level_of(key)
		var full := float(r["bar_bg"].size.x - 2)
		r["bar"].size.x = maxf(0.0, full * SkillsXP.skill_progress(key))
