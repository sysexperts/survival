extends RefCounted

## Kleiner geteilter UI-Zustand. Preload statt Autoload (Auto-Updater-Regel).
## `pause_open` blockiert die Spielersteuerung, solange das ESC-Menü offen ist.

static var pause_open := false
