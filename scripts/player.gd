extends Node2D
class_name Player

## Jack: 8-Richtungs-Bewegung auf der gestapelten Isometrie-Map.
##
## Bewegt sich frei im Bildschirmraum (die Y-Achse wird gestaucht, damit
## das Tempo in der Iso-Perspektive gleichmässig wirkt) und rastet nicht
## auf Zellen ein. Die Höhe kommt aus IsoWorld: der Spieler steht immer
## auf dem obersten Block seiner Zelle, Stufen bis MAX_STEP sind begehbar.

const DIRS := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]

## Bildschirmvektor je Richtung, gleiche Reihenfolge wie DIRS.
## Y zeigt nach unten, Sueden ist also (0, 1).
const DIR_VECTORS: Array[Vector2] = [
	Vector2(0, 1), Vector2(0.7071, 0.7071), Vector2(1, 0), Vector2(0.7071, -0.7071),
	Vector2(0, -1), Vector2(-0.7071, -0.7071), Vector2(-1, 0), Vector2(-0.7071, 0.7071),
]

## Wird ausgelöst, wenn ein Baum gefällt ist. `atlas` sagt, welche Baumart
## es war - Anknüpfpunkt für Inventar und Ressourcen.
signal felled(cell: Vector2i, level: int, atlas: Vector2i)
## Ein Baumstumpf wurde endgueltig entfernt.
signal stump_cleared(cell: Vector2i)
## Es wurde versucht zu faellen, ohne die Axt in der Hand zu haben.
## Das Inventar haengt daran und sagt es dem Spieler - der Player selbst
## kennt weder HUD noch Hinweiszeile.
signal chop_refused

## Ein Stein wurde aufgehoben.
## `gather_id` sagt, WAS aufgehoben wurde (siehe GatherDB) - leer bei den
## alten, in die Karte gemalten Steinen.
signal stone_collected(cell: Vector2i, level: int, gather_id: String)

## Jack ist bei einer Handwerks-Station angekommen (nach Rechtsklick). Das
## Inventar oeffnet daraufhin ihr Fenster - der Player kennt kein HUD.
signal reached_station(station: String)

## Ein Objekt wurde gesetzt - fuer den Multiplayer-Sync (world_sync.gd), damit
## Lagerfeuer und Moebel bei allen erscheinen.
signal placed_campfire(top: Vector2i)
signal placed_furniture(id: String, cell: Vector2i, flipped: bool)

@export var world_path: NodePath = ^"../World"
@export var walk_speed := 60.0
@export var run_speed := 110.0
@export var y_squash := 0.5      ## Iso-Stauchung der vertikalen Bewegung
@export var max_step := 1        ## max. begehbarer Höhenunterschied in Ebenen
@export var start_cell := Vector2i(0, 0)
## Verschiebung des Sprites, damit die Fuesse auf dem Node-Ursprung stehen.
## Die Frames sind 68x68 (die Axt-Animation braucht den Platz), der
## Fusspunkt liegt bei y=52, die Regionsmitte bei 34 -> -18.
## Wird hier gesetzt statt in der Szene, damit player.tscn unberuehrt bleibt.
@export var sprite_offset := Vector2(0, -18)
## Helligkeit der Laterne bei voller Dunkelheit.
@export var lantern_energy := 0.55
## Axtschläge, bis ein Baum fällt.
@export var chops_to_fell := 6
## Frame der Axt-Animation, in dem die Klinge trifft (0-8).
@export var axe_impact_frame := 4
## Stärke des Kamera-Rucks pro Treffer bzw. beim Fällen.
@export var hit_shake := 1.6
@export var fell_shake := 4.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var lantern: PointLight2D = $Lantern

var world: IsoWorld
## Haelt Jack gerade eine Axt? Wird vom Inventar gesetzt und richtet sich
## danach, was in der Hotbar ausgewaehlt ist. Ohne Axt kein Baum.
var has_axe := false
var level := 0                   ## Ebene des Blocks, auf dem Jack steht
var facing := "south"
var busy := false                ## blockierende Animation (Axt) laeuft
var _day_night: Node = null      ## optional, zum Dimmen der Laterne

