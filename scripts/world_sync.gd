extends Node

## Synchronisiert Welt-Veraenderungen zwischen den Spielern:
## Abbau (Baum faellen, Stumpf raeumen, Stein aufheben) UND Bauen
## (Lagerfeuer, Moebel).
##
## Die Welt ist auf allen Rechnern ueber denselben Seed identisch. Es genuegt
## also, die EREIGNISSE zu verteilen - jeder Client wendet dieselbe Aenderung
## an und bleibt im Gleichschritt.
##
## Der ausloesende Spieler hat die Aenderung lokal bereits gemacht (und beim
## Abbau sein Inventar gefuellt bzw. beim Bauen sein Item verbraucht). Bei den
## ANDEREN wird nur die Welt angepasst - kein Inventar, kein Item-Abzug.
##
## Der dedizierte Server spielt nicht mit: er leitet die Ereignisse nur weiter.
##
## PERSISTENZ (Bauten): Weil die Welt nur im RAM der verbundenen Clients lebt,
## verschwaende ohne diesen Teil jeder Server-Neustart alles Gebaute - und ein
## neu beitretender Spieler saehe nichts, was vor ihm gebaut wurde. Der Server
## fuehrt deshalb ein Register aller gesetzten Moebel/Lagerfeuer, schreibt es
## auf Platte (BUILD_FILE) und spielt es jedem Client beim Beitritt vor.
## (Abbau/Sammeln wird noch NICHT persistiert - gefaellte Baeume wachsen ohnehin
## nach; das gehoert zum offenen Chunk-Diff, Milestone 3 in AGENTS.md.)

const BUILD_DIR := "/opt/survival_world"
const BUILD_FILE := BUILD_DIR + "/build.json"
const REMOVED_FILE := BUILD_DIR + "/removed.json"
## Nachwachs-Zeiten - muessen zu den Defaults in regrowth.gd passen. Der Server
## rechnet damit die Restzeit aus und laesst Abgelaufenes weg.
const REGROW_SECONDS := 300.0
const STONE_SECONDS := 240.0
## Lebenspunkte eines Baums (Axtschlaege bis er faellt). GETEILT ueber alle
## Spieler - schlagen zwei am selben Baum, faellt er doppelt so schnell.
const TREE_MAX_HP := 6

var _world: IsoWorld
var _regrowth: Node
var _player: Player
## Verhindert, dass ein fremdes Bau-Ereignis, das wir lokal anwenden, gleich
## wieder als eigenes weiterverteilt wird (place_* feuert dieselben Signale).
var _suppress := false

## Server: alle bisher gesetzten Bauten. Je Eintrag {kind, x, y, id, flipped}.
var _builds: Array = []
## Server: alle Abbau-Ereignisse, je Zelle EINES (das jeweils letzte).
## Schluessel "x,y" -> {kind, x, y, level, ax, ay, gid, t}. t = Unix-Zeit.
var _removed: Dictionary = {}
## Client: vom Server empfangene Bauten, die noch nicht gesetzt werden konnten
## (der Chunk ist evtl. noch nicht geladen). Werden in _process nachgezogen.
var _pending: Array = []
## Server: geteilte Baum-HP je Zelle (Vector2i -> int).
var _tree_hp: Dictionary = {}
## Client: Inventar, um dem toedlichen Schlaeger Holz gutzuschreiben.
var _pinv: Node


func _ready() -> void:
	if not Net.active:
		return
	_world = get_node_or_null(^"../World") as IsoWorld
	_regrowth = get_node_or_null(^"../Regrowth")
	if Net.is_dedicated:
		_load_builds()               # Register vom letzten Lauf wiederherstellen
		_load_removed()
		multiplayer.peer_connected.connect(_on_peer_joined)
		return                       # Server: nur weiterleiten + persistieren
	_pinv = get_node_or_null(^"../Inventory")
	_ensure_player()
	# Ein Frame warten, damit Welt + Spieler stehen, dann den Bau-Stand des
	# Servers anfordern (analog save_sync fuer das Inventar).
	await get_tree().process_frame
	print("WorldSync(client): fordere Bau-Stand an")
	_request_builds.rpc_id(1)


## Holt den Spieler-Node (Gruppe "player") und verbindet die lokalen Signale -
## einmalig. Bewusst nachziehbar: beim Beitritt kann der Spieler beim ersten
## Versuch noch nicht in der Gruppe stehen; sonst bliebe _player fuer immer null
## und das Replay (das ihn zum Setzen braucht) liefe ins Leere.
func _ensure_player() -> bool:
	if _player != null:
		return true
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		return false
	_player.felled.connect(_on_local_felled)
	_player.stump_cleared.connect(_on_local_stump_cleared)
	_player.stone_collected.connect(_on_local_stone_collected)
	_player.placed_campfire.connect(_on_local_campfire)
	_player.placed_furniture.connect(_on_local_furniture)
	_player.destroyed_placed.connect(_on_local_destroy)
	return true


