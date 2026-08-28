extends RefCounted

## Spielerwerte (Leben/Mana/Stamina) für die Anzeige oben links.
## Preload statt Autoload (Auto-Updater-Regel). Aktuell rein kosmetisch: die
## Werte starten voll; ein Gameplay-Verbrauch kann später hier andocken.

static var health := 100.0
static var health_max := 100.0
static var mana := 100.0
static var mana_max := 100.0
static var stamina := 100.0
static var stamina_max := 100.0


static func health_ratio() -> float:
	return clampf(health / maxf(health_max, 1.0), 0.0, 1.0)

static func mana_ratio() -> float:
	return clampf(mana / maxf(mana_max, 1.0), 0.0, 1.0)

static func stamina_ratio() -> float:
	return clampf(stamina / maxf(stamina_max, 1.0), 0.0, 1.0)
