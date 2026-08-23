extends Node

## Verbindet Modell, HUD und das Geschehen in der Welt.
##
## Das HUD wird zur Laufzeit erzeugt, in der Szene steht nur dieser Node.

@export var hotbar_size := 9
@export var bag_rows := 3
## Wie viel Holz ein gefällter Baum bzw. ein gerodeter Stumpf abwirft.
@export var wood_per_tree := 4
@export var wood_per_stump := 1
## Startausruestung: {item_id: Anzahl}.
##
## ZUM TESTEN gefuellt. Fuer den echten Spielstart wieder auf `{}` setzen -
## der Spieler soll mit nichts anfangen und sich alles selbst
## zusammensammeln. Laesst sich auch im Inspector am Inventory-Node leeren,
## ohne den Code anzufassen.
@export var starting_items := {}
## Wie viel gebratenes Fleisch ein Lagerfeuer abwirft.
@export var meat_per_fire := 1
## Wie viele Steine ein von Hand in die Karte gemalter Steinhaufen abwirft.
## Die eingestreuten Rohstoffe bringen die Menge aus der GatherDB mit.
@export var stone_per_pickup := 1

var inventory: Inventory
var hud: InventoryHUD
var crafting: CraftingHUD                ## Grundhandwerk (Taste C, ueberall)
## Fenster der Handwerks-Stationen, je Station eins, erst bei Bedarf gebaut.
## Sie teilen sich dieselbe Bauliste wie das Grundhandwerk - es gibt nur eine.
var station_huds: Dictionary = {}
var queue: CraftQueue
var player: Player
var preview: PlacementPreview
## Kreativ-Inventar (Taste X), nur fuer Admins - sonst null (siehe Net.is_admin).
## Per preload statt ueber den class_name CreativeHUD - sonst kennt der
## Auto-Updater die neue Klasse nicht (siehe chunk_manager.gd/WorldGen).
const CreativeHUDScript := preload("res://scripts/creative_hud.gd")
var creative: Node
var _drop: Node                          ## DropSync (fallengelassene Items), im MP
## Zuletzt gesetzter Kontext-Hinweis (Stein aufheben / Station oeffnen).
## Als String statt bool, weil es jetzt mehrere Sorten gibt.
var _ctx_hint := ""
## Restzeit einer kurzen Meldung. Sie hat Vorrang vor dem Aufheben-Hinweis,
## sonst waere sie im naechsten Bild schon wieder ueberschrieben.
var _notice_left := 0.0
## Wie lange so eine Meldung stehen bleibt.
@export var notice_seconds := 2.5


func _ready() -> void:
	inventory = Inventory.new(hotbar_size, bag_rows)
	hud = InventoryHUD.new()
	add_child(hud)
	hud.setup(inventory)

	# Grundhandwerk: geht ueberall, deshalb haengt es hier und nicht an
	# einer Station in der Welt.
	queue = CraftQueue.new()
	queue.setup(inventory)
	add_child(queue)

	crafting = CraftingHUD.new()
	add_child(crafting)
	crafting.setup(inventory, queue, RecipeDB.HAND, "Üretim")

	for id in starting_items:
		inventory.add(id, int(starting_items[id]))

	# Admins bekommen das Kreativ-Inventar (Taste X). Nur dann gebaut, damit
	# es fuer normale Spieler gar nicht erst existiert.
	if Net.is_admin():
		creative = CreativeHUDScript.new()
		add_child(creative)
		creative.setup(inventory)
		# Kurz einblenden, dass der Admin-Modus laeuft - und welche Taste. So
		# sieht man auch gleich, ob man ueberhaupt als Admin erkannt wurde.
		_notice.call_deferred("Admin modu  ·  X = tüm esyalar")

	var interaction := get_tree().get_first_node_in_group("interaction")
	if interaction:
		preview = interaction.preview
		preview.confirmed.connect(_on_placement_confirmed)
		preview.ended.connect(func(): hud.set_hint(""))

	_drop = get_node_or_null(^"../DropSync")
	hud.drop_sync = _drop

	player = get_tree().get_first_node_in_group("player")
	if player:
		player.felled.connect(_on_felled)
		player.stump_cleared.connect(_on_stump_cleared)
		# Ueber das Signal statt an der Aufruf-Stelle: so zaehlt jeder Weg,
		# der einen Stein aufhebt - E genauso wie der Rechtsklick-Auftrag.
		player.stone_collected.connect(_on_stone_collected)
		player.chop_refused.connect(_on_chop_refused)
		player.reached_station.connect(_on_reached_station)


## --- Speichern/Laden (Multiplayer-Persistenz, siehe save_sync.gd) --------

## Das Inventar als speicherbare Daten.
func to_save() -> Dictionary:
	return {"slots": inventory.slots}


