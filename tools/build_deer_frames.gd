extends SceneTree
## Baut resources/deer_frames.tres aus den PixelLab-Frames in .deer_src/.
## Aufruf: godot --headless --script res://tools/build_deer_frames.gd
##
## Walk-Frames sind 60x60, Idle 48x48 - beide fussbuendig auf ein gemeinsames
## 64x64-Raster gelegt, damit die Fusspunkte aller Animationen aufeinander
## liegen (siehe Frame-Raster-Hinweis in der README). Die Texturen werden
## direkt in die .tres eingebettet, es braucht also keine Sheet-PNGs.

const CELL := 64
const BOTTOM_MARGIN := 2
## Reihenfolge wie player.gd DIRS (Ordnernamen mit Bindestrich).
const DIRS := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]
const WALK_FRAMES := 9
const WALK_FPS := 10.0
const LAY_FRAMES := 9
const LAY_FPS := 10.0

func _initialize() -> void:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for d in DIRS:
		var us: String = d.replace("-", "_")
		# Walk
		var wa := "walk_%s" % us
		sf.add_animation(wa)
		sf.set_animation_loop(wa, true)
		sf.set_animation_speed(wa, WALK_FPS)
		for i in WALK_FRAMES:
			var p := "res://.deer_src/walk/%s/frame_%03d.png" % [d, i]
			sf.add_frame(wa, _load_centered(p))
		# Idle (eine Rotation)
		var ia := "idle_%s" % us
		sf.add_animation(ia)
		sf.set_animation_loop(ia, true)
		sf.set_animation_speed(ia, 1.0)
		sf.add_frame(ia, _load_centered("res://.deer_src/idle/%s.png" % d))
		# Lay down (nicht loopend; rueckwaerts abgespielt = Aufstehen).
		var la := "laydown_%s" % us
		sf.add_animation(la)
		sf.set_animation_loop(la, false)
		sf.set_animation_speed(la, LAY_FPS)
		for j in LAY_FRAMES:
			sf.add_frame(la, _load_centered("res://.deer_src/laydown/%s/frame_%03d.png" % [d, j]))
	var err := ResourceSaver.save(sf, "res://resources/deer_frames.tres")
	print("deer_frames.tres gespeichert, err=", err, " Animationen=", sf.get_animation_names().size())
	quit()


## Laedt einen Frame und legt ihn fussbuendig, waagerecht zentriert auf ein
## transparentes CELLxCELL-Bild. Gibt eine eingebettete ImageTexture zurueck.
func _load_centered(res_path: String) -> ImageTexture:
	var abs := ProjectSettings.globalize_path(res_path)
	var img := Image.load_from_file(abs)
	if img == null:
		push_error("Frame fehlt: %s" % abs)
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var canvas := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var dst := Vector2i((CELL - w) / 2, CELL - h - BOTTOM_MARGIN)
	canvas.blit_rect(img, Rect2i(0, 0, w, h), dst)
	return ImageTexture.create_from_image(canvas)
