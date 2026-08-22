extends RefCounted
class_name PoFrames

## Baut die SpriteFrames für "Po" zur Laufzeit aus den Spritesheets.
##
## Statt ~2000 AtlasTexture-Blöcke in eine .tres zu schreiben, werden die
## Regionen hier gerechnet. Die Sheet-Liste liefert PoSheets (erzeugt von
## tools/build_po.py), die verkleinerten Sheets liegen in
## assets/characters/po_scaled - je Zelle 48x48.
##
## Die Sheets kennen nur fünf Richtungen (Süd, Südwest, West, Nordwest, Nord).
## Die Ostseite entsteht durch Spiegeln, siehe `flipped()`.

const DIR := "res://assets/characters/po_scaled/"

## Zeile im Sheet je Blickrichtung. Die Ost-Richtungen teilen sich die
## Zeile mit ihrem West-Gegenstück und werden gespiegelt gezeichnet.
const ROW_OF := {
	"south": 0, "south-west": 1, "west": 2, "north-west": 3, "north": 4,
	"south-east": 1, "east": 2, "north-east": 3,
}

## Richtungsname, unter dem die Animation abgelegt ist.
const CANON := {
	"south": "south", "south-west": "south_west", "west": "west",
	"north-west": "north_west", "north": "north",
	"south-east": "south_west", "east": "west", "north-east": "north_west",
}

## Diese Aktionen laufen in Schleife, alle anderen einmal durch.
const LOOPING := ["idle", "walk", "run", "sit", "fish", "dig"]

const FPS := {"idle": 8.0, "walk": 10.0, "run": 12.0}
const DEFAULT_FPS := 10.0


## Muss der Sprite für diese Richtung gespiegelt werden? Die Sheets zeigen
## die Westseite, Osten ist deren Spiegelbild.
static func flipped(facing: String) -> bool:
	return facing.ends_with("east")


## Animationsname für Aktion + Blickrichtung, z. B. ("walk", "north-east")
## -> "walk_north_west" (gespiegelt gezeichnet).
static func anim_name(action: String, facing: String) -> String:
	return "%s_%s" % [action, CANON.get(facing, "south")]


static func build() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var cell: int = PoSheets.CELL
	for sheet in PoSheets.SHEETS:
		var tex: Texture2D = load(DIR + sheet + ".png")
		if tex == null:
			push_warning("Po: Sheet fehlt - " + sheet)
			continue
		var cols: int = PoSheets.SHEETS[sheet]
		var action := _action_of(sheet)
		for row in range(PoSheets.ROWS):
			var anim := "%s_%s" % [action, _row_names()[row]]
			sf.add_animation(anim)
			sf.set_animation_speed(anim, FPS.get(action, DEFAULT_FPS))
			sf.set_animation_loop(anim, _loops(action))
			for col in range(cols):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(col * cell, row * cell, cell, cell)
				at.filter_clip = true
				sf.add_frame(anim, at)
	_add_aliases(sf)
	return sf


## Player.gd spricht Jacks Namensschema: idle_/walk_/run_/axe_ mal acht
## Richtungen. Damit Po ohne Umbau derselben Logik folgt, werden diese Namen
## zusaetzlich angelegt und zeigen auf dieselben Frames. Die Westrichtungen
## teilen sich die Frames mit Westen - gespiegelt wird beim Abspielen.
static func _add_aliases(sf: SpriteFrames) -> void:
	for pair in [["idle", "idle"], ["walk", "walk"], ["run", "run"], ["axe", "swing_axe"]]:
		for facing in ROW_OF:
			var src := anim_name(pair[1], facing)
			if not sf.has_animation(src):
				continue
			var dst := "%s_%s" % [pair[0], facing.replace("-", "_")]
			if sf.has_animation(dst):
				continue
			sf.add_animation(dst)
			sf.set_animation_speed(dst, sf.get_animation_speed(src))
			sf.set_animation_loop(dst, sf.get_animation_loop(src))
			for i in range(sf.get_frame_count(src)):
				sf.add_frame(dst, sf.get_frame_texture(src, i))


static func _row_names() -> Array:
	return ["south", "south_west", "west", "north_west", "north"]


## "Character0_WalkHoldingTool_Axe" -> "walkholdingtool_axe"
static func _action_of(sheet: String) -> String:
	return sheet.trim_prefix("Character0_").to_lower()


static func _loops(action: String) -> bool:
	for l in LOOPING:
		if action.begins_with(l):
			return true
	return false
