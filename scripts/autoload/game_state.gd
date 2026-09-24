extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")

signal slipstream_acquired
signal beam_acquired
signal missiles_acquired
signal state_changed
signal ammo_changed(current: int, maximum: int)
signal health_changed(current: int, maximum: int)
signal flux_changed(current: int, maximum: int)
signal flux_module_changed(module: StringName, enabled: bool)
signal player_died
signal pickup_feedback(message: String)

var has_slipstream: bool = false
var has_beam: bool = false
var has_missiles: bool = false
var missile_count: int = 0
var max_missiles: int = 0
var max_health: int = Catalog.DEFAULT_MAX_HEALTH
var health: int = Catalog.DEFAULT_MAX_HEALTH
var active_beam: StringName = &"base"
var energy_tanks: int = 0
var missile_tanks: int = 0
var flux_current: int = 0
var flux_max: int = 0
var flux_tanks: int = 0
var active_flux_module: StringName = &""
var flux_enabled: bool = false
var collected_pickup_ids: Array[String] = []
var world_flags: Dictionary = {}
var discovered_rooms: Array[String] = []
var checkpoint: Dictionary = Catalog.DEFAULT_CHECKPOINT.duplicate(true)

var _abilities: Dictionary = {}


func has_ability(id: StringName) -> bool:
	return _abilities.has(id)


func unlock_ability(id: StringName) -> bool:
	if not Catalog.is_ability(id) or has_ability(id):
		return false
	if not _ability_prerequisites_met(id):
		return false

	var old_health := health
	var old_flux := flux_current
	var old_max_flux := flux_max
	var old_max_health := max_health
	var old_ammo := missile_count
	var old_max_ammo := max_missiles
	if not _apply_ability(id):
		return false
	if id in [&"ice_beam", &"wave_beam"]:
		active_beam = &"ice" if id == &"ice_beam" else &"wave"
	_emit_ability_signal(id)
	_emit_changes(old_health, old_max_health, old_ammo, old_max_ammo)
	_emit_flux_change(old_flux, old_max_flux)
	return true


func collect_pickup(instance_id: String, kind: StringName) -> bool:
	if not Catalog.is_pickup_kind(kind):
		return false
	var is_refill := kind in [&"energy_refill", &"missile_refill", &"flux_refill"]
	if not is_refill and instance_id.is_empty():
		return false
	if not is_refill and collected_pickup_ids.has(instance_id):
		return false

	var old_health := health
	var old_max_health := max_health
	var old_ammo := missile_count
	var old_max_ammo := max_missiles
	var old_flux := flux_current
	var old_max_flux := flux_max
	var missile_unlock := kind == &"missile_tank" and not has_missiles
	var auto_equipped_beam := false
	var was_full := (
		health >= max_health
		if kind == &"energy_refill"
		else (
			missile_count >= max_missiles if kind == &"missile_refill" else flux_current >= flux_max
		)
	)
	var changed := false

	match kind:
		&"energy_refill":
			health = mini(max_health, health + Catalog.ENERGY_REFILL_AMOUNT)
			changed = true
		&"missile_refill":
			if not has_missiles:
				return false
			missile_count = mini(max_missiles, missile_count + Catalog.MISSILE_REFILL_AMOUNT)
			changed = true
		&"flux_refill":
			if _has_owned_flux_ability() and flux_max > 0:
				flux_current = mini(flux_max, flux_current + Catalog.FLUX_TEMPORARY_REFILL)
				changed = true
		&"energy_tank":
			if energy_tanks >= Catalog.MAX_ENERGY_TANKS:
				return false
			energy_tanks += 1
			max_health = Catalog.DEFAULT_MAX_HEALTH + energy_tanks * Catalog.ENERGY_PER_TANK
			health = max_health
			changed = true
		&"missile_tank":
			if missile_tanks >= Catalog.MAX_MISSILE_TANKS:
				return false
			missile_tanks += 1
			has_missiles = true
			_abilities[&"missiles"] = true
			max_missiles = missile_tanks * Catalog.MISSILES_PER_TANK
			missile_count = mini(max_missiles, missile_count + Catalog.MISSILES_PER_TANK)
			changed = true
		&"flux_tank":
			if not _has_owned_flux_ability() or flux_tanks >= Catalog.MAX_FLUX_TANKS:
				return false
			flux_tanks += 1
			flux_max = Catalog.FLUX_BASE_MAX + flux_tanks * Catalog.FLUX_PER_TANK
			flux_current = flux_max
			changed = true
		_:
			if Catalog.is_flux_ability(kind) and not has_ability(kind):
				if not _ability_prerequisites_met(kind):
					return false
				changed = _apply_ability(kind)
			else:
				if has_ability(kind):
					return _consume_duplicate_pickup(instance_id, "UPGRADE ALREADY INSTALLED")
				if not _ability_prerequisites_met(kind):
					return false
				changed = _apply_ability(kind)
			if changed and kind in [&"ice_beam", &"wave_beam"]:
				active_beam = &"ice" if kind == &"ice_beam" else &"wave"
				auto_equipped_beam = true

	if not changed:
		return false
	if not is_refill:
		collected_pickup_ids.append(instance_id)
	if missile_unlock:
		missiles_acquired.emit()
	elif kind != &"missile_tank":
		_emit_ability_signal(kind)
	_emit_changes(old_health, old_max_health, old_ammo, old_max_ammo)
	_emit_flux_change(old_flux, old_max_flux)
	pickup_feedback.emit(_pickup_feedback_message(kind, auto_equipped_beam, was_full))
	return true


