# Übergabe an die nächste KI

Kurzbriefing für alle, die an diesem Projekt weiterarbeiten. Die
`README.md` beschreibt die **Grundlagen** (Map bauen, Isometrie-Stapelung,
Beleuchtung, Fällen) und gilt weiterhin — dieses Dokument beschreibt, was
seitdem dazugekommen ist, und wo die offenen Enden liegen.

**Godot 4.7**, Hauptszene `scenes/main.tscn`. Sprachen: **Ingame-/UI-Texte
Türkisch** (z. B. „Canta", „Oyuncular", „Kizarmis Et"), **Code-Kommentare und
Item-Ids Deutsch**, **Kommunikation mit dem Nutzer Deutsch**. Bitte beibehalten.

---

## ⚡ Übergabe / Infrastruktur (Stand Build 39 = Anzeige „v0.29")

**Alles ist committet, gepusht und live deployt.** GitHub `origin` =
https://github.com/sysexperts/survival (Branch `main`). Lokaler Stand = Server =
`main`.

### Lokale Umgebung (Windows)
- Repo: `C:\Users\vase\Projekte\survival`
- Godot-Binary: `C:\Users\vase\OneDrive - Intelego GmbH\Desktop\Godot.exe` (4.7.2)
- SSH-Key: `~/.ssh/id_vapur_admin`
- **Kein Python/PIL** in der Bash-Umgebung (`python` schlägt fehl). Für
  Bild-Maße `file <png>` nutzen; Sprite-/Frame-Verarbeitung über ein Godot-
  Tool-Skript (siehe `tools/build_deer_frames.gd`), nicht über PIL.

### Server (Linux)
- IP **185.248.140.225** (Proxmox-Container), Website
  http://survival.vapur-it.de/ (Default-Host im Beitreten-Feld:
  `survival.vapur-it.de`).
- Zugang: `ssh -i ~/.ssh/id_vapur_admin root@185.248.140.225`
- Wichtige Pfade:
  - `/opt/survival` — Repo (hier `git pull`)
  - `/opt/godot/godot` — Godot 4.7.2 (Editor-fähig, für Import/Export headless)
  - `/var/www/survival` — Webroot (`game.pck`, `version.json`, Installer/ZIP)
  - `/opt/survival_world/` — **Welt-Persistenz**: `build.json` (gesetzte
    Möbel/Lagerfeuer), `removed.json` (Abbau: gefällt/gerodet/gesammelt, mit
    Zeitstempel) — siehe `scripts/world_sync.gd`.
  - `/opt/survival_saves/<name>.json` — Inventar pro Spielername (kein Account),
    siehe `scripts/save_sync.gd`.
  - Dienst: `survival.service` (dedizierter Relay-Server, Autostart/-Restart).
    Log: `journalctl -u survival -n 50`.

### Deploy-Ablauf (WICHTIG — der Nutzer will IMMER sofort live)
Nach **jeder** Code-Änderung die volle Auslieferung, ohne Rückfrage:
1. `version.txt` erhöhen (Build-Ganzzahl; Anzeige = `v0.(build-10)`).
2. `git add … && git commit && git push origin main`.
3. `game.pck` bauen:
   `"$GODOT" --headless --path . --export-pack "Windows Desktop" build/game.pck`
4. `version.json` schreiben — **MUSS `pck` enthalten**, sonst lädt der Updater
   nicht: `{"version":N,"pck":"game.pck"}`.
5. `game.pck` + `version.json` nach `/var/www/survival/` scp'en.
6. Auf dem Server: `cd /opt/survival && git pull && systemctl restart survival`.

**Drei Auto-Updater-Fallstricke** (die `game.pck` wird per
`load_resource_pack(replace=true)` über die Basis-`.exe` gelegt — die ersetzt
NICHT alles):
- **Neue `class_name`-Klassen** werden nicht registriert → **KEIN `class_name`
  verwenden, stattdessen `preload("res://…gd")`** (Muster: `WorldGen`,
  `SleepZzz`, `CreativeHUD`, `deer.gd`).
