extends Node

## Verbindet Modell, HUD und das Geschehen in der Welt.
##
## Das HUD wird zur Laufzeit erzeugt, in der Szene steht nur dieser Node.

@export var hotbar_size := 9
@export var bag_rows := 6
## Feste Taschengröße: 4 Spalten x 10 Reihen = 40.
@export var bag_slots := 40
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
var _needs: Node = null                  ## SurvivalNeeds (Hunger/Essen), kann null sein
## Kreativ-Inventar (Taste X), nur fuer Admins - sonst null.
## Per preload statt ueber den class_name CreativeHUD - sonst kennt der
## Auto-Updater die neue Klasse nicht (siehe chunk_manager.gd/WorldGen).
const CreativeHUDScript := preload("res://scripts/creative_hud.gd")
## Skill-XP (Fortschritt) - statisch, wird mitgespeichert (siehe to_save/from_save).
const SkillsXPScript := preload("res://scripts/skills_xp.gd")
const XpParticlesScript := preload("res://scripts/xp_particles.gd")
var creative: Node
## Admin-Pruefung zentral (per preload, nicht ueber das Net-Autoload - das wird
## vom Auto-Updater nicht ersetzt, siehe admins.gd).
const AdminsScript := preload("res://scripts/admins.gd")
const PlayerStatsScript := preload("res://scripts/player_stats.gd")
const ChestHUDScript := preload("res://scripts/chest_hud.gd")
const FurnaceHUDScript := preload("res://scripts/furnace_hud.gd")
const SkillsHUDScript := preload("res://scripts/skills_hud.gd")
const UIStateScript := preload("res://scripts/ui_state.gd")
var chest_hud                             ## Lagertruhen-Fenster (online)
var _chest_sync                           ## ChestSync-Node
var furnace_hud                           ## Ofen-Fenster (online)
var _furnace_sync                         ## FurnaceSync-Node
var skills_hud                            ## Skills-Fenster (Taste K)
var _is_admin := false
var _drop: Node                          ## DropSync (fallengelassene Items), im MP
## Zuletzt gesetzter Kontext-Hinweis (Stein aufheben / Station oeffnen).
## Als String statt bool, weil es jetzt mehrere Sorten gibt.
var _ctx_hint := ""
## Restzeit einer kurzen Meldung. Sie hat Vorrang vor dem Aufheben-Hinweis,
## sonst waere sie im naechsten Bild schon wieder ueberschrieben.
var _notice_left := 0.0
## Level-up-Erkennung: gemerkte Level je Skill; steigt eins, kommt ein Banner.
const SKILL_NAMES := {
	"woodcutting": "Oduncu", "mining": "Madenci", "fishing": "Balikci",
	"cooking": "Asci", "smithing": "Demirci", "crafting": "Zanaat", "building": "Insaat",
}
var _last_levels: Dictionary = {}
var _lvl_accum := 0.0
var _lvl_alive := 0.0             ## Karenzzeit, damit der Save-Load kein Banner ausloest
var _announce: Node = null
## Wie lange so eine Meldung stehen bleibt.
@export var notice_seconds := 2.5