var path: Array[Vector2i] = []   ## laufender Klick-Weg, leer = kein Auftrag
var _chop_cell := Vector2i.ZERO  ## Baum, der nach dem Laufen dran ist
var _chop_level := -1
var _chops_left := 0
var _clearing_stump := false     ## Auftrag ist "Stumpf weg", nicht "Baum faellen"
var _pickup_cell := Vector2i(2147483647, 2147483647)  ## Stein, der nach dem Laufen dran ist
var _reach_station := ""          ## Station, die nach dem Laufen geoeffnet wird
var _tree: TreeActor = null      ## Baum als Node, solange gefällt wird
var _camera: Camera2D = null


func _ready() -> void:
	# Jack haengt sich zur Laufzeit in die TileMapLayer um, deshalb ist er
	# ueber den festen Szenenpfad nicht mehr auffindbar -> Gruppe.
	add_to_group("player")
	z_index = 0        # den z_index bringt der Props-Container mit
	_day_night = get_tree().get_first_node_in_group("day_night")
	world = get_node(world_path) as IsoWorld
	sprite.offset = sprite_offset
	sprite.animation_finished.connect(_on_animation_finished)
	# Umriss-Anzeige zur Laufzeit anhaengen - so bleibt player.tscn unberuehrt.
	add_child(OcclusionOutline.create(self, sprite, world))
	add_child(CastShadow.create(sprite))
	sprite.frame_changed.connect(_on_frame_changed)
	# Umhaengen ist waehrend _ready nicht erlaubt -> auf den naechsten Frame legen
	_snap_to_cell.call_deferred(start_cell)


## Setzt Jack auf den obersten Block einer Zelle.
func _snap_to_cell(cell: Vector2i) -> void:
	level = maxi(world.top_level_at(cell), 0)
	global_position = world.cell_to_world(cell, level)
	_reparent_to_level()


## Die Laterne brennt nur, wenn es dunkel genug ist.
func _process(_delta: float) -> void:
	if _day_night and lantern.visible:
		lantern.base_energy = lerpf(0.0, lantern_energy, _day_night.darkness())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			lantern.visible = not lantern.visible


func _physics_process(delta: float) -> void:
	if world == null:
		return
	# Waehrend ein Textfeld (z. B. die Chat-Eingabe) den Fokus hat, keine
	# Steuerung annehmen. Ueber den Fokus statt ein Flag - so kann nichts
	# "haengen bleiben" und die Steuerung dauerhaft blockieren.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var input := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	input = input.limit_length(1.0)

	# Tastatur bricht einen laufenden Auftrag ab - und zwar VOR dem
	# busy-Guard, sonst käme man während der Axt-Animation nie durch und
	# der gefällte Baum bliebe als Node hängen.
	if input != Vector2.ZERO and (busy or not path.is_empty() or _chop_level >= 0
			or _pickup_cell != INVALID_CELL or _reach_station != ""):
		_cancel_task()

	if busy:
		return

	# Axt auf Leertaste. (Enter ist jetzt fuer den Chat reserviert.)
	if Input.is_key_pressed(KEY_SPACE):
		_start_axe()
		return

	if input == Vector2.ZERO:
		if not path.is_empty():
			_follow_path(delta)
			return
		if _chop_level >= 0:
			_begin_chopping()
			return
		if _pickup_cell != INVALID_CELL:
			var target := _pickup_cell
			_pickup_cell = INVALID_CELL
			collect_stone(target)
			return
		if _reach_station != "":
			var s := _reach_station
			_reach_station = ""
			reached_station.emit(s)
			_play("idle")
			return
		_play("idle")
		return

	var running := Input.is_key_pressed(KEY_SHIFT)
	facing = DIRS[_dir_index(input)]
	_play("run" if running else "walk")

	var speed := run_speed if running else walk_speed
	var step := Vector2(input.x, input.y * y_squash) * speed * delta
	# Achsen getrennt bewegen, damit man an Kanten entlanggleitet
	_try_move(Vector2(step.x, 0.0))
	_try_move(Vector2(0.0, step.y))


## Richtungsindex aus dem Eingabevektor.
## Bildschirmwinkel (Y zeigt nach unten): Süden = 90°, Osten = 0°,
## Norden = -90°. DIRS laufen im 45°-Raster von Süden aus.
func _dir_index(v: Vector2) -> int:
	var a := rad_to_deg(atan2(v.y, v.x))
	return wrapi(int(round((90.0 - a) / 45.0)), 0, 8)