func _consume_duplicate_pickup(instance_id: String, message: String) -> bool:
	if collected_pickup_ids.has(instance_id):
		return false
	collected_pickup_ids.append(instance_id)
	state_changed.emit()
	pickup_feedback.emit(message)
	return true


func set_active_beam(kind: StringName) -> bool:
	if not Catalog.is_beam(kind):
		return false
	if kind != &"base" and not has_ability(_ability_for_beam(kind)):
		return false
	if kind == &"base" and not has_beam:
		return false
	if active_beam == kind:
		return true
	active_beam = kind
	state_changed.emit()
	return true


func set_active_flux_module(module: StringName) -> bool:
	if module != &"" and not Catalog.is_flux_ability(module):
		return false
	if module != &"" and not has_ability(module):
		return false
	if module == active_flux_module:
		return true
	active_flux_module = module
	flux_enabled = false
	flux_module_changed.emit(active_flux_module, flux_enabled)
	state_changed.emit()
	return true


func set_flux_enabled(enabled: bool) -> bool:
	if (
		enabled
		and (
			flux_current <= 0
			or active_flux_module == &""
			or active_flux_module == &"echo_scan"
			or not has_ability(active_flux_module)
		)
	):
		return false
	if flux_enabled == enabled:
		return true
	_set_flux_enabled(enabled)
	state_changed.emit()
	return true


func toggle_flux() -> bool:
	return set_flux_enabled(not flux_enabled)


func _set_flux_enabled(enabled: bool) -> void:
	if flux_enabled == enabled:
		return
	flux_enabled = enabled
	flux_module_changed.emit(active_flux_module, flux_enabled)


func spend_flux(amount: int) -> bool:
	if amount <= 0 or flux_max <= 0 or amount > flux_current:
		return false
	flux_current -= amount
	if flux_current == 0:
		_set_flux_enabled(false)
	flux_changed.emit(flux_current, flux_max)
	state_changed.emit()
	return true


func refill_flux(amount: int = Catalog.FLUX_TEMPORARY_REFILL) -> void:
	if amount <= 0 or flux_max <= 0:
		return
	var previous := flux_current
	flux_current = mini(flux_max, flux_current + amount)
	_emit_flux_change(previous, flux_max)


func refill() -> void:
	var old_health := health
	var old_max_health := max_health
	var old_ammo := missile_count
	var old_max_ammo := max_missiles
	var old_flux := flux_current
	var old_max_flux := flux_max
	health = max_health
	if has_missiles:
		missile_count = max_missiles
	if flux_max > 0:
		flux_current = flux_max
	_emit_changes(old_health, old_max_health, old_ammo, old_max_ammo)
	_emit_flux_change(old_flux, old_max_flux)