## Client: noch nicht platzierbare Bauten erneut versuchen. Solange der Chunk
## einer weit entfernten Baute nicht geladen ist, schlaegt place_* fehl - der
## Eintrag bleibt liegen und wird gesetzt, sobald der Spieler hinlaeuft.
func _process(_delta: float) -> void:
	if _pending.is_empty() or _world == null or not _ensure_player():
		return
	var still: Array = []
	for b in _pending:
		if not _apply_build(b):
			still.append(b)
	_pending = still


# --- lokale Aktionen -> an alle senden -----------------------------------

func _on_local_felled(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	_event.rpc(multiplayer.get_unique_id(), "fell", cell, level, atlas, "", false)


func _on_local_stump_cleared(cell: Vector2i) -> void:
	_event.rpc(multiplayer.get_unique_id(), "stump", cell, 0, Vector2i.ZERO, "", false)


func _on_local_stone_collected(cell: Vector2i, level: int, gather_id: String) -> void:
	_event.rpc(multiplayer.get_unique_id(), "stone", cell, level, Vector2i.ZERO, gather_id, false)


func _on_local_campfire(top: Vector2i) -> void:
	if _suppress:
		return
	_event.rpc(multiplayer.get_unique_id(), "campfire", top, 0, Vector2i.ZERO, "", false)


func _on_local_furniture(id: String, cell: Vector2i, flipped: bool) -> void:
	if _suppress:
		return
	_event.rpc(multiplayer.get_unique_id(), "furniture", cell, 0, Vector2i.ZERO, id, flipped)


func _on_local_destroy(cell: Vector2i) -> void:
	if _suppress:
		return
	_event.rpc(multiplayer.get_unique_id(), "destroy", cell, 0, Vector2i.ZERO, "", false)


# --- Empfang -------------------------------------------------------------

@rpc("any_peer", "reliable")
func _event(owner_id: int, kind: String, cell: Vector2i, level: int, atlas: Vector2i, s: String, flag: bool) -> void:
	# Server: Bauten ins Register aufnehmen (ueberleben den Neustart) und an
	# alle anderen Clients weiterreichen.
	if Net.is_dedicated:
		if kind == "furniture":
			_record_build({"kind": "furniture", "x": cell.x, "y": cell.y, "id": s, "flipped": flag})
		elif kind == "campfire":
			_record_build({"kind": "campfire", "x": cell.x, "y": cell.y, "id": "", "flipped": false})
		elif kind == "destroy":
			_remove_build(cell)
		elif kind == "fell" or kind == "stump" or kind == "stone":
			_record_removal(kind, cell, level, atlas, s)
		for pid in multiplayer.get_peers():
			if pid != owner_id:
				_event.rpc_id(pid, owner_id, kind, cell, level, atlas, s, flag)
		return

	if owner_id == multiplayer.get_unique_id():
		return                       # eigene Aktion, schon lokal erledigt
	if _world == null:
		return
	match kind:
		"fell":
			_remove_tree(cell, level)
			if _regrowth:
				_regrowth.replicate_felled(cell, level, atlas)
		"stump":
			_world.remove_prop(cell, level)
			if _regrowth:
				_regrowth.replicate_stump_cleared(cell)
		"stone":
			_world.remove_prop(cell, level)
			if _regrowth:
				_regrowth.replicate_stone_collected(cell, level, s)
		"campfire":
			if _player:
				_suppress = true
				_player.place_campfire_at(cell)
				_suppress = false
		"furniture":
			if _player:
				_suppress = true
				_player.place_furniture_at(ItemDB.canonical(s), cell, flag)
				_suppress = false
		"destroy":
			# Bei einem anderen Spieler abgerissen -> lokal auch entfernen.
			if _player:
				_suppress = true
				_player._do_destroy(cell)
				_suppress = false


# --- Bau-Persistenz (Server) + Replay (Client) ---------------------------

## Server: ein Client ist beigetreten - noch nichts tun. Der Client fordert den
## Bau-Stand selbst an (_request_builds), sobald seine Welt bereit ist; das ist
## robuster, als sofort zu senden, wenn dort evtl. noch nichts steht.
func _on_peer_joined(_id: int) -> void:
	pass


## Client -> Server: "schick mir alle Bauten". Der Server antwortet fuer jede
## gemerkte Baute mit _spawn_build.
@rpc("any_peer", "reliable")
func _request_builds() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	print("WorldSync(server): sende %d Bauten, %d Abbauten an peer %d" % [_builds.size(), _removed.size(), id])
	for b in _builds:
		_spawn_build.rpc_id(id, b["kind"], Vector2i(b["x"], b["y"]), String(b["id"]), bool(b["flipped"]))
	# Abbau-Ereignisse mit der jeweiligen RESTZEIT senden; Abgelaufenes (Baum
	# nachgewachsen, Stein wieder da) ueberspringen.
	var now := Time.get_unix_time_from_system()
	for key in _removed:
		var r: Dictionary = _removed[key]
		var remaining := _remaining(r, now)
		if remaining <= 0.0:
			continue
		_spawn_removal.rpc_id(id, String(r["kind"]), Vector2i(int(r["x"]), int(r["y"])),
			int(r["level"]), Vector2i(int(r["ax"]), int(r["ay"])), String(r["gid"]), remaining)


## Server -> Client: eine gemerkte Baute setzen. Kommt der Chunk nicht sofort
## mit, landet sie in _pending und wird spaeter nachgezogen.
@rpc("any_peer", "reliable")
func _spawn_build(kind: String, cell: Vector2i, id: String, flipped: bool) -> void:
	var b := {"kind": kind, "x": cell.x, "y": cell.y, "id": id, "flipped": flipped}
	var ok := _apply_build(b)
	print("WorldSync(client): Baute %s '%s' @ %s -> %s" % [kind, id, cell, "gesetzt" if ok else "wartet auf Chunk"])
	if not ok:
		_pending.append(b)


## Setzt eine Baute lokal. true = gesetzt (oder steht schon da), false = ging
## gerade nicht (Chunk noch nicht bereit) und sollte erneut versucht werden.
func _apply_build(b: Dictionary) -> bool:
	if _world == null or not _ensure_player():
		return false
	var cell := Vector2i(int(b["x"]), int(b["y"]))
	# Steht dort schon etwas (z. B. beim erneuten Versuch nach Teil-Erfolg),
	# als erledigt werten - place_* wuerde nur an der Belegung scheitern.
	if _world.blocker_at(cell) != null:
		return true
	_suppress = true
	var ok: bool
	if b["kind"] == "campfire":
		ok = _player.place_campfire_at(cell)
	else:
		# Alte deutsche Moebel-Id (aus build.json) auf den neuen Namen heben.
		ok = _player.place_furniture_at(ItemDB.canonical(String(b["id"])), cell, bool(b["flipped"]))
	_suppress = false
	return ok


## Server: eine Baute ins Register aufnehmen und sofort sichern. Doppelte
## (dieselbe Zelle) werden nicht zweimal gespeichert.
func _record_build(b: Dictionary) -> void:
	for e in _builds:
		if e["x"] == b["x"] and e["y"] == b["y"]:
			return
	_builds.append(b)
	_save_builds()


## Server: einen Bau-Eintrag (per Ankerzelle) aus dem Register nehmen und
## sichern - damit ein abgerissenes Objekt nach dem Neustart wegbleibt.
func _remove_build(cell: Vector2i) -> void:
	var before := _builds.size()
	_builds = _builds.filter(func(e): return not (e["x"] == cell.x and e["y"] == cell.y))
	if _builds.size() != before:
		_save_builds()


func _save_builds() -> void:
	DirAccess.make_dir_recursive_absolute(BUILD_DIR)
	var f := FileAccess.open(BUILD_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_builds))
		f.close()


