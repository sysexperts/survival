extends Sprite2D
class_name TreeActor

## Ein Baum, solange er gefällt wird.
##
## Tiles können nicht wackeln, deshalb wird das Prop-Tile beim ersten Schlag
## entfernt und durch diesen Node ersetzt. Er zeigt exakt dieselbe
## Atlas-Region an derselben Stelle, kann aber schwingen, Späne werfen und
## am Ende ausblenden. Wird der Auftrag abgebrochen, setzt der Player das
## Tile über `restore()` zurück.

signal finished

## Ausschlag des Schwingens in Grad, klingt gedämpft ab.
@export var shake_degrees := 2.6
@export var shake_speed := 26.0
@export var shake_damping := 7.0
## Dauer des Ausblendens beim letzten Schlag.
@export var fade_time := 0.5

## Ruhiges Wiegen im Wind, wenn gerade niemand hackt. Bewusst winzig: bei
## 0.9 Grad und einer Krone rund 40 px ueber dem Fuss wandert die Spitze
## keinen ganzen Pixel weit - man sieht Bewegung, aber kein Zappeln.
@export var sway_degrees := 0.9
## Dauer einer vollen Schwingung in Sekunden.
@export var sway_period := 3.6
## Zweite, langsamere Welle darueber - ohne sie wirkt das Wiegen mechanisch.
@export var gust_period := 11.0

var cell: Vector2i
var level: int
var atlas: Vector2i
var source_id: int = IsoWorld.PROP_SOURCE_ID
## Nur bei eingestreuten Rohstoffen gesetzt (siehe GatherDB). Leer bedeutet:
## ein gemaltes Prop aus dem TileSet.
var gather_id := ""
## Fels-Zustand (RockDB-Reihe) oder -1, wenn kein Fels. Steuert Abbau + Drop.
var rock_state := -1

const RockDB := preload("res://scripts/rock_db.gd")

## Amplitude ist immer positiv, die Richtung steckt in _dir. Ein
## vorzeichenbehaftetes _swing würde die Abbruchbedingung unten sofort
## auslösen und das Wackeln nach links komplett verschlucken.
var _swing := 0.0
var _dir := 1.0
var _phase := 0.0
var _done := false
## Zeitversatz je Baum, damit nicht der ganze Wald im Gleichtakt wiegt.
var _sway_offset := 0.0
var _sway_scale := 1.0
var _chips: CPUParticles2D


static func create(world: IsoWorld, p_cell: Vector2i, p_level: int, p_atlas: Vector2i,
		p_source: int = IsoWorld.PROP_SOURCE_ID) -> TreeActor:
	var src := world.tile_set_res.get_source(p_source) as TileSetAtlasSource
	var region_size := src.texture_region_size
	var origin := Vector2(src.get_tile_data(p_atlas, 0).texture_origin)

	var a := TreeActor.new()
	a.cell = p_cell
	a.level = p_level
	a.atlas = p_atlas
	a.source_id = p_source

	var tex := AtlasTexture.new()
	tex.atlas = src.texture
	# Nicht selbst rechnen: das Boden-Sheet (aus dem die Steine kommen) hat
	# Rand und Abstand zwischen den Kacheln, die Quelle kennt beides.
	tex.region = Rect2(src.get_tile_texture_region(p_atlas))
	tex.filter_clip = true
	a.texture = tex
	a.centered = false
	# Der Node-Ursprung soll auf dem Stammfuß liegen, damit der Baum um
	# seinen Fuß schwingt statt um die Bildmitte. Aus texture_origin lässt
	# sich der Fußpunkt zurückrechnen: bx = origin.x + 16, by = origin.y + 40.
	if region_size.y == 32:
		# Steine: quadratische Kachel, die um den Zellmittelpunkt liegt.
		a.offset = -Vector2(origin.x + 16.0, origin.y + 16.0)
	else:
		a.offset = -Vector2(origin.x + 16.0, origin.y + 40.0)
	return a


