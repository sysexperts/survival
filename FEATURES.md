# Vorbereitete Features (standardmäßig AUS)

Recherchierte Survival-Funktionen, als **schlafende** Module eingebaut. Nichts
davon läuft, solange das jeweilige Flag in `scripts/features.gd` auf `false`
steht. Sag mir, welche an sollen — dann setze ich das Flag (und baue bei den
mit *Stub* markierten den vollen Umfang aus) und deploye.

**Aktivieren:** in `scripts/features.gd` das Flag auf `true` setzen.

## Status

| Flag | Status | Was es macht |
|------|--------|--------------|
| `survival_needs` | **fertig** | Hunger/Durst sinken mit der Zeit; leer → Leben sinkt. `eat()/drink()` füllt. Beim Aktivieren erscheint eine Text-Anzeige (Aclik/Susuzluk/Can). |
| `health_regen` | **fertig** | Leben regeneriert langsam, solange satt & getränkt (braucht `survival_needs`). |
| `skills_xp` | **fertig** | XP fürs Fällen (am `axe_swung`-Signal) → Level. Zeigt „Oduncu Sv N". Handwerk/Bauen über `SkillsXp.award()` andockbar. |
| `death_respawn` | teilweise | Bei 0 Leben werden Werte zurückgesetzt (Positions-Respawn beim Aktivieren ergänzen). |
| `temperature` | Stub | Flag + Doku vorhanden; Kälte/Wärme-Logik baue ich beim Aktivieren aus (Anbindung Lagerfeuer/Nacht). |
| `fatigue` | Stub | Müdigkeit; Schlafen setzt zurück. |
| `disease` | Stub | Krankheit/Infektion mit Debuffs. |
| `stat_points` | Stub | Die verstellbaren Attribute (Tragkraft etc.) wirken aufs Gameplay. |
| `weather` | Stub | Regen/Schnee-Overlay + Effekte. |
| `seasons` | Stub | Jahreszeiten → Wachstum/Temperatur. |
| `day_counter` | Stub | Tageszähler + Uhrzeit-Anzeige. |
| `fishing` | Stub | Angeln an Gewässern (Fisch-Animation ist vorhanden). |
| `farming_growth` | Stub | Angepflanztes wächst und wird erntereif. |
| `animal_taming` | Stub | Rehe/Tiere zähmen. |
| `currency` | Stub | Altin als Währung/Handel. |
| `quests` | Stub | Aufgaben mit Belohnungen. |

„Fertig" = funktioniert sofort beim Flag-Umlegen. „Stub" = Flag + Gerüst da, den
vollen Umfang baue ich, sobald du es auswählst (damit kein toter Code auf Verdacht
entsteht).
