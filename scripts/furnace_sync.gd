extends Node

## Online-Ofen (Cooking Campfire): Inhalt (Input/Brennstoff/Output) + Koch-
## Fortschritt liegen server-autoritativ. Der Server kocht (auch wenn niemand
## zusieht), verteilt Aenderungen an alle und persistiert. Angelehnt an
## chest_sync (Voll-Zustand), aber MIT server-seitigem Koch-Timer.
##
## Slots: [0]=Input (kochbares, z.B. roher Fisch), [1]=Brennstoff (komur),
## [2]=Output (fertig gekocht). Regel: 1 Kohle pro Fisch, 30s pro Fisch. Feuer
## brennt nur, solange gekocht wird (Input + Kohle + Platz im Output).
##
## KEIN class_name (Auto-Updater) - Node in main.tscn.

const DIR := "/opt/survival_world"
const FILE := DIR + "/furnaces.json"
const COOK_TIME := 30.0
const OUT_MAX := 16

## Client: Server schickt den Zustand eines Ofens (cell -> state-Dict).
signal furnace_updated(cell: Vector2i, state: Dictionary)

var _furn: Dictionary = {}         ## Server: "x,y" -> {slots:[i,f,o], progress, lit}
var _tick := 0.0


func _ready() -> void:
	add_to_group("furnace_sync")
	if Net.is_dedicated:
		_load()
	set_process(Net.is_dedicated)


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _new_state() -> Dictionary:
	return {"slots": [{}, {}, {}], "progress": 0.0, "lit": false}


# --- Server: Kochen ----------------------------------------------------

func _process(delta: float) -> void:
	if not Net.is_dedicated:
		return
	_tick += delta
	var periodic := _tick >= 1.0
	if periodic:
		_tick = 0.0
	var dirty := false
	for key in _furn.keys():
		var st: Dictionary = _furn[key]
		var disc := _cook_step(st, delta)
		if disc or (periodic and bool(st.get("lit", false))):
			_broadcast(key, st)
		if disc:
			dirty = true
	if dirty:
		_save()


## Ein Kochschritt. Gibt true zurueck bei einer DISKRETEN Aenderung
## (fertiges Stueck oder Feuer an/aus).
func _cook_step(st: Dictionary, delta: float) -> bool:
	var slots: Array = st["slots"]
	var inp: Dictionary = slots[0]
	var fue: Dictionary = slots[1]
	var outp: Dictionary = slots[2]
	var can := not inp.is_empty() and ItemDB.is_raw_fish(String(inp.get("id", ""))) \
		and not fue.is_empty() and String(fue.get("id", "")) == "komur" \
		and int(fue.get("count", 0)) >= 1
	if can:
		var cid := ItemDB.cooked_of(String(inp.get("id", "")))
		if not outp.is_empty() and (String(outp.get("id", "")) != cid or int(outp.get("count", 0)) >= OUT_MAX):
			can = false
	var was_lit := bool(st.get("lit", false))
	if not can:
		st["progress"] = 0.0
		st["lit"] = false
		return was_lit != false
	st["lit"] = true
	st["progress"] = float(st.get("progress", 0.0)) + delta
	if float(st["progress"]) < COOK_TIME:
		return was_lit != true
	# Ein Stueck fertig: 1 Input + 1 Kohle weg, 1 Output dazu.
	st["progress"] = 0.0
	var cid := ItemDB.cooked_of(String(inp.get("id", "")))
	inp["count"] = int(inp.get("count", 0)) - 1
	if int(inp["count"]) <= 0:
		slots[0] = {}
	fue["count"] = int(fue.get("count", 0)) - 1
	if int(fue["count"]) <= 0:
		slots[1] = {}
	if outp.is_empty():
		slots[2] = {"id": cid, "count": 1}
	else:
		outp["count"] = int(outp.get("count", 0)) + 1
	return true


# --- Client-API --------------------------------------------------------

func request(cell: Vector2i) -> void:
	if Net.active and not Net.is_dedicated:
		_srv_request.rpc_id(1, cell)


## Geaenderte Slots (Input/Brennstoff/Output) an den Server. Er behaelt seinen
## Koch-Fortschritt und verteilt weiter.
func push(cell: Vector2i, slots: Array) -> void:
	if Net.is_dedicated or not Net.active:
		return
	_srv_set.rpc_id(1, cell, slots)


# --- Server-RPCs -------------------------------------------------------

@rpc("any_peer", "reliable")
func _srv_request(cell: Vector2i) -> void:
	if not Net.is_dedicated:
		return
	var sid := multiplayer.get_remote_sender_id()
	var st: Dictionary = _furn.get(_key(cell), _new_state())
	_recv.rpc_id(sid, cell, st)


@rpc("any_peer", "reliable")
func _srv_set(cell: Vector2i, slots: Array) -> void:
	if not Net.is_dedicated:
		return
	var key := _key(cell)
	var st: Dictionary = _furn.get(key, _new_state())
	st["slots"] = slots
	_furn[key] = st
	_save()
	# an alle verteilen (auch den Absender, damit alle denselben Stand haben).
	for pid in multiplayer.get_peers():
		_recv.rpc_id(pid, cell, st)


func _broadcast(key: String, st: Dictionary) -> void:
	var parts := key.split(",")
	var cell := Vector2i(int(parts[0]), int(parts[1]))
	for pid in multiplayer.get_peers():
		_recv.rpc_id(pid, cell, st)


# --- Client-Empfang ----------------------------------------------------

@rpc("authority", "reliable")
func _recv(cell: Vector2i, state: Dictionary) -> void:
	if Net.is_dedicated:
		return
	furnace_updated.emit(cell, state)


# --- Persistenz (Server) -----------------------------------------------

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_furn))
		f.close()


func _load() -> void:
	if not FileAccess.file_exists(FILE):
		return
	var f := FileAccess.open(FILE, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		_furn = data
		print("FurnaceSync: %d Oefen geladen." % _furn.size())
