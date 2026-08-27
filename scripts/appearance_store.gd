extends RefCounted

## Hält das Aussehen des lokalen Spielers und lädt/speichert es unter user://.
## Bewusst KEIN Autoload (der Auto-Updater ersetzt Autoloads nicht) - Zugriff
## über statische Felder per preload("res://scripts/appearance_store.gd").

const CCCatalog := preload("res://scripts/cc_catalog.gd")
const SAVE_PATH := "user://appearance.json"

static var _local: Dictionary = {}
static var _loaded := false


static func local() -> Dictionary:
	if not _loaded:
		_load()
	return _local


static func set_local(look: Dictionary) -> void:
	_local = sanitize(look)
	_loaded = true
	_save()


## Sorgt dafür, dass jeder Slot vorhanden und ein String ist; fehlende Slots
## kommen aus dem Standard-Look.
static func sanitize(look: Dictionary) -> Dictionary:
	var out := CCCatalog.default_look()
	for slot in CCCatalog.DRAW_ORDER:
		if look.has(slot):
			out[slot] = String(look[slot])
	return out


static func _load() -> void:
	_loaded = true
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_local = sanitize(data)
				return
	_local = CCCatalog.default_look()


static func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_local))
