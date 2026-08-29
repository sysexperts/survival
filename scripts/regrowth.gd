extends Node

## Baumstümpfe und ihr Nachwachsen - und dasselbe für Steine.
##
## Ablauf: Baum fällt -> Stumpf erscheint und bekommt eine Uhr. Läuft sie
## ab, wächst genau dieselbe Baumart wieder nach. Entfernt der Spieler den
## Stumpf per Rechtsklick, ist die Stelle endgültig geräumt.
##
## Aufgehobene Steine tauchen nach einer Weile an derselben Stelle wieder
## auf, sonst wäre die Karte nach ein paar Minuten leergeräumt.

@export var world_path: NodePath = ^"../World"
## Sekunden, bis aus einem Stumpf wieder ein Baum wird.
@export var regrow_seconds := 300.0
## Sekunden, bis an einer abgeräumten Stelle wieder ein Stein liegt.
@export var stone_seconds := 240.0
## Atlas-Koordinate des Stumpf-Tiles in Quelle 2.
@export var stump_atlas := Vector2i(0, 0)

var world: IsoWorld
var player: Player

## cell -> {"level": int, "atlas": Vector2i, "left": float}
var _pending: Dictionary = {}
## Dasselbe für aufgehobene Steine.
var _stones: Dictionary = {}
## Endgültig geräumte Zellen (Stumpf gerodet, eingestreuter Rohstoff geholt).
## Hier wächst nichts nach - der ChunkManager darf hier auch nichts mehr neu
## generieren, sonst käme das Gefällte/Geerntete beim Nachladen des Chunks
## zurück. cell -> true.
var _cleared: Dictionary = {}


func _ready() -> void:
	world = get_node(world_path) as IsoWorld
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.felled.connect(_on_felled)
		player.stump_cleared.connect(_on_stump_cleared)
		player.stone_collected.connect(_on_stone_collected)
		# Abgebaute Felsen sind endgueltig weg (wie geholte Rohstoffe).
		player.mined.connect(func(cell, _d): _cleared[cell] = true)


func _process(delta: float) -> void:
	# Über eine Kopie der Schlüssel laufen: _grow() verändert das Dictionary.
	for cell in _pending.keys():
		var entry: Dictionary = _pending[cell]
		entry["left"] -= delta
		if entry["left"] <= 0.0:
			_grow(cell, entry)
	for cell in _stones.keys():
		var entry: Dictionary = _stones[cell]
		entry["left"] -= delta
		if entry["left"] <= 0.0:
			_respawn_stone(cell, entry)


