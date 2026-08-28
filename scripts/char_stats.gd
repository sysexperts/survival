extends RefCounted

## Charakter-Attribute, im Buch (linke Seite) mit −/+ anpassbar. Preload-Muster.
## Aktuell Platzhalter ohne Gameplay-Wirkung - nur die Anzeige/Verstellung.

const MINV := 0
const MAXV := 99

## Reihenfolge = Anzeige. key -> Anzeigename.
const ORDER := ["vitalitaet", "staerke", "ruestung", "tempo"]
const LABELS := {
	"vitalitaet": "Vitalitaet", "staerke": "Staerke", "ruestung": "Ruestung", "tempo": "Tempo",
}

static var values := {"vitalitaet": 15, "staerke": 8, "ruestung": 4, "tempo": 10}
## Freie Punkte, die verteilt werden können.
static var points := 3


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