## Setzt das Inventar aus gespeicherten Daten. Ungueltige/unbekannte Eintraege
## werden verworfen, die Slot-Anzahl bleibt wie im aktuellen Spiel.
func from_save(data: Dictionary) -> void:
	if not data.has("slots") or typeof(data["slots"]) != TYPE_ARRAY:
		return
	var saved: Array = data["slots"]
	for i in inventory.slots.size():
		var entry: Variant = saved[i] if i < saved.size() else null
		if typeof(entry) == TYPE_DICTIONARY and entry.has("id") and ItemDB.has(entry["id"]) \
				and int(entry.get("count", 0)) > 0:
			inventory.slots[i] = {"id": String(entry["id"]), "count": int(entry["count"])}
		else:
			inventory.slots[i] = {}
	inventory.changed.emit()


## Zeigt an, wenn ein Stein aufgehoben werden kann - sonst raet man, ob man
## nah genug steht. Die Platzieren-Vorschau hat Vorrang, die schreibt in
## denselben Hinweis.
func _process(delta: float) -> void:
	# Die Axt zaehlt nur, wenn sie in der Hotbar ausgewaehlt ist. Hier
	# nachgefuehrt statt an jeder Stelle, die die Auswahl aendern kann -
	# das sind Tastendruck, Klick und jedes Umlegen im Inventar.
	if player != null:
		var held: Dictionary = inventory.slots[hud.selected]
		player.has_axe = not held.is_empty() and held["id"] == "axt"

	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			hud.set_hint("")
		else:
			return

	# Bei offenem Fenster oder laufender Vorschau keinen Kontext-Hinweis -
	# sonst bliebe er unter der Tasche stehen bzw. neben der Vorschau, die
	# ihren eigenen Hinweis schreibt.
	if player == null or hud.bag_open() or _crafting_open() \
			or (creative != null and creative.is_open()) \
			or (preview != null and preview.active):
		_set_ctx_hint("")
		return

	# Was liegt gerade an? Stein zuerst (haeufigste Aktion, direkt vor den
	# Fuessen), sonst eine Station in Reichweite.
	var want := ""
	# Fallengelassenes Item in Reichweite hat Vorrang - "unten steht, was da liegt".
	if _drop:
		var did: int = _drop.dropped_in_reach()
		if did >= 0:
			var d: Dictionary = _drop.info(did)
			want = "F  %s x%d al" % [ItemDB.display_name(String(d["item_id"])), int(d["count"])]
	if want == "":
		var cell := player.stone_in_reach()
		if cell != Player.INVALID_CELL:
			var what := player.world.gather_id_at(cell)
			want = GatherDB.hint(what) if GatherDB.has(what) else "F  Tas al"
		else:
			var st := player.station_in_reach()
			if st != "":
				want = "F  %s ac" % ItemDB.display_name(st)
	_set_ctx_hint(want)


## Setzt den Kontext-Hinweis nur, wenn er sich geaendert hat - sonst baut das
## HUD jedes Bild dieselbe Zeile neu auf.
func _set_ctx_hint(text: String) -> void:
	if text == _ctx_hint:
		return
	_ctx_hint = text
	hud.set_hint(text)


# --- Handwerk-Stationen -------------------------------------------------

## Ist irgendein Handwerk-Fenster offen (Grundhandwerk oder eine Station)?
func _crafting_open() -> bool:
	if crafting.is_open():
		return true
	return _open_station() != null


## Das gerade offene Stations-Fenster, oder null.
func _open_station() -> CraftingHUD:
	for s in station_huds:
		if station_huds[s].is_open():
			return station_huds[s]
	return null


## Fenster einer Station, beim ersten Aufruf gebaut und gemerkt.
func _station_hud(station: String) -> CraftingHUD:
	if not station_huds.has(station):
		var h := CraftingHUD.new()
		add_child(h)
		h.setup(inventory, queue, station, ItemDB.display_name(station))
		station_huds[station] = h
	return station_huds[station]


## Jack ist per Rechtsklick bei einer Station angekommen - ihr Fenster auf.
func _on_reached_station(station: String) -> void:
	if hud.bag_open():
		hud.toggle_bag()
	_close_all_crafting()
	_station_hud(station).set_open(true)


## Schliesst jedes offene Handwerk-Fenster (Grundhandwerk und Stationen).
func _close_all_crafting() -> void:
	crafting.set_open(false)
	for s in station_huds:
		station_huds[s].set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	# Mausrad blaettert durch die Hotbar (frueher Zoom). Hoch = ein Feld nach
	# links, runter = nach rechts, laeuft am Rand um.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			hud.select(wrapi(hud.selected - 1, 0, hotbar_size))
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			hud.select(wrapi(hud.selected + 1, 0, hotbar_size))
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# E oeffnet die Tasche, C das Handwerk, F ist die Kontextaktion. I
	# bleibt als zweite Taste fuer die Tasche - wer es aus anderen Spielen
	# so kennt, findet es trotzdem.
	#
	# Escape schliesst, was offen ist. Ohne das muesste man sich merken,
	# womit man das Fenster aufgemacht hat.
	if event.keycode == KEY_ESCAPE:
		if _close_windows():
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E or event.keycode == KEY_I:
		_close_all_crafting()
		hud.toggle_bag()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_C:
		if hud.bag_open():
			hud.toggle_bag()
		# C ist das Grundhandwerk. Ein offenes Stationsfenster weicht ihm.
		var was_station := _open_station()
		_close_all_crafting()
		if was_station == null:
			crafting.toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F:
		_use_selected()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_X and creative != null:
		# Admin-Kreativinventar auf/zu. Andere Fenster weichen.
		if hud.bag_open():
			hud.toggle_bag()
		_close_all_crafting()
		creative.toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Q:
		if _drop:
			_drop.drop_selected()
		get_viewport().set_input_as_handled()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		hud.select(event.keycode - KEY_1)