func _load_builds() -> void:
	if not FileAccess.file_exists(BUILD_FILE):
		return
	var f := FileAccess.open(BUILD_FILE, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_ARRAY:
		_builds = data
		print("WorldSync: %d Bauten aus %s geladen." % [_builds.size(), BUILD_FILE])


## Server -> Client: ein Abbau-Ereignis mit RESTZEIT wiederherstellen. Setzt bei
## Regrowth den Stumpf/die Uhr bzw. sperrt die Zelle - der ChunkManager fragt
## Regrowth beim Generieren, deshalb reicht das auch fuer noch nicht geladene
## Chunks (kein _pending noetig wie bei den Bauten).
@rpc("any_peer", "reliable")
func _spawn_removal(kind: String, cell: Vector2i, level: int, atlas: Vector2i, gid: String, remaining: float) -> void:
	if _regrowth == null:
		return
	match kind:
		"fell":
			_regrowth.restore_felled(cell, level, atlas, remaining)
		"stump":
			_regrowth.restore_cleared(cell)
		"stone":
			if gid == "":
				_regrowth.restore_stone_collected(cell, level, remaining)
			else:
				_regrowth.restore_cleared(cell)   # Chunk-Rohstoff: endgueltig weg


## Server: ein Abbau-Ereignis merken (je Zelle das letzte) und sichern.
func _record_removal(kind: String, cell: Vector2i, level: int, atlas: Vector2i, gid: String) -> void:
	_removed["%d,%d" % [cell.x, cell.y]] = {
		"kind": kind, "x": cell.x, "y": cell.y, "level": level,
		"ax": atlas.x, "ay": atlas.y, "gid": gid,
		"t": Time.get_unix_time_from_system(),
	}
	_save_removed()


## Restzeit eines Abbau-Eintrags in Sekunden. Bauten/Stumpf-Rodung und
## Chunk-Rohstoffe kommen nie zurueck (INF), gefaellte Baeume nach REGROW,
## gemalte Steine nach STONE.
func _remaining(r: Dictionary, now: float) -> float:
	var age := now - float(r["t"])
	match String(r["kind"]):
		"fell":
			return REGROW_SECONDS - age
		"stone":
			if String(r["gid"]) == "":
				return STONE_SECONDS - age
			return INF                # Chunk-Rohstoff: endgueltig
		_:                            # "stump" (gerodet): endgueltig
			return INF


func _save_removed() -> void:
	DirAccess.make_dir_recursive_absolute(BUILD_DIR)
	var f := FileAccess.open(REMOVED_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_removed.values()))
		f.close()