func refill_missiles(amount: int) -> void:
	if amount <= 0 or not has_missiles:
		return
	var old_ammo := missile_count
	missile_count = mini(max_missiles, missile_count + amount)
	if missile_count != old_ammo:
		ammo_changed.emit(missile_count, max_missiles)
		state_changed.emit()


func reset_progress() -> void:
	var old_health := health
	var old_max_health := max_health
	var old_ammo := missile_count
	var old_max_ammo := max_missiles
	var old_flux := flux_current
	var old_max_flux := flux_max
	_abilities.clear()
	has_slipstream = false
	has_beam = false
	has_missiles = false
	missile_count = 0
	max_missiles = Catalog.DEFAULT_MAX_MISSILES
	max_health = Catalog.DEFAULT_MAX_HEALTH
	health = max_health
	active_beam = &"base"
	energy_tanks = 0
	missile_tanks = 0
	flux_current = 0
	flux_max = 0
	flux_tanks = 0
	active_flux_module = &""
	flux_enabled = false
	collected_pickup_ids.clear()
	world_flags.clear()
	discovered_rooms.clear()
	checkpoint = Catalog.DEFAULT_CHECKPOINT.duplicate(true)
	_emit_changes(old_health, old_max_health, old_ammo, old_max_ammo)
	_emit_flux_change(old_flux, old_max_flux)


func snapshot() -> Dictionary:
	var abilities: Array[String] = []
	for id in Catalog.ABILITY_IDS:
		if has_ability(id):
			abilities.append(String(id))
	return {
		"version": Catalog.SCHEMA_VERSION,
		"abilities": abilities,
		"active_beam": String(active_beam),
		"energy_tanks": energy_tanks,
		"missile_tanks": missile_tanks,
		"max_health": max_health,
		"health": health,
		"max_missiles": max_missiles,
		"missile_count": missile_count,
		"flux_current": flux_current,
		"flux_max": flux_max,
		"flux_tanks": flux_tanks,
		"active_flux_module": String(active_flux_module),
		"flux_enabled": flux_enabled,
		"collected_ids": collected_pickup_ids.duplicate(),
		"world_flags": world_flags.duplicate(true),
		"discovered_rooms": discovered_rooms.duplicate(),
		"checkpoint": checkpoint.duplicate(true),
	}


func validate_snapshot(data: Dictionary) -> bool:
	return not _validated_snapshot(data).is_empty()


func restore_snapshot(data: Dictionary) -> bool:
	var validated := _validated_snapshot(data)
	if validated.is_empty():
		return false

	var old_health := health
	var old_max_health := max_health
	var old_ammo := missile_count
	var old_max_ammo := max_missiles
	var old_flux := flux_current
	var old_max_flux := flux_max
	_abilities.clear()
	for id in validated["abilities"]:
		_abilities[StringName(id)] = true
	has_slipstream = has_ability(&"slipstream")
	has_beam = has_ability(&"beam")
	has_missiles = has_ability(&"missiles")
	active_beam = StringName(validated["active_beam"])
	energy_tanks = validated["energy_tanks"]
	missile_tanks = validated["missile_tanks"]
	max_health = validated["max_health"]
	health = validated["health"]
	max_missiles = validated["max_missiles"]
	missile_count = validated["missile_count"]
	flux_current = validated["flux_current"]
	flux_max = validated["flux_max"]
	flux_tanks = validated["flux_tanks"]
	active_flux_module = StringName(validated["active_flux_module"])
	flux_enabled = validated["flux_enabled"] and flux_current > 0
	collected_pickup_ids = validated["collected_ids"].duplicate()
	world_flags = validated["world_flags"].duplicate(true)
	discovered_rooms = validated["discovered_rooms"].duplicate()
	checkpoint = validated["checkpoint"].duplicate(true)
	_emit_changes(old_health, old_max_health, old_ammo, old_max_ammo)
	_emit_flux_change(old_flux, old_max_flux)
	flux_module_changed.emit(active_flux_module, flux_enabled)
	return true


