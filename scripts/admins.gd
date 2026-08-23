extends RefCounted

## Wer ist Admin (Gamemaster)? Zentral an EINER Stelle, per preload nutzbar.
##
## KEIN class_name und KEIN Autoload: beides wuerde der Auto-Updater nicht
## sauber mitziehen (neue class_name-Klassen werden nicht registriert, ein
## laufendes Autoload nicht ersetzt). Wer die Liste braucht, bindet dieses
## Skript per preload ein und ruft is_admin() statisch auf.

const NAMES := ["serdar"]

static func is_admin(pname: String) -> bool:
	return pname.strip_edges().to_lower() in NAMES
