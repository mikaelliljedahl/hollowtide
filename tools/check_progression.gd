extends SceneTree

const GameStateScript = preload("res://scripts/autoload/game_state.gd")
const SaveStoreScript = preload("res://scripts/save/save_store.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run_state_tests()
	_run_flux_tests()
	_run_save_tests()
	if _failures.is_empty():
		print("check_progression: PASS")
		await TestShutdown.finish(self, 0)
	else:
		for failure in _failures:
			push_error(failure)
		await TestShutdown.finish(self, 1)


func _run_state_tests() -> void:
	_expect(Catalog.ABILITY_IDS.size() == 13, "catalog has all runtime abilities")
	_expect(
		Catalog.ENEMY_IDS.size() == 13 and Catalog.BOSS_IDS.size() == 3,
		"catalog has enemy and boss rosters"
	)
	_expect(
		Catalog.ENERGY_CONTENT_IDS.size() == 6 and Catalog.MISSILE_CONTENT_IDS.size() == 12,
		"catalog has all tank IDs"
	)
	_expect(load("res://scenes/pickups/pickup.tscn") != null, "generic pickup scene parses")
	_expect(load("res://scenes/pickups/orb.tscn") != null, "legacy orb pickup scene parses")
	_expect(
		load("res://scenes/pickups/weapon_pickup.tscn") != null, "legacy weapon pickup scene parses"
	)
	var state = GameStateScript.new()
	state.reset_progress()
	var before: Dictionary = state.snapshot()
	var invalid := before.duplicate(true)
	invalid["active_beam"] = "ice"
	_expect(not state.restore_snapshot(invalid), "invalid snapshot rejected")
	_expect(state.snapshot() == before, "invalid snapshot leaves state unchanged")

	_expect(state.collect_pickup("orb-01", &"slipstream"), "slip pickup applies")
	var after_slip := state.snapshot()
	_expect(not state.collect_pickup("orb-01", &"slipstream"), "duplicate pickup rejected")
	_expect(state.snapshot() == after_slip, "duplicate pickup has no mutation")
	_expect(state.collect_pickup("energy-01", &"energy_tank"), "energy tank applies")
	_expect(
		state.max_health == 200 and state.health == 200, "energy tank raises and fills capacity"
	)
	state.apply_damage(50)
	_expect(state.collect_pickup("energy-refill", &"energy_refill"), "energy refill applies")
	_expect(
		state.max_health == 200 and state.health == 175,
		"energy refill adds exactly 25, not full heal or capacity"
	)

	_expect(state.collect_pickup("missile-01", &"missile_tank"), "first missile tank applies")
	_expect(
		state.has_missiles and state.max_missiles == 5 and state.missile_count == 5,
		"first missiles have capacity and ammo"
	)
	_expect(state.spend_missile(), "missile spend applies")
	state.refill_missiles(2)
	_expect(
		state.missile_count == 5 and state.max_missiles == 5,
		"missile refill clamps without changing capacity"
	)
	_expect(
		state.collect_pickup("missile-refill", &"missile_refill"), "missile refill pickup applies"
	)
	_expect(state.missile_count == 5, "full missile refill clamps")

	_expect(state.unlock_ability(&"beam"), "base beam unlocks")
	for ability in [&"long_beam", &"ice_beam", &"wave_beam"]:
		_expect(state.unlock_ability(ability), "%s unlocks" % ability)
	for beam in [&"base", &"ice", &"wave"]:
		_expect(state.set_active_beam(beam), "%s beam selection works" % beam)
	_expect(state.unlock_ability(&"bombs"), "bombs require and use slip")
	_expect(not state.set_active_beam(&"missing"), "unknown beam rejected")
	_expect(
		state.snapshot()["version"] == Catalog.SCHEMA_VERSION, "snapshot uses durable schema v2"
	)

	state.reset_progress()
	for index in range(7):
		var accepted := state.collect_pickup("energy-%02d" % index, &"energy_tank")
		_expect(accepted == (index < 6), "energy capacity cap at six")
	for index in range(12):
		_expect(
			state.collect_pickup("missile-%02d" % index, &"missile_tank"),
			"missile tank %d applies" % index
		)
	_expect(state.max_health == 700 and state.max_missiles == 60, "tank caps are exact")
	_expect(
		not state.collect_pickup("missile-over-cap", &"missile_tank"),
		"missile capacity cap at twelve"
	)

	state.reset_progress()
	_expect(
		state.set_checkpoint("nexus_01", Vector2(12.0, 24.0)),
		"checkpoint accepts finite coordinates"
	)
	var checkpoint_snapshot: Dictionary = state.snapshot()
	var bad_checkpoint := checkpoint_snapshot.duplicate(true)
	bad_checkpoint["checkpoint"]["x"] = INF
	_expect(not state.restore_snapshot(bad_checkpoint), "non-finite checkpoint rejected")
	_expect(state.snapshot() == checkpoint_snapshot, "invalid checkpoint leaves state unchanged")
	state.free()


func _run_flux_tests() -> void:
	var state = GameStateScript.new()
	state.reset_progress()
	_expect(
		state.flux_max == 0 and state.flux_current == 0 and state.active_flux_module == &"",
		"old clean state has no latent usable Flux"
	)
	_expect(not state.spend_flux(1), "Flux cannot spend before first system")
	_expect(state.unlock_ability(&"flux_shield"), "first Flux system unlocks")
	_expect(
		state.flux_max == Catalog.FLUX_BASE_MAX and state.flux_current == Catalog.FLUX_BASE_MAX,
		"first Flux system initializes full base capacity"
	)
	_expect(state.set_active_flux_module(&"flux_shield"), "owned Flux module activates")
	_expect(state.set_flux_enabled(true), "active Flux module enables")
	_expect(
		not state.set_active_flux_module(&"echo_scan"), "unowned Flux switch rejects atomically"
	)
	_expect(
		state.active_flux_module == &"flux_shield" and state.flux_enabled,
		"failed Flux switch leaves active state unchanged"
	)
	_expect(state.collect_pickup("flux-tank-01", &"flux_tank"), "Flux Tank collects")
	_expect(
		state.flux_tanks == 1 and state.flux_max == 150 and state.flux_current == 150,
		"Flux Tank adds fifty and refills"
	)
	_expect(not state.collect_pickup("flux-tank-01", &"flux_tank"), "duplicate Flux Tank rejects")
	_expect(state.spend_flux(20), "exact Flux spend succeeds")
	_expect(state.flux_current == 130, "Flux spend is exact")
	state.refill_flux()
	_expect(state.flux_current == 140, "temporary Flux refill adds ten")
	state.refill_flux(1000)
	_expect(state.flux_current == state.flux_max, "Flux refill clamps")
	state.reset_progress()
	var clean := state.snapshot()
	var v1 := clean.duplicate(true)
	v1.erase("flux_current")
	v1.erase("flux_max")
	v1.erase("flux_tanks")
	v1.erase("active_flux_module")
	v1.erase("flux_enabled")
	v1["version"] = Catalog.LEGACY_SCHEMA_VERSION
	_expect(state.restore_snapshot(v1), "v1 snapshot migrates explicitly")
	_expect(state.snapshot()["version"] == Catalog.SCHEMA_VERSION, "migration produces v2 state")
	_expect(
		state.flux_max == 0 and state.active_flux_module == &"",
		"v1 migration defaults Flux inactive and unusable"
	)
	var before := state.snapshot()
	var unknown := before.duplicate(true)
	unknown["future_field"] = true
	_expect(not state.restore_snapshot(unknown), "unknown v2 field rejects")
	_expect(state.snapshot() == before, "unknown state leaves no mutation")
	state.free()


func _run_save_tests() -> void:
	var root := "/tmp/hollowtide-progression-%d" % Time.get_ticks_usec()
	var state = GameStateScript.new()
	var store = SaveStoreScript.new()
	_expect(store.set_test_state(state), "test state injection accepted in debug test context")
	_expect(store.configure_test_environment(root, &"dev"), "isolated dev save root accepted")
	state.reset_progress()
	state.discover_room("fringe_01")
	_expect(
		state.set_checkpoint("fringe_01", Vector2(128.0, 256.0)),
		"checkpoint mutator accepts safe position"
	)
	_expect(store.save_game() == OK, "dev save succeeds")
	state.reset_progress()
	_expect(
		store.load_game() == OK and state.checkpoint["room"] == "fringe_01",
		"checkpoint survives save and load"
	)
	var dev_state := state.snapshot()

	var campaign_state = GameStateScript.new()
	var campaign_store = SaveStoreScript.new()
	_expect(campaign_store.set_test_state(campaign_state), "campaign test state injection accepted")
	_expect(
		campaign_store.configure_test_environment(root, &"campaign"),
		"isolated campaign domain accepted"
	)
	campaign_state.collect_pickup("campaign-orb", &"slipstream")
	_expect(campaign_store.save_game() == OK, "campaign save succeeds")
	_expect(store.has_save() and campaign_store.has_save(), "domains have independent saves")
	_expect(dev_state == state.snapshot(), "campaign save does not mutate dev state")

	state.collect_pickup("dev-energy", &"energy_tank")
	_expect(store.save_game() == OK, "second save creates backup")
	var target := root.path_join("dev/slot_01.json")
	var backup := root.path_join("dev/slot_01.json.bak")
	_expect(FileAccess.file_exists(backup), "valid backup exists")
	var changed_state := state.snapshot()
	var corrupt_file := FileAccess.open(target, FileAccess.WRITE)
	corrupt_file.store_string("not json")
	corrupt_file.close()
	_expect(store.save_game() == ERR_FILE_CORRUPT, "save refuses corrupt primary")
	state.reset_progress()
	_expect(store.load_game() == OK, "corrupt primary loads valid same-domain backup")
	_expect(
		state.snapshot() != changed_state and state.has_slipstream == false,
		"backup restore does not use corrupted primary"
	)

	_expect(store.save_game() == OK, "saving works after backup recovery")
	var archived_corrupt := false
	for file_name in DirAccess.get_files_at(root.path_join("dev")):
		if file_name.begins_with("slot_01.corrupt."):
			archived_corrupt = true
			_expect(
				(
					FileAccess.get_file_as_string(root.path_join("dev").path_join(file_name))
					== "not json"
				),
				"corrupt original preserved"
			)
			DirAccess.remove_absolute(root.path_join("dev").path_join(file_name))
	_expect(archived_corrupt, "backup recovery archives rather than destroys corrupt original")

	var unknown_file := FileAccess.open(target, FileAccess.WRITE)
	unknown_file.store_string(
		JSON.stringify({"schema_version": 999, "domain": "dev", "snapshot": {}})
	)
	unknown_file.close()
	var unknown_target := FileAccess.get_file_as_string(target)
	state.reset_progress()
	_expect(store.save_game() == ERR_FILE_UNRECOGNIZED, "save refuses unknown schema")
	_expect(
		FileAccess.get_file_as_string(target) == unknown_target, "unknown schema remains untouched"
	)
	_expect(store.load_game() == ERR_FILE_UNRECOGNIZED, "unknown schema rejected")
	_expect(state.has_slipstream == false, "unknown schema leaves state unchanged")

	var mismatch_file := FileAccess.open(target, FileAccess.WRITE)
	mismatch_file.store_string(
		JSON.stringify({"schema_version": 1, "domain": "campaign", "snapshot": {}})
	)
	mismatch_file.close()
	_expect(store.load_game() == ERR_INVALID_DATA, "domain mismatch rejected")
	_expect(state.has_slipstream == false, "domain mismatch leaves state unchanged")

	# A well-formed save from before an id rename fails validation; it must not block new saves.
	state.reset_progress()
	var stale_snapshot := state.snapshot()
	stale_snapshot["abilities"] = ["retired_ability"]
	var stale_file := FileAccess.open(target, FileAccess.WRITE)
	stale_file.store_string(
		JSON.stringify(
			{"schema_version": Catalog.SCHEMA_VERSION, "domain": "dev", "snapshot": stale_snapshot}
		)
	)
	stale_file.close()
	state.collect_pickup("dev-after-rename", &"slipstream")
	_expect(store.save_game() == OK, "stale save does not block new progress")
	_expect(store.load_game() == OK and state.has_slipstream, "new save replaces the stale slot")
	var archived_stale := false
	for file_name in DirAccess.get_files_at(root.path_join("dev")):
		if file_name.begins_with("slot_01.stale."):
			archived_stale = true
			DirAccess.remove_absolute(root.path_join("dev").path_join(file_name))
	_expect(archived_stale, "stale save is archived, not destroyed")

	DirAccess.remove_absolute(root.path_join("dev/slot_01.json"))
	DirAccess.remove_absolute(root.path_join("dev/slot_01.json.bak"))
	DirAccess.remove_absolute(root.path_join("dev/slot_01.json.tmp"))
	DirAccess.remove_absolute(root.path_join("campaign/slot_01.json"))
	DirAccess.remove_absolute(root.path_join("campaign/slot_01.json.bak"))
	DirAccess.remove_absolute(root.path_join("campaign/slot_01.json.tmp"))
	DirAccess.remove_absolute(root.path_join("dev"))
	DirAccess.remove_absolute(root.path_join("campaign"))
	DirAccess.remove_absolute(root)
	store.free()
	campaign_store.free()
	state.free()
	campaign_state.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