func set_world_flag(id: String, value: bool = true) -> void:
	if id.is_empty() or (world_flags.get(id, null) == value):
		return
	world_flags[id] = value
	state_changed.emit()


func has_world_flag(id: String) -> bool:
	return world_flags.get(id, false) == true


func set_checkpoint(room: String, position: Vector2) -> bool:
	if not _valid_room(room) or not _valid_position(position):
		return false
	var next := {"room": room, "x": position.x, "y": position.y}
	if checkpoint == next:
		return true
	checkpoint = next
	state_changed.emit()
	return true


func discover_room(room: String) -> bool:
	if not _valid_room(room) or discovered_rooms.has(room):
		return false
	discovered_rooms.append(room)
	state_changed.emit()
	return true


func acquire_slipstream() -> void:
	unlock_ability(&"slipstream")


func acquire_beam() -> void:
	unlock_ability(&"beam")


func acquire_missiles(n: int) -> void:
	if n < 0:
		return
	var first_unlock := not has_missiles
	if first_unlock:
		_abilities[&"missiles"] = true
		has_missiles = true
		max_missiles = Catalog.MISSILES_PER_TANK
	var old_ammo := missile_count
	missile_count = mini(max_missiles, missile_count + n)
	if first_unlock:
		missiles_acquired.emit()
	if first_unlock or old_ammo != missile_count:
		if old_ammo != missile_count or first_unlock:
			ammo_changed.emit(missile_count, max_missiles)
		state_changed.emit()


func spend_missile() -> bool:
	if not has_missiles or missile_count <= 0:
		return false
	missile_count -= 1
	ammo_changed.emit(missile_count, max_missiles)
	state_changed.emit()
	return true


func reset_health() -> void:
	if health == max_health:
		health_changed.emit(health, max_health)
		return
	health = max_health
	health_changed.emit(health, max_health)
	state_changed.emit()


func apply_damage(amount: int) -> void:
	if amount <= 0 or health <= 0:
		return
	var previous_health := health
	health = maxi(health - amount, 0)
	if health == previous_health:
		return
	health_changed.emit(health, max_health)
	state_changed.emit()
	if previous_health > 0 and health == 0:
		player_died.emit()


func heal(amount: int) -> void:
	if amount <= 0 or health >= max_health:
		return
	var previous_health := health
	health = mini(health + amount, max_health)
	if health == previous_health:
		return
	health_changed.emit(health, max_health)
	state_changed.emit()


func _ability_prerequisites_met(id: StringName) -> bool:
	if id == &"bombs" and not has_slipstream:
		return false
	if id in [&"long_beam", &"ice_beam", &"wave_beam"] and not has_beam:
		return false
	return true


func _apply_ability(id: StringName) -> bool:
	if not Catalog.is_ability(id):
		return false
	_abilities[id] = true
	match id:
		&"slipstream":
			has_slipstream = true
		&"beam":
			has_beam = true
		&"missiles":
			has_missiles = true
			if max_missiles < Catalog.MISSILES_PER_TANK:
				max_missiles = Catalog.MISSILES_PER_TANK
		_:
			if Catalog.is_flux_ability(id) and flux_max == 0:
				flux_max = Catalog.FLUX_BASE_MAX
				flux_current = flux_max
	return true


func _has_owned_flux_ability() -> bool:
	for id in Catalog.FLUX_ABILITY_IDS:
		if has_ability(id):
			return true
	return false


func _ability_for_beam(kind: StringName) -> StringName:
	match kind:
		&"ice":
			return &"ice_beam"
		&"wave":
			return &"wave_beam"
	return &"beam"


func _emit_ability_signal(id: StringName) -> void:
	match id:
		&"slipstream":
			slipstream_acquired.emit()
		&"beam":
			beam_acquired.emit()
		&"missiles", &"missile_tank":
			missiles_acquired.emit()


