# SerdarsGame — 2.5D Isometric Survival (Godot 4.7)

> **Weiterarbeiten?** Erst `AGENTS.md` lesen. Dort steht der aktuelle
> Stand (Rohstoffe, Handwerk, Pixel-Font, Steuerung) und was offen ist.
> Dieses Dokument beschreibt die Grundlagen; Steuerung und Inventar-Kapitel
> sind inzwischen teilweise überholt.

Die Map wird **im Godot-Editor** gebaut, mit dem normalen TileMap-Editor.
Es gibt keinen Ingame-Builder.

## Map bauen
1. `scenes/world.tscn` öffnen.
2. Links im Szenenbaum die Ebene wählen: **Level00** (Boden), **Level01**
   (eine Stufe höher), … bis **Level11**.
3. Unten öffnet sich das TileMap-Panel mit dem kompletten Sheet als
   Palette — malen wie bei jeder normalen TileMap. Die Blöcke rasten
   pixelgenau ins isometrische Grid ein und stapeln sich korrekt.
4. In der Werkzeugleiste des TileMap-Panels **„Ausgewählte Ebene
   hervorheben"** aktivieren — dann werden die anderen Ebenen abgedunkelt.
5. Alternativ am **World**-Node `Editor Focus Level` setzen: alle Ebenen
   darüber werden ausgeblendet, damit du frei an die untere Ebene kommst.
   `-1` = alles sichtbar.

Mehr Höhe nötig? Eine Level-Node duplizieren und fortlaufend `LevelNN`
nennen — Offset und Zeichenreihenfolge setzt das Skript automatisch.

`scenes/world.tscn` enthält bereits eine Beispielmap (Hügel mit Stufen,
Plattform auf Stelzen, Kistenturm, See) — als Vorlage gedacht, einfach
überschreiben.

## Wie das Stapeln funktioniert
Das Sheet `assets/RPG-isometric-free.png` ist ein 32×32-Raster
(margin 2/0, separation 2/0). Ein Block = Top-Diamant **32×16** plus
**8 px** Seitenfläche.

`scripts/iso_world.gd` (`@tool`) hält deshalb jede Ebene *n* um
`n * 8 px` nach oben versetzt und setzt `z_index = n`. Untere Ebenen
werden zuerst gezeichnet — die korrekte Maler-Reihenfolge für
achsenparallele Würfel. Innerhalb einer Ebene sortiert der TileMapLayer
isometrisch selbst (`y_sort_enabled`). Das Skript erzeugt keine Nodes,
es richtet nur die vorhandenen aus — die Map bleibt reine Editor-Arbeit.

## Testen
F5 startet `scenes/main.tscn`. Kamera: WASD / mittlere Maustaste,
Mausrad = Zoom.

## API für Gameplay (`IsoWorld`)
| Funktion | Zweck |
|---|---|
| `top_level_at(cell)` | begehbare Höhe der Säule, `-1` = leer (ohne Props) |
| `top_atlas_at(cell)` | Tile-Typ des obersten Blocks (z. B. Ressource) |
| `has_block(cell, level)` | ist die Zelle auf dieser Ebene belegt? |
| `has_prop(cell)` | steht dort ein solides Prop (Baum …)? |
| `pick_block(world_pos)` | Block unter der Maus → `[cell, level]` |
| `world_to_cell` / `cell_to_world` | Umrechnung Maus ↔ Grid |
| `set_block` / `erase_block` | Laufzeit-Änderungen (Abbauen, Bauen) |

## Dateien
- `scenes/world.tscn` — **hier wird die Map gebaut**
- `scenes/main.tscn` — Spielszene (World + Kamera)
- `scripts/iso_world.gd` — Ebenen-Ausrichtung + Gameplay-Abfragen
- `scripts/grid_overlay.gd` — Raster als Bauhilfe im Editor
- `scripts/view_camera.gd` — Testkamera
- `tilesets/iso_tileset.tres` — TileSet (isometrisch, 32×16)


## Charakter: Jack

Von PixelLab.ai geladen (3 States, 8 Richtungen, 48×48). Aus den
Einzelframes wurden Spritesheets gebaut:

| Sheet | Inhalt |
|---|---|
| `jack_idle.png` | 8 Richtungen, 1 Frame (aus den Rotationen) |
| `jack_walk.png` | 8 × 6 Frames |
| `jack_run.png` | 8 × 4 Frames |
| `jack_axe.png` | 8 × 9 Frames (Axtschlag) |

