extends Node

## Netzwerk-Zentrale (Autoload "Net").
##
## Haelt den Spielernamen und baut die Verbindung auf. Nach erfolgreichem
## Host/Join wird die Spielszene geladen - dort uebernimmt NetGame das
## Synchronisieren der Figuren.
##
## Bewusst schlank gehalten: dieser Prototyp synchronisiert nur Position und
## Animation der Spieler, damit man sich gegenseitig laufen sieht. Welt,
## Inventar und Baeume bleiben (noch) lokal - die Welt ist ueber den festen
## Seed 1337 auf beiden Rechnern ohnehin identisch.

const PORT := 24565
const MAX_CLIENTS := 7
const GAME_SCENE := "res://scenes/main.tscn"
## Vorgabe-Serveradresse im Beitreten-Feld. Spieler muessen so nichts tippen.
## Als Hostname - so bleiben ausgelieferte Clients gueltig, auch wenn sich die
## Server-IP mal aendert.
const DEFAULT_HOST := "survival.vapur-it.de"

## Wird true, sobald eine echte Verbindung steht. Im Einzelspieler bleibt es
## false - NetGame haelt sich dann komplett raus.
var active := false
## true nur, wenn dieser Prozess ein DEDIZIERTER Server ist (headless auf dem
## Linux-Server). Dann spielt er nicht mit, sondern leitet nur die Pakete der
## Clients untereinander weiter.
var is_dedicated := false
var player_name := "Oyuncu"
## true, solange die Chat-Eingabe offen ist - der Player pausiert dann.
var chat_open := false

## Fuer das Menue: die Verbindung ist gescheitert (falsche IP / kein Server).
signal connection_failed()


## Anzeige-Version (Alpha) aus der internen Build-Nummer. Die Build-Nummer
## zaehlt in Einerschritten hoch (fuer den Updater-Vergleich), angezeigt wird
## aber "0.1", "0.2", ... Build 11 -> 0.1.
static func version_name(build: int) -> String:
	return "0.%d" % maxi(build - 10, 0)


## Startet einen Server und wechselt sofort ins Spiel. Gibt bei Erfolg einen
## leeren String zurueck, sonst eine Fehlermeldung fuers Menue.
func host() -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		return "Sunucu baslatilamadi (Hata %d).\nZaten calisiyor olabilir mi?" % err
	multiplayer.multiplayer_peer = peer
	active = true
	get_tree().change_scene_to_file(GAME_SCENE)
	return ""


## Startet einen headless-Dauerbetrieb-Server (Linux). Vermittelt nur, spielt
## nicht mit. Wird vom Menue aufgerufen, wenn das Spiel mit "--server" bzw. als
## dedizierter Server-Build gestartet wurde.
func start_dedicated_server() -> void:
	is_dedicated = true
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("Server-Start fehlgeschlagen (Fehler %d)." % err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	active = true
	multiplayer.peer_connected.connect(func(id): print("Spieler verbunden: %d" % id))
	multiplayer.peer_disconnected.connect(func(id): print("Spieler getrennt: %d" % id))
	print("=== Dedizierter Server laeuft auf UDP-Port %d ===" % PORT)
	# Verzoegern: start_dedicated_server() laeuft aus dem _ready des Menues, in
	# dem der Szenenbaum gerade Kinder umbaut - ein direkter Wechsel wirft sonst.
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


## Verbindet sich mit einem Host. Die Spielszene wird erst geladen, wenn die
## Verbindung wirklich steht (siehe _on_connected).
func join(ip: String) -> String:
	ip = ip.strip_edges()
	if ip == "":
		ip = DEFAULT_HOST
	# ENet erwartet eine IP - Hostnamen wie "survival.vapur-it.de" erst aufloesen.
	if not ip.is_valid_ip_address():
		var resolved := IP.resolve_hostname(ip, IP.TYPE_IPV4)
		if resolved == "":
			return "'%s' adresi cözümlenemedi." % ip
		ip = resolved
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return "Baglanilamadi (Hata %d)." % err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_failed, CONNECT_ONE_SHOT)
	return ""


func _on_connected() -> void:
	active = true
	# Verzoegern, damit der Signal-Callback sauber durchlaeuft, bevor die
	# Szene gewechselt wird.
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


func _on_failed() -> void:
	active = false
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


## Startet das Spiel ohne Netzwerk - alles laeuft wie im alten Einzelspieler.
func singleplayer() -> void:
	active = false
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file(GAME_SCENE)