## Ein eingestreuter Rohstoff. Kommt nicht aus dem TileSet, sondern direkt
## aus dem Item-Sheet - deshalb ein eigener Bauweg statt `create()`.
##
## Er läuft unter STONE_SOURCE_ID, damit er dieselbe Behandlung bekommt wie
## ein Stein: begehbar, anleuchtbar, mit E aufsammelbar. Was dabei ins
## Inventar wandert, entscheidet `gather_id`.
static func create_gather(p_cell: Vector2i, p_level: int, p_id: String,
		p_sheet_cell: Vector2i) -> TreeActor:
	var a := TreeActor.new()
	a.cell = p_cell
	a.level = p_level
	a.atlas = p_sheet_cell
	a.source_id = IsoWorld.STONE_SOURCE_ID
	a.gather_id = p_id

	var tex := AtlasTexture.new()
	tex.atlas = GatherDB.sheet_of(p_id)
	tex.region = Rect2(GatherDB.region_for(p_id, p_sheet_cell))
	tex.filter_clip = true
	a.texture = tex
	a.centered = false
	# Nicht die 32x32-Kachel ausrichten, sondern das, was man davon sieht.
	# Die Icons sitzen unterschiedlich in ihren Kacheln - wer die Kachel
	# zentriert, bekommt Props, die neben ihrer Zelle zu liegen scheinen.
	var b := GatherDB.content_bounds_for(p_id, p_sheet_cell)
	var s := GatherDB.scale_of(p_id)
	var anchor := Vector2(b.position.x + b.size.x * 0.5, 0.0)
	if GatherDB.anchor_of(p_id) == "foot":
		# Aufrechte Pflanze: unterer Rand auf die Mitte des Diamanten.
		anchor.y = b.position.y + b.size.y
	else:
		# Liegt flach: die Bildmitte auf die Mitte des Diamanten.
		anchor.y = b.position.y + b.size.y * 0.5
	# Auf ganze Bildschirmpixel runden. `offset` zaehlt im unskalierten
	# Bild; bei halber Groesse wird aus einem halben Bildpixel ein viertel
	# Bildschirmpixel, und bei vierfachem Kamerazoom sieht man genau das
	# als schiefes Prop.
	a.offset = -(anchor * s).round() / s
	a.scale = Vector2(s, s)
	return a


## Ein abbaubarer Fels (RockDB). Rendert aus assets/props/rocks.png, Variante
## `variant` (damit nicht jeder Fels gleich aussieht). Blockiert wie ein Baum,
## wird aber mit der Spitzhacke abgebaut.
static func create_rock(p_cell: Vector2i, p_level: int, state: int, variant: int) -> TreeActor:
	var a := TreeActor.new()
	a.cell = p_cell
	a.level = p_level
	a.atlas = Vector2i(variant, state)          # nur zur Info (Sheet-Spalte/Reihe)
	a.source_id = IsoWorld.ROCK_SOURCE_ID
	a.rock_state = state
	var tex := AtlasTexture.new()
	tex.atlas = load(RockDB.SHEET)
	tex.region = Rect2(RockDB.region(state, variant))
	tex.filter_clip = true
	a.texture = tex
	a.centered = false
	# Fuss (Bild-Unterkante-Mitte) auf die Zellmitte: 48px-Zelle, Basis bei ~y=42.
	a.offset = -Vector2(24, 42)
	return a


