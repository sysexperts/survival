extends SceneTree
## Baut resources/camel_frames.tres aus den PixelLab-Frames in .camel_src/.
## Aufruf: godot --headless --script res://tools/build_camel_frames.gd
## Kamel 56x56, fussbuendig auf 64x64 gelegt (Fusspunkte aller Anims decken sich).

const CELL := 64
const BOTTOM_MARGIN := 2
const DIRS := ["south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west"]
const WALK_FRAMES := 9
const WALK_FPS := 10.0

func _initialize() -> void:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for d in DIRS:
		var us: String = d.replace("-", "_")
		var wa := "walk_%s" % us
		sf.add_animation(wa); sf.set_animation_loop(wa, true); sf.set_animation_speed(wa, WALK_FPS)
		for i in WALK_FRAMES:
			sf.add_frame(wa, _load_centered("res://.camel_src/walk/%s/frame_%03d.png" % [d, i]))
		var ia := "idle_%s" % us
		sf.add_animation(ia); sf.set_animation_loop(ia, true); sf.set_animation_speed(ia, 1.0)
		sf.add_frame(ia, _load_centered("res://.camel_src/idle/%s.png" % d))
		var la := "laydown_%s" % us
		sf.add_animation(la); sf.set_animation_loop(la, true); sf.set_animation_speed(la, 1.0)
		sf.add_frame(la, _load_centered("res://.camel_src/laydown/%s.png" % d))
	var err := ResourceSaver.save(sf, "res://resources/camel_frames.tres")
	print("camel_frames.tres err=", err, " Anims=", sf.get_animation_names().size())
	quit()

func _load_centered(res_path: String) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if img == null:
		push_error("Frame fehlt: %s" % res_path); return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var canvas := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	var w := img.get_width(); var h := img.get_height()
	canvas.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((CELL - w) / 2, CELL - h - BOTTOM_MARGIN))
	return ImageTexture.create_from_image(canvas)
