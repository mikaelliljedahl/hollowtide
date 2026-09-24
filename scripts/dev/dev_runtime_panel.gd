extends RefCounted
class_name DevRuntimePanel

const Catalog = preload("res://scripts/progression/content_catalog.gd")

var _host: Node2D
var _station_baselines: Dictionary
var _session_baseline: Dictionary


func configure(host: Node2D, station_baselines: Dictionary, session_baseline: Dictionary) -> void:
	_host = host
	_station_baselines = station_baselines
	_session_baseline = session_baseline


func handle_action(action: StringName, data: Dictionary) -> void:
	match action:
		&"preset":
			apply_preset(StringName(data.get("id", &"")))
		&"ability":
			toggle_ability(StringName(data.get("id", &"")), bool(data.get("enabled", false)))
		&"capacity":
			apply_capacity(
				int(data.get("energy", 0)),
				int(data.get("missiles", 0)),
				int(data.get("flux_tanks", 0))
			)
		&"resources":
			apply_resources(
				int(data.get("health", 0)), int(data.get("ammo", 0)), int(data.get("flux", 0))
			)
		&"flux_module":
			if GameState.set_active_flux_module(StringName(data.get("id", &""))):
				set_status("Active Flux module selected.")
			else:
				set_status("Flux module is not unlocked.")
		&"flux_toggle":
			if GameState.set_flux_enabled(bool(data.get("enabled", false))):
				set_status("Flux state changed.")
			else:
				set_status("Flux cannot enable at zero charge.")
		&"refill":
			GameState.reset_health()
			GameState.refill_missiles(9999)
			GameState.refill_flux(9999)
			set_status("Resources filled through health, missile, and Flux APIs.")
		&"beam":
			if GameState.set_active_beam(StringName(data.get("id", &""))):
				set_status("Active bolt selected.")
			else:
				set_status("Bolt is not unlocked.")
		&"station":
			_host.call("_teleport_station", int(data.get("index", -1)))
		&"enemy":
			_host.call("_reset_arena")
			var enemy_station: int = (
				_host.get("_current_station") if int(_host.get("_current_station")) > 0 else 7
			)
			_host.call("_teleport_station", enemy_station)
			var station_ids: Array = _host.get("station_ids")
			var enemy_room: String = station_ids[enemy_station]
			var origins: Dictionary = _host.get("_room_origins")
			var enemy_id := StringName(data.get("id", &""))
			var location: Vector2 = origins[enemy_room] + Vector2(1024, 1020)
			if SurpriseCatalog.has(enemy_id):
				location = SurpriseCatalog.dev_spawn_point(
					enemy_id, _host.get_world_2d().direct_space_state, location
				)
			_host.call("_spawn_enemy", enemy_id, location, enemy_room)
			set_status("Enemy spawned in " + enemy_room + ".")
		&"boss":
			_host.call("_reset_arena")
			_host.call("_teleport_station", 8)
			var selected_boss := StringName(data.get("id", &""))
			var origins: Dictionary = _host.get("_room_origins")
			var test_boss: Node2D = _host.call(
				"_spawn_boss",
				selected_boss,
				origins["S8"] + Vector2(1600, 1060),
				int(data.get("phase", 0)),
				true
			)
			set_status(
				"Boss test spawned in S8." if test_boss != null else "Boss test spawn failed."
			)
		&"reset":
			if bool(data.get("all", false)):
				reset_all()
			else:
				reset_station()
		&"save":
			_host.call("_save_game")
		&"load":
			_host.call("_load_game")
		&"cheats":
			set_cheats(bool(data.get("god", false)), bool(data.get("ammo", false)))
		&"overlay":
			_host.set("_overlay_enabled", bool(data.get("enabled", false)))
			var overlay: CanvasLayer = _host.get("_overlay")
			if overlay != null:
				overlay.call("set_enabled", bool(data.get("enabled", false)))
			set_status("Overlay " + ("on." if bool(data.get("enabled", false)) else "off."))
		_:
			set_status("Dev error: unknown panel action " + String(action))


