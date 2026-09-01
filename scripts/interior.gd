extends Node

## Betretbare Huetten (Demo). Rechtsklick auf eine FERTIGE Baraka -> Bild wird
## kurz schwarz -> man steht im Innenraum (eigene kleine Karte). Rechtsklick auf
## das Tuerfeld im Innenraum -> zurueck nach draussen.
##
## Der Innenraum SELBST ist eine echte, editierbare Szene:
##   scenes/hut_interior.tscn  (Floor-Ebene + Walls-Ebene + Spawn/Exit-Marker)
## Diese Szene wird NICHT im Spiel instanziert (sonst doppelt gerendert), sondern
## einmal ausgelesen und beim Betreten weit weg (ORIGIN) in die IsoWorld
## "gestempelt": Floor = begehbarer Boden, Walls = 3 Ebenen hoch (nicht
## uebersteigbar). Chunk-Manager laesst die INTERIOR_ZONE frei (schwarzes Leeres
## rundherum). Zum Editieren einfach hut_interior.tscn im Godot-Editor oeffnen.
##
## KEIN class_name (Auto-Updater) - per Node in main.tscn + setup() eingebunden.

const INTERIOR_SCENE := preload("res://scenes/hut_interior.tscn")

## Innenraeume leben in einer weit abgelegenen Region derselben Welt (ostwaerts
## ab x=INTERIOR_X, siehe chunk_manager: dort wird KEIN Gelaende generiert). So
## weit weg, dass niemand hinlaeuft, aber noch im float-genauen Bereich.
## Pro Spieler ein eigener Slot (per Netzwerk-ID versetzt), damit sich im MP
## niemand denselben Raum teilt. Gestempelt wird nur LOKAL - andere Clients sehen
## den Raum nicht.
const BASE := Vector2i(30000, 30000)
const SLOT_SPAN := 64         ## Felder Abstand zwischen zwei Spieler-Slots
## Standard-Wandhoehe in Ebenen (>=2 = nicht uebersteigbar). Pro Innenraum-Szene
## ueberschreibbar: an der Wurzel (HutInterior) im Inspector die Metadaten
## "wall_height" (int) setzen -> so hoch werden die Waende gestapelt.
const WALL_HEIGHT_DEFAULT := 3
const WALL_HEIGHT_MAX := 8
const FADE := 0.35

var world: Node = null
var player: Node = null

var _inside := false
var _origin := Vector2i.ZERO          ## aktueller Stempel-Ursprung (Spieler-Slot)
var _return_pos := Vector2.ZERO
var _stamped: Array = []              ## [[cell, level], ...] zum Aufraeumen
var _spawn_cell := Vector2i.ZERO
var _exit_cell := Vector2i.ZERO
var _floor: Dictionary = {}           ## lokale Zelle -> Boden-Atlas
var _walls: Dictionary = {}           ## lokale Zelle -> Wand-Atlas
var _wall_height := WALL_HEIGHT_DEFAULT
var _loaded := false
var _fade: ColorRect = null
var _exit_btn: Button = null


func _ready() -> void:
	add_to_group("interior")
	world = get_node_or_null(^"../World")
	_build_fade()
	if world != null:
		_load_layout()


func _player() -> Node:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	return player


func is_inside() -> bool:
	return _inside


## Zelle des Eingangsorts (fuer den Save: NICHT die Innenraum-Position sichern).
func return_cell() -> Vector2i:
	if world == null:
		return Vector2i.ZERO
	return world.world_to_cell(_return_pos, 0)


## Welt-Zelle des Tuer-Ausgangs (fuer den Rechtsklick-Test im Innenraum).
func exit_world_cell() -> Vector2i:
	return _origin + _exit_cell


## Eigener, weit abgelegener Stempel-Ursprung fuer diesen Spieler (Netzwerk-Slot).
func _slot_origin() -> Vector2i:
	var uid := 1
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		uid = multiplayer.get_unique_id()
	return BASE + Vector2i((uid % 512) * SLOT_SPAN, 0)


## Innenraum-Szene einmal auslesen: welche Zellen Boden, welche Wand sind, plus
## Spawn- und Exit-Feld. Die Szene wird danach wieder verworfen.
func _load_layout() -> void:
	var inst := INTERIOR_SCENE.instantiate()
	var fl := inst.get_node("Floor") as TileMapLayer
	var wl := inst.get_node("Walls") as TileMapLayer
	for c in fl.get_used_cells():
		_floor[c] = fl.get_cell_atlas_coords(c)
	for c in wl.get_used_cells():
		_walls[c] = wl.get_cell_atlas_coords(c)
	_spawn_cell = fl.local_to_map((inst.get_node("Spawn") as Node2D).position)
	_exit_cell = fl.local_to_map((inst.get_node("Exit") as Node2D).position)
	# Wandhoehe pro Szene: Metadaten "wall_height" an der Wurzel (sonst Standard).
	if inst.has_meta("wall_height"):
		_wall_height = clampi(int(inst.get_meta("wall_height")), 1, WALL_HEIGHT_MAX)
	inst.free()
	_loaded = true


## Innenraum betreten (nach Rechtsklick auf eine fertige Baraka).
func enter() -> void:
	var p := _player()
	if _inside or not _loaded or world == null or p == null:
		return
	_return_pos = p.global_position
	_origin = _slot_origin()
	# Boden legen ...
	for c in _floor:
		world.set_block(_origin + c, 0, _floor[c])
		_stamped.append([_origin + c, 0])
	# ... und Waende hochziehen (mehrere Ebenen = nicht uebersteigbar).
	for c in _walls:
		for lvl in range(_wall_height):
			world.set_block(_origin + c, lvl, _walls[c])
			_stamped.append([_origin + c, lvl])
	_inside = true
	if _exit_btn != null:
		_exit_btn.visible = true
	_transition(func(): p.teleport_to(world.cell_to_world(_origin + _spawn_cell, 0)))


## Innenraum verlassen: zurueck an die Eingangsstelle, Innenraum abraeumen.
func leave() -> void:
	var p := _player()
	if not _inside or p == null:
		return
	_transition(func():
		p.teleport_to(_return_pos)
		_cleanup())


func _cleanup() -> void:
	for e in _stamped:
		world.erase_block(e[0], e[1])
	_stamped.clear()
	_inside = false
	if _exit_btn != null:
		_exit_btn.visible = false


## Schwarzblende: ausblenden -> in der Mitte `mid` ausfuehren -> wieder aufblenden.
func _transition(mid: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE)
	tw.tween_callback(mid)
	tw.tween_interval(0.12)
	tw.tween_property(_fade, "color:a", 0.0, FADE)


func _build_fade() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 200
	add_child(cl)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_fade)

	# "Rausgehen"-Button unten links - nur im Innenraum sichtbar.
	_exit_btn = Button.new()
	_exit_btn.text = "  Disari Cik  "
	_exit_btn.visible = false
	_exit_btn.focus_mode = Control.FOCUS_NONE
	_exit_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_exit_btn.offset_left = 16
	_exit_btn.offset_top = -56
	_exit_btn.offset_bottom = -16
	_exit_btn.add_theme_font_size_override("font_size", 16)
	_exit_btn.pressed.connect(leave)
	cl.add_child(_exit_btn)