func _ready() -> void:
	# Aus der Zelle abgeleitet statt zufaellig: derselbe Baum wiegt nach
	# einem Neustart gleich, und benachbarte Baeume laufen trotzdem
	# auseinander.
	var key := float(cell.x * 73 + cell.y * 149)
	_sway_offset = fmod(absf(key), TAU)
	_sway_scale = 0.75 + fmod(absf(key * 0.37), 0.5)
	# Stuempfe stehen still, Steine erst recht. Eingestreute Pflanzen
	# duerfen sich wiegen - Holz und Stein liegen dafuer zu schwer da.
	if source_id != IsoWorld.PROP_SOURCE_ID:
		_sway_scale = 0.0
	if gather_id == "bitki_lifi":
		_sway_scale = 0.6 + fmod(absf(key * 0.37), 0.5)
	# Ein gemalter Stein liegt flach am Boden - ein geworfener Schatten
	# wuerde von seiner Mitte ausgehen und daneben liegen.
	#
	# Eingestreute Rohstoffe stehen dagegen auf der Zelle wie ein kleiner
	# Baum. Sie bekommen denselben geworfenen Schatten, nur schwaecher -
	# so liegen sie im selben Sonnenlicht wie alles andere, statt als
	# einziges ohne Schatten aufzufallen.
	if gather_id != "":
		var sh := CastShadow.create(self)
		sh.extra_alpha = GatherDB.SHADOW_ALPHA
		add_child(sh)
	elif source_id != IsoWorld.STONE_SOURCE_ID:
		add_child(CastShadow.create(self))
	_chips = CPUParticles2D.new()
	_chips.texture = _chip_texture()
	_chips.emitting = false
	_chips.one_shot = true
	_chips.explosiveness = 0.9
	_chips.amount = 14
	_chips.lifetime = 0.55
	_chips.position = Vector2(0, -6)          # auf Stammhöhe
	_chips.spread = 55.0
	_chips.initial_velocity_min = 28.0
	_chips.initial_velocity_max = 70.0
	_chips.gravity = Vector2(0, 190)
	_chips.scale_amount_min = 0.7
	_chips.scale_amount_max = 1.4
	_chips.damping_min = 8.0
	_chips.damping_max = 20.0
	_chips.color = Color(0.62, 0.44, 0.26)
	_chips.z_index = 1
	add_child(_chips)


## Kleine Holzspäne: ein 2x2-Pixel-Quadrat reicht, das skalieren die
## Partikel selbst. Spart eine Asset-Datei.
func _chip_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _swing > 0.001:
		_phase += delta * shake_speed
		_swing = move_toward(_swing, 0.0, _swing * shake_damping * delta)
	rotation_degrees = sin(_phase) * _swing * _dir + _sway()


## Wiegen im Wind: eine schnelle Grundwelle, ueberlagert von einer langsamen
## Boe. Beide laufen ueber die Spielzeit, damit alle Baeume im selben Wind
## stehen - nur eben zeitversetzt.
func _sway() -> float:
	if _sway_scale <= 0.0 or _done:
		return 0.0
	var t := float(Time.get_ticks_msec()) / 1000.0 + _sway_offset
	var base := sin(t * TAU / sway_period)
	var gust := 0.6 + 0.4 * sin(t * TAU / gust_period)
	return base * gust * sway_degrees * _sway_scale


func _burst(count: int, away: Vector2, up: float) -> void:
	_chips.amount = count
	_chips.direction = Vector2(away.x, up).normalized()
	_chips.restart()
	_chips.emitting = true


## Ein Axtschlag ist gelandet. `away` zeigt vom Spieler zum Baum und
## bestimmt, wohin Späne und Ausschlag gehen.
func hit(away: Vector2) -> void:
	if _done:
		return
	_swing = shake_degrees
	_dir = 1.0 if away.x >= 0.0 else -1.0
	_phase = 0.0
	_burst(14, away, -1.2)


## Letzter Schlag: kräftiger Ausschlag, dicke Spanwolke, dann ausblenden.
## Bewusst kein Umkippen - in dieser Perspektive sieht das Kippen um den
## Stammfuß falsch aus.
func fell(away: Vector2) -> void:
	if _done:
		return
	_done = true
	_swing = shake_degrees * 1.8
	_dir = 1.0 if away.x >= 0.0 else -1.0
	_phase = 0.0
	_burst(30, away, -0.9)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, fade_time)
	tw.tween_callback(func():
		finished.emit()
		queue_free())


## Bricht ein angefangenes Fällen ab: Schwingen stoppen, gerade stellen.
## Der Node bleibt erhalten - er war nie weg.
func reset() -> void:
	if _done:
		return
	_swing = 0.0
	rotation_degrees = _sway()
