extends Node2D

## Client-Darstellung eines server-simulierten Gegners (Magier). Bekommt Position/
## Richtung/Leben vom Server (enemy_sync) und zeigt Sprite + Lebensleiste. Selbst
## KEINE KI - nur Anzeige. Nahkampf-Treffer meldet er an den Server weiter.
##
## KEIN class_name (Auto-Updater) - per preload eingebunden.

const MageScript := preload("res://scripts/mage.gd")   # nutzt dessen tex()
const MAX_HP := 40.0
const ART_OFFSET := Vector2(-24, -42)

var enemy_id := -1
var sync: Node = null            ## enemy_sync (fuer Nahkampf-Meldung)
var hp := MAX_HP

var _body: Sprite2D
var _dir := 0
var _cast := false
var _tpos := Vector2.ZERO
var _have_pos := false


func _ready() -> void:
	add_to_group("mage")         # interaction.attack_mage findet Gegner ueber diese Gruppe
	z_index = IsoWorld.TALL_Z_INDEX + 1
	_body = Sprite2D.new()
	_body.centered = false
	_body.offset = ART_OFFSET
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)
	_refresh()


## Zustand vom Server: Zielposition (wird weich angefahren), Richtung, Cast, Leben.
func set_state(pos: Vector2, dir: int, cast: bool, p_hp: float) -> void:
	_tpos = pos
	if not _have_pos:
		global_position = pos
		_have_pos = true
	_dir = dir
	_cast = cast
	hp = p_hp
	_refresh()
	queue_redraw()


func _process(delta: float) -> void:
	if _have_pos:
		global_position = global_position.lerp(_tpos, 1.0 - exp(-14.0 * delta))


func _refresh() -> void:
	_body.texture = MageScript.tex("cast" if _cast else "idle", _dir)


## Nahkampf-Treffer (Messer/Schwert): an den Server melden, der rechnet Schaden.
func take_damage(dmg: float) -> void:
	if sync != null and sync.has_method("hit_enemy"):
		sync.hit_enemy(enemy_id, dmg)


## Sanftes Ausblenden beim Tod, dann weg.
func die_out() -> void:
	set_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_property(_body, "position:y", -14.0, 0.5)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	if hp >= MAX_HP:
		return
	var w := 34.0
	var h := 5.0
	var top := ART_OFFSET.y - 12.0
	var x := -w * 0.5
	draw_rect(Rect2(x - 1, top - 1, w + 2, h + 2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(x, top, w, h), Color(0.2, 0.05, 0.05, 0.9))
	draw_rect(Rect2(x, top, w * clampf(hp / MAX_HP, 0.0, 1.0), h), Color(0.85, 0.2, 0.2, 1.0))
