@tool
extends Node2D
class_name IsoWorld

## Isometrische 2.5D-Welt aus gestapelten TileMapLayern.
##
## Die Höhen-Ebenen sind echte Kind-Nodes ("Level00", "Level01", ...) und
## werden ganz normal mit dem TileMap-Editor bemalt. Dieses Skript hält
## nur Offset, z_index, Sortierung und TileSet aller Ebenen synchron.
##
## Warum das funktioniert: die Blöcke im Sheet sind achsenparallele Würfel
## (Top-Diamant 32x16 + 8 px Seitenfläche). Ebene n wird um n * 8 px nach
## oben verschoben und bekommt z_index = n. Untere Ebenen werden also
## zuerst gezeichnet - das ist die korrekte Maler-Reihenfolge. Innerhalb
## einer Ebene sortiert der TileMapLayer isometrisch selbst.
##
## Neue Ebene anlegen: eine bestehende Level-Node duplizieren und
## fortlaufend "LevelNN" nennen - Offset und z_index setzt das Skript.

const TILE_SIZE := Vector2i(32, 16)   ## Grösse des Top-Diamanten
const LEVEL_STEP_PX := 8              ## Blockhöhe in Pixeln
const SOURCE_ID := 0                  ## Bodenbloecke (begehbar, stapelbar)
const PROP_SOURCE_ID := 1             ## Baeume: solide, nicht begehbar
const STUMP_SOURCE_ID := 2            ## Baumstuempfe: begehbar, aber anklickbar
const STONE_SOURCE_ID := 3            ## Kleine Steine: begehbar, aufsammelbar
const ROCK_SOURCE_ID := 4            ## Felsen: solide (blockieren), mit Spitzhacke abbaubar

## --- Untergrund / Buddeln -----------------------------------------------
## Unter der Oberflaeche (Level 0) liegen 2 Dirt-Ebenen (-1, -2); Level -3 ist
## Grundgestein (schwarz, nicht abbaubar) - danach kommt kein tieferes Buddeln.
## Buddeln dient v. a. zum Einebnen von Flaechen, nicht zum tiefen Graben. Die
## Ebenen werden unter jeder Bodenzelle vorbefuellt (siehe _fill_underground),
## damit die Waende eines Lochs solide sind.
const MIN_LEVEL := -3                 ## Grundgestein-Ebene (schwarz, nicht abbaubar)
const UNDER_COUNT := 3                ## Ebenen -1..-3
## Sentinel von top_level_at: gar kein Boden in dieser Saeule (frueher -1, jetzt
## unter MIN_LEVEL, weil -1..-5 jetzt gueltige Boeden sind).
const NO_FLOOR := MIN_LEVEL - 1       ## -6
## Dirt-Kachel fuer Untergrund/Aufschuetten (aus WorldGen.DIRT).
const DIRT_ATLAS := Vector2i(3, 1)
## Untergrund-Ebenen (Index i -> Level -(i+1)), zur Laufzeit erzeugt.
var _below: Array[TileMapLayer] = []

## Kleine Steine sind im Original-Sheet ganz normale Bodenkacheln - deshalb
## liegen sie in der Karte auch in Quelle 0. Beim Spielstart werden genau
## diese Atlas-Koordinaten herausgefischt und zu eigenen Nodes gemacht,
## damit man sie anleuchten und aufheben kann.
const STONE_ATLAS: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]

## z_index-Aufschlag fuer alles, was hoeher als ein Block ist (Props, Figuren).
## Ohne ihn wuerde jede hoehere Terrain-Ebene einen Baum verdecken, auch wenn
## sie hinter ihm liegt - der Ebenen-z_index schlaegt sonst jede Y-Sortierung.
## Figuren brauchen denselben Wert, sonst verschwinden sie hinter jedem Prop.
const TALL_Z_INDEX := 16

## Wird auf alle Ebenen angewendet, damit man es nur an einer Stelle setzt.
@export var tile_set_res: TileSet:
	set(v):
		tile_set_res = v
		_sync()

## Nur im Editor: alle Ebenen oberhalb ausblenden, damit man die
## darunterliegende Ebene ungestört bemalen kann. -1 = alles sichtbar.
@export_range(-1, 31) var editor_focus_level: int = -1:
	set(v):
		editor_focus_level = v
		_sync()

var levels: Array[TileMapLayer] = []


func _ready() -> void:
	_sync()
	if not Engine.is_editor_hint():
		# Im Spiel ist der Editor-Fokus irrelevant.
		for l in levels:
			l.visible = true
		_add_ground_backdrop()
		# Untergrund-Ebenen (-1..-5) anlegen und unter jede Bodenzelle Dirt/
		# Grundgestein legen - erst danach die Props umwandeln.
		_create_underground()
		_fill_underground_authored()
		# Vor dem Umwandeln der Props merken, was von Hand gemalt wurde -
		# der Weltgenerator baut nur außen herum und darf diesen Bereich nie
		# anfassen. _spawn_prop_nodes() entfernt Prop-/Stein-Kacheln aus den
		# Ebenen, deshalb MUSS das Erfassen davor laufen.
		_record_authored()
		_spawn_prop_nodes()


