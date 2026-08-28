extends RefCounted

## Charakter-Attribute, im Buch (linke Seite) mit −/+ anpassbar. Preload-Muster.
## Aktuell Platzhalter ohne Gameplay-Wirkung - nur die Anzeige/Verstellung.

const MINV := 0
const MAXV := 99

## Reihenfolge = Anzeige. key -> Anzeigename.
const ORDER := ["tragkraft", "kraft", "ausdauer", "hiz"]
const LABELS := {
	"tragkraft": "Tasima", "kraft": "Guc", "ausdauer": "Dayaniklilik", "hiz": "Hiz",
}

static var values := {"tragkraft": 50, "kraft": 10, "ausdauer": 10, "hiz": 10}
## Freie Punkte, die verteilt werden können.
static var points := 5


static func adjust(key: String, delta: int) -> void:
	if not values.has(key):
		return
	if delta > 0 and points <= 0:
		return                         # keine Punkte mehr übrig
	var old: int = values[key]
	var nv := clampi(old + delta, MINV, MAXV)
	if nv == old:
		return
	points -= (nv - old)               # +1 kostet 1 Punkt, −1 gibt 1 zurück
	values[key] = nv