func apply_preset(id: StringName) -> void:
	if id == &"start":
		GameState.reset_progress()
		_session_baseline = GameState.snapshot()
		_capture_station_baselines()
		_host.call("_rebuild_runtime_content")
		_host.call("_teleport_station", 0)
		set_status("Start preset applied atomically. Zero pickups, zero missiles.")
		return
	if id != &"all":
		set_status("Unknown preset.")
		return
	var abilities: Array[StringName] = []
	for ability in Catalog.ABILITY_IDS:
		abilities.append(ability)
	apply_ability_set(abilities, 6, 12, 700, 60, Catalog.MAX_FLUX_TANKS, Catalog.MAX_FLUX)
	_session_baseline = GameState.snapshot()
	_capture_station_baselines()
	_host.call("_rebuild_runtime_content")
	set_status("All abilities and maximum capacity applied atomically.")


func toggle_ability(id: StringName, enabled: bool) -> void:
	if not Catalog.is_ability(id):
		set_status("Unknown ability.")
		return
	var desired: Array[StringName] = current_abilities()
	if enabled and not desired.has(id):
		desired.append(id)
	if not enabled:
		desired.erase(id)
		for dependent in Catalog.ABILITY_IDS:
			if dependent == &"bombs" and id == &"slipstream":
				desired.erase(dependent)
			if dependent in [&"long_beam", &"ice_beam", &"wave_beam"] and id == &"beam":
				desired.erase(dependent)
	apply_ability_set(
		desired,
		GameState.energy_tanks,
		GameState.missile_tanks,
		GameState.health,
		GameState.missile_count
	)
	set_status("Ability " + String(id) + (" added." if enabled else " and dependencies removed."))


func apply_capacity(energy: int, missiles: int, flux_tanks: int = 0) -> void:
	apply_ability_set(
		current_abilities(),
		clampi(energy, 0, Catalog.MAX_ENERGY_TANKS),
		clampi(missiles, 0, Catalog.MAX_MISSILE_TANKS),
		GameState.health,
		GameState.missile_count,
		clampi(flux_tanks, 0, Catalog.MAX_FLUX_TANKS),
		GameState.flux_current
	)
	set_status("Capacity applied through state API.")


func apply_resources(health: int, ammo: int, flux: int = 0) -> void:
	apply_ability_set(
		current_abilities(),
		GameState.energy_tanks,
		GameState.missile_tanks,
		health,
		ammo,
		GameState.flux_tanks,
		flux
	)
	set_status("Resources applied through state API.")


func current_abilities() -> Array[StringName]:
	var result: Array[StringName] = []
	for id in Catalog.ABILITY_IDS:
		if GameState.has_ability(id):
			result.append(id)
	return result