## Oeffentliche Fassungen fuer den Multiplayer-Sync (world_sync.gd): dieselben
## Effekte, wenn ein ANDERER Spieler die Aktion ausgeloest hat.
func replicate_felled(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	_on_felled(cell, level, atlas)


func replicate_stump_cleared(cell: Vector2i) -> void:
	_on_stump_cleared(cell)


func replicate_stone_collected(cell: Vector2i, level: int, gather_id: String) -> void:
	_on_stone_collected(cell, level, gather_id)


func _on_felled(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	world.set_prop(cell, level, stump_atlas, IsoWorld.STUMP_SOURCE_ID)
	_pending[cell] = {"level": level, "atlas": atlas, "left": regrow_seconds}


func _on_stump_cleared(cell: Vector2i) -> void:
	_pending.erase(cell)
	_cleared[cell] = true         # endgültig - ChunkManager generiert hier nichts mehr


func _grow(cell: Vector2i, entry: Dictionary) -> void:
	_pending.erase(cell)
	var level: int = entry["level"]
	# Falls in der Zwischenzeit doch jemand den Stumpf abgeräumt hat oder
	# etwas anderes auf der Zelle steht: nichts tun.
	if not world.has_stump(cell):
		return
	world.remove_prop(cell, level)
	world.set_prop(cell, level, entry["atlas"], IsoWorld.PROP_SOURCE_ID)


## Eingestreute Rohstoffe wachsen NICHT nach - was weg ist, ist weg.
## Nur die von Hand in die Karte gemalten Steine kommen wieder.
func _on_stone_collected(cell: Vector2i, level: int, gather_id: String) -> void:
	if gather_id != "":
		# Chunk-generierte Rohstoffe (Äste, Fasern, Stein) wachsen NICHT nach.
		# Ohne Vermerk erzeugt der ChunkManager sie beim Nachladen deterministisch
		# neu - deshalb die Zelle endgültig sperren.
		_cleared[cell] = true
		return
	var atlas := IsoWorld.STONE_ATLAS[randi() % IsoWorld.STONE_ATLAS.size()]
	_stones[cell] = {"level": level, "atlas": atlas, "left": stone_seconds}


## Der neue Stein ist bewusst nicht zwingend derselbe wie der aufgehobene -
## mal liegt da ein groesserer Haufen, mal ein einzelner Kiesel.
func _respawn_stone(cell: Vector2i, entry: Dictionary) -> void:
	_stones.erase(cell)
	var level: int = entry["level"]
	# Steht dort inzwischen etwas anderes, faellt der Stein aus.
	if world.prop_node(cell) != null or world.blocker_at(cell) != null:
		return
	world.set_prop(cell, level, entry["atlas"], IsoWorld.STONE_SOURCE_ID)


## Restzeit eines Stumpfs in Sekunden, -1 wenn dort keiner wartet.
## Praktisch für eine spätere Anzeige.
func time_left(cell: Vector2i) -> float:
	return _pending[cell]["left"] if _pending.has(cell) else -1.0


# --- Vom ChunkManager beim Generieren gefragt --------------------------------

## Was soll auf dieser Zelle statt des generierten Props stehen?
## ""      = normal generieren (nichts geändert)
## "stump" = ein Stumpf (Baum gefällt, wächst noch nach)
## "empty" = gar nichts (endgültig geräumt / Rohstoff geholt)
## So bleibt Gefälltes/Geerntetes auch nach dem Nachladen eines Chunks weg.
func suppresses_prop(cell: Vector2i) -> String:
	if _pending.has(cell):
		return "stump"
	if _cleared.has(cell) or _stones.has(cell):
		return "empty"
	return ""


# --- Vom Netzwerk beim Beitritt wiederhergestellt (world_sync.gd) ------------

## Ein anderswo gefällter Baum: Stumpf setzen (falls Boden geladen), vorhandenen
## Baum entfernen, Nachwachs-Uhr mit der RESTZEIT starten. Ist der Chunk noch
## nicht da, genügt der _pending-Eintrag - der ChunkManager setzt den Stumpf
## dann beim Generieren (suppresses_prop).
func restore_felled(cell: Vector2i, level: int, atlas: Vector2i, remaining: float) -> void:
	var n := world.prop_node(cell)
	if n != null and n.source_id == IsoWorld.PROP_SOURCE_ID:
		world.remove_prop(cell, level)
	if world.top_level_at(cell) >= 0 and not world.has_stump(cell):
		world.set_prop(cell, level, stump_atlas, IsoWorld.STUMP_SOURCE_ID)
	_pending[cell] = {"level": level, "atlas": atlas, "left": remaining}


## Ein anderswo endgültig gerodeter Stumpf / geholter Rohstoff: Zelle sperren
## und alles Vorhandene entfernen.
func restore_cleared(cell: Vector2i) -> void:
	_pending.erase(cell)
	_cleared[cell] = true
	if world.prop_node(cell) != null:
		world.remove_prop(cell)


## Ein anderswo aufgehobener (gemalter) Stein: Respawn-Uhr mit Restzeit starten.
func restore_stone_collected(cell: Vector2i, level: int, remaining: float) -> void:
	if world.has_stone(cell):
		world.remove_prop(cell, level)
	var atlas := IsoWorld.STONE_ATLAS[randi() % IsoWorld.STONE_ATLAS.size()]
	_stones[cell] = {"level": level, "atlas": atlas, "left": remaining}