## Kurze Meldung ueber der Hotbar, die von selbst wieder verschwindet.
func _notice(text: String) -> void:
	hud.set_hint(text)
	_notice_left = notice_seconds
	_ctx_hint = text


func _on_chop_refused() -> void:
	_notice("Bunun icin elinde bir balta olmali")


func _on_stone_collected(_cell: Vector2i, _level: int, gather_id: String) -> void:
	if GatherDB.has(gather_id):
		_grant(gather_id, GatherDB.amount(gather_id))
	else:
		_grant("stein", stone_per_pickup)
	_set_ctx_hint("")


func _on_felled(_cell: Vector2i, _level: int, _atlas: Vector2i) -> void:
	_grant("holz", wood_per_tree)


func _on_stump_cleared(_cell: Vector2i) -> void:
	_grant("holz", wood_per_stump)


func _grant(id: String, amount: int) -> void:
	var left := inventory.add(id, amount)
	if left > 0:
		push_warning("Inventar voll: %d x %s gingen verloren" % [left, id])


## "E" ist eine Kontextaktion: liegt ein Stein in Reichweite, wird er
## aufgehoben; steht ein fertiges Lagerfeuer da, wird abgeholt - sonst wird
## der ausgewaehlte Gegenstand benutzt.
func _use_selected() -> void:
	if player == null:
		return
	# Offenes Stationsfenster: F schliesst es wieder - so ist dieselbe Taste
	# auf und zu, ohne dass man zur Maus greifen muss.
	var open_station := _open_station()
	if open_station != null:
		open_station.set_open(false)
		return
	if hud.bag_open() or crafting.is_open():
		return
	# Eine laufende Vorschau bricht IMMER ab, egal was gerade ausgewaehlt
	# ist. Stand diese Pruefung weiter unten, blieb die Vorschau haengen,
	# sobald man zwischendurch ein anderes Hotbar-Feld waehlte - und weil
	# sie alle Klicks schluckt, liess sich die Figur dann nicht mehr
	# bewegen.
	if preview != null and preview.active:
		preview.cancel()
		return
	# Liegt ein fallengelassenes Item in Reichweite? Das zuerst aufheben.
	if _drop:
		var did: int = _drop.dropped_in_reach()
		if did >= 0:
			_drop.pickup(did)
			return
	# Steine zuerst: sie liegen direkt vor den Fuessen und sind die
	# haeufigste Kontextaktion.
	var stone := player.stone_in_reach()
	if stone != Player.INVALID_CELL and player.collect_stone(stone):
		return
	var fire := player.campfire_in_reach(true)
	if fire != null and fire.collect():
		_grant("gebratenes_fleisch", meat_per_fire)
		return
	# Steht eine Handwerks-Station in Reichweite, ihr Fenster oeffnen. Vor
	# dem Platzieren, damit man an der Bank ihr Menue bekommt statt eine
	# zweite danebenzustellen.
	var station := player.station_in_reach()
	if station != "":
		if hud.bag_open():
			hud.toggle_bag()
		_close_all_crafting()
		_station_hud(station).set_open(true)
		return
	var slot: Dictionary = inventory.slots[hud.selected]
	if slot.is_empty():
		return
	if preview == null:
		return
	if slot["id"] == "lagerfeuer":
		preview.begin_campfire()
		hud.set_hint("Sol tik koy  ·  Sag tik veya Esc iptal")
	elif ItemDB.is_furniture(slot["id"]):
		preview.begin_furniture(slot["id"])
		hud.set_hint("Sol tik koy  ·  R döndür  ·  Sag tik veya Esc iptal")


func _on_placement_confirmed(top_cell: Vector2i) -> void:
	# Was gesetzt wird, verraet die Vorschau - so bleibt hier eine Stelle,
	# egal ob Lagerfeuer oder Moebel.
	if preview.kind == PlacementPreview.Kind.CAMPFIRE:
		if player.place_campfire_at(top_cell):
			inventory.remove("lagerfeuer", 1)
	elif player.place_furniture_at(preview.item_id, top_cell, preview.flipped):
		inventory.remove(preview.item_id, 1)


## Schliesst das oberste offene Fenster. false, wenn keines offen war -
## dann darf Escape weiterlaufen (die Platzieren-Vorschau haengt daran).
func _close_windows() -> bool:
	if creative != null and creative.is_open():
		creative.set_open(false)
		return true
	var station := _open_station()
	if station != null:
		station.set_open(false)
		return true
	if crafting.is_open():
		crafting.set_open(false)
		return true
	if hud.bag_open():
		hud.toggle_bag()
		return true
	return false