Layout: eine Zeile pro Richtung, Reihenfolge
`south, south-east, east, north-east, north, north-west, west, south-west`.
`resources/jack_frames.tres` enthält daraus 32 Animationen
(`walk_north_east`, `axe_south`, …). Das Original-ZIP liegt unter
`assets/characters/jack/_source_pixellab.zip`.


> **Frame-Raster:** Die Quell-Frames von PixelLab sind **nicht alle gleich
> gross** — die Axt-Animation liefert je nach Richtung 60, 64 oder 68 px
> statt 48. Der erste Sheet-Bau hat sie in ein 48er-Raster geklebt, wodurch
> jeder Frame in seine Nachbarn überlief. Sichtbar wurde das erst durch den
> Umriss-Shader, der 1 px über den Frame hinaus tastet und dann fremde
> Pixel las. Jetzt liegen alle Animationen auf einem gemeinsamen Raster:
> **68 px Inhalt, mittig, plus 2 px transparenter Rand** (Zelle 72). Die
> grösseren Quell-Leinwände sind zentrierte Erweiterungen, deshalb liegen
> die Fusspunkte danach exakt aufeinander. Neue Sheets immer so bauen —
> ohne Rand blutet jeder Randeffekt in den Nachbar-Frame.

### Steuerung
| Taste | Aktion |
|---|---|
| Linksklick | Jack läuft zur angeklickten Stelle |
| Rechtsklick auf einen Baum | hinlaufen und fällen |
| WASD / Pfeiltasten | Laufen (8 Richtungen), bricht einen Klick-Auftrag ab |
| Shift | Rennen |
| Leertaste | Axtschlag (blockiert bis die Animation durch ist) |
| 1–9 | Hotbar-Feld wählen |
| F | Kontextaktion: aufheben, benutzen, platzieren |
| E oder I | Tasche öffnen und schliessen |
| C | Handwerk öffnen und schliessen |
| Esc | oberstes Fenster schliessen |
| L | Laterne an/aus |
| Mausrad | Zoom |

### Bewegung & Höhe
`scripts/player.gd` bewegt Jack frei im Bildschirmraum (Y-Achse um
`y_squash` gestaucht, damit das Tempo in der Iso-Perspektive gleichmässig
wirkt) — kein Einrasten auf Zellen. Die Höhe kommt aus `IsoWorld`:

- Jack steht immer auf dem obersten Block seiner Zelle.
- Stufen bis `max_step` (Standard 1) sind begehbar, höhere Wände und
  Löcher blockieren. Bewegung wird pro Achse geprüft, dadurch gleitet er
  an Kanten entlang statt hängen zu bleiben.
- Beim Höhenwechsel hängt er sich in den `TileMapLayer` über seinem
  Standblock um. Godots Y-Sort sortiert ihn dadurch korrekt zwischen die
  Blöcke dieser Ebene — er verschwindet hinter höheren Blöcken und läuft
  vor niedrigeren durch.

Zur Laufzeit ist er über die Gruppe `player` erreichbar
(`get_tree().get_first_node_in_group("player")`), **nicht** über einen
festen Szenenpfad — er wechselt ja den Parent.



## Maus-Steuerung und Fällen

`scripts/interaction.gd` (Node `Interaction` in `main.tscn`) verarbeitet
die Maus, `scripts/grid_path.gd` rechnet die Wege.

**Wegfindung:** A* über die Zellen, bei jeder Anfrage frisch gerechnet —
die Karte ändert sich ja, sobald ein Baum fällt. Begehbar ist ein Schritt
nur, wenn dort Boden liegt, kein Prop steht und der Höhenunterschied
höchstens `max_step` beträgt. Die Suche ist auf 4000 Knoten gedeckelt,
damit ein unerreichbares Ziel nicht die ganze Karte durchkämmt.

> **Nachbarschaft:** Das TileSet nutzt Godots *Stacked*-Layout, dort hängen
> die Nachbarzellen von der Zeilen-Parität ab (bei geradem `y` liegen die
> westlichen Nachbarn bei `x-1`, bei ungeradem die östlichen bei `x+1`).
> `IsoWorld.neighbors()` kapselt das — nicht selbst `(±1, 0)` annehmen,
> sonst springen die Wege diagonal durch die Landschaft.

