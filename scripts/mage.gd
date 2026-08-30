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
## Bewegung: verfolgt den Spieler bis zur Leine (LEASH_MAX vom Haus-Posten),
## haelt dabei CHASE_STOP Abstand (zum Schiessen). Geht der Spieler zu weit weg,
## kehrt sie zum Haus zurueck und verschwindet hinein.
const WALK_SPEED := 42.0          ## Verfolgungstempo
const RETURN_SPEED := 50.0        ## Rueckweg zum Haus
const LEASH_MAX := 240.0          ## so weit vom Posten folgt sie hoechstens
const CHASE_STOP := 70.0          ## Wunschabstand zum Spieler (bleibt zurueck)
var _home := Vector2.ZERO         ## Posten vor dem Haus
var _returning := false
static var _tex_cache: Dictionary = {}

## died -> vom Spieler getoetet (Haus: 30 min Sperre). retreated -> zurueck ins
## Haus gegangen (Haus darf sofort wieder einen schicken).
signal died
signal retreated


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
	_home = start + Vector2(0, 46)     # Posten deutlich VOR dem Haus
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.5)
	tw.tween_property(self, "global_position", _home, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _dir_index(v: Vector2) -> int:
	# 8 Sektoren, 0 = Sued (unten), im Uhrzeigersinn. y verdoppelt (Iso 2:1).
	var a := atan2(v.x, v.y * 2.0)       # 0 = nach Sueden, +x = Osten
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
	# IMMER Blickkontakt zum Spieler. Beim Zaubern steht sie.
	_update_dir()
	if _cast_left <= 0.0:
		_move(delta)
	_refresh_body()
	queue_redraw()


## Verfolgt den Spieler (bis zur Leine) oder kehrt zum Haus zurueck.
func _move(delta: float) -> void:
	var player_from_home: float = player.global_position.distance_to(_home)
	# Spieler zu weit weg -> heimkehren; kommt er wieder nah, Verfolgung aufnehmen.
	if _returning and player_from_home < LEASH_MAX * 0.7:
		_returning = false
	if _returning or player_from_home > LEASH_MAX:
		_returning = true
		var toh := _home - global_position
		if toh.length() < 8.0:
			_go_inside()
			return
		_step(toh.normalized() * RETURN_SPEED * delta)
		return
	# Verfolgen bis CHASE_STOP; naeher nicht (dann stehen bleiben und zaubern).
	var toP: Vector2 = player.global_position - global_position
	if toP.length() > CHASE_STOP:
		var stepv: Vector2 = toP.normalized() * WALK_SPEED * delta
		# Nicht ueber die Leine hinaus.
		if (global_position + stepv).distance_to(_home) <= LEASH_MAX:
			_step(stepv)


## Ein Bewegungsschritt, aber nicht auf blockierte/lochige Zellen.
func _step(v: Vector2) -> void:
	var np := global_position + v
	var cell: Vector2i = world.world_to_cell(np, 0)
	if world.top_level_at(cell) > world.NO_FLOOR and world.blocker_at(cell) == null \
			and not world.is_water(cell):
		global_position = np


## Zurueck ins Haus: einblenden-weg + hoch (in die Tuer), dann verschwinden.
func _go_inside() -> void:
	if _dead:
		return
	_dead = true                 # keine weitere Logik/Schuesse mehr
	retreated.emit()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_property(self, "global_position:y", global_position.y - 20.0, 0.4)
	tw.chain().tween_callback(queue_free)


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
