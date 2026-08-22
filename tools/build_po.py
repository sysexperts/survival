"""Verkleinert die Po-Spritesheets auf spielbare Groesse.

Die Rohsheets in assets/characters/Po bleiben unangetastet (und per .gdignore
aus Godots Import heraus); das Ergebnis landet in assets/characters/po_scaled.
Die Rohsheets liegen in 460x460-Zellen vor - im Spiel ist Jack rund 37 px
hoch, deshalb wird auf 48er-Zellen heruntergerechnet (Faktor 460/64). Alle
Sheets teilen dieselbe Leinwand, die Fusslinie bleibt dadurch ueberall gleich.

Aufruf:  python tools/build_po.py
"""
import io
import os
from PIL import Image

SRC = os.path.join("assets", "characters", "Po")
DST = os.path.join("assets", "characters", "po_scaled")
CELL_SRC = 460
CELL_DST = 48


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    count = 0
    sheets = []
    for name in sorted(os.listdir(SRC)):
        if not name.lower().endswith(".png"):
            continue
        im = Image.open(os.path.join(SRC, name)).convert("RGBA")
        cols = im.width // CELL_SRC
        rows = im.height // CELL_SRC
        if cols * CELL_SRC != im.width or rows * CELL_SRC != im.height:
            print("uebersprungen (kein 460er-Raster):", name, im.size)
            continue
        # Jede Zelle einzeln verkleinern. Ein Resize ueber das ganze Sheet
        # wuerde an den Zellgrenzen benachbarte Frames einblenden - die Figur
        # bekaeme dadurch eine Pixelzeile Fuss aus dem Nachbarframe und
        # stuende im Spiel nicht mehr auf dem Boden.
        out = Image.new("RGBA", (cols * CELL_DST, rows * CELL_DST), (0, 0, 0, 0))
        for r in range(rows):
            for c in range(cols):
                box = (c * CELL_SRC, r * CELL_SRC, (c + 1) * CELL_SRC, (r + 1) * CELL_SRC)
                cell = im.crop(box).resize((CELL_DST, CELL_DST), Image.LANCZOS)
                out.paste(cell, (c * CELL_DST, r * CELL_DST))
        out.save(os.path.join(DST, name))
        sheets.append((os.path.splitext(name)[0], cols))
        count += 1
        print("%-46s %dx%d -> %d Spalten, %d Zeilen" % (name, im.width, im.height, cols, rows))
    _write_index(sheets)
    print("fertig:", count, "Sheets in", DST)


def _write_index(sheets) -> None:
    """Schreibt die Sheet-Liste als GDScript-Konstante.

    Zur Laufzeit waere ein DirAccess-Listing unzuverlaessig: im Export heissen
    die Dateien anders (.ctex). Die Liste wird deshalb hier festgeschrieben.
    """
    lines = [
        "extends RefCounted",
        "class_name PoSheets",
        "",
        "## Erzeugt von tools/build_po.py - nicht von Hand aendern.",
        "## Je Eintrag: Dateiname ohne Endung -> Anzahl Spalten (= Frames).",
        "",
        "const CELL := %d" % CELL_DST,
        "const ROWS := 5   ## Sued, Suedost, Ost, Nordost, Nord",
        "",
        "const SHEETS := {",
    ]
    for name, cols in sheets:
        lines.append('\t"%s": %d,' % (name, cols))
    lines.append("}")
    lines.append("")
    with io.open(os.path.join("scripts", "po_sheets.gd"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
