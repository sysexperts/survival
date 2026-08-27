extends RefCounted

## Baut zur Laufzeit ein SpriteFrames aus einem Aussehen-Dictionary, indem die
## gewählten Layer-Sheets (cc_scaled/<state>/) übereinandergeblendet und in
## Einzelframes zerschnitten werden.
##
## Wie bei PoFrames zeigen die Sheets nur die Westseite (fünf Zeilen: Süd,
## Südwest, West, Nordwest, Nord). Die Ost-Richtungen teilen sich die Frames
## mit ihrem West-Gegenstück und werden beim Zeichnen gespiegelt (flip_h),
## siehe `flipped()`.

const CCCatalog := preload("res://scripts/cc_catalog.gd")

const DIR := "res://assets/characters/cc_scaled/"

## Zeile im Sheet je Blickrichtung; Ost teilt sich die Zeile mit West.
const ROW_OF := {
	"south": 0, "south-west": 1, "west": 2, "north-west": 3, "north": 4,
	"south-east": 1, "east": 2, "north-east": 3,
}

const LOOPING := ["idle", "walk", "run", "sleep"]
const FPS := {"idle": 8.0, "walk": 10.0, "run": 12.0}
const DEFAULT_FPS := 10.0

## Fertige SpriteFrames je Aussehen zwischenspeichern - mehrere Mitspieler mit
## gleichem Look teilen sich dann eine Instanz.
static var _cache: Dictionary = {}


## Muss der Sprite für diese Richtung gespiegelt werden?
static func flipped(facing: String) -> bool:
	return facing.ends_with("east")


static func _key(look: Dictionary) -> String:
	var parts: Array = []
	for slot in CCCatalog.DRAW_ORDER:
		parts.append("%s=%s" % [slot, look.get(slot, "")])
	return "|".join(parts)


static func build(look: Dictionary) -> SpriteFrames:
	var key := _key(look)
	if _cache.has(key):
		return _cache[key]

	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var cell: int = CCCatalog.CELL

	for state in CCCatalog.STATE_COLS:
		var cols: int = CCCatalog.STATE_COLS[state]
		var tex := _composite(state, cols, look)
		if tex == null:
			continue
		for facing in ROW_OF:
			var row: int = ROW_OF[facing]
			var anim := "%s_%s" % [state, String(facing).replace("-", "_")]
			if sf.has_animation(anim):
				continue
			sf.add_animation(anim)
			sf.set_animation_speed(anim, FPS.get(state, DEFAULT_FPS))
			sf.set_animation_loop(anim, _loops(state))
			for col in range(cols):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(col * cell, row * cell, cell, cell)
				at.filter_clip = true
				sf.add_frame(anim, at)

	_cache[key] = sf
	return sf


## Blendet die gewählten Layer eines Zustands zu einer Textur zusammen.
static func _composite(state: String, cols: int, look: Dictionary) -> Texture2D:
	var cell: int = CCCatalog.CELL
	var w := cols * cell
	var h := CCCatalog.ROWS * cell
	var canvas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var any := false
	for slot in CCCatalog.DRAW_ORDER:
		var token := String(look.get(slot, ""))
		if token == "":
			continue
		var path := DIR + state + "/" + token + ".png"
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue
		var layer_tex: Texture2D = load(path)
		if layer_tex == null:
			continue
		var img := layer_tex.get_image()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != w or img.get_height() != h:
			continue  # Sheet passt nicht zum Zustand - überspringen
		canvas.blend_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
		any = true
	if not any:
		return null
	return ImageTexture.create_from_image(canvas)


static func _loops(state: String) -> bool:
	return state in LOOPING


static func clear_cache() -> void:
	_cache.clear()
