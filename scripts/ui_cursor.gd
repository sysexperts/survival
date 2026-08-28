extends RefCounted

## Setzt den Maus-Cursor auf die Pfeil-/Hand-Grafik aus dem Cute-Fantasy-UI-Pack.
## Preload statt class_name (Auto-Updater-Regel). Aufruf einmal beim Start
## (main_menu.gd) - der Cursor bleibt danach für die ganze Sitzung gesetzt.
##
## Die Cursor liegen in UI_ALL.png; die Rechtecke stammen aus einer
## Komponenten-Analyse (tools/bars_rects.gd). 9x12 px, hier x3 vergrößert.

const SHEET := "res://assets/UI/Cute_Fantasy_UI/UI/UI_ALL.png"
const SCALE := 4

## Weiße Cursor, Normal-Reihe (y=1218). Pfeil ganz links, Hand als vierte.
const ARROW_RECT := Rect2i(4, 1218, 10, 13)
const HAND_RECT := Rect2i(51, 1218, 10, 13)
## Klick-Punkt (Spitze) im nativen Bild, vor der Skalierung.
const ARROW_HOTSPOT := Vector2i(2, 2)
const HAND_HOTSPOT := Vector2i(5, 1)


static func apply() -> void:
	var tex: Texture2D = load(SHEET)
	if tex == null:
		return
	var img := tex.get_image()
	Input.set_custom_mouse_cursor(_make(img, ARROW_RECT), Input.CURSOR_ARROW, Vector2(ARROW_HOTSPOT * SCALE))
	var hand := _make(img, HAND_RECT)
	Input.set_custom_mouse_cursor(hand, Input.CURSOR_POINTING_HAND, Vector2(HAND_HOTSPOT * SCALE))
	# Ibeam/Drag etc. sollen nicht auf den Systempfeil zurückfallen -> auch Pfeil.
	Input.set_custom_mouse_cursor(_make(img, ARROW_RECT), Input.CURSOR_IBEAM, Vector2(ARROW_HOTSPOT * SCALE))


static func _make(sheet_img: Image, rect: Rect2i) -> ImageTexture:
	var sub := sheet_img.get_region(rect)
	sub.resize(rect.size.x * SCALE, rect.size.y * SCALE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(sub)
