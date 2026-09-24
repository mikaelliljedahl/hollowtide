extends SceneTree

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const GameStateScript = preload("res://scripts/autoload/game_state.gd")
const SaveStoreScript = preload("res://scripts/save/save_store.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run_state_tests()
	_run_save_tests()
	if _failures.is_empty():
		print("check_flux_state: PASS")
		await TestShutdown.finish(self, 0)
	else:
		for failure in _failures:
			push_error(failure)
		await TestShutdown.finish(self, 1)


func _run_state_tests() -> void:
	_expect(Catalog.SCHEMA_VERSION == 2, "Flux uses durable schema v2")
	_expect(
		Catalog.FLUX_ABILITY_IDS == [&"flux_shield", &"burst_beam", &"echo_scan"],
		"Flux ability IDs are stable"
	)
	var state = GameStateScript.new()
	state.reset_progress()
	_expect(
		(
			state.flux_current == 0
			and state.flux_max == 0
			and state.flux_tanks == 0
			and state.active_flux_module == &""
			and not state.flux_enabled
		),
		"old-save defaults have no usable Flux"
	)
	_expect(not state.set_flux_enabled(true), "Flux cannot enable without active owned module")
	_expect(state.unlock_ability(&"flux_shield"), "Flux Shield unlocks")
	_expect(
		state.flux_current == Catalog.FLUX_BASE_MAX and state.flux_max == Catalog.FLUX_BASE_MAX,
		"first Flux system grants base capacity and full charge"
	)
	_expect(state.unlock_ability(&"burst_beam"), "Burst Beam unlocks")
	_expect(state.unlock_ability(&"echo_scan"), "Echo Scan unlocks")
	_expect(state.set_active_flux_module(&"flux_shield"), "Shield activates")
	_expect(state.set_flux_enabled(true), "Shield enables")
	var shield_state := state.snapshot()
	_expect(not state.set_active_flux_module(&"missing"), "unknown module rejects")
	_expect(not state.set_active_flux_module(&"flux_tank"), "non-module rejects")
	_expect(state.snapshot() == shield_state, "failed module switches are atomic")
	_expect(state.set_active_flux_module(&"burst_beam"), "Burst switches exclusively")
	_expect(
		state.active_flux_module == &"burst_beam" and not state.flux_enabled,
		"switch leaves only one module active and disables it"
	)
	_expect(state.set_flux_enabled(true), "Burst enables")
	_expect(state.spend_flux(8), "exact Flux spend succeeds")
	_expect(state.flux_current == 92, "Flux spend subtracts exact amount")
	_expect(not state.spend_flux(93), "insufficient Flux spend rejects atomically")
	_expect(state.flux_current == 92, "failed spend does not mutate")
	state.spend_flux(2)
	_expect(state.collect_pickup("", &"flux_refill"), "Flux refill is valid")
	_expect(state.flux_current == 100, "Flux refill gives ten")
	state.refill_flux()
	_expect(state.flux_current == 100, "temporary refill adds ten and clamps")
	state.refill_flux(10000)
	_expect(state.flux_current == state.flux_max, "refill clamps to maximum")
	for index in range(Catalog.MAX_FLUX_TANKS):
		_expect(
			state.collect_pickup("flux-tank-%02d" % index, &"flux_tank"),
			"Flux Tank %d collects" % (index + 1)
		)
	_expect(
		state.flux_max == Catalog.MAX_FLUX and state.flux_current == Catalog.MAX_FLUX,
		"Flux caps at 300"
	)
	state.set_active_flux_module(&"flux_shield")
	state.set_flux_enabled(true)
	_expect(state.spend_flux(Catalog.MAX_FLUX), "zeroing Flux succeeds")
	_expect(not state.flux_enabled, "zero Flux disables active module")
	_expect(
		not state.collect_pickup("flux-tank-overflow", &"flux_tank"), "Flux Tank overflow rejects"
	)
	var roundtrip := state.snapshot()
	var restored = GameStateScript.new()
	_expect(restored.restore_snapshot(roundtrip), "v2 Flux snapshot restores")
	_expect(restored.snapshot() == roundtrip, "v2 Flux snapshot roundtrips exactly")
	state.free()
	restored.free()


func _run_save_tests() -> void:
	var root := "/tmp/hollowtide-flux-%d" % Time.get_ticks_usec()
	var dev_state = GameStateScript.new()
	var campaign_state = GameStateScript.new()
	var dev_store = SaveStoreScript.new()
	var campaign_store = SaveStoreScript.new()
	_expect(dev_store.set_test_state(dev_state), "dev test state accepted")
	_expect(campaign_store.set_test_state(campaign_state), "campaign test state accepted")
	_expect(dev_store.configure_test_environment(root, &"dev"), "dev test root accepted")
	_expect(
		campaign_store.configure_test_environment(root, &"campaign"), "campaign test root accepted"
	)
	dev_state.unlock_ability(&"echo_scan")
	dev_state.set_active_flux_module(&"echo_scan")
	dev_state.spend_flux(Catalog.ECHO_SCAN_COST)
	_expect(dev_store.save_game() == OK, "dev Flux save succeeds")
	campaign_state.unlock_ability(&"flux_shield")
	campaign_state.set_active_flux_module(&"flux_shield")
	_expect(campaign_store.save_game() == OK, "campaign Flux save succeeds")
	_expect(
		dev_store.has_save() and campaign_store.has_save(), "dev and campaign saves are separate"
	)
	_expect(
		dev_store.load_game() == OK and dev_state.active_flux_module == &"echo_scan",
		"dev reload stays dev"
	)
	_expect(
		campaign_store.load_game() == OK and campaign_state.active_flux_module == &"flux_shield",
		"campaign reload stays campaign"
	)
	_expect(
		dev_state.active_flux_module != campaign_state.active_flux_module,
		"domains do not cross-restore Flux"
	)

	var target := root.path_join("dev/slot_01.json")
	var before := dev_state.snapshot()
	var corrupt := FileAccess.open(target, FileAccess.WRITE)
	corrupt.store_string("not json")
	corrupt.close()
	_expect(
		dev_store.load_game() == ERR_FILE_CORRUPT,
		"corrupt primary rejects without fallback mutation"
	)
	_expect(dev_state.snapshot() == before, "corrupt primary leaves state unchanged")
	var unknown := FileAccess.open(target, FileAccess.WRITE)
	unknown.store_string(JSON.stringify({"schema_version": 999, "domain": "dev", "snapshot": {}}))
	unknown.close()
	var unknown_text := FileAccess.get_file_as_string(target)
	_expect(dev_store.load_game() == ERR_FILE_UNRECOGNIZED, "future schema rejects")
	_expect(dev_state.snapshot() == before, "future schema leaves state unchanged")
	_expect(
		FileAccess.get_file_as_string(target) == unknown_text, "future schema is not overwritten"
	)

	var legacy_root := root.path_join("legacy")
	var legacy_v1 := _legacy_snapshot()
	for legacy_domain in [&"dev", &"campaign"]:
		var directory := legacy_root.path_join(String(legacy_domain))
		DirAccess.make_dir_recursive_absolute(directory)
		var legacy_file := FileAccess.open(directory.path_join("slot_01.json"), FileAccess.WRITE)
		legacy_file.store_string(
			JSON.stringify(
				{"schema_version": 1, "domain": String(legacy_domain), "snapshot": legacy_v1}
			)
		)
		legacy_file.close()
		var legacy_state = GameStateScript.new()
		var legacy_store = SaveStoreScript.new()
		_expect(legacy_store.set_test_state(legacy_state), "legacy state accepted")
		_expect(
			legacy_store.configure_test_environment(legacy_root, legacy_domain),
			"legacy domain root accepted"
		)
		_expect(legacy_store.load_game() == OK, "v1 %s save migrates" % legacy_domain)
		_expect(
			(
				legacy_state.has_slipstream
				and legacy_state.health == 175
				and legacy_state.world_flags.get("legacy:flag", false)
				and legacy_state.flux_max == 0
				and legacy_state.active_flux_module == &""
			),
			"v1 %s preserves old state and defaults Flux" % legacy_domain
		)
		legacy_state.free()
		legacy_store.free()

	_remove_tree(root)
	dev_store.free()
	campaign_store.free()
	dev_state.free()
	campaign_state.free()


func _legacy_snapshot() -> Dictionary:
	return {
		"version": Catalog.LEGACY_SCHEMA_VERSION,
		"abilities": ["slipstream"],
		"active_beam": "base",
		"energy_tanks": 1,
		"missile_tanks": 0,
		"max_health": 200,
		"health": 175,
		"max_missiles": 0,
		"missile_count": 0,
		"collected_ids": ["legacy:slip"],
		"world_flags": {"legacy:flag": true},
		"discovered_rooms": ["legacy_room"],
		"checkpoint": {"room": "legacy_room", "x": 12.0, "y": 24.0},
	}


func _remove_tree(path: String) -> void:
	for domain in [&"dev", &"campaign"]:
		var directory := path.path_join(String(domain))
		for file_name in ["slot_01.json", "slot_01.json.bak", "slot_01.json.tmp"]:
			DirAccess.remove_absolute(directory.path_join(file_name))
		DirAccess.remove_absolute(directory)
	var legacy_root := path.path_join("legacy")
	for domain in [&"dev", &"campaign"]:
		DirAccess.remove_absolute(legacy_root.path_join(String(domain)).path_join("slot_01.json"))
		DirAccess.remove_absolute(legacy_root.path_join(String(domain)))
	DirAccess.remove_absolute(legacy_root)
	DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
