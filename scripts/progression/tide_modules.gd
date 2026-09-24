extends RefCounted

## Tide Glyph loadout: found sockets, owned glyphs and the socketed set, plus the save-key
## validation. Held by GameState as `GameState.tide`. The socketed set changes only while a save
## shrine session is open (see scripts/campaign/tide_hook.gd); combat code reads the stat
## multipliers through `multiplier`, `add` and `scale_int`.

signal changed

const TideCatalog = preload("res://scripts/progression/tide_catalog.gd")
const SAVE_KEY := "tide_modules"

var sockets_found := 0
var owned: Array[StringName] = []
var equipped: Array[StringName] = []
var _station_open := false


func reset() -> void:
	sockets_found = 0
	owned.clear()
	equipped.clear()
	_station_open = false
	changed.emit()


func capacity() -> int:
	return TideCatalog.BASE_CAPACITY + sockets_found


func used() -> int:
	var total := 0
	for id in equipped:
		total += TideCatalog.cost(id)
	return total


func owns(id: StringName) -> bool:
	return owned.has(id)


func is_equipped(id: StringName) -> bool:
	return equipped.has(id)


## Applies a socket or glyph pickup kind; false when it would change nothing.
func collect(kind: StringName) -> bool:
	if kind == TideCatalog.SOCKET_KIND:
		if sockets_found >= TideCatalog.MAX_SOCKETS_FOUND:
			return false
		sockets_found += 1
		changed.emit()
		return true
	var id := TideCatalog.glyph_for_kind(kind)
	if id == &"" or owned.has(id):
		return false
	owned.append(id)
	changed.emit()
	return true


func feedback(kind: StringName) -> String:
	if kind == TideCatalog.SOCKET_KIND:
		return "TIDE SOCKET · capacity %d" % capacity()
	return "%s · Tide Glyph" % TideCatalog.glyph_name(TideCatalog.glyph_for_kind(kind)).to_upper()


func open_station() -> void:
	_station_open = true


func close_station() -> void:
	_station_open = false


func at_station() -> bool:
	return _station_open


## True when `id` could be socketed now. Capacity is a hard limit: there is no overload rule.
func can_equip(id: StringName) -> bool:
	return (
		_station_open
		and owned.has(id)
		and not equipped.has(id)
		and used() + TideCatalog.cost(id) <= capacity()
	)


func equip(id: StringName) -> bool:
	if not can_equip(id):
		return false
	equipped.append(id)
	changed.emit()
	return true


func unequip(id: StringName) -> bool:
	if not _station_open or not equipped.has(id):
		return false
	equipped.erase(id)
	changed.emit()
	return true


func toggle(id: StringName) -> bool:
	return unequip(id) if equipped.has(id) else equip(id)


## Product of every socketed glyph's multiplier for `stat` (1.0 when none touches it).
func multiplier(stat: StringName) -> float:
	var result := 1.0
	for id in equipped:
		var mods: Dictionary = TideCatalog.GLYPHS[id]["mods"]
		if mods.has(stat) and not TideCatalog.is_add_stat(stat):
			result *= float(mods[stat])
	return result


## Sum of every socketed glyph's additive value for an `_add` stat.
func add(stat: StringName) -> int:
	var result := 0
	for id in equipped:
		var mods: Dictionary = TideCatalog.GLYPHS[id]["mods"]
		if mods.has(stat) and TideCatalog.is_add_stat(stat):
			result += int(mods[stat])
	return result


## `base` scaled by `stat`, rounded; a positive base never drops to zero.
func scale_int(stat: StringName, base: int) -> int:
	if base <= 0:
		return base
	return maxi(1, roundi(base * multiplier(stat)))


## The optional snapshot value; empty while nothing has been found, so such saves stay identical
## to saves written before Tide Glyphs existed.
func snapshot_value() -> Dictionary:
	if sockets_found == 0 and owned.is_empty():
		return {}
	var owned_ids: Array[String] = []
	for id in owned:
		owned_ids.append(String(id))
	var equipped_ids: Array[String] = []
	for id in equipped:
		equipped_ids.append(String(id))
	return {"sockets_found": sockets_found, "owned": owned_ids, "equipped": equipped_ids}


func restore(validated_value: Dictionary) -> void:
	sockets_found = int(validated_value["sockets_found"])
	owned.assign(validated_value["owned"])
	equipped.assign(validated_value["equipped"])
	_station_open = false
	changed.emit()


## Validated copy of a snapshot value, or {} when it is malformed. An empty dictionary (the key
## was absent) validates as nothing found. A valid result always has all three keys.
static func validated(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var data: Dictionary = value
	var empty: Array[StringName] = []
	if data.is_empty():
		return {"sockets_found": 0, "owned": empty, "equipped": empty.duplicate()}
	if data.size() != 3 or not data.has_all(["sockets_found", "owned", "equipped"]):
		return {}
	var sockets: Variant = data["sockets_found"]
	if not _integral(sockets) or sockets < 0 or sockets > TideCatalog.MAX_SOCKETS_FOUND:
		return {}
	var owned_ids: Variant = _glyph_list(data["owned"])
	var equipped_ids: Variant = _glyph_list(data["equipped"])
	if owned_ids == null or equipped_ids == null:
		return {}
	var total := 0
	for id: StringName in equipped_ids:
		if not owned_ids.has(id):
			return {}
		total += TideCatalog.cost(id)
	if total > TideCatalog.BASE_CAPACITY + int(sockets):
		return {}
	return {"sockets_found": int(sockets), "owned": owned_ids, "equipped": equipped_ids}


static func _integral(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and floorf(value) == value)


## Unique known glyph ids as Array[StringName], or null when any entry is invalid.
static func _glyph_list(value: Variant) -> Variant:
	if not value is Array:
		return null
	var result: Array[StringName] = []
	for entry: Variant in value:
		if not entry is String or not TideCatalog.is_glyph(StringName(entry)):
			return null
		if result.has(StringName(entry)):
			return null
		result.append(StringName(entry))
	return result