**Hover-Rand:** `scripts/outline.gdshader` färbt transparente Pixel ein,
die an undurchsichtige grenzen. Abgetastet werden nur die vier
Himmelsrichtungen, keine Diagonalen — mit Diagonalen bekommen die
Treppenkanten der Pixelart an jeder Stufe von zwei Seiten Rand und wirken
doppelt so dick. Über `thickness` am Material weiter justierbar. Das `Interaction`-Node legt dafür ein
Sprite mit genau der Atlas-Region des Baums an derselben Stelle darüber.
Der Treffertest ist **pixelgenau**: erst Rechteck, dann Alpha-Wert im
Sheet. Man trifft also die Krone, nicht ein unsichtbares Kastenfeld.
Überlappende Bäume werden wie beim Zeichnen sortiert (erst Ebene, dann
Bildschirm-Y), sodass immer der vorderste anspringt.

**Fällen:** Rechtsklick sucht die nächste begehbare Nachbarzelle des
Baums, läuft hin, dreht sich zum Baum und schlägt `chops_to_fell` mal
(Standard 6, im Inspector am Player änderbar). Danach verschwindet der Baum und `Player` sendet das Signal
`felled(cell, atlas)` — dort hängst du später Inventar und Ressourcen an.
`atlas` sagt, welche Baumart es war.


### Fäll-Effekte

Ein Tile kann nicht wackeln. Beim ersten Schlag wird das Prop-Tile deshalb
entfernt und durch `scripts/tree_actor.gd` ersetzt — einen Sprite2D mit
derselben Atlas-Region an derselben Stelle. Der Node-Ursprung liegt auf dem
Stammfuß, damit der Baum um seinen Fuß schwingt statt um die Bildmitte.

Pro Treffer: gedämpftes Schwingen, eine Ladung Holzspäne (`CPUParticles2D`,
2×2-Pixel-Textur zur Laufzeit erzeugt — spart eine Asset-Datei) und ein
kurzer Kamera-Ruck über `FollowCamera.shake()`. Der Treffer wird an Frame
`axe_impact_frame` der Axt-Animation ausgelöst, nicht am Ende — sonst wirkt
der Ruck versetzt zum Bild.

Beim letzten Schlag: kräftigerer Ausschlag, dicke Spanwolke, dann
**Ausblenden**. Bewusst kein Umkippen — in dieser Perspektive sieht das
Kippen um den Stammfuß falsch aus.

Bricht man mitten im Fällen ab (WASD), setzt `TreeActor.restore()` das Tile
mit der richtigen Baumart zurück. Damit das überhaupt greift, wird die
Abbruch-Prüfung in `_physics_process` **vor** dem `busy`-Guard gemacht —
sonst käme man während der Axt-Animation nie durch und der Baum bliebe
dauerhaft verschwunden.

Stellschrauben: `shake_degrees`, `shake_speed`, `shake_damping`, `fade_time`
am `TreeActor`; `hit_shake`, `fell_shake`, `axe_impact_frame` am `Player`.

## Inventar und Ressourcen

Drei Teile, sauber getrennt:

| Datei | Aufgabe |
|---|---|
| `scripts/item_db.gd` | Was es an Gegenständen gibt (Name, Stapelgrösse, Icon) |
| `scripts/inventory.gd` | Reines Datenmodell: Slots, Stapeln, Umlegen |
| `scripts/inventory_hud.gd` | Hotbar und Tasche, komplett im Code aufgebaut |
| `scripts/player_inventory.gd` | Verbindet die drei mit dem Spielgeschehen |

**Ertrag:** Ein gefällter Baum gibt `wood_per_tree` Holz (Standard 4), ein
gerodeter Stumpf `wood_per_stump` (Standard 1). Das hängt an den Signalen
`Player.felled` und `Player.stump_cleared`, die es vorher schon gab.

**Bedienung:** `1`–`9` wählen ein Hotbar-Feld, `E` öffnet die Tasche.
Umgelegt wird per Drag & Drop (`scripts/inventory_slot.gd`), zwischen
Hotbar und Tasche in beide Richtungen: gleiche Sorte wird zusammengeführt,
verschiedene getauscht. Maus über ein Feld zeigt den Namen.