func _ready() -> void:
	inventory = Inventory.new(hotbar_size, bag_rows, bag_slots)
	# HUD ist jetzt eine echte Szene (Layout im Editor schiebbar), statt im Code
	# zusammengebaut. Preload statt class_name-Instanz - der Auto-Updater ersetzt
	# das PackedScene in der game.pck, kennt aber neue class_names nicht.
	hud = load("res://scenes/inventory_hud.tscn").instantiate()
	add_child(hud)
	hud.setup(inventory)

	# Grundhandwerk: geht ueberall, deshalb haengt es hier und nicht an
	# einer Station in der Welt.
	queue = CraftQueue.new()
	queue.setup(inventory)
	add_child(queue)
	# Grundhandwerk lebt jetzt im Buch (Basic-Crafts-Reiter) statt im C-Fenster.
	hud.attach_crafting(queue)

	crafting = CraftingHUD.new()
	add_child(crafting)
	crafting.setup(inventory, queue, RecipeDB.HAND, "Üretim")

	# Lagertruhen-Fenster (online) - eine Instanz, oeffnet je nach Truhe.
	_chest_sync = get_node_or_null(^"../ChestSync")
	chest_hud = ChestHUDScript.new()
	add_child(chest_hud)
	chest_hud.setup(inventory, _chest_sync)
	chest_hud.wants_notice.connect(_notice)
	# Skills-Fenster (Taste K).
	skills_hud = SkillsHUDScript.new()
	add_child(skills_hud)
	skills_hud.setup()
	# Escape schliesst das oberste Fenster (zentral im Pause-Menue, siehe UIState).
	UIStateScript.close_top = _close_windows

	for id in starting_items:
		inventory.add(id, int(starting_items[id]))

	# Admins bekommen das Kreativ-Inventar (Taste X). Nur dann gebaut, damit
	# es fuer normale Spieler gar nicht erst existiert.
	_is_admin = AdminsScript.is_admin(String(Net.player_name))
	print("[Admin] player_name='%s' is_admin=%s" % [Net.player_name, _is_admin])
	if _is_admin:
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
	_needs = get_node_or_null(^"../SurvivalNeeds")

	player = get_tree().get_first_node_in_group("player")
	if player:
		player.felled.connect(_on_felled)
		player.stump_cleared.connect(_on_stump_cleared)
		# Insaat-XP beim Setzen von Moebeln/Bauwerken/Lagerfeuer.
		player.placed_furniture.connect(func(_id, _cell, _o): SkillsXPScript.gain("building", 8.0))
		player.placed_campfire.connect(func(_top): SkillsXPScript.gain("building", 8.0))
		# Ueber das Signal statt an der Aufruf-Stelle: so zaehlt jeder Weg,
		# der einen Stein aufhebt - E genauso wie der Rechtsklick-Auftrag.
		player.stone_collected.connect(_on_stone_collected)
		player.chop_refused.connect(_on_chop_refused)
		player.axe_swung.connect(_on_axe_swung)
		player.reached_station.connect(_on_reached_station)
		player.reached_chest.connect(func(cell):
			if chest_hud != null:
				if hud.bag_open(): hud.toggle_bag()
				_close_all_crafting()
				chest_hud.open(cell))
		# Ofen (online) - eine Instanz, oeffnet je nach angeklicktem Ofen.
		_furnace_sync = get_node_or_null(^"../FurnaceSync")
		furnace_hud = FurnaceHUDScript.new()
		add_child(furnace_hud)
		furnace_hud.setup(inventory, _furnace_sync, player)
		player.reached_furnace.connect(func(cell, kind):
			if furnace_hud != null:
				if hud.bag_open(): hud.toggle_bag()
				_close_all_crafting()
				furnace_hud.open(cell, kind))
		player.bed_busy.connect(func(): _notice("Bu yatak dolu"))
		# Hinlegen: Spawnpunkt gemerkt -> Hinweis im Chat.
		player.lay_down.connect(func():
			var ch := get_tree().get_first_node_in_group("chat")
			if ch != null and ch.has_method("local_system"):
				ch.local_system("Dogum noktan kaydedildi. Uyandiginda burada dogacaksin."))
		# Buddeln gibt einen Dirt-Block, Aufschuetten verbraucht einen.
		player.dug.connect(func(_c):
			if player.last_dug_atlas == IsoWorld.CLAY_ATLAS:
				_grant("kil", randi_range(3, 10))
			else:
				_grant("toprak", 1))
		player.raised.connect(func(_c): inventory.remove("toprak", 1))
		# Fels-Abbau: pro Schlag faellt ein Stueck auf den BODEN (wie Holz beim
		# Baum) - im Einzelspieler direkt ins Inventar. Zu schwache Hacke -> Hinweis.
		player.mine_drop.connect(_on_mine_drop)
		player.mine_refused.connect(func(tier):
			_notice("Bu kaya icin en az demir kazma lazim" if tier >= 2 else "Bir kazma lazim"))
		# Spitzhacke nutzt sich beim Abbauen ab (Gold schneller, siehe player.gd).
		player.tool_worn.connect(_wear_selected)
		# Ackerbau: Pflanzen verbraucht 1 Samen; Ernten gibt Produkt + Samen zurueck.
		player.planted.connect(_on_planted)
		player.crop_harvested.connect(_on_crop_harvested)
		# Giessen zieht eine Kannen-Ladung ab; Auffuellen setzt sie auf voll.
		player.watered_crop.connect(func(_c): _use_can_charge())
		player.can_filled.connect(_fill_can_full)