- **Autoloads** (z. B. `Net`) werden beim Start aus der Basis-`.exe`
  instanziert und NICHT ersetzt → neue Methoden dort fehlen am Client. Neue
  Logik in normale (nicht-Autoload) Skripte legen. (Deshalb liegt die
  Admin-Prüfung in `scripts/admins.gd`, per preload, statt in `Net`.)
- **Neue Assets (PNG o. ä.) UND neue `class_name`** brauchen vor dem
  Server-Neustart einen Editor-Import auf dem Server:
  `/opt/godot/godot --headless --editor --path . --quit`. Eingebettete `.tres`
  (z. B. `deer_frames.tres`) brauchen das NICHT. Nach dem Restart Log auf
  `SCRIPT ERROR`/`Parse Error` prüfen.

### PixelLab (Sprites/Animationen)
- API-Key: `a3aceed9-0867-4fb2-ac6c-0f45c25caf93` (auch in der Memory
  `pixellab-api.md`). Auth: `Authorization: Bearer <key>`.
- Charaktere listen: `GET https://api.pixellab.ai/v2/characters` →
  ID + `name` + `state_name`. ZIP eines States:
  `GET /v2/characters/<id>/zip` (Rotations + Animations-Frames pro Richtung).
- **Jack** (Spieler) und **deer** (Reh) liegen dort. Deer-States:
  `f02ca099…` Walking, `11d475ee…` „lay down" (+ Grasen),
  `444c2ffa…` Idle, **`31f0cac7…` „die"** (Sterbe-Animation, für die Jagd
  bereit, noch nicht geladen).
- Frames werden **fußbündig auf ein gemeinsames Raster** gelegt (Jack 72,
  Reh 64), da PixelLab je Animation unterschiedliche Frame-Größen liefert.
  Deer-Frames baut `tools/build_deer_frames.gd` (Frames aus dem gitignorierten
  `.deer_src/`, eingebettet in `resources/deer_frames.tres`).

### Was seit der letzten Übergabe dazugekommen ist
- **Bett**: Jack legt sich hinein (Rechtsklick), Liege-Pose `south_east`
  (gespiegelt `south_west`), Bild via `sprite.offset` auf die Matratze gehoben;
  **Zzz**-Effekt (`scripts/sleep_zzz.gd`) klein über dem Kopf, gespiegelt.
- **Welt-Persistenz** (`scripts/world_sync.gd`): Server merkt Möbel/Lagerfeuer
  (build.json) UND Abbau mit Restzeit (removed.json) und spielt sie Beitretenden
  vor → überlebt Neustart. Chunk-Diff (Milestone 3) ist damit **erledigt**:
  `regrowth.suppresses_prop()` + `chunk_manager.gd` verhindern, dass Gefälltes
  beim Nachladen wiederkommt.
- **Admin/Gamemaster**: `scripts/admins.gd` (`NAMES=["serdar"]`). Admins bekommen
  Taste **X** = Kreativ-Inventar (`scripts/creative_hud.gd`, alle Items) und ein
  **GM-Abzeichen** über dem Kopf (`assets/gamemaster.png`, animiert in
  `name_plate.gd`).
- **TAB-Spielerliste** (`net_game.gd`), **Inventar 6 Taschenzeilen**
  (`player_inventory.gd bag_rows`).
- **Baum-Durability**: geteilte, server-autoritative HP
  (`world_sync._tree_hit`, `TREE_MAX_HP=6`) — zwei Spieler fällen doppelt so
  schnell; HP wird geloggt. Einzelspieler zählt lokal.
- **Reh** (`scripts/deer.gd`, `scripts/deer_spawner.gd`): wandert, ist scheu
  (flieht vor Spielern), legt sich hin/steht auf, Baby-Rehe. **MP-Sync per
  Host-Autorität**: der Server bestimmt den Client mit kleinster Peer-ID zum
  „Deer-Host", der simuliert und den Zustand übers Relay verteilt; andere zeigen
  Remote-Rehe. Spawnt nahe **jedem** Spieler.

