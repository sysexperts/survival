extends SceneTree
## Segmentiert login_screen.png anhand der Alpha-Kanten und listet die
## Bounding-Boxes der einzelnen Sprites. Aufruf:
##   godot --headless --script res://tools/atlas_scan.gd

const SRC := "res://assets/UI/Cute_Fantasy_UI/UI/login_screen.png"
const MIN_A := 40      # Alpha-Schwelle: darueber = "gehoert zum Sprite"
const MIN_AREA := 1500 # kleine Fleckchen ignorieren

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if img == null:
		var tex := load(SRC) as Texture2D
		img = tex.get_image()
	var w := img.get_width()
	var h := img.get_height()
	print("SIZE ", w, "x", h)
	# Alpha-Stichproben (Hintergrund?)
	print("corner a=", img.get_pixel(2, 2).a, " center a=", img.get_pixel(w/2, h/2).a)

	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			mask[y * w + x] = 1 if img.get_pixel(x, y).a * 255.0 >= MIN_A else 0

	# Connected components (4-nachbar), iterativ per Stack.
	var seen := PackedByteArray()
	seen.resize(w * h)
	var boxes := []
	var stack := PackedInt32Array()
	for sy in h:
		for sx in w:
			var si := sy * w + sx
			if mask[si] == 0 or seen[si] == 1:
				continue
			var minx := sx; var maxx := sx; var miny := sy; var maxy := sy
			var area := 0
			stack.clear()
			stack.push_back(si)
			seen[si] = 1
			while stack.size() > 0:
				var i := stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				var x := i % w
				var y := i / w
				area += 1
				minx = min(minx, x); maxx = max(maxx, x)
				miny = min(miny, y); maxy = max(maxy, y)
				if x > 0 and mask[i-1] == 1 and seen[i-1] == 0:
					seen[i-1] = 1; stack.push_back(i-1)
				if x < w-1 and mask[i+1] == 1 and seen[i+1] == 0:
					seen[i+1] = 1; stack.push_back(i+1)
				if y > 0 and mask[i-w] == 1 and seen[i-w] == 0:
					seen[i-w] = 1; stack.push_back(i-w)
				if y < h-1 and mask[i+w] == 1 and seen[i+w] == 0:
					seen[i+w] = 1; stack.push_back(i+w)
			if area >= MIN_AREA:
				boxes.append([minx, miny, maxx - minx + 1, maxy - miny + 1, area])

	# Nach y, dann x sortieren.
	boxes.sort_custom(func(a, b):
		if abs(a[1] - b[1]) > 20:
			return a[1] < b[1]
		return a[0] < b[0])
	print("BOXES ", boxes.size())
	for b in boxes:
		print("R ", b[0], " ", b[1], " ", b[2], " ", b[3], "  area=", b[4])
	quit()
