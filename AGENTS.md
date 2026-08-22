# Übergabe an die nächste KI

Kurzbriefing für alle, die an diesem Projekt weiterarbeiten. Die
`README.md` beschreibt die **Grundlagen** (Map bauen, Isometrie-Stapelung,
Beleuchtung, Fällen) und gilt weiterhin — dieses Dokument beschreibt, was
seitdem dazugekommen ist, und wo die offenen Enden liegen.

**Godot 4.7**, Hauptszene `scenes/main.tscn`. Sprache im Projekt ist
**Deutsch**: Item-Ids, Kommentare, Oberflächentexte. Bitte beibehalten.

---

## Wie der Nutzer arbeitet

- Er beschreibt Wünsche auf Deutsch, oft mit angehängten Bildausschnitten
  aus den Sheets („das erste Bild ist X"). Wenn ein Bild fehlt oder nicht
  ankommt: **nachfragen statt raten**. Falsch geratene Zellen kosten mehr
  Zeit als eine Rückfrage.
- Zum Identifizieren von Sheet-Zellen hilft ein Rasterbild: Sheet mit
  Python/PIL vergrössern, Gitter und Spalten-/Zeilennummern darüberlegen,
  ansehen. Genau so wurden alle Zellen unten gefunden.
- Er testet selbst im Editor. Änderungen sollten deshalb **ohne
  Editor-Handgriffe** funktionieren — Szenen werden im Code aufgebaut,
  nicht in `.tscn` zusammengeklickt.

## Testen ohne Editor

Godot liegt unter
`C:\Users\sysexperts\AppData\Local\GodotEngine\Godot_v4.7.1-stable_win64_console.exe`.

```bash
godot --headless --path <projekt> --quit-after 90
```

Prüft, dass alles fehlerfrei lädt und läuft. Für alles Weitere hat sich
bewährt: ein temporäres `tools/_shot.gd` schreiben, als Node in
`main.tscn` hängen, Spielzustand darin herstellen, Werte per `print`
ausgeben und mit
`get_viewport().get_texture().get_image().save_png("user://x.png")` ein
Bild machen (landet in
`%APPDATA%\Godot\app_userdata\SerdarsGame\`). **Danach wieder entfernen** —
weder das Skript noch der Node gehören ins Projekt.

Ein Bildschirmfoto von aussen (PowerShell, `PrintWindow`) funktioniert
**nicht**: Godot rendert über die GPU, das Fenster kommt schwarz zurück.

Neue `class_name`-Skripte und neue Assets sind erst nach einem
Editor-Durchlauf bekannt:

```bash
godot --headless --editor --path <projekt> --quit
```

Ohne das bricht der Start mit „Identifier ... not declared" ab. Der Fehler
`res://_gen.gd not found` ist alt und harmlos.

---

## Was es gibt

### Rohstoffe auf der Karte

| Datei | Aufgabe |
|---|---|
| `scripts/gather_db.gd` | Welche Grafik, welche Ausbeute, wie dicht gesät |
| `scripts/resource_scatter.gd` | Verteilt sie beim Spielstart |
| `scripts/tree_actor.gd` | `create_gather()` baut den Prop-Node |

Holz (Äste), Pflanzenfaser (Baumwolle) und Stein werden beim Start über
die begehbaren Zellen gestreut — fester Seed, Mindestabstand, Freiraum um
den Startpunkt. **Aufgesammeltes wächst nicht nach**; `scripts/regrowth.gd`
lässt eingestreute Rohstoffe bewusst aus und kümmert sich nur um die von
Hand in die Karte gemalten Steine und die Baumstümpfe.

Technisch laufen sie unter `IsoWorld.STONE_SOURCE_ID` und erben damit die
komplette Stein-Behandlung (begehbar, anleuchtbar, mit `F` aufsammelbar).
Was ins Inventar wandert, entscheidet `TreeActor.gather_id`.

Drei Dinge, die dabei leicht schiefgehen und schon gefixt sind — bitte
nicht versehentlich zurückdrehen:

- `IsoWorld.remove_prop()` darf bei eingestreuten Rohstoffen **nicht** die
  Bodenkachel löschen. Sie liegen obendrauf, gemalte Steine nicht.
- Alles, was ein Prop-Bild braucht (Hervorhebung, Treffertest), muss über
  `prop_texture()` / `prop_scale()` / `prop_alpha_at()` gehen. Die
  Atlas-Koordinate eines Rohstoffs existiert im TileSet nicht; eine leere
  Region lässt sonst das ganze Sheet aufblitzen.
- Ausgerichtet wird am **sichtbaren Umriss** (`GatherDB.content_bounds()`),
  nicht an der 32×32-Kachel, und der Offset wird auf ganze
  Bildschirmpixel gerundet. Bei vierfachem Kamerazoom sieht man jedes
  Viertelpixel.

`GatherDB.BLOCKED_GROUND` listet Bodenkacheln, die schon ein Objekt im
Bild tragen (Büsche, Schädel) — dort wird nichts abgelegt.

### Inventar

`scripts/inventory.gd` (Datenmodell), `scripts/inventory_hud.gd` (Hotbar +
Tasche), `scripts/inventory_slot.gd` (ein Feld), `scripts/item_db.gd`
(Gegenstände), `scripts/player_inventory.gd` (verbindet alles).

Umgelegt wird per **Drag & Drop** über Godots eigenes System
(`_get_drag_data` / `_can_drop_data` / `_drop_data` in `InventorySlot`),
funktioniert zwischen Hotbar und Tasche in beide Richtungen. Das frühere
Klick-Aufnehmen-Klick-Ablegen ist raus. Maus über ein Feld zeigt den
Namen (`tooltip_text`).

Die Hotbar liegt in der Zeichenreihenfolge **über** der Sperrfläche —
sonst könnte man bei offener Tasche nichts hineinziehen.

### Handwerk

| Datei | Aufgabe |
|---|---|
| `scripts/recipe_db.gd` | Rezepte, Kosten, Bauzeit, Station |
| `scripts/craft_queue.gd` | Bauliste: was gefertigt wird, was ansteht |
| `scripts/crafting_hud.gd` | Fenster mit Stückzahl-Regler und Bauliste |

`C` öffnet das Grundhandwerk. Jedes Rezept trägt seine `station`:
`RecipeDB.HAND` geht überall, alles andere braucht eine Station.
**Dasselbe Fenster bedient später die Werkbank** — es bekommt beim
`setup()` nur eine andere Station.

Bauen dauert. Stückzahl einstellen, „Bauen" reiht ein, die Liste
arbeitet sie im Takt von `seconds` ab — auch bei geschlossenem Fenster,
weil `CraftQueue` ein eigener Node am Inventar ist.

**Zutaten werden beim Einreihen abgebucht**, nicht Stück für Stück. Sonst
liesse sich derselbe Vorrat mehrfach verplanen. Ein Abbruch gibt die
Zutaten der offenen Stücke vollständig zurück. Vor dem Bauen wird auch der
**Platz** fürs Ergebnis geprüft (`Inventory.room_for`) — sonst wären die
Zutaten weg und das Werkstück nirgends.

### Oberfläche

Die Schrift ist ein selbst gebauter Bitmap-Font, erzeugt von
`tools/build_pixel_font.py` aus **Bitstream Vera Mono** (liegt bei
Windows, Lizenz erlaubt Weitergabe und Ableitungen — anders als bei
Consolas & Co.). Zwei Varianten: `pixel` (11 px, Oberfläche) und
`pixel_bold` (9 px, Namensschild über der Figur).

Als Bitmap statt TTF, weil eine TTF bei jeder Grösse neu gerastert wird.
**Deshalb: nur ganzzahlige Vielfache der Rastergrösse benutzen** — 11 oder
22, nicht 13 oder 16. Alles andere verwäscht. Der Zeichensatz ist ASCII
plus Umlaute und ein paar Sonderzeichen; ein `−` (echtes Minuszeichen)
gibt ein leeres Kästchen, ein `-` nicht. Neue Zeichen: `CHARS` im Skript
ergänzen und neu bauen.

Eingehängt über `gui/theme/custom` in `project.godot` →
`resources/pixel_theme.tres`.

Das Namensschild (`scripts/name_plate.gd`) ist bewusst ein selbst
zeichnender `Node2D` und kein `Control`: ein Control lässt sich nicht
sauber über die Props heben, und die Figur wechselt je nach Höhenebene den
Eltern-Node.

### Steuerung (aktueller Stand)

| Taste | Aktion |
|---|---|
| Linksklick | hinlaufen |
| Rechtsklick | Baum fällen, Stumpf roden, Rohstoff holen |
| WASD / Pfeile | laufen, Shift rennen |
| 1–9 | Hotbar-Feld |
| **E** oder I | Tasche |
| **C** | Handwerk |
| **F** | Kontextaktion (aufheben, benutzen, platzieren) |
| Esc | oberstes Fenster schliessen |
| L | Laterne |

`F` war früher `E`. Die Hinweistexte in `GatherDB` nennen die Taste im
Klartext — beim Umbelegen mit ändern.

---

## Sheets und Zellen

| Sheet | Raster | Inhalt |
|---|---|---|
| `assets/props/prop1.png` | 32×32, 22×15 | Item-Icons |
| `assets/props/basic furniture.png` | **64×64**, 6×3 | Einrichtung |
| `assets/RPG-isometric-free.png` | 32×32, Rand 2 | Bodenblöcke |

Belegte Zellen in `prop1.png`: Äste `(9,9)`/`(9,11)`, Holzbündel `(9,13)`,
Baumwollpflanze `(3,0)`, Faserflocke `(5,1)`, Steine `(10,0)`–`(10,5)`,
Seil `(1,4)`, Holzbrett `(9,14)`, **Steinaxt `(15,5)`**.

Alle 17 Möbel sind als Items registriert (`ItemDB.FURNITURE`). Werkbank
`(0,1)`, Webetisch `(3,1)`.

---

## Laufendes Vorhaben: chunk-basierter World-Generator

Ziel des Nutzers: ein Minecraft-artiger Weltgenerator — neue Kartenteile
entstehen, während man in eine Richtung läuft. Optik/Aufbau wie bisher,
**Höhe maximal bis Layer 03**. Wenn das steht, kommen **Biome** dazu.

**Entscheidungen (mit dem Nutzer abgestimmt):**

- **Handbau + Prozedural drumherum.** Die gemalte Beispielmap in
  `world.tscn` bleibt als fester Startbereich stehen; generiert wird nur
  außenrum. Der Authored-Bereich wird nie überschrieben. Heikel ist der
  Grenzabgleich: geplant ist flacher Boden auf Basishöhe der Handbau-Ränder
  direkt außen, Hügel (Noise, Level 01–03) erst ein paar Zellen weiter.
- **Persistenz:** deterministische Chunk-Erzeugung (Chunk-Seed aus
  Welt-Seed + Chunk-Koordinate) **plus leichter Änderungs-Diff pro Chunk**,
  damit Aufgesammeltes/Gefälltes wegbleibt (passt zum „kein Nachwachsen"-
  Prinzip von `resource_scatter.gd` und zu `regrowth.gd`).

**Warum das Fundament passt:** `IsoWorld.set_block/erase_block` erlauben
Laufzeit-Terrain, `spawn_gather()` und die Prop-als-Node-Umwandlung sind
schon dynamisch, `GatherDB`/`ItemDB` sind datengetrieben (ideal für Biome),
A* rechnet ohnehin pro Anfrage neu.

**Umbau-Brennpunkte:**

- `IsoWorld._spawn_prop_nodes()` läuft **einmal** über alle Zellen → muss
  pro-Chunk werden (laden/entladen), sonst wächst der Node-Baum unbegrenzt.
- `ResourceScatter._scatter()` streut **einmal global** über
  `free_ground_cells()` → chunk-lokal + deterministischer Chunk-Seed.
- Das halbversetzte **Stacked-Raster** (Parität in `neighbors()`): Chunks im
  **durchgehenden** Zellkoordinatensystem generieren, nicht in lokalen
  Chunk-Koordinaten — dann bleibt die Parität an Grenzen stimmig.
- Höhe aus `FastNoiseLite`: pro Zelle Level00…03 stapeln.

**Milestones (Reihenfolge):**

1. Chunk-Streaming Boden + Höhe (`scripts/world_gen.gd` +
   `scripts/chunk_manager.gd`), Authored-Bereich aussparen. — **offen**
2. Props/Rohstoffe pro Chunk (Umbau von `_spawn_prop_nodes` + Scatter). — offen
3. Änderungs-Diff pro Chunk (an `Player.felled`/`stump_cleared`). — offen
4. Biome: zweiter, großmaßstäbiger Noise + Biom-Datentabellen im
   `*_db.gd`-Stil; Übergänge feinschleifen. — offen

**Git:** Das Projekt ist jetzt ein Git-Repo (Branch `main`), Remote
`origin` = https://github.com/sysexperts/survival (public). Erster Commit
„Stand vor World-Generator" ist der Ausgangspunkt vor dem Umbau.

## Offene Enden

1. **Die Axt hat kein Rezept.** Sie existiert als Item und `Player.chop()`
   verlangt sie in der ausgewählten Hotbar, aber sie ist nirgends
   herstellbar — Bäume sind damit vorerst gesperrt. Der Nutzer muss noch
   sagen, was sie kosten soll und ob sie ins Grundhandwerk oder an die
   Werkbank gehört.
2. **Möbel lassen sich nicht aufstellen.** Sie sind Gegenstände, mehr
   nicht. Zum Platzieren gibt es `scripts/placement_preview.gd`, das
   bisher nur das Lagerfeuer kennt (2×2, `can_place_2x2`) — das wäre der
   Ansatzpunkt für eine allgemeine Bauvorschau.
3. **Werkbank als Station.** Sobald sie in der Welt steht: `CraftingHUD`
   mit `RecipeDB.WERKBANK` aufsetzen und Rezepte dorthin verschieben.
4. **`starting_items` in `player_inventory.gd` ist eine Testfüllung**
   (Axt + 40 von allem). Für den echten Spielstart auf `{}` zurück — der
   Spieler soll mit nichts anfangen.
5. **Die README ist teilweise veraltet**, vor allem Steuerung und der
   Inventar-Abschnitt. Die Grundlagenteile stimmen.

## Konventionen

- Kommentare erklären das **Warum**, nicht das Was — und stehen dort, wo
  jemand sonst über eine Entscheidung stolpert. Siehe die vorhandenen
  Skripte, der Ton ist durchgehend so.
- Daten gehören in eine `*_db.gd` (`ItemDB`, `GatherDB`, `RecipeDB`),
  nicht verstreut in die Logik. Neue Rohstoffe, Rezepte oder Gegenstände
  sollen ein Eintrag sein, keine Codeänderung.
- Keine neuen Nodes von Hand in `.tscn` klicken, wenn es im Code geht.
- Nach jeder Änderung headless durchlaufen lassen und das Ergebnis
  **wirklich prüfen** — bei Grafik heisst das: Bild machen und ansehen.
