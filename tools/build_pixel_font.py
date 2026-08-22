"""Baut den Pixel-Font des Spiels.

Rasterisiert eine TrueType-Vorlage OHNE Kantenglaettung auf eine feste
Pixelhoehe und schreibt das Ergebnis als BMFont (.fnt + .png) nach
assets/fonts/. Godot laedt .fnt direkt als FontFile.

Warum nicht die TTF direkt in Godot laden? Weil dann jede Schriftgroesse
neu gerastert wird und die Glyphen je nach Groesse anders ausfallen. Als
Bitmap steht jedes Pixel fest - genau das macht einen Pixel-Font aus, und
beim Hochskalieren auf ein Vielfaches bleibt es scharf.

Vorlage ist Bitstream Vera Sans Mono (VeraMono.ttf). Die Lizenz erlaubt
Weitergabe und abgeleitete Werke ausdruecklich - anders als bei den
meisten Windows-Systemschriften.

Aufruf:  python tools/build_pixel_font.py
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "fonts")
# Was gebaut wird: Name -> (Vorlagen in Reihenfolge der Vorliebe, Pixelhoehe)
#
# "pixel" ist die Schrift der Oberflaeche. "pixel_bold" ist kleiner und
# fetter und sitzt ueber den Figuren - dort muss der Name auf buntem
# Untergrund lesbar bleiben, ohne gross zu wirken.
FONTS = {
    "pixel": ([
        r"C:\Windows\Fonts\VeraMono.ttf",
        r"C:\Windows\Fonts\consola.ttf",
        r"C:\Windows\Fonts\lucon.ttf",
    ], 11),
    "pixel_bold": ([
        r"C:\Windows\Fonts\VeraMoBd.ttf",
        r"C:\Windows\Fonts\consolab.ttf",
    ], 9),
}
PAD = 1            # Rand zwischen den Glyphen im Atlas

CHARS = (
    "".join(chr(c) for c in range(32, 127))
    + "ÄÖÜäöüß"
    + "·×–—…°«»€"
)


def pick_source(sources):
    for path in sources:
        if os.path.exists(path):
            return path
    sys.exit("Keine Vorlagenschrift gefunden: " + ", ".join(sources))


def render(font, ch, box):
    """Ein Zeichen als 1-Bit-Bild plus Tintenrechteck."""
    img = Image.new("L", box, 0)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"                      # Kantenglaettung aus
    d.text((PAD, PAD), ch, font=font, fill=255)
    return img, img.getbbox()


def build(name, sources, size):
    src = pick_source(sources)
    font = ImageFont.truetype(src, size)
    ascent, descent = font.getmetrics()
    line_height = ascent + descent
    box = (size * 3, line_height + PAD * 2 + size)

    glyphs = []                            # (ch, bild, xoff, yoff, advance)
    for ch in CHARS:
        img, ink = render(font, ch, box)
        advance = int(round(font.getlength(ch)))
        if ink is None:                    # Leerzeichen
            glyphs.append((ch, None, 0, 0, advance))
            continue
        x0, y0, x1, y1 = ink
        glyphs.append((ch, img.crop(ink), x0 - PAD, y0 - PAD, advance))

    # Gitter-Packung: einfach, und der Atlas bleibt klein genug.
    cell_w = max((g[1].width for g in glyphs if g[1]), default=1) + PAD
    cell_h = max((g[1].height for g in glyphs if g[1]), default=1) + PAD
    cols = 16
    rows = (len(glyphs) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * cell_w, rows * cell_h), (0, 0, 0, 0))

    lines = []
    for i, (ch, img, xoff, yoff, advance) in enumerate(glyphs):
        gx = (i % cols) * cell_w
        gy = (i // cols) * cell_h
        w = h = 0
        if img is not None:
            w, h = img.size
            # Weiss mit der Glyphe als Alpha: so kann Godot sie einfaerben.
            solid = Image.new("RGBA", img.size, (255, 255, 255, 0))
            solid.putalpha(img)
            atlas.paste(solid, (gx, gy))
        lines.append(
            "char id=%d x=%d y=%d width=%d height=%d "
            "xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
            % (ord(ch), gx, gy, w, h, xoff, yoff, advance)
        )

    os.makedirs(OUT_DIR, exist_ok=True)
    png_name = name + ".png"
    atlas.save(os.path.join(OUT_DIR, png_name))

    head = [
        'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 '
        "stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0"
        % (name, size),
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0"
        % (line_height, ascent, atlas.width, atlas.height),
        'page id=0 file="%s"' % png_name,
        "chars count=%d" % len(lines),
    ]
    with open(os.path.join(OUT_DIR, name + ".fnt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(head + lines) + "\n")

    print("%-11s %s  %dx%d px, Zeilenhoehe %d, %d Zeichen"
          % (name + ":", os.path.basename(src), atlas.width, atlas.height,
             line_height, len(glyphs)))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (sources, size) in FONTS.items():
        build(name, sources, size)


if __name__ == "__main__":
    main()
