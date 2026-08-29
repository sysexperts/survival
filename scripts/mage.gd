extends Node2D

## Magier-Gegner. Kommt aus dem mage_house, dreht sich zum Spieler, schiesst
## blaue Lichtkugeln (mage_orb) und hat eine Lebensleiste. Mit einem Messer/
## Schwert (Nahkampf) toetbar. Rein lokal simuliert (pro Client).
##
## KEIN class_name (Auto-Updater) - per preload einbinden.

const Orb := preload("res://scripts/mage_orb.gd")

const DIR_FILE := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]
const BASE := "res://assets/game_assets/enemies/mage/"

const MAX_HP := 40.0
const SHOOT_RANGE := 260.0        ## nur schiessen, wenn der Spieler naeher ist
const SHOOT_INTERVAL := 2.2
const CAST_SHOW := 0.45           ## wie lange die Cast-Pose gezeigt wird
const SCALE := 1.0
## Fuss auf die Zellmitte, waagerecht zentriert (48er-Sprite).
const ART_OFFSET := Vector2(-24, -42)

var world = null
var player = null
var hp := MAX_HP
var _dead := false

var _body: Sprite2D
var _dir := 0
var _cast_left := 0.0
var _cooldown := 1.0              ## kurze Anfangs-Verzoegerung
var _hit_flash := 0.0
## Umherlaufen (an der Leine ums Haus). Waehrend des Zauberns steht die Hexe.
const WANDER_RADIUS := 58.0
const WALK_SPEED := 26.0
var _home := Vector2.ZERO
var _wtarget := Vector2.ZERO
var _wwait := 0.0
static var _tex_cache: Dictionary = {}

signal died


static func tex(kind: String, dir: int) -> Texture2D:
	var key := "%s#%d" % [kind, dir % 8]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var t: Texture2D = load("%s%s_%s.png" % [BASE, kind, DIR_FILE[dir % 8]])
	_tex_cache[key] = t
	return t


static func create(p_world, p_player, p_pos: Vector2):
	var m = new()
	m.world = p_world
	m.player = p_player
	m.global_position = p_pos
	return m


func _ready() -> void:
	add_to_group("mage")
	z_index = IsoWorld.TALL_Z_INDEX + 1
	_body = Sprite2D.new()
	_body.centered = false
	_body.offset = ART_OFFSET
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)
	_update_dir()
	_refresh_body()
	# Heraustreten: einblenden + ein Stueck aus der Tuer nach vorn.
	modulate.a = 0.0
	var start := global_position + Vector2(0, -6)
	global_position = start
	_home = start + Vector2(0, 18)     # Leine-Mittelpunkt vor dem Haus
	_wtarget = _home
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.5)
	tw.tween_property(self, "global_position", _home, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _dir_index(v: Vector2) -> int:
	# Iso: y stauchen, dann in 8 Sektoren. 0=Sued, im Uhrzeigersinn.
	var a := atan2(-v.x, v.y * 2.0)      # 0 = nach Sueden (unten)
	var idx := int(round(a / (PI / 4.0))) % 8
	return (idx + 8) % 8


func _update_dir() -> void:
	if is_instance_valid(player):
		_dir = _dir_index(player.global_position - global_position)


func _refresh_body() -> void:
	var kind := "cast" if _cast_left > 0.0 else "idle"
	_body.texture = tex(kind, _dir)
	_body.scale = Vector2(SCALE, SCALE)
	_body.modulate = Color(1.6, 1.2, 1.2) if _hit_flash > 0.0 else Color(1, 1, 1)


func _process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(player):
		return
	if _cast_left > 0.0:
		_cast_left -= delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
	# Schiessen, wenn der Spieler in Reichweite ist.
	var dist := global_position.distance_to(player.global_position)
	_cooldown -= delta
	if dist <= SHOOT_RANGE and _cooldown <= 0.0:
		_shoot()
		_cooldown = SHOOT_INTERVAL
	# Waehrend des Zauberns steht die Hexe und schaut den Spieler an; sonst
	# schlendert sie an der Leine umher (schaut in Laufrichtung).
	if _cast_left > 0.0:
		_update_dir()
	else:
		_wander(delta)
	_refresh_body()
	queue_redraw()


## Zufaelliges Umherschlendern um _home (kleine Leine), auf begehbarem Boden.
func _wander(delta: float) -> void:
	_wwait -= delta
	if _wwait <= 0.0 or global_position.distance_to(_wtarget) < 4.0:
		_pick_wander()
	var to := _wtarget - global_position
	if to.length() > 2.0:
		global_position += to.normalized() * WALK_SPEED * delta
		_dir = _dir_index(to)             # Blick in Laufrichtung (Iso in _dir_index)
	else:
		_update_dir()


func _pick_wander() -> void:
	for i in 6:
		var ang := randf() * TAU
		var r := randf() * WANDER_RADIUS
		var p := _home + Vector2(cos(ang) * r, sin(ang) * r * 0.55)   # Iso-Ellipse
		if world.top_level_at(world.world_to_cell(p, 0)) >= 0:        # Boden vorhanden
			_wtarget = p
			break
	_wwait = randf_range(1.2, 2.8)


func _shoot() -> void:
	_cast_left = CAST_SHOW
	var from := global_position + Vector2(0, -22)   # etwa auf Stabhoehe
	var orb = Orb.new()
	get_parent().add_child(orb)
	orb.setup(from, player)


## Nahkampf-Treffer (Messer/Schwert). `dmg` Schaden.
func take_damage(dmg: float) -> void:
	if _dead:
		return
	hp -= dmg
	_hit_flash = 0.12
	if hp <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	died.emit()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_property(_body, "position:y", -14.0, 0.5)
	tw.chain().tween_callback(queue_free)


## Lebensleiste ueber dem Kopf (rot), solange nicht voll und lebendig.
func _draw() -> void:
	if _dead or hp >= MAX_HP:
		return
	var w := 34.0
	var h := 5.0
	var top := ART_OFFSET.y - 12.0
	var x := -w * 0.5
	draw_rect(Rect2(x - 1, top - 1, w + 2, h + 2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(x, top, w, h), Color(0.2, 0.05, 0.05, 0.9))
	draw_rect(Rect2(x, top, w * clampf(hp / MAX_HP, 0.0, 1.0), h), Color(0.85, 0.2, 0.2, 1.0))
