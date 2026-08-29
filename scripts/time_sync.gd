extends Node

## Synchronisiert die Tageszeit ueber alle Spieler.
##
## Der dedizierte Server ist die Uhr: er schickt time_of_day regelmaessig an
## alle Clients. Die Clients lassen ihre Zeit lokal weiterlaufen (damit es
## fluessig bleibt) und korrigieren sie mit jedem Server-Wert. So sehen alle
## dieselbe Uhrzeit.

const SYNC_EVERY := 2.0

var _day: Node
var _accum := 0.0


func _ready() -> void:
	if not Net.active:
		return
	_day = get_tree().get_first_node_in_group("day_night")
	if Net.is_dedicated:
		# Neuen Spielern sofort die aktuelle Zeit schicken.
		multiplayer.peer_connected.connect(func(id):
			if _day:
				_set_time.rpc_id(id, _day.time_of_day))


func _process(delta: float) -> void:
	if not Net.is_dedicated or _day == null:
		return
	_accum += delta
	if _accum < SYNC_EVERY:
		return
	_accum = 0.0
	_set_time.rpc(_day.time_of_day)


@rpc("any_peer", "unreliable")
func _set_time(t: float) -> void:
	if Net.is_dedicated or _day == null:
		return
	# Waehrend der Schlaf-Ueberblendung nicht dazwischenfunken (sonst ruckt die
	# Zeit auf den Server-Wert zurueck).
	if _day.has_method("is_skipping") and _day.is_skipping():
		return
	_day.time_of_day = t
