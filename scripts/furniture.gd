extends Sprite2D
class_name Furniture

## Ein gesetztes Moebelstueck (Werkbank, Webetisch, ...).
##
## Anders als ein Baum wird ein Moebel nicht gemalt, sondern im Spiel ueber
## die Vorschau platziert. Es belegt eine Zelle, sitzt mittig darauf und
## laesst sich beim Setzen spiegeln - so zeigt die Werkbank mal nach links,
## mal nach rechts. Haengt im y-sortierten Props-Container, sortiert sich
## also korrekt zwischen Baeume und Figuren ein.

## Die Moebel im Sheet sind 64x64 gezeichnet und fuellen die Zelle fast ganz
## aus - deutlich groesser als ein 32er-Block. Verkleinert auf ein Mass, das
## neben Jack und den Baeumen stimmt. An EINER Stelle, damit die Vorschau
## dieselbe Groesse zeigt wie das gesetzte Moebel.
const ART_SCALE := 0.62
## Anker im 64er-Bild. x = 32 ist die waagerechte Mitte des Sheets, y = 56
## legt den Fuss des Objekts auf die Kachelmitte (die Grafiken enden bei
## ~58). Als Sprite-Offset - der von der Zeichenposition abgezogen wird -
## also negativ.
const ART_OFFSET := Vector2(-32, -56)

## Sonderfaelle. Die meisten Moebel sind ein normales 1x1-Stueck; was hier
## steht, weicht davon ab. `long` = 1x2 (zwei Zellen entlang der unteren
## Bildschirm-Diagonale), `scale`/`offset` stechen die Standardwerte aus,
## damit das groessere Bild die zwei Zellen ausfuellt.
const CONFIG := {
	"bett": {"long": true, "scale": 1.0, "offset": Vector2(-32, -50)},
	"feldbett": {"long": true, "scale": 1.0, "offset": Vector2(-32, -50)},
}


static func is_long(id: String) -> bool:
	return CONFIG.get(id, {}).get("long", false)


static func scale_of(id: String) -> float:
	return CONFIG.get(id, {}).get("scale", ART_SCALE)


static func offset_of(id: String) -> Vector2:
	return CONFIG.get(id, {}).get("offset", ART_OFFSET)


var id := ""
var cell: Vector2i
var level: int
var flipped := false
var world: IsoWorld


static func create(p_world: IsoWorld, p_id: String, p_cell: Vector2i, p_level: int, p_flipped: bool) -> Furniture:
	var f := Furniture.new()
	f.world = p_world
	f.id = p_id
	f.cell = p_cell
	f.level = p_level
	f.flipped = p_flipped
	# ItemDB liefert die 64x64-Region als AtlasTexture - dieselbe, die auch
	# das Inventar-Icon benutzt, es braucht also keine zweite Grafik.
	f.texture = ItemDB.icon(p_id)
	f.centered = false
	return f


func _ready() -> void:
	var s := scale_of(id)
	scale = Vector2(s, s)
	offset = offset_of(id)
	# Spiegeln um den Sprite-Ursprung (x = 0 = waagerechte Mitte), damit das
	# Moebel nach dem Drehen an derselben Stelle sitzt.
	flip_h = flipped
	add_child(CastShadow.create(self))
	# Terrain, das höher ist und vor dem Möbel liegt, korrekt darüber zeichnen.
	# Als Geschwister (nicht als Kind), damit es die Möbel-Skalierung nicht erbt.
	get_parent().add_child.call_deferred(
		TerrainOcclusion.create(world, self, _footprint_cells))


## Die vom Möbel belegten Zellen - eine (1x1) oder zwei (1x2 Bett).
func _footprint_cells() -> Array:
	return world.footprint_long(cell) if is_long(id) else [cell]