### Offene nächste Schritte (Priorität grob absteigend)
1. **Feldbett-Layering-Bug**: hinter dem Feldbett stimmt die Zeichenreihenfolge
   nicht ganz, und die Liege-Pose passt nicht (mein `BED_SLEEP_OFFSET` in
   `player.gd` ist für „bett" getunt; das flachere Feldbett braucht eigene Werte
   und ggf. eine Prüfung der Y-Sortierung/`TerrainOcclusion`).
2. **Reh jagen/töten**: die „die"-Animation (`31f0cac7…`) laden, ins
   `deer_frames.tres` aufnehmen; Angriff (Speer/Waffe) + Reh-Tod als
   world_sync-Ereignis (analog Baum-Fall) an alle verteilen; Drop (Fleisch →
   `gebratenes_fleisch`/Rohfleisch). Achtung: das Reh wird bisher nur vom
   Deer-Host simuliert — Treffer müssen an den Host/Server laufen.
3. **Bessere Reh-Autorität**: der dedizierte Server simuliert nichts (kein
   Terrain, kein lokaler Spieler → `ChunkManager` läuft dort nicht). Aktuell
   löst das die Host-Autorität. Für robustere NPCs später überlegen, ob der
   Server Terrain generieren soll.
4. **Milestone 4 — Biome**: zweiter, großmaßstäbiger Noise + Biom-Tabellen im
   `*_db.gd`-Stil (siehe unten „Laufendes Vorhaben").
5. **Axt-Rezept** fehlt weiterhin (Item existiert, aber nicht herstellbar).

### Kleiner Hinweis
`removed.json` wurde beim Aufräumen eines Test-Baums einmal komplett geleert —
ein paar Abbau-Diffs echter Spieler sind dadurch zurückgesetzt (kein
Bau-Verlust; Abbau wächst ohnehin nach). Beim nächsten Mal nur den einzelnen
Test-Eintrag entfernen, nicht die ganze Datei.

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
| **M** | Vollbildkarte an/aus (Links-/Rechtsklick = Wegpunkt setzen/löschen); der Zielpfeil oben rechts zeigt zum aktiven Wegpunkt (kleine Pfeile schalten um) |

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
   `scripts/chunk_manager.gd`), Authored-Bereich aussparen. — **erledigt**
2. Props/Rohstoffe pro Chunk (Umbau von `_spawn_prop_nodes` + Scatter). — **erledigt**
3. Änderungs-Diff pro Chunk (an `Player.felled`/`stump_cleared`). — **erledigt**
   (`regrowth.gd` merkt geräumte/gefällte Zellen und bietet `suppresses_prop()`;
   `chunk_manager.gd` fragt es beim Generieren, damit Gefälltes/Geerntetes beim
   Nachladen wegbleibt. Der dedizierte Server persistiert Abbau **und** Bauten
   in `/opt/survival_world/` und spielt sie beim Beitritt vor — siehe
   `world_sync.gd`. Überlebt Server-Neustart.)
4. Biome: zweiter, großmaßstäbiger Noise + Biom-Datentabellen im
   `*_db.gd`-Stil; Übergänge feinschleifen. — offen

**Git:** Das Projekt ist jetzt ein Git-Repo (Branch `main`), Remote
`origin` = https://github.com/sysexperts/survival (public). Erster Commit
„Stand vor World-Generator" ist der Ausgangspunkt vor dem Umbau.

### Milestone 1 — erledigt (so wurde es umgesetzt)

Boden + Höhe entstehen chunk-weise um den Spieler, der Handbau-Bereich bleibt
unangetastet. Noch **keine** Props/Rohstoffe (das ist Milestone 2).

**Was dazugekommen ist:**

- `scripts/world_gen.gd` (`class_name WorldGen`, reine Logik): `FastNoiseLite`
  mit festem Welt-Seed. `noise_height(cell)` → 0..3, `height_at(cell, dist)`
  blendet über `EDGE_RING` (3) Zellen vom Handbau-Rand (`BASE_HEIGHT` 0) in
  die Noise-Höhe, damit keine harte Stufe entsteht.
