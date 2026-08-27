@tool
extends SceneTree

## Verkleinert die Layer-Sheets des "Customaizable Character"-Packs auf 48px-
## Zellen und legt sie unter assets/characters/cc_scaled/<state>/ ab. Läuft
## headless:
##   "$GODOT" --headless --path . --script tools/build_cc_scaled.gd
##
## Quelle: assets/characters/character_creator/CustomaizableCharacter/<Ordner>
## Ziel:   assets/characters/cc_scaled/<state>/<Kategorie>_<Variante>.png
##
## Nur die fünf Aktionen, die player.gd fährt, werden gebaut (idle/walk/run/
## axe/sleep). Die Zellen sind quadratisch (Quell-Zelle 460px -> Ziel 48px);
## fünf Zeilen (Süd, Südwest, West, Nordwest, Nord).

const SRC := "res://assets/characters/character_creator/CustomaizableCharacter/"
const DST := "res://assets/characters/cc_scaled/"
const CELL_DST := 48
const CELL_SRC := 460
const ROWS := 5

## Spielzustand -> (Quellordner, Spaltenzahl). Die "_hold"-Sätze tragen die
## Körperpose mit Werkzeug in der Hand (inkl. Layer13_Axe / NegativeLayer1_Axe).
## run/axe brauchen keinen eigenen _hold-Satz: dieselbe Körperpose, und die
## Axt-Layer liegen bereits in cc_scaled/run bzw. /axe.
const ACTIONS := {
	"idle":  ["Idle", 8],
	"walk":  ["Walk", 6],
	"run":   ["Run(HoldingToolOrNot)", 4],
	"axe":   ["Swing", 6],
	"sleep": ["Sit", 4],
	"idle_hold": ["IdleHoldingTool", 8],
	"walk_hold": ["WalkHoldingTool", 6],
}


func _init() -> void:
	var total := 0
	for state_key in ACTIONS:
		var state := String(state_key)
		var folder: String = ACTIONS[state][0]
		var cols: int = ACTIONS[state][1]
		var src_dir: String = SRC + folder + "/"
		var dst_dir: String = DST + state + "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst_dir))
		var d := DirAccess.open(src_dir)
		if d == null:
			push_error("Quellordner fehlt: " + src_dir)
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".png"):
				_scale_one(src_dir + f, dst_dir + f, cols)
				total += 1
			f = d.get_next()
		d.list_dir_end()
		print("  %s: fertig (%s)" % [state, folder])
	print("cc_scaled: %d Dateien geschrieben." % total)
	quit()


func _scale_one(src: String, dst: String, cols: int) -> void:
	if FileAccess.file_exists(ProjectSettings.globalize_path(dst)):
		return  # schon gebaut - Wiederaufnahme nach Abbruch
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	if img == null:
		push_warning("Bild nicht ladbar: " + src)
		return
	# Jede Zelle einzeln verkleinern, damit keine Farbe über Zellgrenzen blutet.
	var out := Image.create(cols * CELL_DST, ROWS * CELL_DST, false, Image.FORMAT_RGBA8)
	for row in range(ROWS):
		for col in range(cols):
			var cell := img.get_region(Rect2i(col * CELL_SRC, row * CELL_SRC, CELL_SRC, CELL_SRC))
			cell.resize(CELL_DST, CELL_DST, Image.INTERPOLATE_LANCZOS)
			out.blit_rect(cell, Rect2i(0, 0, CELL_DST, CELL_DST),
				Vector2i(col * CELL_DST, row * CELL_DST))
	out.save_png(ProjectSettings.globalize_path(dst))
