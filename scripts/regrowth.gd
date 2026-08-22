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


func _ready() -> void:
	world = get_node(world_path) as IsoWorld
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.felled.connect(_on_felled)
		player.stump_cleared.connect(_on_stump_cleared)
		player.stone_collected.connect(_on_stone_collected)


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


func _on_felled(cell: Vector2i, level: int, atlas: Vector2i) -> void:
	world.set_prop(cell, level, stump_atlas, IsoWorld.STUMP_SOURCE_ID)
	_pending[cell] = {"level": level, "atlas": atlas, "left": regrow_seconds}


func _on_stump_cleared(cell: Vector2i) -> void:
	_pending.erase(cell)


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