- `IsoWorld` merkt sich beim Spielstart **vor** `_spawn_prop_nodes()` in
  `_record_authored()` alle gemalten Zellen (`authored_cells`) plus eine
  Bounding-Box (`authored_bounds`). `is_authored()`, `in_authored_bounds()`
  und `dist_to_authored()` steuern, was generiert wird. Der Generator spart
  die **ganze Bounding-Box** aus, nicht nur bemalte Zellen — sonst würde der
  See (unbemalte Lücke) mit Gras zugeschüttet.
- `scripts/chunk_manager.gd` (`class_name ChunkManager`, Node in `main.tscn`):
  findet Welt + Spieler (Gruppe `player`, deferred, weil der Spieler den
  Parent wechselt), bestimmt gedrosselt (alle 0,2 s) den Spieler-Chunk, lädt
  Chunks im `RADIUS` (2) und entlädt jenseits `RADIUS+1`. Chunkgröße 16 im
  **durchgehenden** Zellkoordinatensystem (Stacked-Parität). Pro Update nur
  wenige Chunks (`LOAD_BUDGET`), der erste Load beim Start ungedrosselt.
  Entladen löscht nur die selbst generierten Blöcke (gemerkt pro Chunk).

### Milestone 2 — erledigt (Boden-Varianz + Props pro Chunk)

- `WorldGen` entscheidet jetzt zusätzlich datengetrieben: `ground_atlas(cell)`
  wählt aus drei Grüntönen (`GRASS`) bzw. Erdkacheln (`DIRT`) - Erdflächen über
  eine eigene Noise (`is_dirt`, `DIRT_THRESHOLD`). `prop_at(cell)` liefert pro
  Zelle nichts, einen Baum (Wald-Noise lässt sie klumpen: `TREE_P_MEADOW` →
  `TREE_P_FOREST`) oder einen Rohstoff (`holz`/`pflanzenfaser`/`stein`). Alles
  über einen reinen Koordinaten-Hash (`_hash`/`_rand`), also reihenfolge-
  unabhängig reproduzierbar.
- `ChunkManager._gen_cell()` setzt Bodensäule (oberste Ebene = Deckkachel),
  `_place_prop()` platziert Baum (`set_prop`, eine Ebene über dem Boden) oder
  Rohstoff (`spawn_gather`, deterministisches Sheet-Bild). Pro Chunk werden
  Blöcke UND Prop-Zellen gemerkt; `_unload_chunk()` räumt beides weg
  (`remove_prop` + `erase_block`), sonst wächst der Node-Baum.
- Lückenlücke am Übergang behoben: statt die ganze Bounding-Box auszusparen,
  wird nur je gemalte Zelle übersprungen (`is_authored`). Die Randhöhe wird an
  den **tatsächlichen** Nachbarn angeglichen (`IsoWorld.nearest_authored()` →
  bündig, keine Stufe/Lücke am konkaven Rand). `authored_cells` speichert dazu
  jetzt die Höhe je Zelle statt nur `true`.
- Milestone 3 (Diff) fehlt noch: ein neu geladener Chunk zeigt gefällte Bäume
  wieder, weil `prop_at` deterministisch neu generiert. Ansatz: pro Chunk die
  über `Player.felled`/`stump_cleared`/`stone_collected` entfernten Zellen
  merken und beim Laden auslassen.

**Noch nicht getestet** (kein Godot in der Bau-Umgebung): bitte einmal
`godot --headless --editor … --quit` (neue `class_name` bekannt machen), dann
headless laufen lassen und per temporärem `tools/_shot.gd` prüfen, dass (a)
außen neuer Boden erscheint, (b) der Handbau-Bereich inkl. See unverändert
ist, (c) am Übergang keine harte Höhenkante steht. Feintuning ggf. an
`WorldGen.frequency`/`EDGE_RING` und `ChunkManager.RADIUS`/`LOAD_BUDGET`.

<details><summary>Ursprüngliche Milestone-1-Anleitung (zur Referenz)</summary>

Ziel: Boden + Höhe entstehen chunk-weise um den Spieler, der Handbau-Bereich
bleibt unangetastet. **Noch keine** Props/Rohstoffe (das ist Milestone 2).

