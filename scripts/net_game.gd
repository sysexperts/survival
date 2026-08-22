extends Node

## Verbindet im laufenden Spiel den lokalen Spieler mit dem Netzwerk.
##
## Drei Rollen, je nach Start:
##   * Client (normaler Spieler): sendet Position + Animation der eigenen Figur
##     und zeigt die anderen als RemotePlayer an.
##   * Dedizierter Server (Net.is_dedicated): spielt NICHT mit, sondern leitet
##     die Pakete der Clients untereinander weiter (Relay) - in der
##     Client/Server-Topologie sind Clients nur mit dem Server verbunden, nicht
##     direkt miteinander.
##   * Einzelspieler (Net.active == false): haelt sich komplett raus.
##
## Jedes Paket traegt die owner_id (die Peer-ID des Absenders) explizit mit,
## damit auch WEITERGELEITETE Pakete beim Empfaenger korrekt der richtigen
## Figur zugeordnet werden - get_remote_sender_id() waere dann der Server.

const RemotePlayerScript := preload("res://scripts/remote_player.gd")
## Wie oft pro Sekunde der eigene Zustand verschickt wird.
const SEND_HZ := 15.0

var _local: Player
var _world: IsoWorld
var _avatars: Dictionary = {}     ## owner_id -> RemotePlayer
var _accum := 0.0


func _ready() -> void:
	_world = get_node_or_null(^"../World") as IsoWorld
	_local = get_tree().get_first_node_in_group("player") as Player

	if not Net.active:
		return                       # Einzelspieler: nichts zu tun

	if Net.is_dedicated:
		print("NetGame: Relay-Modus aktiv.")
	elif _local:
		var plate := _local.get_node_or_null(^"NamePlate") as NamePlate
		if plate:
			plate.player_name = Net.player_name

	multiplayer.peer_disconnected.connect(_on_peer_left)


func _process(delta: float) -> void:
	# Der dedizierte Server sendet keine eigene Figur.
	if Net.is_dedicated or not Net.active or _local == null:
		return
	_accum += delta
	if _accum < 1.0 / SEND_HZ:
		return
	_accum = 0.0
	var sprite := _local.get_node_or_null(^"Sprite") as AnimatedSprite2D
	if sprite == null:
		return
	_recv_state.rpc(multiplayer.get_unique_id(), Net.player_name,
		_local.global_position, sprite.animation, sprite.frame)


## Zustand eines Spielers. Unreliable - bei 15 Paketen/s ist ein verlorenes egal.
@rpc("any_peer", "unreliable")
func _recv_state(owner_id: int, pname: String, pos: Vector2, anim: StringName, frame: int) -> void:
	# Server: an alle anderen Clients weiterreichen, selbst nichts anzeigen.
	if Net.is_dedicated:
		for pid in multiplayer.get_peers():
			if pid != owner_id:
				_recv_state.rpc_id(pid, owner_id, pname, pos, anim, frame)
		return

	if owner_id == multiplayer.get_unique_id():
		return                       # das eigene Echo ignorieren
	var av: RemotePlayer = _avatars.get(owner_id)
	if av == null:
		av = _spawn_avatar(owner_id)
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
	if Net.is_dedicated:
		# Allen verbleibenden Clients sagen: dieser Spieler ist weg.
		_despawn.rpc(id)
		return
	_remove_avatar(id)


@rpc("any_peer", "reliable")
func _despawn(owner_id: int) -> void:
	_remove_avatar(owner_id)


func _remove_avatar(id: int) -> void:
	var av: RemotePlayer = _avatars.get(id)
	if av and is_instance_valid(av):
		av.queue_free()
	_avatars.erase(id)
