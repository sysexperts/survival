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

## Server: owner_id -> {name, pos}. Aus den Status-Paketen gefuellt, damit
## Admin-Befehle (/tp) Spieler ueber ihren Namen finden und ihre Position kennen.
var _server_states: Dictionary = {}


func _ready() -> void:
	add_to_group("net_game")
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
		_local.global_position, sprite.animation, sprite.frame,
		_local.held_tool, _local.held_metal)


## Zustand eines Spielers. Unreliable - bei 15 Paketen/s ist ein verlorenes egal.
## tool/metal = gehaltenes Werkzeug (Pack-Layer + Metall), "" = leere Hand.
@rpc("any_peer", "unreliable")
func _recv_state(owner_id: int, pname: String, pos: Vector2, anim: StringName, frame: int, tool: String, metal: String) -> void:
	# Server: an alle anderen Clients weiterreichen, selbst nichts anzeigen.
	if Net.is_dedicated:
		# Fuer Admin-Befehle merken, wer wo steht (Name -> Peer -> Position).
		_server_states[owner_id] = {"name": pname, "pos": pos}
		for pid in multiplayer.get_peers():
			if pid != owner_id:
				_recv_state.rpc_id(pid, owner_id, pname, pos, anim, frame, tool, metal)
		return

	if owner_id == multiplayer.get_unique_id():
		return                       # das eigene Echo ignorieren
	var av: RemotePlayer = _avatars.get(owner_id)
	if av == null:
		av = _spawn_avatar(owner_id)
		if av == null:
			return
	av.set_player_name(pname)
	av.apply_state(pos, anim, frame, tool, metal)


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
	av.owner_id = id
	_world.props_root.add_child(av)
	_avatars[id] = av
	# Aussehen schon bekannt? Dann direkt anwenden.
	if _looks.has(id):
		av.set_look(_looks[id])
	return av


func _on_peer_left(id: int) -> void:
	if Net.is_dedicated:
		_server_states.erase(id)
		# Allen verbleibenden Clients sagen: dieser Spieler ist weg.
		_despawn.rpc(id)
		return
	_remove_avatar(id)


# --- Admin: Teleport (server-autoritativ) --------------------------------

## Server: Peer-Id zu einem Spielernamen (unscharf, Gross/Klein egal), oder -1.
## Der eigene Server-Prozess spielt nicht mit und taucht daher nicht auf.
func peer_id_of_name(pname: String) -> int:
	var want := pname.strip_edges().to_lower()
	for id in _server_states:
		if String(_server_states[id].get("name", "")).strip_edges().to_lower() == want:
			return id
	return -1


## Server: letzte bekannte Weltposition eines Peers.
func peer_pos(id: int) -> Vector2:
	return _server_states.get(id, {}).get("pos", Vector2.ZERO)


## Server: alle bekannten Spielernamen (fuer Fehlermeldungen).
func known_names() -> Array:
	var out: Array = []
	for id in _server_states:
		out.append(String(_server_states[id].get("name", "")))
	return out


# --- Belegte Betten (damit nicht zwei im selben Bett liegen) --------------

## owner_id -> Bett-Ankerzelle, in dem dieser Spieler gerade liegt. Auf jedem
## Client gefuehrt (eigener + fremde), damit man vor dem Hinlegen pruefen kann.
var _occupied_beds: Dictionary = {}
const NO_BED := Vector2i(2147483647, 2147483647)


## Liegt in diesem Bett schon EIN ANDERER Spieler? (Der eigene zaehlt nicht.)
func is_bed_taken(cell: Vector2i) -> bool:
	if not Net.active:
		return false
	var me := multiplayer.get_unique_id()
	for id in _occupied_beds:
		if id != me and _occupied_beds[id] == cell:
			return true
	return false


## Meldet allen, in welchem Bett der lokale Spieler jetzt liegt (NO_BED = steht auf).
func set_my_bed(cell: Vector2i) -> void:
	if Net.is_dedicated or not Net.active:
		return
	_recv_bed.rpc(multiplayer.get_unique_id(), cell)


@rpc("any_peer", "reliable")
func _recv_bed(owner_id: int, cell: Vector2i) -> void:
	# Belegung ueberall mitfuehren - auch am Server, damit er die Mehrheit kennt.
	if cell == NO_BED:
		_occupied_beds.erase(owner_id)
	else:
		_occupied_beds[owner_id] = cell
	# Server: an die anderen weiterreichen und pruefen, ob die Mehrheit schlaeft.
	if Net.is_dedicated:
		for pid in multiplayer.get_peers():
			if pid != owner_id:
				_recv_bed.rpc_id(pid, owner_id, cell)
		_maybe_sleep_skip()


## Server: Schlafen die MEISTEN Spieler und ist es Nacht? Dann den Morgen
## einleiten (Zeit auf Morgen setzen + allen Clients die Ueberblendung sagen).
func _maybe_sleep_skip() -> void:
	if not Net.is_dedicated:
		return
	var total := multiplayer.get_peers().size()
	if total <= 0:
		return
	if _occupied_beds.size() * 2 <= total:   # keine Mehrheit
		return
	var day := get_tree().get_first_node_in_group("day_night")
	if day == null or not day.has_method("is_night") or not day.is_night():
		return
	# Zeit sofort auf Morgen (autoritativ) - dadurch ist is_night() danach false
	# und es feuert nicht doppelt. Die Clients blenden weich dorthin.
	day.time_of_day = day.MORNING
	_sleep_skip_now.rpc()


## Server -> alle Clients: weiche Ueberblendung zum Morgen + Banner + Aufwachen.
@rpc("authority", "call_remote", "reliable")
func _sleep_skip_now() -> void:
	if Net.is_dedicated:
		return
	var day := get_tree().get_first_node_in_group("day_night")
	if day != null and day.has_method("skip_to_morning"):
		day.skip_to_morning()
	var ann := get_tree().get_first_node_in_group("announce")
	if ann != null and ann.has_method("flash"):
		ann.flash("Gunaydin!  Yeni bir gun basliyor")
	var wait: float = day.SKIP_SECONDS if day != null else 2.6
	await get_tree().create_timer(wait).timeout
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("wake"):
		pl.wake()


## Server -> gezielter Client: setzt dessen lokale Figur an eine Weltposition.
func teleport_peer(target_id: int, pos: Vector2) -> void:
	_do_teleport.rpc_id(target_id, pos)


@rpc("authority", "call_remote", "reliable")
func _do_teleport(pos: Vector2) -> void:
	if _local and is_instance_valid(_local) and _local.has_method("teleport_to"):
		_local.teleport_to(pos)


@rpc("any_peer", "reliable")
func _despawn(owner_id: int) -> void:
	_remove_avatar(owner_id)


func _remove_avatar(id: int) -> void:
	var av: RemotePlayer = _avatars.get(id)
	if av and is_instance_valid(av):
		av.queue_free()
	_avatars.erase(id)
	_occupied_beds.erase(id)


## Owner-ID (Peer) des naechsten Remote-Avatars innerhalb `radius` um `point`
## (Weltkoordinaten), oder 0. Fuer das Aufhelfen eines bewusstlosen Mitspielers.
func avatar_owner_near(point: Vector2, radius: float) -> int:
	var best := 0
	var best_d := radius
	for oid in _avatars:
		var av = _avatars[oid]
		if av == null or not is_instance_valid(av):
			continue
		var d: float = av.global_position.distance_to(point)
		if d <= best_d:
			best_d = d
			best = int(oid)
	return best


## Der Remote-Avatar zu einer Owner-ID (oder null).
func avatar_node(owner_id: int):
	return _avatars.get(owner_id)
