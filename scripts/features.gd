extends RefCounted

## Zentrale Feature-Schalter. ALLE standardmäßig AUS - die neuen Systeme sind
## eingebaut, aber schlafend, bis hier ein Flag auf true steht. So kann jederzeit
## einzeln zugeschaltet werden, ohne das laufende Spiel zu verändern.
##
## Preload-Muster (kein Autoload/class_name wegen Auto-Updater). Abfrage überall:
##   const Features := preload("res://scripts/features.gd")
##   if Features.on("survival_needs"): ...
##
## Zum Aktivieren: das jeweilige Flag unten auf true setzen (oder zur Laufzeit
## Features.set_flag("x", true) im Debug).

## name -> [aktiv, Kurzbeschreibung]. Beschreibung nur zur Doku/Übersicht.
static var FLAGS := {
	# --- Überlebens-Grundbedürfnisse ---
	"survival_needs":   [true,  "Hunger sinkt mit der Zeit; Essen füllt auf"],
	"thirst":           [false, "Durst sinkt zusätzlich (braucht eine Trinkquelle) - vorerst aus"],
	"health_regen":     [false, "Leben regeneriert langsam, solange Bedürfnisse gedeckt sind"],
	"temperature":      [false, "Kälte nachts / fern vom Feuer, Wärme am Lagerfeuer"],
	"fatigue":          [false, "Müdigkeit steigt; Schlafen setzt sie zurück"],
	"disease":          [false, "Krankheit/Infektion mit Debuffs, heilbar"],
	"death_respawn":    [false, "Bei 0 Leben: Tod + Wiedereinstieg am Bett/Startpunkt"],
	# --- Fortschritt ---
	"skills_xp":        [false, "Skill-XP/Level für Fällen, Handwerk, Bauen (Skills-Tab)"],
	"stat_points":      [false, "Verteilbare Attributpunkte wirken aufs Gameplay (Tragkraft etc.)"],
	# --- Welt & Umwelt ---
	"weather":          [false, "Wetterwechsel: Regen/Schnee mit Effekten"],
	"seasons":          [false, "Jahreszeiten beeinflussen Wachstum/Temperatur"],
	"day_counter":      [false, "Tageszähler + Uhrzeit-Anzeige"],
	# --- Aktivitäten ---
	"fishing":          [false, "Angeln an Gewässern (Fisch-Animation ist vorhanden)"],
	"farming_growth":   [false, "Angepflanztes wächst über Zeit und wird erntereif"],
	"animal_taming":    [false, "Rehe/Tiere zähmen und halten"],
	# --- Wirtschaft / Sozial ---
	"currency":         [false, "Altin (Gold) als Währung, Handel"],
	"quests":           [false, "Aufgaben/Ziele mit Belohnungen"],
}


static func on(feature: String) -> bool:
	var e = FLAGS.get(feature, null)
	return e != null and bool(e[0])


static func set_flag(feature: String, value: bool) -> void:
	if FLAGS.has(feature):
		FLAGS[feature][0] = value


static func description(feature: String) -> String:
	var e = FLAGS.get(feature, null)
	return String(e[1]) if e != null else ""