## --- Speichern/Laden (Multiplayer-Persistenz, siehe save_sync.gd) --------

## Das Inventar als speicherbare Daten. Inklusive Skill-XP, damit der
## Fortschritt (EXP-Leiste/Level) pro Spielername einen Neustart ueberlebt.
func to_save() -> Dictionary:
	var d := {"slots": inventory.slots, "xp": SkillsXPScript.xp.duplicate()}
	# Position merken -> beim naechsten Login startet man wieder hier (Logout-Ort).
	if player != null and is_instance_valid(player) and player.world != null:
		var c: Vector2i = player.world.world_to_cell(player.global_position, player.level)
		# Im Huetten-Innenraum? Dann den Eingangsort sichern, sonst spawnt man beim
		# naechsten Login im ungestempelten Leeren (Innenraum wird nicht persistiert).
		var interior := get_node_or_null(^"../Interior")
		if interior != null and interior.is_inside():
			c = interior.return_cell()
		d["pos"] = {"x": c.x, "y": c.y}
	return d


## Setzt das Inventar aus gespeicherten Daten. Ungueltige/unbekannte Eintraege
## werden verworfen, die Slot-Anzahl bleibt wie im aktuellen Spiel.
func from_save(data: Dictionary) -> void:
	if not data.has("slots") or typeof(data["slots"]) != TYPE_ARRAY:
		return
	var saved: Array = data["slots"]
	for i in inventory.slots.size():
		var entry: Variant = saved[i] if i < saved.size() else null
		# Alte deutsche Id auf den aktuellen tuerkischen Namen heben.
		var cid := ItemDB.canonical(String(entry["id"])) if typeof(entry) == TYPE_DICTIONARY and entry.has("id") else ""
		if cid != "" and ItemDB.has(cid) and int(entry.get("count", 0)) > 0:
			var rebuilt := {"id": cid, "count": int(entry["count"])}
			# Dayaniklilik mitnehmen, damit eine halb verbrauchte Axt nach dem
			# Neuladen nicht wieder voll ist. Auf den gueltigen Bereich klemmen.
			if entry.has("dur") and ItemDB.has_durability(cid):
				rebuilt["dur"] = clampi(int(entry["dur"]), 1, ItemDB.max_durability(cid))
			inventory.slots[i] = rebuilt
		else:
			inventory.slots[i] = {}
	# Skill-XP wiederherstellen (nur bekannte Skills, als Zahl).
	if data.has("xp") and typeof(data["xp"]) == TYPE_DICTIONARY:
		for skill in SkillsXPScript.xp.keys():
			if data["xp"].has(skill):
				SkillsXPScript.xp[skill] = float(data["xp"][skill])
	# Gespeicherte Position wiederherstellen (Logout-Ort). Neue Namen haben keine
	# -> sie bleiben am globalen Spawn (player.start_cell).
	if data.has("pos") and typeof(data["pos"]) == TYPE_DICTIONARY \
			and player != null and is_instance_valid(player):
		var p: Dictionary = data["pos"]
		var cell := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
		# Rettungsnetz fuer kaputte Saves, die im Huetten-Innenraum (weit ostwaerts,
		# ohne gestempelten Boden) gespeichert wurden: dort steht kein Boden ->
		# stattdessen sicher am globalen Spawn starten. (Grenze wie
		# chunk_manager.INTERIOR_X; grosszuegig ab x>=20000.)
		if cell.x >= 20000:
			cell = player.start_cell
		player._snap_to_cell(cell)
		# Steckt die gespeicherte Position in einem Baum? Sofort + verzoegert
		# rausruecken (Props laden nach dem Snap evtl. erst nach).
		player.ensure_unstuck()
		get_tree().create_timer(2.0).timeout.connect(player.ensure_unstuck)
		get_tree().create_timer(4.0).timeout.connect(player.ensure_unstuck)
	inventory.changed.emit()