## Verschiebt Jack, wenn das Ziel begehbar ist, und passt die Höhe an.
func _try_move(delta_pos: Vector2) -> void:
	if delta_pos == Vector2.ZERO:
		return
	var target := global_position + delta_pos
	var cell := world.world_to_cell(target, level)
	if world.has_prop(cell):
		return                                  # Baum o. ae. im Weg
	var top := world.top_level_at(cell)
	if top < 0 or absi(top - level) > max_step:
		return                                  # Loch oder zu hohe Stufe
	if top != level:
		# Höhe wechseln: die Standfläche liegt (top - level) * 8 px höher
		target.y -= float(top - level) * IsoWorld.LEVEL_STEP_PX
		level = top
		_reparent_to_level()
	global_position = target


## Jack gehoert in denselben y-sortierten Container wie die Props. Nur so
## entscheidet zwischen ihm und einem Baum die Bildschirmposition statt des
## Ebenen-z_index. Der Container traegt den z_index, Jack selbst bleibt 0.
func _reparent_to_level() -> void:
	if not is_inside_tree() or world.props_root == null:
		return
	if get_parent() != world.props_root:
		reparent(world.props_root, true)


# --- Animation ---------------------------------------------------------

func _play(state: String) -> void:
	var anim := "%s_%s" % [state, facing.replace("-", "_")]
	if sprite.animation == anim and sprite.is_playing():
		return
	# Beim reinen Richtungswechsel den Zyklus weiterlaufen lassen,
	# statt den Schritt neu zu starten.
	var same_state := String(sprite.animation).begins_with(state + "_")
	var f := sprite.frame
	var progress := sprite.frame_progress
	sprite.play(anim)
	if same_state:
		sprite.set_frame_and_progress(f, progress)


func _start_axe() -> void:
	busy = true
	sprite.play("axe_%s" % facing.replace("-", "_"))


## Die Klinge trifft mitten in der Animation, nicht am Ende - sonst wirkt
## der Ruck versetzt zum Bild.
func _on_frame_changed() -> void:
	if not String(sprite.animation).begins_with("axe_"):
		return
	if sprite.frame != axe_impact_frame or not is_instance_valid(_tree):
		return
	var away := (_tree.global_position - global_position).normalized()
	if _chops_left > 1:
		_tree.hit(away)
		_shake(hit_shake)


