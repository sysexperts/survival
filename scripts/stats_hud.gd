extends Control

## Leben/Mana/Stamina oben links im Cute-Fantasy-UI-Look: die Pack-Vorlage
## "Porträt + 3 Balken" (rot/blau/grün) aus UI_Bars, mit dem eigenen
## Charakter-Kopf im Rahmen.
##
## Die Balken sind aktuell voll gezeichnet (Werte starten voll). Sobald es
## echten Verbrauch gibt, können die Füllungen dynamisch werden.

const UiAtlas := preload("res://scripts/ui_atlas.gd")
const CCFrames := preload("res://scripts/cc_frames.gd")
const AppearanceStore := preload("res://scripts/appearance_store.gd")

## Vorlage-Block (Porträt-Rahmen + 3 volle Balken) im Sheet.
const BLOCK_REGION := Rect2i(256, 6, 48, 19)
const SCALE := 3
## Innenfläche des Porträt-Rahmens im Block (lokale Pixel, vor Skalierung). Der
## Rahmen hat einen gefüllten (nicht transparenten) Innenraum, deshalb kommt der
## Kopf ÜBER den Block, auf diese Fläche.
const PORTRAIT_INNER := Rect2i(3, 3, 14, 14)
## Kopf-Ausschnitt aus dem 48px-Idle-Frame.
const HEAD_CROP := Rect2i(12, 3, 24, 22)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Porträt-Rahmen + Balken (Basis).
	var block := TextureRect.new()
	block.texture = UiAtlas.tex("bars", BLOCK_REGION)
	block.custom_minimum_size = Vector2(BLOCK_REGION.size * SCALE)
	block.size = Vector2(BLOCK_REGION.size * SCALE)
	block.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(block)

	# Kopf ÜBER den Block, auf die Porträt-Innenfläche, geclippt.
	var head := _head_texture()
	if head != null:
		var clip := Control.new()
		clip.position = Vector2(PORTRAIT_INNER.position * SCALE)
		clip.size = Vector2(PORTRAIT_INNER.size * SCALE)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(clip)
		var tr := TextureRect.new()
		tr.texture = head
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(tr)


## Kopf des eigenen Charakters aus dem Idle-Frame ausschneiden.
func _head_texture() -> Texture2D:
	var sf := CCFrames.build(AppearanceStore.local())
	if not sf.has_animation(&"idle_south") or sf.get_frame_count(&"idle_south") == 0:
		return null
	var img := sf.get_frame_texture(&"idle_south", 0).get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var crop := HEAD_CROP.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	return ImageTexture.create_from_image(img.get_region(crop))