func _emit_changes(old_health: int, old_max_health: int, old_ammo: int, old_max_ammo: int) -> void:
	if health != old_health or max_health != old_max_health:
		health_changed.emit(health, max_health)
	if missile_count != old_ammo or max_missiles != old_max_ammo:
		ammo_changed.emit(missile_count, max_missiles)
	state_changed.emit()


func _emit_flux_change(old_current: int, old_maximum: int) -> void:
	if flux_current != old_current or flux_max != old_maximum:
		flux_changed.emit(flux_current, flux_max)
		state_changed.emit()


func _has_exact_keys(data: Dictionary, expected: Array) -> bool:
	if data.size() != expected.size():
		return false
	for key in expected:
		if not data.has(key):
			return false
	for key in data:
		if not key is String or not expected.has(key):
			return false
	return true


func _validated_snapshot(data: Dictionary) -> Dictionary:
	var version_value: Variant = data.get("version", null)
	if _valid_int(version_value, Catalog.LEGACY_SCHEMA_VERSION, Catalog.LEGACY_SCHEMA_VERSION):
		var legacy := _validated_legacy_snapshot(data)
		if legacy.is_empty():
			return {}
		legacy["version"] = Catalog.SCHEMA_VERSION
		legacy["flux_current"] = 0
		legacy["flux_max"] = 0
		legacy["flux_tanks"] = 0
		legacy["active_flux_module"] = ""
		legacy["flux_enabled"] = false
		return legacy
	if not _valid_int(version_value, Catalog.SCHEMA_VERSION, Catalog.SCHEMA_VERSION):
		return {}
	var expected_v2 := [
		"version",
		"abilities",
		"active_beam",
		"energy_tanks",
		"missile_tanks",
		"max_health",
		"health",
		"max_missiles",
		"missile_count",
		"flux_current",
		"flux_max",
		"flux_tanks",
		"active_flux_module",
		"flux_enabled",
		"collected_ids",
		"world_flags",
		"discovered_rooms",
		"checkpoint"
	]
	if not _has_exact_keys(data, expected_v2):
		return {}
	return _validated_snapshot_fields(data, true)


func _validated_legacy_snapshot(data: Dictionary) -> Dictionary:
	var expected_v1 := [
		"version",
		"abilities",
		"active_beam",
		"energy_tanks",
		"missile_tanks",
		"max_health",
		"health",
		"max_missiles",
		"missile_count",
		"collected_ids",
		"world_flags",
		"discovered_rooms",
		"checkpoint"
	]
	if not _has_exact_keys(data, expected_v1):
		return {}
	return _validated_snapshot_fields(data, false)


func _validated_snapshot_fields(data: Dictionary, allow_flux: bool) -> Dictionary:
	var ability_data := _validated_abilities(data.get("abilities", null), allow_flux)
	if ability_data.is_empty():
		return {}
	var abilities: Array[String] = ability_data["abilities"]
	var active_value: Variant = data.get("active_beam", null)
	if not active_value is String or not Catalog.is_beam(StringName(active_value)):
		return {}
	var active := StringName(active_value)
	if active != &"base" and not abilities.has(String(_ability_for_beam(active))):
		return {}
	if not _validated_ability_prerequisites(abilities):
		return {}
	var resource_data := _validated_resources(data, abilities)
	if resource_data.is_empty():
		return {}
	var list_data := _validated_lists(data)
	if list_data.is_empty():
		return {}
	var checkpoint_data := _validated_checkpoint(data.get("checkpoint", null))
	if checkpoint_data.is_empty():
		return {}
	var result := {
		"abilities": abilities,
		"active_beam": String(active),
		"energy_tanks": resource_data["energy_tanks"],
		"missile_tanks": resource_data["missile_tanks"],
		"max_health": resource_data["max_health"],
		"health": resource_data["health"],
		"max_missiles": resource_data["max_missiles"],
		"missile_count": resource_data["missile_count"],
		"collected_ids": list_data["collected_ids"],
		"world_flags": list_data["world_flags"],
		"discovered_rooms": list_data["discovered_rooms"],
		"checkpoint": checkpoint_data,
	}
	if allow_flux:
		var flux_data := _validated_flux(data, abilities)
		if flux_data.is_empty():
			return {}
		result.merge(flux_data)
	return result