**Icons** werden aus dem vorhandenen Block-Sheet geschnitten
(`ItemDB.ITEMS[...]["cell"]` ist die Zelle darin), es braucht also keine
zusätzlichen Grafiken. Ein neues Item ist ein Eintrag in `ItemDB.ITEMS`
plus eine Stelle, die `inventory.add()` aufruft.

**Zwei Fallstricke, die eingebaut sind:**

- Ein `PanelContainer` mit `PRESET_CENTER` setzt nur seine **Ecke** in die
  Bildmitte und wächst nach rechts unten. Die Tasche steckt deshalb in
  einem `CenterContainer` über den ganzen Bildschirm.
- Bei offener Tasche liegt eine abdunkelnde `ColorRect`-Sperrfläche mit
  `MOUSE_FILTER_STOP` darunter. Ohne sie rutscht ein Klick neben der
  Tasche als Laufbefehl in die Welt durch.

## Lagerfeuer

`assets/props/camp.png` ist ein 4x3-Raster mit 128er-Zellen. Die Frames
werden **spaltenweise** gezählt (oben nach unten, dann nächste Spalte):

| Frame | Inhalt | Animation |
|---|---|---|
| 1, 2 | Zelt, zwei Seiten | noch nicht benutzt |
| 3 | Feuer aus | `aus` |
| 4 | Feuer brennt, nichts am Spiess | `ohne_fleisch` (Reserve) |
| 5–10 | Feuer mit rohem Fleisch | `brennt` |
| 11 | Fleisch durchgebraten | `fertig` |

**Ablauf:** anzünden → `brennt` → nach `cook_seconds` (30 s) → `fertig`
→ abgeholt → `aus`. Das Fleisch ist Teil der Brenn-Animation, nicht ein
Extra — deshalb ist `brennt` die Frame-Folge 5–10 und nicht Frame 4.

> Frame 6 ist eine exakte Kopie von 5 und verdoppelt damit eine Pose in
> der Schleife. Bewusst so gelassen, weil die Vorgabe 5–10 lautet — wenn
> es stockend wirkt, einfach die 6 aus `campfire_frames.tres` streichen.
> Frame 10 und 11 haben dieselbe Silhouette und unterscheiden sich nur in
> der Fleischfarbe, roh gegen durchgebraten.

**Massstab:** Das Camp-Sheet ist grösser gezeichnet als der Rest (101 px
breit gegenüber 32 px beim Baum). `art_scale = 0.5` bringt es auf ein
Verhältnis, das zu Jack passt — im Vergleichsrender war die volle Grösse
etwa viermal zu gross.

**Bedienung — `E` ist eine Kontextaktion:**

1. Steht ein Lagerfeuer mit fertigem Fleisch in Reichweite (eigene Zelle
   oder Nachbarzelle), wird abgeholt: Feuer geht aus, `Gebratenes Fleisch`
   landet im Inventar.
2. Sonst startet der **Platzieren-Modus** für den ausgewählten Gegenstand.

**Platzieren-Modus** (`scripts/placement_preview.gd`): Das Lagerfeuer klebt
halbdurchsichtig am Mauszeiger, umrandet in **Weiss**. Passt es an der
Stelle nicht, wird der Rand **rot**. Linksklick setzt, Rechtsklick, `Esc`
oder nochmal `E` bricht ab. Solange der Modus läuft, schluckt die Vorschau
alle Klicks — es rutscht also kein Laufbefehl oder Fällauftrag durch, und
das Baum-Hover ist ausgeschaltet.

> Beides in einem Node: der Umriss-Shader kann Körper und Rand getrennt
> steuern. `fill_alpha = 0.5` macht den Körper halbdurchsichtig,
> `outline_color` schaltet zwischen Weiss und Rot.

> **Falle beim Platzieren-Modus:** Der Abbruch über `E` muss **vor** allen
> anderen Prüfungen stehen. Lag er weiter unten, blieb die Vorschau
> hängen, sobald man zwischendurch ein anderes Hotbar-Feld wählte — die
> Prüfung `slot.is_empty()` sprang vorher heraus. Und weil die Vorschau
> alle Mausklicks schluckt, liess sich die Figur dann nicht mehr bewegen,
> ohne dass die Ursache erkennbar war. Deshalb zeigt das HUD jetzt
> zusätzlich eine Hinweiszeile, solange ein Modus die Klicks abfängt.