func _load_removed() -> void:
	if not FileAccess.file_exists(REMOVED_FILE):
		return
	var f := FileAccess.open(REMOVED_FILE, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_ARRAY:
		return
	# Abgelaufenes (schon nachgewachsen) beim Laden aussortieren, damit die
	# Datei nicht unbegrenzt waechst.
	var now := Time.get_unix_time_from_system()
	for r in data:
		if typeof(r) == TYPE_DICTIONARY and _remaining(r, now) > 0.0:
			_removed["%d,%d" % [int(r["x"]), int(r["y"])]] = r
	print("WorldSync: %d Abbauten aus %s geladen." % [_removed.size(), REMOVED_FILE])


# --- Baum-Durability (geteilte HP, server-autoritativ) -------------------

## Client -> Server: "ich habe diesen Baum einmal geschlagen".
func report_tree_hit(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	_tree_hit.rpc_id(1, cell, level, atlas)


@rpc("any_peer", "reliable")
func _tree_hit(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	# Schon gefaellt und noch nicht nachgewachsen? Dann Schlaege ignorieren -
	# sonst wuerde ein Nachzuegler-Schlag die HP des (spaeter) nachgewachsenen
	# Baums vermindern.
	var key := "%d,%d" % [cell.x, cell.y]
	if _removed.has(key) and _remaining(_removed[key], Time.get_unix_time_from_system()) > 0.0:
		return
	var killer := multiplayer.get_remote_sender_id()
	var hp := int(_tree_hp.get(cell, TREE_MAX_HP)) - 1
	print("[Baum] Zelle %s: %d/%d HP (Schlag von %d)" % [cell, maxi(hp, 0), TREE_MAX_HP, killer])
	if hp > 0:
		_tree_hp[cell] = hp
		return
	_tree_hp.erase(cell)
	_record_removal("fell", cell, level, atlas, "")
	# Jeder Client faellt den Baum; nur der toedliche Schlaeger bekommt Holz.
	for pid in multiplayer.get_peers():
		_fell_now.rpc_id(pid, cell, level, atlas, pid == killer)


@rpc("any_peer", "reliable")
func _fell_now(cell: Vector2i, level: int, atlas: Vector2i, got_wood: bool) -> void:
	_apply_fell(cell, level, atlas, got_wood)


## Faellt den Baum lokal: Umkipp-Animation, Stumpf + Nachwachs-Uhr, und - nur
## beim toedlichen Schlaeger - Holz gutschreiben. KEIN felled.emit (das wuerde
## das Ereignis erneut ans Netz verteilen).
func _apply_fell(cell: Vector2i, level: int, atlas: Vector2i, got_wood: bool) -> void:
	_remove_tree(cell, level)
	if _regrowth:
		_regrowth.replicate_felled(cell, level, atlas)
	if got_wood and _pinv and _pinv.has_method("grant_wood_for_tree"):
		_pinv.grant_wood_for_tree()


## Entfernt einen Baum wie beim lokalen Faellen - mit Umkipp-Animation, wenn
## der Node noch da ist, sonst hart entfernen.
func _remove_tree(cell: Vector2i, _level: int) -> void:
	var node: TreeActor = _world.prop_node(cell)
	if node:
		_world.detach_prop(cell)
		node.fell(Vector2(0, 1))
	# Kein else mit remove_prop! Ist kein Baum-Node da, gibt es nichts zu
	# entfernen. remove_prop wuerde bei fehlendem Node die Bodenkachel loeschen
	# (n == null) und beim Zuschauer ein Loch reissen.