func _validated_abilities(value: Variant, allow_flux: bool) -> Dictionary:
	if not value is Array:
		return {}
	var abilities: Array[String] = []
	for entry in value:
		if not entry is String or not Catalog.is_ability(StringName(entry)) or abilities.has(entry):
			return {}
		if not allow_flux and Catalog.is_flux_ability(StringName(entry)):
			return {}
		abilities.append(entry)
	return {"abilities": abilities}


func _validated_flux(data: Dictionary, abilities: Array[String]) -> Dictionary:
	var tank_value: Variant = data.get("flux_tanks", null)
	var max_value: Variant = data.get("flux_max", null)
	var current_value: Variant = data.get("flux_current", null)
	if (
		not _valid_int(tank_value, 0, Catalog.MAX_FLUX_TANKS)
		or not _valid_int(max_value, 0, Catalog.MAX_FLUX)
		or not _valid_int(current_value, 0, Catalog.MAX_FLUX)
	):
		return {}
	var tanks := int(tank_value)
	var has_flux := false
	for id in Catalog.FLUX_ABILITY_IDS:
		if abilities.has(String(id)):
			has_flux = true
			break
	var expected_max := Catalog.FLUX_BASE_MAX + tanks * Catalog.FLUX_PER_TANK if has_flux else 0
	if int(max_value) != expected_max or int(current_value) > expected_max:
		return {}
	if not has_flux and tanks != 0:
		return {}
	var active_value: Variant = data.get("active_flux_module", null)
	var enabled_value: Variant = data.get("flux_enabled", null)
	if not active_value is String or not enabled_value is bool:
		return {}
	var active := StringName(active_value)
	if active != &"" and (not Catalog.is_flux_ability(active) or not abilities.has(String(active))):
		return {}
	if bool(enabled_value) and active == &"":
		return {}
	return {
		"flux_current": int(current_value),
		"flux_max": int(max_value),
		"flux_tanks": tanks,
		"active_flux_module": String(active),
		"flux_enabled": bool(enabled_value),
	}


func _validated_ability_prerequisites(abilities: Array[String]) -> bool:
	if abilities.has("bombs") and not abilities.has("slipstream"):
		return false
	for variant in ["long_beam", "ice_beam", "wave_beam"]:
		if abilities.has(variant) and not abilities.has("beam"):
			return false
	return true


func _pickup_feedback_message(kind: StringName, auto_equipped_beam: bool, was_full: bool) -> String:
	# Names come from ContentCatalog.DISPLAY_NAMES (D19); internal ids are unchanged.
	var title := Catalog.display_name(kind).to_upper()
	if kind == &"missiles" or kind == &"missile_tank":
		return (
			"%s · %d / %d %s" % [title, missile_count, max_missiles, Catalog.AMMO_NAME.to_upper()]
		)
	if kind == &"ice_beam" or kind == &"wave_beam":
		return "%s · auto-equipped" % title if auto_equipped_beam else "%s unlocked" % title
	if kind == &"energy_tank":
		return "%s · max health %d" % [title, max_health]
	if kind == &"energy_refill":
		return (
			"VITALITY FULL · %d / %d" % [health, max_health]
			if was_full
			else "VITALITY · %d / %d" % [health, max_health]
		)
	if kind == &"missile_refill":
		var ammo := Catalog.AMMO_NAME.to_upper()
		return (
			"%s FULL · %d / %d" % [ammo, missile_count, max_missiles]
			if was_full
			else "%s · %d / %d" % [ammo, missile_count, max_missiles]
		)
	if kind == &"flux_refill":
		return (
			"FLUX FULL · %d / %d" % [flux_current, flux_max]
			if was_full
			else "FLUX · %d / %d" % [flux_current, flux_max]
		)
	var details := {
		&"beam": " · X fires active beam",
		&"long_beam": " · passive range increase",
		&"bombs": " · X emits it in ball",
		&"pressure_seal": " · passive protection",
		&"flux_tank": " · max Flux %d" % flux_max,
	}
	if details.has(kind):
		return title + String(details[kind])
	if Catalog.DISPLAY_NAMES.has(kind):
		return "%s unlocked" % title
	return "UPGRADE ACQUIRED"