func apply_ability_set(
	abilities: Array[StringName],
	energy: int,
	missiles: int,
	health: int,
	ammo: int,
	flux_tanks: int = 0,
	flux: int = 0
) -> void:
	var normalized := normalize_abilities(abilities)
	var target := GameState.snapshot()
	target["abilities"] = []
	target["active_beam"] = "base"
	target["energy_tanks"] = clampi(energy, 0, Catalog.MAX_ENERGY_TANKS)
	target["missile_tanks"] = clampi(missiles, 0, Catalog.MAX_MISSILE_TANKS)
	target["max_health"] = 100 + int(target["energy_tanks"]) * 100
	target["health"] = clampi(health, 0, int(target["max_health"]))
	var has_missiles := normalized.has(&"missiles")
	target["max_missiles"] = maxi(int(target["missile_tanks"]), 1 if has_missiles else 0) * 5
	target["missile_count"] = (clampi(ammo, 0, int(target["max_missiles"])) if has_missiles else 0)
	var has_flux := false
	for id in normalized:
		if Catalog.is_flux_ability(id):
			has_flux = true
			break
	target["flux_tanks"] = clampi(flux_tanks, 0, Catalog.MAX_FLUX_TANKS) if has_flux else 0
	target["flux_max"] = (
		Catalog.FLUX_BASE_MAX + int(target["flux_tanks"]) * Catalog.FLUX_PER_TANK if has_flux else 0
	)
	target["flux_current"] = clampi(flux, 0, int(target["flux_max"])) if has_flux else 0
	target["active_flux_module"] = (
		String(GameState.active_flux_module)
		if has_flux and normalized.has(GameState.active_flux_module)
		else ""
	)
	target["flux_enabled"] = false
	for id in normalized:
		target["abilities"].append(String(id))
	if normalized.has(&"ice_beam"):
		target["active_beam"] = "ice"
	elif normalized.has(&"wave_beam"):
		target["active_beam"] = "wave"
	if GameState.restore_snapshot(target):
		return
	GameState.reset_progress()
	for id in normalized:
		GameState.unlock_ability(id)
	for index in int(target["energy_tanks"]):
		GameState.collect_pickup("dev.config.energy.%02d" % index, &"energy_tank")
	for index in int(target["missile_tanks"]):
		GameState.collect_pickup("dev.config.missile.%02d" % index, &"missile_tank")
	GameState.reset_health()
	var target_health := int(target["health"])
	GameState.apply_damage(GameState.health - target_health)
	while GameState.missile_count > int(target["missile_count"]):
		if not GameState.spend_missile():
			break
	if normalized.has(&"ice_beam"):
		GameState.set_active_beam(&"ice")
	elif normalized.has(&"wave_beam"):
		GameState.set_active_beam(&"wave")


func normalize_abilities(abilities: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in Catalog.ABILITY_IDS:
		if not abilities.has(id):
			continue
		if id == &"bombs" and not result.has(&"slipstream"):
			result.append(&"slipstream")
		if id in [&"long_beam", &"ice_beam", &"wave_beam"] and not result.has(&"beam"):
			result.append(&"beam")
		if not result.has(id):
			result.append(id)
	return result


func reset_station() -> void:
	var current_room: String = _host.get("_current_room")
	var baseline: Dictionary = _station_baselines.get(current_room, GameState.snapshot())
	var merged := GameState.snapshot()
	merged["world_flags"] = merge_local_flags(
		merged["world_flags"], baseline["world_flags"], "dev:" + current_room + ":"
	)
	if not GameState.restore_snapshot(merged):
		set_status("Station reset denied: snapshot validation rejected state.")
		return
	_host.call("_rebuild_runtime_content", current_room == "S8")
	_host.call("_teleport_station", int(_host.get("_current_station")))
	set_status("Station " + current_room + " reset; runtime reset, saved world flags preserved.")


func reset_all() -> void:
	if _session_baseline.is_empty() or not GameState.restore_snapshot(_session_baseline):
		GameState.reset_progress()
	_host.call("_clear_dev_runtime")
	_host.call("_rebuild_runtime_content", false)
	_host.call("_teleport_station", 0)
	set_status("Dev session reset. Runtime reset; session flags restored. No disk changes.")


func merge_local_flags(current: Dictionary, baseline: Dictionary, prefix: String) -> Dictionary:
	var result := current.duplicate(true)
	for key in baseline:
		if String(key).begins_with(prefix):
			result[key] = baseline[key]
	for key in result.keys():
		if String(key).begins_with(prefix) and not baseline.has(key):
			result.erase(key)
	return result


func set_cheats(god: bool, ammo: bool) -> void:
	_host.set("_cheat_ammo", ammo)
	var player: Node = _host.get("_player")
	if player != null and _has_property(player, "dev_invulnerable"):
		player.set("dev_invulnerable", god)
	set_status("Cheats: invulnerability=" + str(god) + ", infinite ammo=" + str(ammo))


func _capture_station_baselines() -> void:
	for room_id in _host.get("station_ids"):
		_station_baselines[room_id] = GameState.snapshot()


func set_status(message: String) -> void:
	_host.call("_set_status", message)


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.get("name", "") == property_name:
			return true
	return false
