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
const AdminsScript := preload("res://scripts/admins.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")
## Wie oft pro Sekunde der eigene Zustand verschickt wird.
const SEND_HZ := 15.0

var _local: Player
var _world: IsoWorld
var _avatars: Dictionary = {}     ## owner_id -> RemotePlayer
var _looks: Dictionary = {}       ## owner_id -> Aussehen-Dictionary
var _accum := 0.0

## TAB-Spielerliste (wie in Minecraft), nur solange TAB gehalten wird.
var _tab_layer: CanvasLayer
var _tab_panel: PanelContainer
var _tab_list: VBoxContainer


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

	if not Net.is_dedicated:
		_build_tab_list()
		# Eigenes Aussehen bekanntgeben und bei jedem neuen Mitspieler erneut
		# senden, damit auch spätere Beitretende die richtige Figur sehen.
		multiplayer.peer_connected.connect(func(_id): broadcast_look())
		broadcast_look.call_deferred()


## Sendet das Aussehen des lokalen Spielers an alle. Ruft die UI nach jeder
## Änderung im Görünüm-Editor auf.
func broadcast_look() -> void:
	if Net.is_dedicated or not Net.active:
		return
	_recv_look.rpc(multiplayer.get_unique_id(), AppearanceStore.local())


## Aussehen eines Spielers. Selten - deshalb reliable.
@rpc("any_peer", "reliable")
func _recv_look(owner_id: int, look: Dictionary) -> void:
	if Net.is_dedicated:
		for pid in multiplayer.get_peers():
			if pid != owner_id:
				_recv_look.rpc_id(pid, owner_id, look)
		return
	if owner_id == multiplayer.get_unique_id():
		return
	_looks[owner_id] = look
	var av: RemotePlayer = _avatars.get(owner_id)
	if av and is_instance_valid(av):
		av.set_look(look)


# --- TAB-Spielerliste ----------------------------------------------------

func _build_tab_list() -> void:
	_tab_layer = CanvasLayer.new()
	_tab_layer.layer = 120
	add_child(_tab_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_layer.add_child(center)
	_tab_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.88)
	style.border_color = Color(0.35, 0.37, 0.45, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	_tab_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_tab_panel)
	_tab_list = VBoxContainer.new()
	_tab_list.add_theme_constant_override("separation", 4)
	_tab_list.custom_minimum_size = Vector2(200, 0)
	_tab_panel.add_child(_tab_list)
	_tab_layer.visible = false


func _input(event: InputEvent) -> void:
	if _tab_layer == null or not (event is InputEventKey) or event.echo:
		return
	if event.keycode != KEY_TAB:
		return
	# TAB haelt die Liste offen; loslassen schliesst sie. accept, damit TAB
	# nicht den UI-Fokus weiterschaltet.
	if event.pressed:
		_refresh_tab_list()
		_tab_layer.visible = true
	else:
		_tab_layer.visible = false
	get_viewport().set_input_as_handled()


func _refresh_tab_list() -> void:
	for c in _tab_list.get_children():
		c.queue_free()
	# Namen sammeln: eigener zuerst, dann die Mitspieler.
	var names: Array = [Net.player_name]
	for av in _avatars.values():
		if is_instance_valid(av) and av.pname != "":
			names.append(av.pname)
	var title := Label.new()
	title.text = "Oyuncular (%d)" % names.size()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	_tab_list.add_child(title)
	for n in names:
		var l := Label.new()
		l.text = n
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Admins golden hervorheben.
		if AdminsScript.is_admin(n):
			l.add_theme_color_override("font_color", Color(1, 0.84, 0.3))
		_tab_list.add_child(l)


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


## Weltpositionen aller sichtbaren Spieler (eigener + Mitspieler). Der
## Deer-Host spawnt darueber Rehe in der Naehe JEDES Spielers.
func all_player_positions() -> Array:
	var out: Array = []
	if _local and is_instance_valid(_local):
		out.append(_local.global_position)
	for av in _avatars.values():
		if is_instance_valid(av):
			out.append(av.global_position)
	return out


func _spawn_avatar(id: int) -> RemotePlayer:
	if _world == null or _world.props_root == null:
		return null                  # Welt noch nicht bereit - naechstes Paket
	var av: RemotePlayer = RemotePlayerScript.new()
	_world.props_root.add_child(av)
	_avatars[id] = av
	# Aussehen schon bekannt? Dann direkt anwenden.
	if _looks.has(id):
		av.set_look(_looks[id])
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