func _shake(amount: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
	if _camera and _camera.has_method("shake"):
		_camera.shake(amount)


func _on_animation_finished() -> void:
	if not String(sprite.animation).begins_with("axe_"):
		return
	busy = false
	if _chops_left > 0:
		_chops_left -= 1
		if _chops_left > 0:
			_start_axe()
			return
		var cell := _chop_cell
		var lvl := _chop_level
		if _clearing_stump:
			world.remove_prop(cell, lvl)
			_shake(hit_shake)
			path.clear()
			_chop_level = -1
			_chops_left = 0
			_clearing_stump = false
			stump_cleared.emit(cell)
			_play("idle")
			return
		var atlas := _tree.atlas if is_instance_valid(_tree) else Vector2i.ZERO
		if is_instance_valid(_tree):
			# Aus der Verwaltung nehmen, aber am Leben lassen: der Node
			# blendet noch aus und raeumt sich danach selbst weg.
			world.detach_prop(cell)
			_tree.fell((_tree.global_position - global_position).normalized())
			_shake(fell_shake)
		_tree = null                 # blendet selbstständig aus und räumt sich auf
		path.clear()
		_chop_level = -1
		_chops_left = 0
		felled.emit(cell, lvl, atlas)
	_play("idle")


# --- Klick-Aufträge -----------------------------------------------------

## Läuft zur angeklickten Zelle. Gibt false zurück, wenn es keinen Weg gibt.
func walk_to(cell: Vector2i) -> bool:
	_cancel_task()
	var here := world.world_to_cell(global_position, level)
	# Auf ein Prop kann man nicht treten - dann daneben stellen.
	if world.has_prop(cell):
		cell = GridPath.adjacent_to(world, cell, here, max_step)
		if cell.x == 2147483647:
			return false
	path = GridPath.find(world, here, cell, max_step)
	return not path.is_empty()


## Läuft zu einer Handwerks-Station und öffnet sie bei Ankunft (Rechtsklick).
## `cell` ist die belegte Zelle der Station. false, wenn dort keine steht
## oder kein Weg daneben führt.
func walk_to_station(cell: Vector2i) -> bool:
	var node := world.blocker_at(cell)
	if not (node is Furniture and RecipeDB.is_station(node.id)):
		return false
	_cancel_task()
	var here := world.world_to_cell(global_position, level)
	var stand := GridPath.adjacent_to(world, cell, here, max_step)
	if stand.x == 2147483647:
		return false            # kein begehbares Feld neben der Station
	if stand == here:
		reached_station.emit(node.id)   # steht schon daneben
		return true
	path = GridPath.find(world, here, stand, max_step)
	if path.is_empty():
		return false
	_reach_station = node.id
	return true


## Läuft zum Stumpf und entfernt ihn mit einem Schlag - endgültig, es
## wächst danach nichts mehr nach.
func clear_stump(cell: Vector2i, stump_level: int) -> bool:
	if not chop(cell, stump_level):
		return false
	_clearing_stump = true
	return true


## Läuft zum Baum und fällt ihn. Steht Jack schon daneben, schlägt er sofort.
func chop(cell: Vector2i, prop_level: int) -> bool:
	# Ohne Axt in der Hand faellt hier gar nichts. Bewusst vor dem
	# Wegwerfen des laufenden Auftrags: ein Klick ins Leere soll nicht den
	# Weg abbrechen, auf dem Jack gerade ist.
	if not has_axe:
		chop_refused.emit()
		return false
	_cancel_task()
	var here := world.world_to_cell(global_position, level)
	var stand := GridPath.adjacent_to(world, cell, here, max_step)
	if stand.x == 2147483647:
		return false            # kein begehbares Feld neben dem Baum
	_chop_cell = cell
	_chop_level = prop_level
	if stand != here:
		path = GridPath.find(world, here, stand, max_step)
		if path.is_empty():
			_cancel_task()
			return false
	return true


func _cancel_task() -> void:
	path.clear()
	_pickup_cell = INVALID_CELL
	_reach_station = ""
	_chop_level = -1
	_chops_left = 0
	_clearing_stump = false
	busy = false                 # einen laufenden Axtschlag mit abbrechen
	if is_instance_valid(_tree):
		_tree.reset()
	_tree = null


## Bewegt Jack zum nächsten Wegpunkt. Ein Punkt gilt als erreicht, sobald
## er näher als ARRIVE_PX dran ist - sonst zappelt er auf der Stelle.
const ARRIVE_PX := 2.0
## Abstand der Prüfpunkte auf der Sichtlinie beim Glätten.
const LOS_SAMPLE_PX := 3.0
## So viele Wegpunkte werden pro Frame höchstens übersprungen. Deckelt die
## Sichtlinien-Tests bei langen Wegen.
const SMOOTH_LOOKAHEAD := 12

func _follow_path(delta: float) -> void:
	_smooth_path()
	var target := world.cell_to_world(path[0], world.top_level_at(path[0]))
	var to_target := target - global_position
	if to_target.length() <= ARRIVE_PX:
		global_position = target
		level = world.top_level_at(path[0])
		_reparent_to_level()
		path.remove_at(0)
		if path.is_empty() and _chop_level < 0 and _pickup_cell == INVALID_CELL:
			_play("idle")
		return

	# Blickrichtung aus der Bildschirmrichtung, Y-Stauchung herausgerechnet,
	# damit dieselben 8 Sektoren gelten wie bei der Tastatur.
	facing = DIRS[_dir_index(Vector2(to_target.x, to_target.y / y_squash))]
	_play("walk")
	var step := to_target.normalized() * walk_speed * delta
	if step.length() > to_target.length():
		step = to_target
	_try_move(Vector2(step.x, 0.0))
	_try_move(Vector2(0.0, step.y))


## Zellweise A*-Wege sehen aus wie Treppen. Deshalb wird vor jedem Schritt
## der am weitesten entfernte Wegpunkt gesucht, zu dem die direkte Linie frei
## ist - dazwischenliegende Punkte fallen weg. Ergebnis: Jack läuft schnurgerade
## und schneidet Kurven, statt am Raster entlangzuknicken.
func _smooth_path() -> void:
	var last := mini(path.size() - 1, SMOOTH_LOOKAHEAD)
	for i in range(last, 0, -1):
		var lvl := world.top_level_at(path[i])
		if lvl != level:
			continue                 # Höhenwechsel: lieber am Raster bleiben
		if _line_is_walkable(global_position, world.cell_to_world(path[i], lvl)):
			for _n in range(i):
				path.remove_at(0)
			return


## Ist die gerade Linie zwischen zwei Weltpunkten auf der aktuellen Ebene frei?
func _line_is_walkable(from: Vector2, to: Vector2) -> bool:
	var delta := to - from
	# In Iso-Pixeln ist ein Schritt (16, 8) - die Y-Achse doppelt so fein
	# abtasten wäre unnötig, LOS_SAMPLE_PX ist klein genug für beide.
	var steps := int(ceilf(delta.length() / LOS_SAMPLE_PX))
	for i in range(1, steps + 1):
		var p := from + delta * (float(i) / float(steps))
		if not _point_is_walkable(p):
			return false
	return true


## Prüft die Zelle unter einem Weltpunkt - und die beiden seitlich versetzten
## Punkte dazu, damit Jack nicht mit der Schulter durch eine Ecke rutscht.
func _point_is_walkable(p: Vector2) -> bool:
	for offset in [Vector2.ZERO, Vector2(3.0, 0.0), Vector2(-3.0, 0.0)]:
		var cell := world.world_to_cell(p + offset, level)
		if world.has_prop(cell):
			return false
		if world.top_level_at(cell) != level:
			return false
	return true


func _begin_chopping() -> void:
	var exists := world.has_stump(_chop_cell) if _clearing_stump else world.has_prop(_chop_cell)
	if not exists:
		_cancel_task()                      # Ziel ist inzwischen weg
		_play("idle")
		return
	# Blickrichtung auf den BODEN unter dem Baum, nicht auf die Prop-Ebene:
	# die liegt 8 px höher und würde die Richtung verfälschen.
	var ground := maxi(world.top_level_at(_chop_cell), 0)
	var to_tree := world.cell_to_world(_chop_cell, ground) - global_position
	facing = DIRS[_dir_index(Vector2(to_tree.x, to_tree.y / y_squash))]
	# Das Prop-Tile weicht einem Node, damit der Baum wackeln und umkippen
	# kann. Bei Abbruch setzt _cancel_task() das Tile zurück.
	if _clearing_stump:
		# Ein Stumpf braucht keinen wackelnden Node - ein Schlag genuegt.
		_chops_left = 1
		_start_axe()
		return
	_tree = world.prop_node(_chop_cell)
	if _tree == null:
		_cancel_task()
		_play("idle")
		return
	_chops_left = chops_to_fell
	_start_axe()


# --- Objekte setzen -----------------------------------------------------

## Stellt ein Lagerfeuer auf ein 2x2-Feld. `top` ist dessen oberste Zelle.
## Gibt false zurueck, wenn dort kein Platz ist - dann wird auch kein Item
## verbraucht.
func place_campfire_at(top: Vector2i) -> bool:
	if not world.can_place_2x2(top):
		return false
	var lvl := maxi(world.top_level_at(top), 0)
	var fire := Campfire.create(top, lvl)
	fire.cells = world.footprint_2x2(top)
	world.props_root.add_child(fire)
	fire.global_position = world.footprint_center(top, lvl)
	for c in fire.cells:
		world.block_cell(c, fire)
	var taken := fire.cells.duplicate()
	fire.tree_exiting.connect(func():
		for c in taken:
			world.unblock_cell(c))
	placed_campfire.emit(top)
	return true


## Stellt ein Moebel auf eine einzelne Zelle. `flipped` spiegelt es.
## Gibt false zurueck, wenn dort kein Platz ist - dann wird auch kein Item
## verbraucht.
func place_furniture_at(id: String, cell: Vector2i, flipped: bool) -> bool:
	var long := Furniture.is_long(id)
	var cells: Array[Vector2i] = []
	if long:
		if not world.can_place_long(cell):
			return false
		cells = world.footprint_long(cell)
	else:
		if not world.can_place_1x1(cell):
			return false
		cells = [cell]
	var lvl := maxi(world.top_level_at(cell), 0)
	var f := Furniture.create(world, id, cell, lvl, flipped)
	world.props_root.add_child(f)
	f.global_position = world.footprint_long_center(cell, lvl) if long else world.cell_to_world(cell, lvl)
	for c in cells:
		world.block_cell(c, f)
	var taken := cells.duplicate()
	f.tree_exiting.connect(func():
		for c in taken:
			world.unblock_cell(c))
	placed_furniture.emit(id, cell, flipped)
	return true


## Stein in Reichweite, oder INVALID_CELL wenn keiner nah genug liegt.
##
## Bewusst ueber den Bildschirmabstand statt ueber Nachbarzellen: eine Zelle
## hat in diesem Halbversatz-Raster nur vier Nachbarn, die seitlich
## anliegenden Zellen gehoeren NICHT dazu. Wer von der Seite ankommt, stuende
## optisch direkt am Stein und waere trotzdem "nicht in Reichweite".
const INVALID_CELL := Vector2i(2147483647, 2147483647)
## Greifweite in Zellen. Gemessen wird im Zellmass (ein Diamant ist 32x16 px
## gross), sonst reicht Jack in der Iso-Sicht nach oben und unten nur halb so
## weit wie zur Seite.
@export var pickup_radius := 1.25

func stone_in_reach() -> Vector2i:
	var best := INVALID_CELL
	var best_dist := INF
	for entry in world.prop_placements():
		if int(entry[3]) != IsoWorld.STONE_SOURCE_ID:
			continue
		var to_stone := world.cell_to_world(entry[0], entry[1]) - global_position
		var d := Vector2(to_stone.x / IsoWorld.TILE_SIZE.x,
			to_stone.y / IsoWorld.TILE_SIZE.y).length()
		if d <= pickup_radius and d < best_dist:
			best_dist = d
			best = entry[0]
	return best


## Laeuft zum Stein und hebt ihn auf. Liegt er schon in Reichweite, wird
## sofort zugegriffen. false, wenn dort keiner liegt oder kein Weg hinfuehrt.
func fetch_stone(cell: Vector2i) -> bool:
	_cancel_task()
	if not world.has_stone(cell):
		return false
	if stone_in_reach() == cell:
		return collect_stone(cell)
	var here := world.world_to_cell(global_position, level)
	# Steine blockieren nicht - man kann direkt auf ihre Zelle laufen.
	path = GridPath.find(world, here, cell, max_step)
	if path.is_empty():
		return false
	_pickup_cell = cell
	return true


## Hebt den Stein auf dieser Zelle auf. false, wenn dort keiner (mehr) liegt.
func collect_stone(cell: Vector2i) -> bool:
	var lvl := world.stone_level(cell)
	if lvl < 0:
		return false
	# Kurz hinschauen, das reicht als Geste - eine Aufheb-Animation hat
	# Jack nicht.
	var to_stone := world.cell_to_world(cell, lvl) - global_position
	if to_stone.length() > 1.0:
		facing = DIRS[_dir_index(Vector2(to_stone.x, to_stone.y / y_squash))]
		_play("idle")
	# Vor dem Entfernen abfragen - danach ist der Node weg.
	var what := world.gather_id_at(cell)
	world.remove_prop(cell, lvl)
	stone_collected.emit(cell, lvl, what)
	return true


## Lagerfeuer in Reichweite: die eigene Zelle und ihre Nachbarn.
## `only_ready` liefert nur Feuer, deren Fleisch fertig ist.
func campfire_in_reach(only_ready := false) -> Campfire:
	var here := world.world_to_cell(global_position, level)
	var cells: Array[Vector2i] = [here]
	cells.append_array(world.neighbors(here))
	for c in cells:
		var node := world.blocker_at(c)
		if node is Campfire and (not only_ready or node.is_ready()):
			return node
	return null


## Handwerks-Station in Reichweite (eigene Zelle + Nachbarn), oder "".
## Gibt die Station-Id zurueck (= die Moebel-Id, z. B. "werkbank").
func station_in_reach() -> String:
	var here := world.world_to_cell(global_position, level)
	var cells: Array[Vector2i] = [here]
	cells.append_array(world.neighbors(here))
	for c in cells:
		var node := world.blocker_at(c)
		if node is Furniture and RecipeDB.is_station(node.id):
			return node.id
	return ""
