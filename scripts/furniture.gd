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
## neben der Charakter und den Baeumen stimmt. An EINER Stelle, damit die Vorschau
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
	"yatak": {"long": true, "scale": 1.0, "offset": Vector2(-32, -50)},
	# Feldbett tiefer aufgesetzt (-38 statt -50): die duennen Beine stehen so auf
	# dem Boden. Sonst hing das erhoehte Cot ueber der Zelle dahinter in der Luft -
	# lief man dahinter, sah es aus, als wuerde es schweben. Die Liegepose wird in
	# player.gd um denselben Betrag mitgesenkt (BED_SLEEP_OFFSETS), bleibt also gleich.
	"portatif_yatak": {"long": true, "scale": 1.0, "offset": Vector2(-32, -38)},
	# Hochbeet: soll GENAU eine Zelle gross sein, damit man daraus ein Feld
	# kacheln kann. Das gezeichnete Beet ist 58 px breit (Mitte x=32), die
	# Oberseiten-Raute liegt mittig bei y=28. Skalierung 32/58 macht die Raute
	# genau tile-breit (Top-Diamant = 32 px), der Offset legt ihre Mitte auf die
	# Zellmitte. So sitzt jedes Beet in seinem Diamanten und Nachbarn kacheln
	# nahtlos (die Y-Sortierung zeichnet das vordere ueber das hintere).
	# `tileable`: darf direkt neben anderen Moebeln stehen (Ausnahme von der
	# Abstandsregel) - damit man aus Hochbeeten ein zusammenhaengendes Feld legt.
	"yukseltilmis_tarha": {"scale": 32.0 / 58.0, "offset": Vector2(-32, -28), "tileable": true},
	# Richtungs-Tische (68x68, eigener Sprite-Satz). Mitte x=34, Fuss bei ~60.
	"calisma_tezgahi": {"scale": ART_SCALE, "offset": Vector2(-34, -58)},
	"ileri_uretim_masasi": {"scale": ART_SCALE, "offset": Vector2(-34, -58)},
	"dokuma_tezgahi": {"scale": ART_SCALE, "offset": Vector2(-34, -58)},
	"ileri_dokuma_tezgahi": {"scale": ART_SCALE, "offset": Vector2(-34, -58)},
	# working_table2: die Grafik ist klein (~21px) und sitzt oben links im
	# 68er-Bild. Groesser skaliert und Anker auf die tatsaechliche Fuss-Mitte.
	"uretim_masasi_v2": {"scale": 1.45, "offset": Vector2(-13, -23)},
	"ileri_uretim_masasi_v2": {"scale": 1.45, "offset": Vector2(-12, -23)},
	"ustun_uretim_masasi": {"scale": 1.45, "offset": Vector2(-12, -23)},
	"eritme_firini": {"scale": ART_SCALE, "offset": Vector2(-34, -58)},
	# Mesale (Fackel): 32er-Objekt, 1:1. Der Basis-Sprite wird beim Setzen
	# unsichtbar gemacht; ein animiertes Feuer-Kind uebernimmt die Anzeige.
	# tileable: darf direkt neben andere Objekte gestellt werden (kein Abstand).
	"mesale": {"scale": 1.0, "offset": Vector2(-16, -30), "tileable": true},
}


static func is_long(id: String) -> bool:
	return CONFIG.get(id, {}).get("long", false)


## Darf direkt an andere Moebel angrenzen (kein Mindestabstand)?
static func tileable(id: String) -> bool:
	return CONFIG.get(id, {}).get("tileable", false)


static func scale_of(id: String) -> float:
	return CONFIG.get(id, {}).get("scale", ART_SCALE)


static func offset_of(id: String) -> Vector2:
	return CONFIG.get(id, {}).get("offset", ART_OFFSET)


var id := ""
var cell: Vector2i
var level: int
## Ausrichtung 0..3 (S/O/N/W). Bei Richtungs-Moebeln waehlt sie den Sprite,
## bei den uebrigen nur, ob gespiegelt wird (ungerade = gespiegelt).
var orient := 0
var world: IsoWorld


static func create(p_world: IsoWorld, p_id: String, p_cell: Vector2i, p_level: int, p_orient: int) -> Furniture:
	var f := Furniture.new()
	f.world = p_world
	f.id = p_id
	f.cell = p_cell
	f.level = p_level
	f.orient = p_orient
	# Richtungs-Moebel bekommen ihren eigenen Sprite je Ausrichtung, alle
	# anderen die 64er-Region wie das Inventar-Icon (kein zweites Bild noetig).
	f.texture = ItemDB.dir_texture(p_id, p_orient) if ItemDB.has_dirs(p_id) else ItemDB.icon(p_id)
	f.centered = false
	return f


func _ready() -> void:
	var s := scale_of(id)
	scale = Vector2(s, s)
	offset = offset_of(id)
	# Nicht-Richtungs-Moebel drehen sich durch Spiegeln (ungerade Ausrichtung).
	# Richtungs-Moebel tragen die Drehung schon im Sprite, nie spiegeln.
	flip_h = (orient % 2 == 1) and not ItemDB.has_dirs(id)
	add_child(CastShadow.create(self))
	# Terrain, das höher ist und vor dem Möbel liegt, korrekt darüber zeichnen.
	# Als Geschwister (nicht als Kind), damit es die Möbel-Skalierung nicht erbt.
	get_parent().add_child.call_deferred(
		TerrainOcclusion.create(world, self, _footprint_cells))
	if id == "mesale":
		_make_torch()


## Fackel: statisches Basis-Icon ausblenden, animiertes Feuer + Licht setzen.
## Die 5 Feuer-Frames liegen in Reihe 1 des 160x64-Objekt-Sheets (je 32x32).
func _make_torch() -> void:
	self_modulate = Color(1, 1, 1, 0)          # Basis-Sprite unsichtbar (Schatten bleibt)
	var sheet: Texture2D = load("res://assets/game_assets/objects/torch.png")
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("burn")
	sf.set_animation_speed("burn", 9.0)
	sf.set_animation_loop("burn", true)
	for c in range(5):
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(c * 32, 32, 32, 32)
		sf.add_frame("burn", at)
	var flame := AnimatedSprite2D.new()
	flame.sprite_frames = sf
	flame.centered = false
	flame.offset = Vector2(-16, -30)
	flame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flame.play("burn")
	add_child(flame)
	var light := PointLight2D.new()
	light.texture = load("res://resources/light_gradient.tres")
	light.color = Color(1, 0.66, 0.32)
	light.texture_scale = 1.1
	light.position = Vector2(0, -22)
	light.set_script(load("res://scripts/flicker_light.gd"))
	light.base_energy = 0.75
	light.flicker_amount = 0.24
	light.flicker_speed = 9.0
	add_child(light)


## Die vom Möbel belegten Zellen - eine (1x1) oder zwei (1x2 Bett).
func _footprint_cells() -> Array:
	return world.footprint_long(cell) if is_long(id) else [cell]