## Zeigt an, wenn ein Stein aufgehoben werden kann - sonst raet man, ob man
## nah genug steht. Die Platzieren-Vorschau hat Vorrang, die schreibt in
## denselben Hinweis.
## Prueft ~alle 0.4s, ob ein Skill-Level gestiegen ist -> goldener Level-up-Banner
## (derselbe wie der Morgen-Banner). Karenz am Anfang, damit der Save-Load beim
## Login kein Banner ausloest.
func _check_levelups(delta: float) -> void:
	_lvl_alive += delta
	_lvl_accum += delta
	if _lvl_accum < 0.4:
		return
	_lvl_accum = 0.0
	for skill in SKILL_NAMES:
		var lv := SkillsXPScript.level_of(skill)
		var prev := int(_last_levels.get(skill, lv))
		if lv > prev and _lvl_alive > 3.0:
			_show_levelup(String(SKILL_NAMES[skill]), lv)
		_last_levels[skill] = lv


func _show_levelup(sname: String, lvl: int) -> void:
	if _announce == null or not is_instance_valid(_announce):
		_announce = get_tree().get_first_node_in_group("announce")
	if _announce != null and _announce.has_method("flash"):
		_announce.flash("%s  Seviye %d!" % [sname, lvl], 2.4)
	# Kleines Extra-Feedback: XP-Partikel-Puff zum Spieler.
	if player != null and is_instance_valid(player):
		XpParticlesScript.spawn(player.get_parent(), player.global_position, player, 10)


func _process(delta: float) -> void:
	_check_levelups(delta)
	# Die Axt zaehlt nur, wenn sie in der Hotbar ausgewaehlt ist. Hier
	# nachgefuehrt statt an jeder Stelle, die die Auswahl aendern kann -
	# das sind Tastendruck, Klick und jedes Umlegen im Inventar.
	if player != null:
		var held: Dictionary = inventory.slots[hud.selected]
		var hid := "" if held.is_empty() else String(held["id"])
		# Welches Werkzeug die Figur zeigt (Halte-Sprite). Faellen weiterhin nur
		# mit einer Axt - aber jetzt jede Stufe (Stein/Eisen/Gold), nicht nur Stein.
		var hold: Array = ItemDB.hold_of(hid)
		player.held_tool = String(hold[0])
		player.held_metal = String(hold[1])
		player.has_axe = String(hold[0]) == "Axe"
		player.held_is_dirt = hid == "toprak"
		player.held_pick_tier = ItemDB.pick_tier(hid)
		player.held_item_id = hid

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


## der Charakter ist per Rechtsklick bei einer Station angekommen - ihr Fenster auf.
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
	# ...aber nicht, solange die Tasche offen ist: dort blaettert das Mausrad
	# durch die Taschen-Reihen, und die Hotbar-Auswahl darf dabei nicht mitwandern.
	if event is InputEventMouseButton and event.pressed and not hud.bag_open():
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
	# Escape wird zentral im Pause-Menue behandelt (schliesst zuerst ein offenes
	# Fenster ueber UIState.close_top, sonst Menue) - hier NICHT mehr abfangen.
	if event.keycode == KEY_E or event.keycode == KEY_I:
		_close_all_crafting()
		hud.toggle_bag()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_C:
		# C oeffnet das Grundhandwerk - jetzt als Basic-Crafts-Seite im Buch.
		# Steht man an einer Station, hat deren Fenster weiterhin Vorrang.
		var was_station := _open_station()
		if was_station == null:
			_close_all_crafting()
			hud.open_craft_page()
		elif hud.bag_open():
			hud.toggle_bag()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F:
		_use_selected()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		# Leertaste = Angeln (Olta in der Hand + direkt am Wasser).
		if not _any_window_open():
			_try_fish()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_X or event.physical_keycode == KEY_X:
		# Admin-Kreativinventar auf/zu. physical_keycode als Fallback fuer
		# abweichende Tastatur-Layouts. Log, damit wir sehen ob die Taste
		# ankommt und ob der Admin-Modus aktiv ist.
		print("[Admin] X gedrueckt - creative=%s is_admin=%s" % [creative != null, _is_admin])
		if creative != null:
			if hud.bag_open():
				hud.toggle_bag()
			_close_all_crafting()
			creative.toggle()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Q:
		if _drop:
			_drop.drop_selected()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_K:
		# Skills-Fenster auf/zu.
		if skills_hud != null:
			skills_hud.toggle()
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


