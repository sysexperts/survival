extends Player
class_name PoPlayer

## Testfigur "Po" - dieselbe Steuerung wie der Charakter, nur andere Grafik.
##
## der Charakter bleibt unangetastet: Po erbt die komplette Spieler-Logik und tauscht
## nur die SpriteFrames aus (zur Laufzeit von PoFrames gebaut) und spiegelt
## den Sprite für die Ost-Richtungen - die Sheets zeigen nur die Westseite.

func _ready() -> void:
	sprite.sprite_frames = PoFrames.build()
	super()
	_play("idle")


func _play(state: String) -> void:
	sprite.flip_h = PoFrames.flipped(facing)
	super(state)


func _start_axe() -> void:
	sprite.flip_h = PoFrames.flipped(facing)
	super()