## Bodenfarbener Hintergrund HINTER allen Kacheln (im Welt-Canvas). Zwischen den
## Iso-Kacheln scheint sonst die dunkle Environment-/Clear-Farbe durch, die NICHT
## vom Tag/Nacht-CanvasModulate mitgedunkelt wird - beim Regen/Nachts trat das als
## dunkles Diamant-Gitter hervor ("durchsichtige" Kacheln). Dieser Rect liegt im
## selben Canvas, wird also mitgedunkelt; die Nachtfarbe der Kacheln und der Naht
## bleiben im Gleichschritt. Die UI-CanvasLayer sind nicht betroffen.
func _add_ground_backdrop() -> void:
	if has_node("GroundBackdrop"):
		return
	var bg := ColorRect.new()
	bg.name = "GroundBackdrop"
	# Etwa die mittlere Bodenfarbe (Gras/Erde), damit die duennen Naehte darin
	# verschwinden. Wird wie die Kacheln vom CanvasModulate multipliziert.
	bg.color = Color(0.33, 0.37, 0.22)
	var r := 16000.0
	bg.position = Vector2(-r, -r)
	bg.size = Vector2(r * 2.0, r * 2.0)
	bg.z_index = -4096                 # hinter allen Boden-/Untergrund-Ebenen
	bg.z_as_relative = false
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)


## Erzeugt die Untergrund-Ebenen (-1..-5) als eigene TileMapLayer ("Under1"..).
## Sie liegen tiefer (positiver y-Offset) und hinter der Oberflaeche (kleinerer
## z_index). Die unterste (-5) wird fast schwarz eingefaerbt = Grundgestein.
func _create_underground() -> void:
	if not _below.is_empty():
		return
	for i in range(UNDER_COUNT):
		var lvl := -(i + 1)
		var l := TileMapLayer.new()
		l.name = "Under%d" % (i + 1)
		l.tile_set = tile_set_res
		l.position = Vector2(0, -lvl * LEVEL_STEP_PX)
		l.z_index = lvl
		l.y_sort_enabled = true
		if lvl == MIN_LEVEL:
			l.modulate = Color(0.06, 0.06, 0.08)   # Grundgestein = schwarz
		add_child(l)
		_below.append(l)


## Fuellt unter jeder Bodenzelle (Block auf Level 0) die Untergrund-Ebenen:
## -1..-4 Dirt, -5 Grundgestein. So sind Loch-Waende solide.
func _fill_underground_authored() -> void:
	if levels.is_empty():
		return
	for cell in levels[0].get_used_cells():
		_fill_underground(cell)