## Ein Axtschlag ist gefallen: der ausgewaehlten Axt einen Dayaniklilik-Punkt
## abziehen. Bei 0 zerbricht sie - Feld leeren, Meldung, und has_axe sofort
## selbst auf false setzen, damit der laufende Faell-Auftrag noch in
## derselben Runde stoppt (nicht erst beim naechsten _process).
func _on_axe_swung() -> void:
	_wear_selected(1)


## Nutzt das ausgewaehlte Werkzeug um `amount` Dayaniklilik ab (Axtschlag,
## Fels-Abbau). Bei 0 zerbricht es - Feld leeren, Meldung, has_axe zuruecksetzen.
func _wear_selected(amount: int) -> void:
	var i := hud.selected
	var slot: Dictionary = inventory.slots[i]
	if slot.is_empty() or not ItemDB.has_durability(slot["id"]):
		return
	# Frische Alete tragen noch kein "dur" - dann als voll behandeln.
	var dur: int = int(slot.get("dur", ItemDB.max_durability(slot["id"])))
	dur -= amount
	if dur > 0:
		slot["dur"] = dur
		inventory.changed.emit()   # Dayaniklilik-Cubugu neu zeichnen
		return
	# Zerbrochen.
	inventory.slots[i] = {}
	inventory.changed.emit()
	if player != null:
		player.has_axe = false
	_notice("Alet kirildi")


func _on_stone_collected(_cell: Vector2i, _level: int, gather_id: String) -> void:
	if GatherDB.has(gather_id):
		_grant(gather_id, GatherDB.amount(gather_id))
	else:
		_grant("tas", stone_per_pickup)
	_set_ctx_hint("")


## Ein beim Fels-Abbau herausgeschlagenes Stueck: im Multiplayer als Boden-Item
## (leicht gestreut) ueber DropSync, im Einzelspieler direkt ins Inventar.
func _on_mine_drop(cell: Vector2i, drop_id: String) -> void:
	if Net.active and _drop != null and player != null:
		var lvl := maxi(player.world.top_level_at(cell), 0)
		var ang := randf() * TAU
		var r := randf_range(6.0, 16.0)
		var off := Vector2(cos(ang) * r, sin(ang) * r * 0.5)   # Iso-Ellipse
		_drop._request_drop.rpc_id(1, drop_id, 1, cell, lvl, off)
	else:
		_grant(drop_id, 1)


func _on_felled(_cell: Vector2i, _level: int, _atlas: Vector2i) -> void:
	# Im Multiplayer faellt das Holz als Boden-Item (server-autoritativ in
	# world_sync.gd, ueber die Schlaege verteilt) - NICHT direkt ins Inventar,
	# sonst gaebe es das Holz doppelt. Nur im Einzelspieler direkt gutschreiben.
	if Net.active:
		return
	_grant("odun", wood_per_tree)


## Holz fuer einen im Multiplayer (server-autoritativ) gefaellten Baum - wird
## von world_sync beim toedlichen Schlaeger aufgerufen (dort laeuft kein
## felled-Signal, um Doppel-Verteilung zu vermeiden).
func grant_wood_for_tree() -> void:
	_grant("odun", wood_per_tree)


func _on_stump_cleared(_cell: Vector2i) -> void:
	_grant("odun", wood_per_stump)


const CropDB := preload("res://scripts/crop_db.gd")