**Das Lagerfeuer belegt ein 2x2-Feld.** Im Stacked-Layout sind das die
Zellen `top`, `top+(0,1)`, `top+(dx,1)` und `top+(0,2)` — auf dem
Bildschirm eine grosse Raute, 64 px breit und 32 px hoch
(`IsoWorld.footprint_2x2()`). Gesetzt wird nur, wenn alle vier Zellen
Boden haben, frei sind und **auf derselben Höhe liegen** — ein Feuer soll
nicht über eine Stufe hinweg stehen. Alle vier Zellen werden blockiert.

**Massstab und Ankerpunkt:** Das Camp-Sheet ist grösser gezeichnet als der
Rest (101 px breit gegenüber 32 px beim Baum), deshalb `ART_SCALE = 0.5`.
Der Anker `ART_OFFSET = (-64, -88)` setzt das Feuer mittig auf das Feld:

- `x = 64` ist die waagerechte Mitte des **gesamten Bildinhalts** (13..113),
  nicht die Mitte der Glut. Die rechte Spiessstange steht weiter raus als
  die linke — auf die Glut zentriert wirkte das Ganze rechtslastig.
- `y = 88` setzt die Aschfläche so, dass sie das 2x2-Feld ausfüllt. Auf
  dem Fusspunkt (112) sass das Feuer sichtbar zu weit oben im Feld.

Beide Werte stehen als Konstanten in `campfire.gd`, damit die Vorschau
exakt das zeigt, was nachher gesetzt wird.

Das Feuer hängt im selben y-sortierten Props-Container wie Bäume und Jack,
sortiert sich also korrekt ein, und blockiert seine Zelle über
`IsoWorld.block_cell()` — die Wegfindung läuft darum herum.

## Look & Beleuchtung

Der Stil kommt aus einem Post-Processing-Pass plus einem weichen
Tageslicht — keine platzierten Einzellichter.

| Datei | Zweck |
|---|---|
| `scripts/day_night.gd` | Tageslicht-Zyklus (`CanvasModulate`) |
| `scripts/vignette.gdshader` | weiche Randabdunklung |
| `scripts/flicker_light.gd` | unruhiges Licht (für Laterne/Feuer) |
| `scripts/blob_shadow.gd` | weicher Schattenwurf unter Figuren |
| `resources/light_gradient.tres` | Lichtabfall-Textur für Light2D |

**Bloom** liegt auf dem `WorldEnvironment` in `scenes/main.tscn`
(`glow_intensity 0.72`, `glow_hdr_threshold 0.7`, `glow_bloom 0.06`) — nur die hellsten
Pixel glühen, damit die Pixelart scharf bleibt. Dazu leichte
Sättigungsanhebung (1.05).

> **Nicht** `rendering/viewport/hdr_2d` aktivieren. Das schiebt den
> 2D-Canvas durch das Tonemapping und frisst die Farben — getestet, sah
> deutlich matter aus. Bloom funktioniert auch ohne, über einen
> `glow_hdr_threshold` unter 1.0.

**Tageslicht:** Der `DayNight`-Node färbt die Szene weich von kühlem
Mondlicht über Sonnenaufgang und goldene Stunde zurück in die Nacht.
Bewusst flach gehalten — auch nachts bleibt alles lesbar.
`day_length` = Sekunden pro Tag (Standard **1200**, also 20 Minuten; `0` hält den Zyklus an). Das Skript ist
`@tool`: `time_of_day` im Inspector schieben zeigt die Stimmung direkt im
Editor-Viewport. Kompletter Austausch über `sky_gradient`.

**Vignette:** ColorRect mit Shader auf einem eigenen `CanvasLayer`, damit
sie vom Tageslicht unberührt bleibt. Stärke und Weichheit sind
Shader-Parameter im Inspector.

**Laterne:** Jack hat ein `PointLight2D`, standardmässig **aus**. Mit
**L** einschalten — es dimmt dann über `DayNight.darkness()` automatisch
mit der Tageszeit. Vorlage für Feuer, Lampen oder Leuchtitems.

### Zeichenreihenfolge bei hohen Objekten

Der `z_index` eines TileMapLayers schlägt **jede** Y-Sortierung. Als Tile
bekäme ein Baum `Ebene + 16` — ein Baum auf einem Hügel läge damit immer
über allem darunter, auch über einer Figur, die eindeutig davor steht.