## Legt unter EINE Zelle die Untergrund-Bloecke (falls noch nicht da) - aber nur
## UNTER dem aktuellen Boden. Sonst wuerde ein bereits gebuddeltes Loch wieder
## aufgefuellt (Block "poppt" daneben auf, sobald man nebenan gräbt).
func _fill_underground(cell: Vector2i) -> void:
	var top := top_level_at(cell)
	for i in range(UNDER_COUNT):
		var lvl := -(i + 1)
		if lvl >= top:
			continue                     # nicht auf/ueber dem aktuellen Boden
		var l := _lay(lvl)
		if l != null and l.get_cell_source_id(cell) == -1:
			l.set_cell(cell, SOURCE_ID, DIRT_ATLAS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED and is_inside_tree():
		_sync()


## Sammelt die Level-Nodes und richtet sie aus.
func _sync() -> void:
	if not is_inside_tree():
		return
	levels.clear()
	var found: Array = []
	for c in get_children():
		if c is TileMapLayer and not String(c.name).begins_with("Under"):
			found.append([_level_of(c), c])
	found.sort_custom(func(a, b): return a[0] < b[0])

	for entry in found:
		var lvl: int = entry[0]
		var layer: TileMapLayer = entry[1]
		layer.position = Vector2(0, -lvl * LEVEL_STEP_PX)
		layer.z_index = lvl
		layer.y_sort_enabled = true
		if tile_set_res != null:
			layer.tile_set = tile_set_res
		if Engine.is_editor_hint():
			layer.visible = editor_focus_level < 0 or lvl <= editor_focus_level
		levels.append(layer)


## Level-Index aus dem Node-Namen ("Level03" -> 3), sonst Reihenfolge.
func _level_of(node: Node) -> int:
	var n := String(node.name)
	var digits := ""
	for i in range(n.length() - 1, -1, -1):
		var ch: String = n.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		else:
			break
	return int(digits) if digits != "" else node.get_index()


func level_count() -> int:
	return levels.size()


## Ebene zu einem Level - Oberflaeche (>=0) aus `levels`, Untergrund (<0) aus
## `_below`. null, wenn es die Ebene nicht gibt.
func _lay(level: int) -> TileMapLayer:
	if level >= 0:
		return levels[level] if level < levels.size() else null
	var i := -level - 1
	return _below[i] if i < _below.size() else null


func layer(level: int) -> TileMapLayer:
	return _lay(level)


# --- Abfragen für Gameplay ---------------------------------------------

## Welt-Position -> Zellkoordinate auf der gegebenen Höhen-Ebene.
func world_to_cell(world_pos: Vector2, level: int) -> Vector2i:
	var l := layer(level)
	return l.local_to_map(l.to_local(world_pos)) if l else Vector2i.ZERO


## Zellkoordinate -> Welt-Position (Mittelpunkt des Top-Diamanten).
func cell_to_world(cell: Vector2i, level: int) -> Vector2:
	var l := layer(level)
	return l.to_global(l.map_to_local(cell)) if l else Vector2.ZERO


func has_block(cell: Vector2i, level: int) -> bool:
	var l := _lay(level)
	return l != null and l.get_cell_source_id(cell) != -1


## Höchste begehbare Ebene an dieser Zelle, oder NO_FLOOR wenn die Säule leer ist.
## Sucht jetzt bis in den Untergrund (MIN_LEVEL). Props zählen nicht als Boden.
func top_level_at(cell: Vector2i) -> int:
	for lvl in range(levels.size() - 1, MIN_LEVEL - 1, -1):
		var l := _lay(lvl)
		if l != null and l.get_cell_source_id(cell) == SOURCE_ID:
			return lvl
	return NO_FLOOR


## Atlas-Koordinate des obersten Blocks (z. B. für Ressourcen-Typ).
func top_atlas_at(cell: Vector2i) -> Vector2i:
	var lvl := top_level_at(cell)
	var l := _lay(lvl)
	return l.get_cell_atlas_coords(cell) if l != null else Vector2i(-1, -1)


## Findet den Block, den die Maus optisch trifft: von oben nach unten,
## weil ein höherer Block die Zellen darunter verdeckt. Auch Untergrund
## (Loch-Boden), damit man in einem Loch weitergraben kann.
## Gibt [cell, level] zurück, oder [] wenn nichts getroffen wurde.
func pick_block(world_pos: Vector2) -> Array:
	for lvl in range(levels.size() - 1, MIN_LEVEL - 1, -1):
		var cell := world_to_cell(world_pos, lvl)
		if has_block(cell, lvl):
			return [cell, lvl]
	return []


# --- Laufzeit-Änderungen (Abbauen / Bauen im Spiel) --------------------

func set_block(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	var l := _lay(level)
	if l != null:
		l.set_cell(cell, SOURCE_ID, atlas)


func erase_block(cell: Vector2i, level: int) -> void:
	var l := _lay(level)
	if l != null:
		l.erase_cell(cell)


# --- Buddeln / Aufschuetten (Terraforming) ------------------------------

## Kann diese Zelle abgebaut werden? (Boden vorhanden UND nicht Grundgestein.)
func can_dig(cell: Vector2i) -> bool:
	if has_prop(cell) or has_stump(cell) or blocker_at(cell) != null:
		return false
	var top := top_level_at(cell)
	return top > MIN_LEVEL and top > NO_FLOOR


## Baut den obersten Block einer Zelle ab (eine Ebene tiefer). Der Block darunter
## ist durch die Vorbefuellung schon da (Dirt bzw. Grundgestein). Gibt true
## zurueck, wenn wirklich abgebaut wurde. Vor dem Aufruf can_dig() pruefen.
func dig_cell(cell: Vector2i) -> bool:
	if not can_dig(cell):
		return false
	var top := top_level_at(cell)
	# Sicherheitsnetz: Untergrund der Zelle UND der Nachbarn befuellen, falls noch
	# nicht geschehen (Chunk-Rand). Ohne die Nachbarn haette das Loch stellenweise
	# keine Wand (dann scheint der dunkle Hintergrund durch = "Border").
	_fill_underground(cell)
	for n in neighbors(cell):
		# NUR Nachbarn, die selbst Boden haben (Wand). Leere Nachbarn (Lueckenrand,
		# See, ungeladener Chunk) NICHT befuellen - sonst poppt daneben ein Block auf.
		if top_level_at(n) > NO_FLOOR:
			_fill_underground(n)
	erase_block(cell, top)
	return true


## Schuettet auf einer Zelle einen Dirt-Block oben drauf (eine Ebene hoeher).
## Deckelt bei der obersten Oberflaechen-Ebene. Gibt true bei Erfolg zurueck.
func raise_cell(cell: Vector2i) -> bool:
	if has_prop(cell) or has_stump(cell) or blocker_at(cell) != null:
		return false
	var top := top_level_at(cell)
	if top <= NO_FLOOR:
		return false
	var new_level := top + 1
	if new_level > levels.size() - 1:
		return false                     # nicht hoeher als die oberste Ebene
	set_block(cell, new_level, DIRT_ATLAS)
	return true


## Textur des obersten Bodenblocks einer Zelle (fuer die Maus-Hervorhebung beim
## Buddeln). null, wenn dort kein Block liegt.
func block_texture(cell: Vector2i) -> Texture2D:
	var lvl := top_level_at(cell)
	var l := _lay(lvl)
	if l == null:
		return null
	var atlas := l.get_cell_atlas_coords(cell)
	if atlas == Vector2i(-1, -1):
		return null
	var src := tile_set_res.get_source(SOURCE_ID) as TileSetAtlasSource
	if src == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = src.texture
	at.region = src.get_tile_texture_region(atlas)
	return at


## Obere-linke Ecke des obersten Bodenblocks in Weltkoordinaten (32x32-Kachel;
## der Top-Diamant-Mittelpunkt liegt bei (16,8) innerhalb der Kachel).
func block_top_left(cell: Vector2i) -> Vector2:
	var lvl := top_level_at(cell)
	return cell_to_world(cell, lvl) + Vector2(-16, -8)


# --- Nachbarschaft ------------------------------------------------------

## Die vier kantenbenachbarten Zellen.
##
## Das TileSet nutzt Godots "Stacked"-Layout: dort haengt die Nachbarschaft
## von der Zeilen-Paritaet ab. Bei geradem y liegen die westlichen Nachbarn
## bei x-1, bei ungeradem y die oestlichen bei x+1. Wer das ignoriert,
## bekommt Wege, die diagonal durch die Landschaft springen.
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var odd := absi(cell.y) % 2 == 1
	var dx := 1 if odd else -1
	return [
		Vector2i(cell.x, cell.y - 1),
		Vector2i(cell.x + dx, cell.y - 1),
		Vector2i(cell.x, cell.y + 1),
		Vector2i(cell.x + dx, cell.y + 1),
	]


## Die vier Zellen eines 2x2-Feldes, ausgehend von der OBERSTEN Zelle.
##
## Im Stacked-Layout haengen die beiden unteren Nachbarn von der
## Zeilen-Paritaet ab, die vierte Zelle liegt zwei Zeilen tiefer bei
## gleichem x. Auf dem Bildschirm ergibt das eine grosse Raute:
## 64 px breit, 32 px hoch.
func footprint_2x2(top: Vector2i) -> Array[Vector2i]:
	var dx := 1 if absi(top.y) % 2 == 1 else -1
	return [
		top,
		Vector2i(top.x, top.y + 1),
		Vector2i(top.x + dx, top.y + 1),
		Vector2i(top.x, top.y + 2),
	]


## Mittelpunkt eines 2x2-Feldes in Weltkoordinaten.
func footprint_center(top: Vector2i, level: int) -> Vector2:
	return (cell_to_world(top, level) + cell_to_world(Vector2i(top.x, top.y + 2), level)) * 0.5


## Passt hier ein 2x2-Objekt hin? Alle vier Zellen muessen Boden haben,
## frei sein und auf derselben Hoehe liegen - ein Lagerfeuer soll nicht
## ueber eine Stufe hinweg stehen.
func can_place_2x2(top: Vector2i) -> bool:
	var level := -1
	for c in footprint_2x2(top):
		var l := top_level_at(c)
		if l < 0 or has_prop(c) or has_stump(c) or blocker_at(c) != null:
			return false
		if level == -1:
			level = l
		elif l != level:
			return false
	return not _furniture_adjacent(footprint_2x2(top))


## Passt hier ein 1x1-Objekt hin (z. B. ein Moebel)? Die Zelle muss Boden
## haben und frei sein - kein Prop (Baum, Stein, Stumpf, Rohstoff) und kein
## bereits gesetztes Objekt. `prop_node` deckt Baeume, Steine, Rohstoffe und
## die zu Nodes gewordenen Stuempfe ab; `has_stump` faengt zusaetzlich den
## Editor-/Tile-Fall ab, bevor die Props zu Nodes werden.
func can_place_1x1(cell: Vector2i, allow_adjacent := false) -> bool:
	if top_level_at(cell) < 0:
		return false
	if blocker_at(cell) != null or prop_node(cell) != null or has_stump(cell):
		return false
	# `allow_adjacent`: kachelbare Moebel (Hochbeet) duerfen aneinander stehen.
	if allow_adjacent:
		return true
	return not _furniture_adjacent([cell])


## Steht auf einer Nachbarzelle des Fussabdrucks schon ein Moebel/Lagerfeuer?
## Verhindert, dass zwei Objekte so dicht stehen, dass ihre (deutlich groesser
## als eine Zelle gezeichneten) Bilder sichtbar ineinanderlaufen. Die eigenen
## Fussabdruck-Zellen zaehlen nicht als Nachbarn.
func _furniture_adjacent(foot: Array) -> bool:
	for c in foot:
		for n in neighbors(c):
			if n in foot:
				continue
			if blocker_at(n) != null:
				return true
	return false


## Die Nachbarzelle unten rechts auf dem Bildschirm. Ueber die Weltposition
## bestimmt statt ueber feste Offsets - im Stacked-Layout haengt die Richtung
## von der Zeilen-Paritaet ab.
func down_right_cell(cell: Vector2i) -> Vector2i:
	var base := cell_to_world(cell, 0)
	for n in neighbors(cell):
		var d := cell_to_world(n, 0) - base
		if d.x > 0.0 and d.y > 0.0:
			return n
	return cell


## Die zwei Zellen eines 1x2-Moebels (z. B. Bett): die Zelle und ihr
## Nachbar unten rechts - eine liegende Raute entlang der Diagonale.
func footprint_long(top: Vector2i) -> Array[Vector2i]:
	return [top, down_right_cell(top)]


## Mittelpunkt eines 1x2-Feldes in Weltkoordinaten.
func footprint_long_center(top: Vector2i, level: int) -> Vector2:
	return (cell_to_world(top, level) + cell_to_world(down_right_cell(top), level)) * 0.5


## Passt hier ein 1x2-Moebel hin? Beide Zellen frei, mit Boden, gleiche Hoehe.
func can_place_long(top: Vector2i) -> bool:
	var lvl := -1
	for c in footprint_long(top):
		var l := top_level_at(c)
		if l < 0 or blocker_at(c) != null or prop_node(c) != null or has_stump(c):
			return false
		if lvl == -1:
			lvl = l
		elif l != lvl:
			return false
	return not _furniture_adjacent(footprint_long(top))


## Kann man von `from` nach `to` treten? Prueft Loch, Prop und Stufenhoehe.
func can_step(from: Vector2i, to: Vector2i, max_step: int = 1) -> bool:
	if has_prop(to):
		return false
	var a := top_level_at(from)
	var b := top_level_at(to)
	# Boden vorhanden (auch Untergrund/Loch-Boden) und Stufe begehbar.
	return a > NO_FLOOR and b > NO_FLOOR and absi(b - a) <= max_step


# --- Handbau-Bereich (für den Weltgenerator) ---------------------------
#
# Der gemalte Startbereich bleibt fester Bestandteil der Welt; der
# chunk-basierte Generator (siehe scripts/chunk_manager.gd) baut nur außen
# herum und darf diese Zellen weder erzeugen noch beim Entladen löschen.

## Alle von Hand gemalten Zellen -> ihre oberste Ebene. Als Dictionary (nicht
## bloße Bounding-Box), weil die gemalte Map unregelmäßig ist: nur wirklich
## Belegtes wird ausgespart, sonst klafft am konkaven Rand eine Lücke. Die
## gespeicherte Höhe braucht der Generator, um außen bündig anzuschließen.
var authored_cells: Dictionary = {}

## Grobe Umschließung des Handbau-Bereichs - nur als billiger Vorfilter, um
## die Rand-Suche (nearest_authored) auf Zellen nahe der Map zu beschränken.
var authored_bounds: Rect2i = Rect2i()


func _record_authored() -> void:
	authored_cells.clear()
	var has_any := false
	var min_c := Vector2i.ZERO
	var max_c := Vector2i.ZERO
	# Erst alle Zellen sammeln, dann die Höhe bestimmen - top_level_at braucht
	# die fertig eingelesenen Ebenen.
	var seen := {}
	for l in levels:
		for cell in l.get_used_cells():
			seen[cell] = true
			if not has_any:
				min_c = cell
				max_c = cell
				has_any = true
			else:
				min_c.x = mini(min_c.x, cell.x)
				min_c.y = mini(min_c.y, cell.y)
				max_c.x = maxi(max_c.x, cell.x)
				max_c.y = maxi(max_c.y, cell.y)
	for cell in seen:
		authored_cells[cell] = maxi(top_level_at(cell), 0)
	authored_bounds = Rect2i(min_c, max_c - min_c + Vector2i.ONE) if has_any else Rect2i()


## Wurde diese Zelle von Hand gemalt? Dann nie generieren.
func is_authored(cell: Vector2i) -> bool:
	return authored_cells.has(cell)


## Zellabstand (Chebyshev) zur Handbau-Bounding-Box; groß, wenn weit weg.
## Billiger Vorfilter: nur nahe der Box lohnt die genaue Rand-Suche.
func dist_to_authored(cell: Vector2i) -> int:
	if authored_cells.is_empty():
		return 9999
	var b := authored_bounds
	var dx := maxi(maxi(b.position.x - cell.x, cell.x - (b.position.x + b.size.x - 1)), 0)
	var dy := maxi(maxi(b.position.y - cell.y, cell.y - (b.position.y + b.size.y - 1)), 0)
	return maxi(dx, dy)


## Nächster gemalter Nachbar einer (nicht gemalten) Zelle innerhalb `radius`.
## Rückgabe: Vector2i(abstand, randhöhe); abstand -1, wenn keiner in Reichweite.
## Damit blendet der Generator die Höhe bündig an den echten Rand an - nicht
## an die grobe Bounding-Box, sonst entstünde am konkaven Rand eine Stufe.
func nearest_authored(cell: Vector2i, radius: int) -> Vector2i:
	var best_d := radius + 1
	var best_h := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := Vector2i(cell.x + dx, cell.y + dy)
			if authored_cells.has(c):
				var d := maxi(absi(dx), absi(dy))
				if d < best_d:
					best_d = d
					best_h = authored_cells[c]
	return Vector2i(best_d, best_h) if best_d <= radius else Vector2i(-1, 0)


# --- Props als Nodes ----------------------------------------------------
#
# Gemalt werden Bäume und Stümpfe ganz normal als Tiles - im Editor bleibt
# alles wie gehabt. Beim Spielstart werden sie einmalig in Sprite-Nodes
# umgewandelt und aus den TileMapLayern entfernt.
#
# Der Grund: der z_index eines Layers schlägt jede Y-Sortierung. Als Tile
# bekäme ein Prop `Ebene + TALL_Z_INDEX` und ein Baum auf einem Hügel würde
# damit immer über allem darunter liegen - auch über einer Figur, die
# eindeutig vor ihm steht. Als Nodes hängen alle Props und der Spieler in
# EINEM y-sortierten Container mit EINEM z_index, dann entscheidet nur noch
# die Bildschirmposition. Genau das ist in dieser Perspektive richtig.

var props_root: Node2D = null
var _prop_nodes: Dictionary = {}      ## Vector2i -> TreeActor


func _spawn_prop_nodes() -> void:
	props_root = Node2D.new()
	props_root.name = "Props"
	props_root.y_sort_enabled = true
	props_root.z_index = TALL_Z_INDEX
	add_child(props_root)
	for i in levels.size():
		for src in [PROP_SOURCE_ID, STUMP_SOURCE_ID]:
			for cell in levels[i].get_used_cells_by_id(src):
				_make_prop_node(cell, i, levels[i].get_cell_atlas_coords(cell), src)
				levels[i].erase_cell(cell)
		# Steine stecken in der Bodenquelle und muessen ueber die
		# Atlas-Koordinate erkannt werden. Die Kachel verschwindet dabei aus
		# der Ebene: darunter liegt ueberall fester Boden, der Spieler steht
		# nach der Umwandlung also nicht mehr OBEN AUF dem Stein, sondern
		# davor - genau richtig zum Aufheben.
		for atlas in STONE_ATLAS:
			for cell in levels[i].get_used_cells_by_id(SOURCE_ID, atlas):
				_make_prop_node(cell, i, atlas, STONE_SOURCE_ID)
				levels[i].erase_cell(cell)


func _make_prop_node(cell: Vector2i, level: int, atlas: Vector2i, source_id: int) -> TreeActor:
	var node := TreeActor.create(self, cell, level, atlas, source_id)
	props_root.add_child(node)
	if source_id == STONE_SOURCE_ID:
		# Ein Stein ist eine 32x32-Kachel und wird um den Zellmittelpunkt
		# gezeichnet - der Node liegt deshalb genau da, wo die Kachel lag.
		node.global_position = cell_to_world(cell, level)
	else:
		# Der Fuß steht auf der Oberfläche eine Ebene unter dem Prop - genau da,
		# wo ihn der texture_origin des Tiles auch hingesetzt hätte.
		node.global_position = cell_to_world(cell, maxi(level - 1, 0))
	_prop_nodes[cell] = node
	invalidate_props()
	return node


## Setzt einen eingestreuten Rohstoff auf die Zelle. Gibt false zurueck,
## wenn dort schon etwas steht.
func spawn_gather(cell: Vector2i, level: int, id: String, sheet_cell: Vector2i) -> bool:
	if props_root == null or prop_node(cell) != null or blocker_at(cell) != null:
		return false
	var node := TreeActor.create_gather(cell, level, id, sheet_cell)
	props_root.add_child(node)
	node.global_position = cell_to_world(cell, level)
	_prop_nodes[cell] = node
	invalidate_props()
	return true


## Setzt einen abbaubaren Felsen (RockDB-Zustand + Variante) auf die Zelle.
func spawn_rock(cell: Vector2i, level: int, state: int, variant: int) -> bool:
	if props_root == null or prop_node(cell) != null or blocker_at(cell) != null:
		return false
	var node := TreeActor.create_rock(cell, level, state, variant)
	props_root.add_child(node)
	node.global_position = cell_to_world(cell, level)
	_prop_nodes[cell] = node
	invalidate_props()
	return true


## Fels-Zustand auf dieser Zelle (RockDB-Reihe) oder -1, wenn dort kein Fels ist.
func rock_state_at(cell: Vector2i) -> int:
	var n := prop_node(cell)
	return n.rock_state if n != null and n.source_id == ROCK_SOURCE_ID else -1


## Fertige Textur des Props - genau das, was der Node zeigt. Damit
## laesst sich die Hervorhebung bauen, ohne zu wissen, aus welchem Sheet
## das Bild stammt.
func prop_texture(cell: Vector2i) -> Texture2D:
	var n := prop_node(cell)
	return n.texture if n else null


## Skalierung des Props. Die Hervorhebung muss dieselbe benutzen.
func prop_scale(cell: Vector2i) -> Vector2:
	var n := prop_node(cell)
	return n.scale if n else Vector2.ONE


## Deckkraft an einer Stelle im Prop-Bild, in unskalierten Bildpixeln ab
## der linken oberen Ecke. Fuer den pixelgenauen Treffertest der Maus.
##
## Frueher hat der Aufrufer sich die Region selbst aus der TileSet-Quelle
## geholt - fuer eingestreute Rohstoffe gibt es die dort aber gar nicht,
## und die leere Region liess dann das komplette Sheet aufblitzen.
func prop_alpha_at(cell: Vector2i, local: Vector2i) -> float:
	var n := prop_node(cell)
	if n == null:
		return 0.0
	var tex := n.texture as AtlasTexture
	if tex == null:
		return 0.0
	var img: Image
	if n.rock_state >= 0:
		if _rock_image == null:
			_rock_image = (load(RockDB.SHEET) as Texture2D).get_image()
		img = _rock_image
	elif n.gather_id != "":
		if _gather_image == null:
			_gather_image = GatherDB.sheet().get_image()
		img = _gather_image
	else:
		img = _source_image(n.source_id)
	var px := Vector2i(tex.region.position) + local
	if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
		return 0.0
	return img.get_pixelv(px).a


## Welcher Rohstoff liegt auf dieser Zelle? "" wenn keiner.
func gather_id_at(cell: Vector2i) -> String:
	var n := prop_node(cell)
	return n.gather_id if n else ""


func prop_node(cell: Vector2i) -> TreeActor:
	var n = _prop_nodes.get(cell)
	return n if is_instance_valid(n) else null


## Alles Anklickbare als [cell, level, atlas, source_id].
func prop_placements() -> Array:
	if not _props_dirty:
		return _props_cache
	_props_cache.clear()
	for cell in _prop_nodes:
		var n: TreeActor = _prop_nodes[cell]
		if is_instance_valid(n):
			_props_cache.append([cell, n.level, n.atlas, n.source_id])
	_props_dirty = false
	return _props_cache


var _props_cache: Array = []
var _props_dirty := true


func invalidate_props() -> void:
	_props_dirty = true


## Bildschirm-Rechteck, in dem das Prop tatsächlich gezeichnet wird.
func prop_rect(cell: Vector2i, _level: int = 0, _atlas: Vector2i = Vector2i.ZERO,
		_source_id: int = PROP_SOURCE_ID) -> Rect2:
	var n := prop_node(cell)
	if n == null:
		return Rect2()
	return Rect2(n.global_position + n.offset * n.scale, n.texture.get_size() * n.scale)


func set_prop(cell: Vector2i, level: int, atlas: Vector2i, source_id: int = PROP_SOURCE_ID) -> void:
	if level < 0 or level >= levels.size():
		return
	if props_root == null:
		levels[level].set_cell(cell, source_id, atlas)   # Editor-Fall
		invalidate_props()
		return
	# Nur ein evtl. vorhandenes Prop-NODE entfernen - den Boden NICHT anfassen.
	# (remove_prop wuerde bei fehlendem Node die Bodenkachel loeschen und ein
	# Loch reissen, z. B. wenn nach dem Faellen der Stumpf gesetzt wird.)
	var existing := prop_node(cell)
	if existing:
		existing.queue_free()
		_prop_nodes.erase(cell)
	_make_prop_node(cell, level, atlas, source_id)


## Entfernt ein Prop sofort. Für das Fällen wird stattdessen detach_prop()
## benutzt, damit der Baum noch in Ruhe ausblenden kann.
func remove_prop(cell: Vector2i, level: int = -1) -> void:
	var n := prop_node(cell)
	if n:
		n.queue_free()
	_prop_nodes.erase(cell)
	# Die Kachel nur loeschen, wenn das Prop KEIN Node war (also eine gemalte
	# Kachel wie ein Stein). Zusaetzlich absichern: NIE eine Bodenkachel
	# (SOURCE_ID) loeschen - egal welcher Level uebergeben wird -, sonst
	# entsteht ein Loch (z. B. wenn beim Faellen der Stumpf gesetzt wird und
	# der Zuschauer keinen Baum-Node hat).
	if n == null and level >= 0 and level < levels.size():
		if levels[level].get_cell_source_id(cell) != SOURCE_ID:
			levels[level].erase_cell(cell)
	invalidate_props()


## Nimmt das Prop aus der Verwaltung, lässt den Node aber weiterleben -
## er räumt sich nach seiner Ausblend-Animation selbst weg.
func detach_prop(cell: Vector2i) -> void:
	_prop_nodes.erase(cell)
	invalidate_props()


## Steht auf dieser Zelle ein Baum? Bäume blockieren die Bewegung.
## Zellen, die durch gesetzte Objekte belegt sind (Lagerfeuer o. ae.).
## Getrennt von den Props, weil solche Objekte nicht gemalt, sondern im
## Spiel platziert werden.
var _blocked_cells: Dictionary = {}


func block_cell(cell: Vector2i, by: Node) -> void:
	_blocked_cells[cell] = by


func unblock_cell(cell: Vector2i) -> void:
	_blocked_cells.erase(cell)


func blocker_at(cell: Vector2i) -> Node:
	var n = _blocked_cells.get(cell)
	return n if is_instance_valid(n) else null


## Alle gesetzten Moebel als [cell, Furniture]. Fuer Hover und Rechtsklick -
## Moebel stecken nicht in den Prop-Nodes, sondern belegen nur eine Zelle.
func furniture_cells() -> Array:
	var out: Array = []
	for c in _blocked_cells:
		var n = _blocked_cells[c]
		if is_instance_valid(n) and n is Furniture:
			out.append([c, n])
	return out


func has_prop(cell: Vector2i) -> bool:
	var b := blocker_at(cell)
	# Kachelbare Moebel (Hochbeet) blockieren den Weg NICHT - man laeuft drueber.
	# Fuers Platzieren/Zerstoeren zaehlen sie weiter (das prueft blocker_at direkt).
	if b != null and not (b is Furniture and Furniture.tileable(b.id)):
		return true
	var n := prop_node(cell)
	if n:
		# Baeume UND Felsen blockieren den Weg.
		return n.source_id == PROP_SOURCE_ID or n.source_id == ROCK_SOURCE_ID
	# Editor bzw. vor der Umwandlung: noch als Tile prüfen
	for l in levels:
		if l.get_cell_source_id(cell) == PROP_SOURCE_ID:
			return true
	return false


## Steht auf dieser Zelle ein Baumstumpf? Stümpfe blockieren nicht - einen
## gefällten Baum soll man überqueren können.
func has_stump(cell: Vector2i) -> bool:
	var n := prop_node(cell)
	if n:
		return n.source_id == STUMP_SOURCE_ID
	for l in levels:
		if l.get_cell_source_id(cell) == STUMP_SOURCE_ID:
			return true
	return false


## Liegt auf dieser Zelle ein Stein? Steine blockieren nicht - man geht
## ueber sie drueber und hebt sie mit E auf.
func has_stone(cell: Vector2i) -> bool:
	var n := prop_node(cell)
	return n != null and n.source_id == STONE_SOURCE_ID


## Ebene des Steins auf dieser Zelle, -1 wenn dort keiner liegt.
func stone_level(cell: Vector2i) -> int:
	var n := prop_node(cell)
	return n.level if n and n.source_id == STONE_SOURCE_ID else -1


func stump_level(cell: Vector2i) -> int:
	var n := prop_node(cell)
	if n and n.source_id == STUMP_SOURCE_ID:
		return n.level
	for i in levels.size():
		if levels[i].get_cell_source_id(cell) == STUMP_SOURCE_ID:
			return i
	return -1


## Alle Zellen, auf denen etwas liegen kann: fester Boden obenauf, nichts
## drauf, nichts drum herum blockiert. Liefert [cell, level].
func free_ground_cells() -> Array:
	var seen := {}
	var out: Array = []
	for l in levels:
		for cell in l.get_used_cells():
			if seen.has(cell):
				continue
			seen[cell] = true
			var lvl := top_level_at(cell)
			if lvl < 0:
				continue
			if prop_node(cell) != null or blocker_at(cell) != null:
				continue
			if has_prop(cell) or has_stump(cell):
				continue
			# Manche Bodenkacheln tragen ihr Objekt im Bild - Busch, Schaedel.
			# Sie sind begehbar, aber optisch schon besetzt.
			if GatherDB.BLOCKED_GROUND.has(levels[lvl].get_cell_atlas_coords(cell)):
				continue
			out.append([cell, lvl])
	return out


# --- Sichtbare Ausdehnung eines Props ------------------------------------
#
# Das Tile-Rechteck ist 32x64, der Baum darin aber deutlich schmaler und
# oben oft mehrere Pixel leer. Fuer Verdeckungstests ist deshalb der
# tatsaechlich undurchsichtige Bereich noetig, sonst "verdeckt" ein Baum
# schon mit seiner leeren Ecke.

var _content_rects: Dictionary = {}   ## "src:x:y" -> Rect2 (lokal zur Region)
var _source_images: Dictionary = {}


# --- Farben für die Minimap ---------------------------------------------
#
# Die Minimap zeichnet pro Zelle einen Punkt in der Durchschnittsfarbe der
# obersten Kachel. Einmal pro Atlas-Kachel berechnet und gemerkt.

var _atlas_colors: Dictionary = {}


## Durchschnittsfarbe einer Atlas-Kachel (nur undurchsichtige Pixel).
func atlas_color(source_id: int, atlas: Vector2i) -> Color:
	var key := "%d:%d:%d" % [source_id, atlas.x, atlas.y]
	if _atlas_colors.has(key):
		return _atlas_colors[key]
	var src := tile_set_res.get_source(source_id) as TileSetAtlasSource
	var region := src.get_tile_texture_region(atlas)
	var img := _source_image(source_id)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(region.position.y, region.position.y + region.size.y):
		for x in range(region.position.x, region.position.x + region.size.x):
			var px := img.get_pixel(x, y)
			if px.a > 0.5:
				r += px.r
				g += px.g
				b += px.b
				n += 1
	var col := Color(r / n, g / n, b / n) if n > 0 else Color(0, 0, 0, 0)
	_atlas_colors[key] = col
	return col


## Farbe der obersten Bodenkachel einer (gemalten) Zelle, transparent wenn leer.
func ground_color(cell: Vector2i) -> Color:
	var lvl := top_level_at(cell)
	if lvl < 0:
		return Color(0, 0, 0, 0)
	return atlas_color(SOURCE_ID, levels[lvl].get_cell_atlas_coords(cell))


func _source_image(source_id: int) -> Image:
	if not _source_images.has(source_id):
		var src := tile_set_res.get_source(source_id) as TileSetAtlasSource
		_source_images[source_id] = src.texture.get_image()
	return _source_images[source_id]


## Undurchsichtiger Bereich eines Prop-Tiles, relativ zur Regionsecke.
## Wird pro Tile-Art einmal berechnet und gemerkt.
func content_bounds(source_id: int, atlas: Vector2i) -> Rect2:
	var key := "%d:%d:%d" % [source_id, atlas.x, atlas.y]
	if _content_rects.has(key):
		return _content_rects[key]
	var src := tile_set_res.get_source(source_id) as TileSetAtlasSource
	var size := src.texture_region_size
	var img := _source_image(source_id)
	var min_x := size.x
	var min_y := size.y
	var max_x := -1
	var max_y := -1
	for y in size.y:
		for x in size.x:
			if img.get_pixel(atlas.x * size.x + x, atlas.y * size.y + y).a > 0.1:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	var rect := Rect2()
	if max_x >= 0:
		rect = Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	_content_rects[key] = rect
	return rect


## Weltrechteck des sichtbaren Teils eines Props.
func prop_content_rect(cell: Vector2i) -> Rect2:
	var n := prop_node(cell)
	if n == null:
		return Rect2()
	# Eingestreute Rohstoffe kommen nicht aus dem TileSet - ihre Atlas-Zelle
	# waere in der TileSet-Quelle gar nicht vorhanden.
	var b := _gather_bounds(n.atlas) if n.gather_id != "" else content_bounds(n.source_id, n.atlas)
	return Rect2(n.global_position + (n.offset + b.position) * n.scale, b.size * n.scale)


var _gather_image: Image = null
var _rock_image: Image = null
const RockDB := preload("res://scripts/rock_db.gd")


## Undurchsichtiger Bereich einer Zelle im Rohstoff-Sheet, relativ zur
## Zellecke. Die GatherDB rechnet das ohnehin fuer die Ausrichtung aus.
func _gather_bounds(sheet_cell: Vector2i) -> Rect2:
	return GatherDB.content_bounds(sheet_cell)
