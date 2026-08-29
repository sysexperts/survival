extends RefCounted

## Daten der abbaubaren Felsen (Sheet assets/props/rocks.png).
##
## 4 Zustaende (Sheet-Reihen) x 8 Varianten (Spalten, damit nicht jeder Fels
## gleich aussieht). Reine Daten - Rendern macht TreeActor.create_rock, Platzieren
## der ChunkManager, Abbauen der Player.

const SHEET := "res://assets/props/rocks.png"
const CELL := 48
const VARIANTS := 8
const ROWS := 5

## Zustand (Sheet-Reihe) -> Abbau-Daten:
##   drop   = Item, das beim Abbau faellt
##   amount = wie viele
##   tier   = benoetigte Spitzhacken-Stufe (1=Stein, 2=Eisen+)
## amount = feste Menge; amount_max (optional) macht daraus eine Spanne
## [amount, amount_max], die pro Fels ausgewuerfelt wird.
## Reihenfolge = Sheet-Reihe (rocks.png).
const STATES := [
	{"name": "Kaya", "drop": "tas", "amount": 5, "amount_max": 10, "tier": 1},   # 0 Stein
	{"name": "Demir Cevheri", "drop": "demir_cevheri", "amount": 2, "tier": 2},  # 1 Eisen
	{"name": "Altin Cevheri", "drop": "altin_cevheri", "amount": 2, "tier": 2},  # 2 Gold
	{"name": "Ham Elmas", "drop": "ham_elmas", "amount": 1, "tier": 2},   # 3 Diamant
	{"name": "Komur Cevheri", "drop": "komur", "amount": 3, "amount_max": 14, "tier": 1},  # 4 Kohle
]

## Streu-Gewichte (Summe 1): Stein haeufig, Kohle oft, Eisen ab und zu, Gold
## selten, Diamant sehr selten.
const WEIGHTS := [0.60, 0.13, 0.05, 0.02, 0.20]


## Wuerfelt einen Zustand aus einem 0..1-Zufallswert (kumulativ nach WEIGHTS).
static func pick_state(rand01: float) -> int:
	var acc := 0.0
	for i in WEIGHTS.size():
		acc += WEIGHTS[i]
		if rand01 < acc:
			return i
	return 0


## Bildregion einer Variante im Sheet.
static func region(state: int, variant: int) -> Rect2i:
	return Rect2i(variant * CELL, state * CELL, CELL, CELL)


static func drop_of(state: int) -> String:
	return String(STATES[clampi(state, 0, ROWS - 1)]["drop"])


## Menge fuer diesen Fels - feste Zahl oder zufaellig aus [amount, amount_max].
static func amount_of(state: int) -> int:
	var s: Dictionary = STATES[clampi(state, 0, ROWS - 1)]
	var lo := int(s["amount"])
	if s.has("amount_max"):
		return randi_range(lo, int(s["amount_max"]))
	return lo


## Benoetigte Spitzhacken-Stufe fuer diesen Zustand.
static func tier_of(state: int) -> int:
	return int(STATES[clampi(state, 0, ROWS - 1)]["tier"])
