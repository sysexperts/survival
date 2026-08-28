extends RefCounted

## Zugriff auf das "Cute Fantasy UI"-Pack: liefert AtlasTexturen, StyleBoxen
## (9-Patch-Rahmen) und die Pack-Schrift. Preload statt class_name (Auto-Updater-
## Regel):  const UiAtlas := preload("res://scripts/ui_atlas.gd")
##
## Nutzung:
##   UiAtlas.tex("frames", Rect2i(0, 0, 48, 48))      # beliebige Region
##   UiAtlas.cell("icons", 0, 0)                        # Zelle nach Raster
##   UiAtlas.frame_box("frames", 0, 0, 8)               # StyleBoxTexture (Panel)
##   label.add_theme_font_override("font", UiAtlas.font())

const BASE := "res://assets/UI/Cute_Fantasy_UI/"

## Sheet-Kürzel -> Dateipfad.
const SHEETS := {
	"all":          BASE + "UI/UI_ALL.png",
	"frames":       BASE + "UI/UI_Frames.png",
	"buttons":      BASE + "UI/UI_Buttons.png",
	"button_icons": BASE + "UI/UI_Button_Icons.png",
	"icons":        BASE + "UI/UI_Icons.png",
	"bars":         BASE + "UI/UI_Bars.png",
	"frames_slots": BASE + "UI/UI_Frames.png",
	"sliders":      BASE + "UI/UI_Sliders.png",
	"selectors":    BASE + "UI/UI_Selectors.png",
	"ribbons":      BASE + "UI/UI_Ribbons.png",
	"crosshairs":   BASE + "UI/UI_Crosshairs.png",
	"popup":        BASE + "UI/UI_Pop_Up.png",
	"book":         BASE + "UI/Book_UI.png",
	"premade":      BASE + "UI/UI_Premade.png",
	"loading":      BASE + "UI/Loading_Icon.png",
	"pointer":      BASE + "UI/Pointer_Click_Anim.png",
}

## Zellraster (Kantenlänge in px) der gleichmäßig gerasterten Sheets. Für die
## unregelmäßigen (buttons, sliders, bars) direkt tex(...) mit Rect2i nutzen.
const GRID := {
	"frames": Vector2i(48, 48),        # 27 x 7  (Farbthemen je Zeile)
	"icons": Vector2i(16, 16),         # 39 x 16
	"button_icons": Vector2i(16, 16),  # 31 x 14
	"crosshairs": Vector2i(16, 16),    # 4 x 10
	"popup": Vector2i(48, 48),         # 2 x 2
}

const FONT_PATH := BASE + "Fonts/CuteFantasy-5x9.ttf"

static var _tex_cache: Dictionary = {}
static var _tex_res_cache: Dictionary = {}
static var _font: FontFile = null


## AtlasTexture für eine Region eines Sheets (gecacht).
static func tex(sheet: String, region: Rect2i) -> AtlasTexture:
	var key := "%s:%d,%d,%d,%d" % [sheet, region.position.x, region.position.y, region.size.x, region.size.y]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var at := AtlasTexture.new()
	at.atlas = _sheet_tex(sheet)
	at.region = Rect2(region)
	at.filter_clip = true
	_tex_cache[key] = at
	return at


## AtlasTexture einer Rasterzelle (nur für Sheets in GRID).
static func cell(sheet: String, col: int, row: int) -> AtlasTexture:
	var g: Vector2i = GRID.get(sheet, Vector2i(16, 16))
	return tex(sheet, Rect2i(col * g.x, row * g.y, g.x, g.y))


## StyleBoxTexture aus einer Rahmen-Zelle - für Panel/Button-Hintergründe.
## `margin` = Rand fürs 9-Patch-Strecken (Ecken bleiben unverzerrt).
static func frame_box(sheet: String, col: int, row: int, margin: int = 8) -> StyleBoxTexture:
	var g: Vector2i = GRID.get(sheet, Vector2i(48, 48))
	return box_region(sheet, Rect2i(col * g.x, row * g.y, g.x, g.y), margin)


static func box_region(sheet: String, region: Rect2i, margin: int = 8) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(sheet, region)
	sb.set_texture_margin_all(margin)
	# Inhalt etwas vom Rahmen abrücken.
	sb.set_content_margin_all(margin)
	return sb


## Pack-Schrift (pixelscharf importiert). Für ein Label:
##   label.add_theme_font_override("font", UiAtlas.font())
static func font() -> FontFile:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func _sheet_tex(sheet: String) -> Texture2D:
	if _tex_res_cache.has(sheet):
		return _tex_res_cache[sheet]
	var path: String = SHEETS.get(sheet, sheet)  # erlaubt auch direkten Pfad
	var t: Texture2D = load(path)
	_tex_res_cache[sheet] = t
	return t
