extends Node

## Verbindet im laufenden Spiel den lokalen Spieler mit dem Netzwerk.
##
## Jeder Rechner steuert seinen EIGENEN Player aus main.tscn (Tastatur/Maus
## wie gehabt) und sendet dessen Position + Animation regelmaessig an alle
## anderen. Umgekehrt bekommt er die Zustaende der anderen und zeigt sie als
## RemotePlayer an. So sieht jeder jeden laufen, ohne dass am bestehenden
## Einzelspieler-Code etwas kaputtgeht.
##
## Im Einzelspieler (Net.active == false) haelt sich dieser Node komplett raus.

const RemotePlayerScript := preload("res://scripts/remote_player.gd")
## Wie oft pro Sekunde der eigene Zustand verschickt wird. 15 reicht fuer
## fluessig wirkende Bewegung und haelt die Last klein.
const SEND_HZ := 15.0

var _local: Player
var _world: IsoWorld
var _avatars: Dictionary = {}     ## peer_id -> RemotePlayer
var _accum := 0.0


func _ready() -> void:
	_world = get_node_or_null(^"../World") as IsoWorld
	_local = get_tree().get_first_node_in_group("player") as Player

	if not Net.active:
		return                       # Einzelspieler: nichts zu tun

	# Eigenen Namen ueber die Figur haengen.
	if _local:
		var plate := _local.get_node_or_null(^"NamePlate") as NamePlate
		if plate:
			plate.player_name = Net.player_name

	multiplayer.peer_disconnected.connect(_on_peer_left)


func _process(delta: float) -> void:
	if not Net.active or _local == null:
		return
	_accum += delta
	if _accum < 1.0 / SEND_HZ:
		return
	_accum = 0.0
	var sprite := _local.get_node_or_null(^"Sprite") as AnimatedSprite2D
	if sprite == null:
		return
	_recv_state.rpc(Net.player_name, _local.global_position,
		sprite.animation, sprite.frame)


## Zustand eines anderen Spielers. Unreliable, weil bei 15 Paketen/s ein
## verlorenes egal ist - das naechste ist gleich da.
@rpc("any_peer", "unreliable")
func _recv_state(pname: String, pos: Vector2, anim: StringName, frame: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var av: RemotePlayer = _avatars.get(id)
	if av == null:
		av = _spawn_avatar(id)
		if av == null:
			return
	av.set_player_name(pname)
	av.apply_state(pos, anim, frame)


func _spawn_avatar(id: int) -> RemotePlayer:
	if _world == null or _world.props_root == null:
		return null                  # Welt noch nicht bereit - naechstes Paket
	var av: RemotePlayer = RemotePlayerScript.new()
	_world.props_root.add_child(av)
	_avatars[id] = av
	return av


func _on_peer_left(id: int) -> void:
	var av: RemotePlayer = _avatars.get(id)
	if av and is_instance_valid(av):
		av.queue_free()
	_avatars.erase(id)
