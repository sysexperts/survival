extends RefCounted

## Kleiner geteilter UI-Zustand. Preload statt Autoload (Auto-Updater-Regel).
## `pause_open` blockiert die Spielersteuerung, solange das ESC-Menü offen ist.

static var pause_open := false

## Schliesst das oberste offene Spiel-Fenster (Truhe/Station/Handwerk/Tasche/
## Vorschau). Wird vom Inventar gesetzt; das Pause-Menue ruft es bei Escape ZUERST
## auf - so hat "Fenster schliessen" IMMER Vorrang vor "Menue oeffnen", egal in
## welcher Knoten-Reihenfolge Escape ankommt. Gibt true zurueck, wenn etwas
## geschlossen wurde.
static var close_top := Callable()

static func close_top_window() -> bool:
	return close_top.is_valid() and bool(close_top.call())
