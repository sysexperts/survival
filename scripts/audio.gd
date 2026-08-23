extends Object

## Ses yardimcisi. class_name YOK - Auto-Updater yeni sinifi tanimaz
## (bkz. chunk_manager.gd/WorldGen), bu yuzden her yerde preload ile kullanilir.
##
## Ses kanallari (bus) kod ile olusturuluyor, proje ayari ile DEGIL: guncellenmis
## istemcilerde proje ayarlari temel .exe'den okundugu icin yeni bir bus ayari
## etki etmezdi (bkz. AGENTS - Net autoload tuzagi).

## "Efekt" ses kanalinin adi. Ayarlar menusu ilerde bu kanalin sesini
## AudioServer.set_bus_volume_db ile ayarlayabilir.
const EFFECTS_BUS := "Efektler"


## "Efektler" kanalini (yoksa) olusturur ve indexini dondurur. Master'a gonderir.
static func ensure_effects_bus() -> int:
	var idx := AudioServer.get_bus_index(EFFECTS_BUS)
	if idx != -1:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, EFFECTS_BUS)
	AudioServer.set_bus_send(idx, "Master")
	return idx
