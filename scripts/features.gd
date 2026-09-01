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
##
## WICHTIG (Stand v210): NUR diese Flags schalten wirklich Code (per
## Features.on geprueft): "survival_needs", "thirst", "skills_xp". Alle anderen
## Eintraege sind PLATZHALTER fuer eine kuenftige Gating-Moeglichkeit - das
## jeweilige Feature ist bereits fest eingebaut und laeuft UNABHAENGIG vom Flag
## (frueher stand hier faelschlich "false", obwohl das Feature live war). Ihren
## Wert zu aendern hat daher KEINE Wirkung.
static var FLAGS := {
	# === VERDRAHTET (schalten echt Code) ================================
	"survival_needs":   [true,  "VERDRAHTET: Hunger sinkt/Essen fuellt auf, 0 Leben -> bewusstlos"],
	"thirst":           [false, "VERDRAHTET: zusaetzlich Durst (braucht Trinkquelle) - aus"],
	"skills_xp":        [false, "VERDRAHTET: EXTRA Fael-XP pro Schwung + award(). Kern-Skill-XP laeuft ohnehin ungated - aus, damit nicht doppelt"],

	# === UNGENUTZT (Feature laeuft ungated; Flag ohne Wirkung) ==========
	"health_regen":     [true,  "LAEUFT (in survival_needs): Leben regeneriert wenn satt"],
	"death_respawn":    [true,  "LAEUFT: 0 Leben -> bewusstlos + Respawn (downed-System)"],
	"weather":          [true,  "LAEUFT: Regen (weather.gd, Admin /rain)"],
	"fishing":          [true,  "LAEUFT: Angeln an Gewaessern"],
	"farming_growth":   [true,  "LAEUFT: Angepflanztes waechst (crop.gd)"],
	"day_counter":      [true,  "LAEUFT: Tag/Nacht-Zyklus (day_night.gd)"],

	# === GEPLANT (noch nicht eingebaut) ================================
	"temperature":      [false, "GEPLANT: Kaelte/Waerme"],
	"fatigue":          [false, "GEPLANT: Muedigkeit"],
	"disease":          [false, "GEPLANT: Krankheit/Debuffs"],
	"stat_points":      [false, "GEPLANT: verteilbare Attributpunkte"],
	"seasons":          [false, "GEPLANT: Jahreszeiten"],
	"animal_taming":    [false, "GEPLANT: Tiere zaehmen"],
	"currency":         [false, "GEPLANT: Altin als Waehrung/Handel"],
	"quests":           [false, "GEPLANT: Aufgaben/Belohnungen"],
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