## Samen gepflanzt (nur lokal ausgeloest) -> 1 Samen abbuchen.
func _on_planted(_cell: Vector2i, crop_id: String, _started: float) -> void:
	var seed: String = CropDB.CROPS[crop_id]["seed"]
	inventory.remove(seed, 1)


## Reife Pflanze geerntet -> Produkt + ein paar Samen (Nutzerwunsch), Menge je
## im Bereich der crop_db. So traegt sich der Anbau selbst.
func _on_crop_harvested(_cell: Vector2i, crop_id: String) -> void:
	var d: Dictionary = CropDB.CROPS[crop_id]
	var pc: Array = d["produce_count"]
	var sc: Array = d["seed_return"]
	_grant(String(d["produce"]), randi_range(int(pc[0]), int(pc[1])))
	_grant(String(d["seed"]), randi_range(int(sc[0]), int(sc[1])))


# --- Essen (Hunger) -----------------------------------------------------

## Isst ein Stueck des gewaehlten Essens: stillt Hunger, verbraucht 1.
func _eat_selected(id: String) -> void:
	if _needs == null or not _needs.has_method("eat"):
		_notice("Aclik sistemi kapali")
		return
	if PlayerStatsScript.hunger >= PlayerStatsScript.hunger_max:
		_notice("Karnin tok")
		return
	_needs.eat(float(ItemDB.food_value(id)))
	inventory.remove(id, 1)
	_notice("%s yedin  (+%d Aclik)" % [ItemDB.display_name(id), ItemDB.food_value(id)])
	hud.update_food_hint()   # war es das letzte Stueck -> Hinweis ggf. ausblenden


# --- Giesskanne (Sulama Kabi) -------------------------------------------

## Aktuelle Ladungen der gewaehlten Kanne (Dayaniklilik). -1 = keine Kanne.
func _can_charges() -> int:
	var slot: Dictionary = inventory.slots[hud.selected]
	if slot.is_empty() or not ItemDB.is_watering_can(String(slot["id"])):
		return -1
	return int(slot.get("dur", ItemDB.max_durability("sulama_kabi")))


## Giessen anstossen (von interaction): nur wenn Ladung da ist.
func try_water(cell: Vector2i) -> void:
	if _can_charges() <= 0:
		_notice("Sulama kabi bos")
		return
	player.water_crop(cell)


## Auffuellen anstossen (von interaction): an eine Wasserkachel laufen.
func try_fill(cell: Vector2i) -> void:
	player.fill_can(cell)


## Zieht nach erfolgreichem Giessen 1 Ladung ab (zerbricht NICHT bei 0).
func _use_can_charge() -> void:
	var i := hud.selected
	var slot: Dictionary = inventory.slots[i]
	if slot.is_empty() or not ItemDB.is_watering_can(String(slot["id"])):
		return
	var dur := int(slot.get("dur", ItemDB.max_durability("sulama_kabi")))
	slot["dur"] = maxi(0, dur - 1)
	inventory.changed.emit()


## Kanne am Wasser voll auffuellen.
func _fill_can_full() -> void:
	var i := hud.selected
	var slot: Dictionary = inventory.slots[i]
	if slot.is_empty() or not ItemDB.is_watering_can(String(slot["id"])):
		return
	slot["dur"] = ItemDB.max_durability("sulama_kabi")
	inventory.changed.emit()
	_notice("Sulama kabi dolu")


func _grant(id: String, amount: int) -> void:
	var left := inventory.add(id, amount)
	if left > 0:
		push_warning("Inventar voll: %d x %s gingen verloren" % [left, id])


## "E" ist eine Kontextaktion: liegt ein Stein in Reichweite, wird er
## aufgehoben; steht ein fertiges Lagerfeuer da, wird abgeholt - sonst wird
## der ausgewaehlte Gegenstand benutzt.
## Ist irgendein Spiel-Fenster offen? (Dann macht F nichts - Escape schliesst.)
func _any_window_open() -> bool:
	return (chest_hud != null and chest_hud.is_open()) \
		or (furnace_hud != null and furnace_hud.is_open()) \
		or (skills_hud != null and skills_hud.is_open()) \
		or _open_station() != null or crafting.is_open() or hud.bag_open() \
		or (creative != null and creative.is_open())