1. **Authored-Bereich merken.** In `IsoWorld` beim Spielstart die Grenzen
   der gemalten Map festhalten, *bevor* generiert wird: über alle Level
   `get_used_cells()` sammeln und Bounding-Box (min/max x/y) speichern, z. B.
   `authored_bounds: Rect2i`. Zellen innerhalb dieser Box nie generieren.
   Wichtig: das passiert vor `_spawn_prop_nodes()` bzw. dessen Nachfolger.

2. **`scripts/world_gen.gd` (neu, `class_name WorldGen`).** Reine Logik,
   kein Node-Zustand nötig. `FastNoiseLite` mit festem Welt-Seed
   (`@export var world_seed`). Funktion `height_at(cell: Vector2i) -> int`:
   Noise → `clampi(floor(n_normiert * 3), 0, 3)` (max Layer 03!). Direkt am
   Authored-Rand (Ring von ~3 Zellen) Höhe auf die Basishöhe der Handbau-
   Kante zwingen, damit keine harte Stufe entsteht — nach außen per `lerp`
   in die Noise-Höhe überblenden. Boden-Atlas vorerst fest die
   Gras-Kachel(n), die auch der Handbau nutzt (in `world.tscn` nachsehen;
   Atlas-Koords stehen in den `tile_map_data`-Blöcken, Quelle 0).

3. **Chunk generieren.** Ein Chunk = quadratischer Block von N×N Zellen
   (Start: N=16) im **durchgehenden** Zellkoordinatensystem (NICHT lokale
   Chunk-Koords — sonst kippt die Stacked-Parität, siehe README/neighbors).
   Für jede Zelle des Chunks, die außerhalb `authored_bounds` liegt: über
   `IsoWorld.set_block(cell, lvl, atlas)` die Säule Level00..height_at(cell)
   füllen. Chunk-Koordinate ↔ Zellbereich sauber umrechnen und testen.

4. **`scripts/chunk_manager.gd` (neu, Node in `main.tscn`).** Hält
   Referenz auf `IsoWorld` und den Spieler (Gruppe `player`, NICHT über
   festen Pfad — er wechselt den Parent, siehe README). In
   `_physics_process` (gedrosselt, z. B. alle ~0.2 s) die Spieler-Zelle →
   Chunk bestimmen. Chunks im Radius R (Start: 2) laden, die außerhalb
   R+1 wieder entladen. `loaded_chunks: Dictionary` (Chunk-Koord → true).
   Entladen = die generierten (nicht-authored) Blöcke des Chunks wieder
   `erase_block`en. Achtung: Authored-Zellen dabei niemals löschen.

5. **Verdrahtung.** `chunk_manager` nach `World` und `Player` initialisieren
   lassen (Reihenfolge in `main.tscn` prüfen; `World._ready` läuft zuerst).
   Den ersten Chunk-Load einmal beim Start erzwingen, damit der Spieler
   nicht ins Leere fällt, falls er am Kartenrand steht.

**Testen (Pflicht, siehe „Testen ohne Editor" oben):**
Erst `godot --headless --editor ... --quit` (neue `class_name` bekannt
machen), dann headless laufen lassen und per temporärem `tools/_shot.gd`
ein PNG machen: Spieler ein Stück nach außen bewegen und prüfen, dass (a)
neuer Boden erscheint, (b) der Handbau-Bereich unverändert ist, (c) keine
harte Höhenkante am Übergang steht. `tools/_shot.gd` danach wieder
entfernen.

**Fallstricke:**
- Stacked-Parität: nur im durchgehenden Koordinatensystem arbeiten.
- `authored_bounds` als **Bounding-Box** ist grob (rechteckig); falls die
  gemalte Map nicht rechteckig ist, lieber ein `Dictionary` der tatsächlich
  belegten Authored-Zellen führen und darüber prüfen.
- Performance: pro Frame nur wenige Chunks laden/entladen, sonst ruckelt es.

**Nach Milestone 1:** diesen Abschnitt auf „erledigt" setzen, Milestone-2-
Anleitung analog ergänzen, committen + pushen.

</details>

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