Deshalb werden Bäume und Stümpfe beim **Spielstart** einmalig aus den
TileMapLayern geholt und in Sprite-Nodes umgewandelt
(`IsoWorld._spawn_prop_nodes()`). Alle Props **und** der Spieler hängen in
einem einzigen y-sortierten Container `World/Props` mit `z_index = 16`.
Damit entscheidet nur noch die Bildschirmposition, und das ist in dieser
Perspektive genau richtig: wer weiter unten steht, ist vorn.

Am Editor-Ablauf ändert das nichts — gemalt wird weiter ganz normal als
Tile auf `LevelNN`.

**Der Preis:** Terrain, das **vor** einer Figur oder einem Prop liegt und
höher ist, verdeckt sie nicht mehr — Jack bleibt sichtbar, wenn er hinter
eine Mauer läuft. Das ist in Iso-Spielen eine übliche Wahl (die Figur geht
nie verloren). Sauber lösbar wäre auch das nur, indem hohe Sprites pro
Höhenebene zerlegt werden.

### Figur hinter Objekten sichtbar halten

`scripts/occlusion_outline.gd` blendet einen weissen Umriss der Figur ein,
sobald ein Baum sie verdeckt. Der Node spiegelt Bild für Bild die Animation
des Spieler-Sprites und zeichnet sie mit `fill_alpha = 0` — also nur den
Rand — bei `z_index 50` über allem anderen.

Der Verdeckungstest hat drei Stufen, jede davon war nötig:

1. **Wer liegt vorn?** Props und Spieler hängen im selben y-sortierten
   Container, deshalb genügt der Vergleich der Fusspunkt-Y: was weiter
   unten steht, wird später gezeichnet und liegt vorn.
2. **Sichtbare Ausdehnung statt Tile-Rechteck.** Ein Tile ist 32×64, der
   Baum darin aber deutlich schmaler und oben mehrere Pixel leer. Geprüft
   wird gegen `IsoWorld.prop_content_rect()` — den tatsächlich
   undurchsichtigen Bereich, einmal pro Baumart aus dem Sheet berechnet und
   gemerkt.
3. **Mindestüberdeckung** (`min_cover`, Standard 0,28). Ohne diese
   Schwelle genügte schon eine Kronenspitze, die Jacks Füsse streift —
   dann erschien der Umriss, obwohl er praktisch voll sichtbar war.

Gemessen: der Umriss springt an, solange der Baumfuss höchstens ~32 px
unter Jack steht; ab ~48 px bleibt er aus.

**Stümpfe sind ausgenommen:** Ein Stumpf ist nur 14 px hoch, sein
Tile-Rechteck aber 64 — ohne den Filter löste er den Umriss fälschlich aus.

Der Node wird von `player.gd` zur Laufzeit erzeugt, damit `player.tscn`
dafür nicht angefasst werden muss. Stellschrauben im Skript: `color`,
`core_size`, `min_cover`, `check_radius`.

### Wandernde Schatten

`scripts/cast_shadow.gd` wirft für Bäume, Stümpfe, Lagerfeuer und Jack
einen Schatten, der dem Sonnenstand folgt.

**Warum nicht Godots 2D-Schatten:** Die bräuchten pro Objekt ein
`LightOccluder2D` mit Polygon und würden Silhouetten im Bildschirmraum
werfen, die die Iso-Geometrie ignorieren. Stattdessen wird die Grafik
selbst ein zweites Mal gezeichnet — schwarz, am Fusspunkt verankert,
geschert und gestreckt.

**Die Scherung** bildet ab, was physikalisch passiert: ein Punkt in Höhe
`h` über dem Boden landet im Schatten bei `fuss + richtung * h * laenge`.
Als `Transform2D` heisst das: x-Achse bleibt, y-Achse wird auf
`-richtung * laenge` gelegt. Ein Zweizeiler, kein Shader nötig.

**Der Sonnenstand** kommt aus `day_night.gd` und ist rein aus
`time_of_day` abgeleitet, ohne eigenen Zustand:

| Funktion | Bedeutung |
|---|---|
| `sun_elevation()` | 0 bei Auf- und Untergang, 1 mittags |
| `shadow_dir()` | Bildschirmvektor: morgens nach Westen, abends nach Osten |
| `shadow_length()` | `shadow_length_low` (1.9) bis `shadow_length_high` (0.55) |
| `shadow_strength()` | Deckkraft, nachts 0, an den Rändern weich ausgeblendet |

Das Y der Richtung ist bewusst flach (0.5), damit der Schatten auf der
Iso-Bodenebene liegt statt senkrecht nach unten zu kippen.

Die Schatten liegen auf `z_index = -1` relativ zum Props-Container, also
unter allen Objekten und über dem Boden. Sie haben `light_mask = 0` und
leuchten dadurch nicht mit. Der weiche Blob unter Jack
(`blob_shadow.gd`) bleibt als Kontaktschatten, ist aber dezenter
geworden, damit er den geworfenen nicht überlagert.

Stellschrauben am `DayNight`-Node: `sunrise`, `sunset`,
`shadow_length_low/high`, `shadow_alpha`. Pro Objekt zusätzlich
`extra_alpha` am `CastShadow` — das Lagerfeuer steht z. B. auf 0.7, weil
es flacher baut.

## Bäume und Stümpfe

`assets/props/baeume.png` ist **Quelle 1** im TileSet (17 Bäume, 32×64),
`assets/props/baumstumpf.png` ist **Quelle 2** (der Stumpf). Die Trennung
ist wichtig, weil beide unterschiedlich funktionieren:

| | Quelle 1 — Baum | Quelle 2 — Stumpf |
|---|---|---|
| Bewegung | blockiert | begehbar |
| Rechtsklick | 6 Axtschläge, fällt | 1 Schlag, endgültig weg |
| danach | Stumpf erscheint | nichts |

**Kreislauf:** Baum fällen → Stumpf erscheint → nach `regrow_seconds`
(Standard 300 s = 5 min) wächst **dieselbe Baumart** wieder nach. Entfernt
der Spieler den Stumpf vorher per Rechtsklick, ist die Stelle endgültig
geräumt. Das steuert `scripts/regrowth.gd` (Node `Regrowth` in
`main.tscn`) über die Signale `Player.felled(cell, level, atlas)` und
`Player.stump_cleared(cell)`. `Regrowth.time_left(cell)` gibt die Restzeit
— praktisch für eine spätere Anzeige.

**Regel beim Malen: Props kommen auf die Ebene *über* ihren Bodenblock** —
genau wie ein gestapelter Block. Boden auf `Level00` → Baum auf `Level01`.

> **Vorzeichen von `texture_origin`:** Godot **subtrahiert** den Wert von
> der Zeichenposition, ein *positiver* Y-Wert schiebt die Textur nach
> **oben**. Formel für neue Props mit Fußpunkt `(bx, by)` in einer
> Region der Größe `(w, h)`: `origin = (round(bx) - w/2, by - h/2 - 8)`.
> Für 32×64 also `(round(bx) - 16, by - 40)`. Alle 17 Bäume und der Stumpf
> teilen sich den Fußpunkt (14,5 / 53) und damit `(-2, 13)`.
> Immer gegen das Grid prüfen, nicht gegen die Textur: ein falsch
> gesetztes Prop landet auf gleichförmigem Gras einfach auf einer anderen
> Kachel und sieht trotzdem plausibel aus.

## Wann eine eigene Szene?

Eine eigene `.tscn` bekommt, was **mehrfach vorkommt oder unabhängig
wiederverwendbar** ist — `player.tscn` (könnte mehrfach existieren),
`world.tscn` (eigenständige Map). Einmalige Dinge gehören direkt als
Nodes in die Elternszene: Kamera, Vignette und `WorldEnvironment` sind
deshalb einfach Kinder von `main.tscn`, und deren Environment- und
Shader-Material-Ressourcen liegen als `[sub_resource]` inline in der
Szene statt in eigenen Dateien.

Faustregel: erst inline bauen, erst herausziehen, wenn du es ein zweites
Mal brauchst.

## Nächste Schritte für Survival

Der aktuelle Stand und die offenen Punkte stehen in **`AGENTS.md`**.
Kurz: Axt-Rezept fehlt, Möbel lassen sich noch nicht aufstellen, die
Werkbank ist noch keine Station.

Assets: CanadianBoy (`assets/LICENSE-CanadianBoy.txt`) — frei nutzbar, nicht weiterverkaufen.