func _validated_resources(data: Dictionary, abilities: Array[String]) -> Dictionary:
	var energy_value: Variant = data.get("energy_tanks", null)
	var missile_tanks_value: Variant = data.get("missile_tanks", null)
	if (
		not _valid_int(energy_value, 0, Catalog.MAX_ENERGY_TANKS)
		or not _valid_int(missile_tanks_value, 0, Catalog.MAX_MISSILE_TANKS)
	):
		return {}
	var energy_count := int(energy_value)
	var missile_tank_count := int(missile_tanks_value)
	var expected_health := Catalog.DEFAULT_MAX_HEALTH + energy_count * Catalog.ENERGY_PER_TANK
	var has_missiles := abilities.has("missiles")
	if missile_tank_count > 0 and not has_missiles:
		return {}
	var expected_missiles := (
		maxi(missile_tank_count, 1 if has_missiles else 0) * Catalog.MISSILES_PER_TANK
	)
	var max_health_value: Variant = data.get("max_health", null)
	var max_missiles_value: Variant = data.get("max_missiles", null)
	if (
		not _valid_int(max_health_value, expected_health, expected_health)
		or not _valid_int(max_missiles_value, expected_missiles, expected_missiles)
	):
		return {}
	var health_value: Variant = data.get("health", null)
	var ammo_value: Variant = data.get("missile_count", null)
	if (
		not _valid_int(health_value, 0, expected_health)
		or not _valid_int(ammo_value, 0, expected_missiles)
	):
		return {}
	var ammo_count := int(ammo_value)
	if not has_missiles and ammo_count != 0:
		return {}
	return {
		"energy_tanks": energy_count,
		"missile_tanks": missile_tank_count,
		"max_health": int(max_health_value),
		"health": int(health_value),
		"max_missiles": int(max_missiles_value),
		"missile_count": ammo_count,
	}


func _validated_lists(data: Dictionary) -> Dictionary:
	var ids_value: Variant = data.get("collected_ids", null)
	if not ids_value is Array:
		return {}
	var ids: Array[String] = []
	for entry in ids_value:
		if not entry is String or entry.is_empty() or ids.has(entry):
			return {}
		ids.append(entry)
	var flags_value: Variant = data.get("world_flags", null)
	if not flags_value is Dictionary:
		return {}
	var flags: Dictionary = {}
	for key in flags_value:
		if not key is String or key.is_empty() or not flags_value[key] is bool:
			return {}
		flags[key] = flags_value[key]
	var rooms_value: Variant = data.get("discovered_rooms", null)
	if not rooms_value is Array:
		return {}
	var rooms: Array[String] = []
	for entry in rooms_value:
		if not entry is String or not _valid_room(entry) or rooms.has(entry):
			return {}
		rooms.append(entry)
	return {"collected_ids": ids, "world_flags": flags, "discovered_rooms": rooms}


func _validated_checkpoint(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var checkpoint: Dictionary = value
	if not _has_exact_keys(checkpoint, ["room", "x", "y"]):
		return {}
	var room_value: Variant = checkpoint.get("room", null)
	var x_value: Variant = checkpoint.get("x", null)
	var y_value: Variant = checkpoint.get("y", null)
	if (
		not room_value is String
		or not _valid_room(room_value)
		or not _valid_coordinate(x_value)
		or not _valid_coordinate(y_value)
	):
		return {}
	return {"room": room_value, "x": float(x_value), "y": float(y_value)}


func _valid_int(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		return is_finite(value) and floorf(value) == value and value >= minimum and value <= maximum
	return false


func _valid_room(room: String) -> bool:
	return not room.is_empty() and room.length() <= 128


func _valid_coordinate(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and absf(float(value)) <= 10000000.0
	)


func _valid_position(position: Vector2) -> bool:
	return _valid_coordinate(position.x) and _valid_coordinate(position.y)