## F = ausgewaehltes Item benutzen (platzieren/essen) oder vor den Fuessen
## aufheben. OEffnet KEINE Truhen/Stationen mehr - das macht der Rechtsklick.
var _fishing := false

## Leertaste am Wasser: mit Olta in der Hand auswerfen, kurz warten, Fisch fangen.
func _try_fish() -> void:
	if player == null or _any_window_open() or _fishing:
		return
	if player.held_item_id != "olta":
		return
	var water := player.water_in_reach()
	if water == Player.INVALID_CELL:
		_notice("Su kenarinda olmalisin")
		return
	_fishing = true
	player.begin_fishing(water)             # Auswurf-Animation, danach Pause
	_notice("Balik bekleniyor...")
	await get_tree().create_timer(randf_range(3.0, 10.0)).timeout
	if not is_instance_valid(player):
		_fishing = false
		return
	# Zwischendurch weggegangen/Angel gewechselt -> abbrechen.
	if player.held_item_id != "olta" or player.water_in_reach() == Player.INVALID_CELL:
		_fishing = false
		player.end_fishing()
		return
	player.reel_fishing()                   # Einhol-Animation nochmal
	await get_tree().create_timer(0.6).timeout
	_fishing = false
	if not is_instance_valid(player):
		return
	player.end_fishing()
	# Verschleiss pro Wurf (auch bei Fehlversuch).
	if player.held_item_id == "olta":
		_wear_selected(1)
	# Einfache Angel: 50% Fangchance.
	if randf() < 0.5:
		_grant(ItemDB.random_raw_fish(), 1)
		SkillsXPScript.gain("fishing", 5.0)   # Balikci-XP
		_notice("Balik yakalandi!")
	else:
		_notice("Balik kacti")


func _use_selected() -> void:
	if player == null or _any_window_open():
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
	# Kochen laeuft ueber den Ofen (Rechtsklick), nicht mehr per F am Feuer.
	var slot: Dictionary = inventory.slots[hud.selected]
	if slot.is_empty():
		return
	# Essbares (Mais, Fleisch): F stillt den Hunger.
	if ItemDB.is_food(slot["id"]):
		_eat_selected(slot["id"])
		return
	if preview == null:
		return
	if slot["id"] == "kamp_atesi":
		preview.begin_campfire()
		hud.set_hint("Sol tik koy  ·  Sag tik veya Esc iptal")
	elif ItemDB.is_building(slot["id"]):
		preview.begin_building(slot["id"])
		hud.set_hint("Sol tik koy  ·  R döndür  ·  duz zemin gerekli  ·  Sag/Esc iptal")
	elif ItemDB.is_furniture(slot["id"]):
		preview.begin_furniture(slot["id"])
		hud.set_hint("Sol tik koy  ·  R döndür  ·  Sag tik veya Esc iptal")


func _on_placement_confirmed(top_cell: Vector2i) -> void:
	# Was gesetzt wird, verraet die Vorschau - so bleibt hier eine Stelle,
	# egal ob Lagerfeuer, Moebel oder Gebaeude.
	if preview.kind == PlacementPreview.Kind.CAMPFIRE:
		if player.place_campfire_at(top_cell):
			inventory.remove("kamp_atesi", 1)
	elif preview.kind == PlacementPreview.Kind.BUILDING:
		if player.place_building_at(preview.item_id, top_cell, preview.orient):
			inventory.remove(preview.item_id, 1)
	elif player.place_furniture_at(preview.item_id, top_cell, preview.orient):
		inventory.remove(preview.item_id, 1)


## Schliesst das oberste offene Fenster. false, wenn keines offen war -
## dann darf Escape weiterlaufen (die Platzieren-Vorschau haengt daran).
func _close_windows() -> bool:
	if chest_hud != null and chest_hud.is_open():
		chest_hud.set_open(false)
		return true
	if furnace_hud != null and furnace_hud.is_open():
		furnace_hud.set_open(false)
		return true
	if skills_hud != null and skills_hud.is_open():
		skills_hud.set_open(false)
		return true
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
