extends Node

## Post-ending Trials (docs/features/trials.md): hidden before the ending, gauntlet waves run in
## order and clear, the boss rush chains three bosses with a refill, results are recorded, the best
## time is kept only when better, the save round-trips and old saves still load.
## godot --headless --path . res://tools/check_trials.tscn -- --test-mode

const START_MENU := preload("res://scenes/ui/start_menu.tscn")
const TRIALS_SCENE := preload("res://scenes/trials/trials.tscn")
const TestShutdown = preload("res://tools/test_shutdown.gd")
const Assist = preload("res://scripts/progression/assist.gd")
const KILL_KINDS: Array[StringName] = [&"missile", &"beam", &"bomb", &"undertow"]

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_record_rules()
	await _hidden_before_ending()
	await _gauntlet_clears_in_order()
	await _gauntlet_death_fails()
	await _boss_rush_chains_three()
	_best_kept_only_when_better()
	_save_round_trip_and_old_saves()
	for failure in _failures:
		print("FAIL ", failure)
	print("trials: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	get_tree().paused = false
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


# --- helpers ---------------------------------------------------------------------------------


func _check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _until(condition: Callable, seconds: float) -> bool:
	for _frame in int(seconds * 60.0):
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _save_path() -> String:
	var root := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test-save-root="):
			root = argument.trim_prefix("--test-save-root=")
	return root.path_join("campaign").path_join("slot_01.json")


func _disk_snapshot() -> Dictionary:
	var file := FileAccess.open(_save_path(), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed["snapshot"] if parsed is Dictionary else {}


func _write_wrapper(snapshot: Dictionary) -> void:
	var wrapper := {
		"schema_version": int(snapshot["version"]), "domain": "campaign", "snapshot": snapshot
	}
	var file := FileAccess.open(_save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(wrapper))
	file.close()


## A campaign save at the depths, optionally past the Tidal Heart.
func _write_campaign_save(finished: bool) -> void:
	GameState.reset_progress()
	for id in [&"beam", &"slipstream", &"ice_beam"]:
		GameState.unlock_ability(id)
	GameState.collect_pickup("fringe_02.quiver", &"missile_tank")
	GameState.set_world_flag("boss:stone_guardian")
	if finished:
		GameState.set_world_flag(TrialCatalog.UNLOCK_FLAG)
	GameState.discover_room("fringe_01")
	GameState.set_checkpoint("depths_02", Vector2(416, 960))
	GameState.health = 60
	_check(SaveStore.save_game() == OK, "campaign save written (finished=%s)" % finished)


func _without_records(snapshot: Dictionary) -> Dictionary:
	var copy := snapshot.duplicate(true)
	copy.erase(TrialRecords.SNAPSHOT_KEY)
	return copy


func _trial() -> TrialsRoot:
	var root := TRIALS_SCENE.instantiate() as TrialsRoot
	add_child(root)
	await _frames(4)
	return root


func _close(root: TrialsRoot) -> void:
	get_tree().paused = false
	root.queue_free()
	for node in get_tree().get_nodes_in_group(&"transient"):
		node.queue_free()
	await _frames(3)


func _kill(enemy: Variant) -> void:
	for kind in KILL_KINDS:
		if not is_instance_valid(enemy) or (enemy as Node).is_queued_for_deletion():
			return
		var health: Variant = enemy.get("health")
		if health is int and int(health) <= 0:
			return
		enemy.call("take_damage", 9999, kind)


func _find_button(node: Node, fragment: String) -> Button:
	if node is Button and (node as Button).text.contains(fragment):
		return node
	for child in node.get_children():
		var found := _find_button(child, fragment)
		if found != null:
			return found
	return null


# --- cases -----------------------------------------------------------------------------------


func _record_rules() -> void:
	print("record rules")
	_check(TrialRecords.format_time(83456) == "1:23.45", "clear time reads m:ss.cc")
	var records := TrialRecords.with_result({}, TrialCatalog.GAUNTLET, 90000, 3)
	_check(records == {"gauntlet": {"time_ms": 90000, "hits": 3}}, "first clear becomes the best")
	var slower := TrialRecords.with_result(records, TrialCatalog.GAUNTLET, 95000, 0)
	_check(slower == records, "a slower clear keeps the best")
	var tie := TrialRecords.with_result(records, TrialCatalog.GAUNTLET, 90000, 0)
	_check(tie == records, "an equal time keeps the best")
	var faster := TrialRecords.with_result(records, TrialCatalog.GAUNTLET, 80000, 5)
	_check(faster["gauntlet"] == {"time_ms": 80000, "hits": 5}, "a faster clear replaces the best")
	_check(TrialRecords.validated({"gauntlet": {"time_ms": 1, "hits": 0}}) != null, "valid records")
	_check(
		TrialRecords.validated({"arena": {"time_ms": 1, "hits": 0}}) == null,
		"unknown mode rejected"
	)
	_check(
		TrialRecords.validated({"gauntlet": {"time_ms": 0, "hits": 0}}) == null,
		"zero time rejected"
	)
	_check(TrialRecords.validated({"gauntlet": {"time_ms": 5}}) == null, "missing hits rejected")
	_check(TrialRecords.validated([]) == null, "non-dictionary rejected")
	var spawns := TrialCatalog.all_spawn_ids()
	var kinds := {}
	for id in spawns:
		kinds[id] = true
	_check(kinds.size() == 12 and not kinds.has("lava_monster"), "gauntlet uses 12 common enemies")
	_check(
		TrialsRoot.gauntlet_spawn_offsets().size() == spawns.size(), "one authored point per spawn"
	)


func _hidden_before_ending() -> void:
	print("hidden before the ending")
	_check(not SaveStore.has_save(), "fresh test root has no save")
	_check(not TrialsEntry.is_unlocked(), "no save: Trials locked")
	var menu := START_MENU.instantiate()
	add_child(menu)
	await _frames(2)
	_check(_find_button(menu, "Trials") == null, "no save: no Trials entry")
	menu.queue_free()
	await _frames(2)
	_write_campaign_save(false)
	_check(not TrialsEntry.is_unlocked(), "unfinished save: Trials locked")
	_check(not TrialsEntry.prepare(TrialCatalog.GAUNTLET), "unfinished save: a trial cannot start")
	menu = START_MENU.instantiate()
	add_child(menu)
	await _frames(2)
	_check(_find_button(menu, "Trials") == null, "unfinished save: no Trials entry")
	menu.queue_free()
	await _frames(2)
	_write_campaign_save(true)
	var before := GameState.snapshot()
	_check(TrialsEntry.is_unlocked(), "finished save: Trials unlocked")
	_check(GameState.snapshot() == before, "checking the unlock leaves GameState untouched")
	menu = START_MENU.instantiate()
	add_child(menu)
	await _frames(2)
	var entry := _find_button(menu, "Trials")
	_check(entry != null, "finished save: the start menu shows Trials")
	if entry != null:
		entry.emit_signal("pressed")
		await _frames(2)
		var panel := menu.get_node_or_null("TrialsMenu") as Control
		_check(panel != null and panel.visible, "Trials opens its menu")
		_check(
			_find_button(menu, "Gauntlet") != null and _find_button(menu, "Boss Rush") != null,
			"both trials are listed"
		)
	menu.queue_free()
	await _frames(2)


func _gauntlet_clears_in_order() -> void:
	print("gauntlet")
	_write_campaign_save(true)
	var campaign := _disk_snapshot()
	_check(TrialsEntry.prepare(TrialCatalog.GAUNTLET), "a finished save starts the gauntlet")
	_check(
		(
			GameState.max_health == 700
			and GameState.max_missiles == 60
			and GameState.has_ability(&"undertow_dash")
		),
		"fixed full kit equipped"
	)
	var root := await _trial()
	var arena := root.arena
	_check(arena != null and root.room.area_id == TrialCatalog.GAUNTLET_AREA, "gauntlet room built")
	await _frames(20)
	_check(arena.state == AmbushArena.State.ARMED, "the arena waits until the player walks in")
	root.player.dev_invulnerable = true
	root.player.global_position = TrialRoomBuilder.feet(root.room, Vector2i(20, 14))
	root.player.velocity = Vector2.ZERO
	_check(
		await _until(func() -> bool: return root.phase == TrialsRoot.Phase.RUNNING, 1.0),
		"sealing starts the clock"
	)
	GameState.apply_damage(5)
	_check(root.hits == 1, "a hit is counted")
	var order: Array[int] = []
	var ids_ok := true
	var elites_ok := true
	for _frame in 60 * 60:
		if arena.state == AmbushArena.State.CLEARED:
			break
		if arena.state == AmbushArena.State.FIGHTING and arena.alive_count() > 0:
			if order.is_empty() or order[-1] != arena.wave_index:
				order.append(arena.wave_index)
				var spawned: Array[String] = []
				var elite_wave := arena.wave_index in TrialCatalog.ELITE_WAVES
				for enemy in arena.enemies:
					if is_instance_valid(enemy) and enemy.get("health") is int and enemy.health > 0:
						spawned.append(String(enemy.get("enemy_id")))
						if EnemyElite.is_elite(enemy) != elite_wave:
							elites_ok = false
							print(
								"  wave %d elite mismatch on %s" % [arena.wave_index, spawned[-1]]
							)
				var wanted: Array[String] = []
				for id in TrialCatalog.WAVES[arena.wave_index] as Array:
					wanted.append(String(id))
				spawned.sort()
				wanted.sort()
				if spawned != wanted:
					ids_ok = false
					print("  wave %d spawned %s, wanted %s" % [arena.wave_index, spawned, wanted])
			for enemy in arena.enemies:
				_kill(enemy)
		await get_tree().physics_frame
	_check(order == [0, 1, 2, 3, 4, 5], "all six waves ran in order (%s)" % [order])
	_check(ids_ok, "every wave spawned exactly its catalog enemies")
	_check(elites_ok, "only the last two waves spawn elites")
	_check(arena.state == AmbushArena.State.CLEARED, "the gauntlet clears")
	var result := root.result
	_check(
		bool(result.get("cleared", false)) and int(result.get("time_ms", 0)) > 0, "clear recorded"
	)
	_check(int(result.get("hits", -1)) == 1, "result carries the hit count")
	_check(bool(result.get("new_best", false)), "first clear is the new best")
	var disk := _disk_snapshot()
	var stored: Dictionary = disk.get(TrialRecords.SNAPSHOT_KEY, {})
	_check(
		stored.get("gauntlet", {}).get("time_ms", -1) == result.get("time_ms"),
		"best time stored in the campaign save"
	)
	_check(_without_records(disk) == campaign, "nothing else in the campaign save changed")
	_check(not GameState.has_world_flag("trials.gauntlet"), "no trial flag reaches the campaign")
	_check(GameState.health == 60 and GameState.max_health == 100, "campaign state restored")
	var shown := await _until(func() -> bool: return root.results_panel.visible, 2.0)
	_check(shown and get_tree().paused, "results panel shown over a paused game")
	var time_label := root.results_panel.find_child("ResultTime", true, false) as Label
	_check(
		(
			time_label != null
			and time_label.text.contains(TrialRecords.format_time(result["time_ms"]))
		),
		"results panel shows the clear time"
	)
	var hits_label := root.results_panel.find_child("ResultHits", true, false) as Label
	_check(hits_label != null and hits_label.text.ends_with("1"), "results panel shows hits taken")
	await _close(root)


func _gauntlet_death_fails() -> void:
	print("gauntlet death")
	_check(TrialsEntry.prepare(TrialCatalog.GAUNTLET), "gauntlet restarts")
	var best: Variant = _disk_snapshot().get(TrialRecords.SNAPSHOT_KEY, {})
	Assist.forced[Assist.SKIP_AMBUSHES] = true
	var root := await _trial()
	root.player.global_position = TrialRoomBuilder.feet(root.room, Vector2i(20, 14))
	_check(
		await _until(func() -> bool: return root.phase == TrialsRoot.Phase.RUNNING, 1.0),
		"the skip-ambushes assist does not skip the gauntlet"
	)
	Assist.forced.erase(Assist.SKIP_AMBUSHES)
	GameState.apply_damage(99999)
	await _until(func() -> bool: return root.phase == TrialsRoot.Phase.DONE, 2.0)
	_check(not bool(root.result.get("cleared", true)), "death ends the run as failed")
	_check(
		_disk_snapshot().get(TrialRecords.SNAPSHOT_KEY, {}) == best, "a failed run saves nothing"
	)
	await _close(root)


func _boss_rush_chains_three() -> void:
	print("boss rush")
	var campaign := _disk_snapshot()
	_check(TrialsEntry.prepare(TrialCatalog.BOSS_RUSH), "a finished save starts the boss rush")
	var root := await _trial()
	root.player.dev_invulnerable = true
	var seen: Array[String] = []
	var areas_ok := true
	var refilled := true
	for index in TrialCatalog.BOSSES.size():
		var boss_id: StringName = TrialCatalog.BOSSES[index]
		var spawned := await _until(
			func() -> bool:
				var boss := root.current_boss()
				return boss != null and root.boss_index == index and boss.get("enemy_id") == boss_id,
			TrialCatalog.BREATHER_SECONDS + 3.0
		)
		if not spawned:
			break
		seen.append(String(boss_id))
		areas_ok = areas_ok and root.room.area_id == TrialCatalog.BOSS_AREAS[boss_id]
		GameState.apply_damage(40)
		var boss := root.current_boss()
		boss.call("_die")
		if index < TrialCatalog.BOSSES.size() - 1:
			await _frames(2)
			refilled = refilled and root.phase == TrialsRoot.Phase.BREATHER
			refilled = refilled and GameState.health == GameState.max_health
	_check(
		seen == ["stone_guardian", "furnace_mother", "tidal_heart"],
		"three bosses in order (%s)" % [seen]
	)
	_check(areas_ok, "each boss fights in its own area art")
	_check(refilled, "a breather with a full refill follows each boss")
	_check(
		await _until(func() -> bool: return root.phase == TrialsRoot.Phase.DONE, 2.0), "rush ends"
	)
	_check(bool(root.result.get("cleared", false)), "the boss rush clears")
	_check(int(root.result.get("hits", 0)) == 3, "hits counted across all three bosses")
	var disk := _disk_snapshot()
	var stored: Dictionary = disk.get(TrialRecords.SNAPSHOT_KEY, {})
	_check(stored.has("boss_rush") and stored.has("gauntlet"), "both bests stored")
	_check(
		_without_records(disk) == _without_records(campaign), "boss flags and checkpoint untouched"
	)
	await _close(root)


func _best_kept_only_when_better() -> void:
	print("best kept only when better")
	TrialsEntry.campaign_snapshot = _disk_snapshot()
	var best := int(_disk_snapshot()[TrialRecords.SNAPSHOT_KEY]["gauntlet"]["time_ms"])
	var slower := TrialsEntry.record(TrialCatalog.GAUNTLET, best + 1000, 0)
	_check(not bool(slower["new_best"]), "a slower clear is not a new best")
	_check(slower["previous"]["time_ms"] == best, "the previous best is reported")
	_check(_disk_snapshot()[TrialRecords.SNAPSHOT_KEY]["gauntlet"]["time_ms"] == best, "best kept")
	var faster := TrialsEntry.record(TrialCatalog.GAUNTLET, best - 1, 9)
	_check(bool(faster["new_best"]) and faster["saved"] == OK, "a faster clear is saved")
	var stored: Dictionary = _disk_snapshot()[TrialRecords.SNAPSHOT_KEY]["gauntlet"]
	_check(
		int(stored["time_ms"]) == best - 1 and int(stored["hits"]) == 9,
		"the faster time and its hits replace the best"
	)


func _save_round_trip_and_old_saves() -> void:
	print("save round trip and old saves")
	_check(SaveStore.load_game() == OK, "save with trial bests loads")
	var records := GameState.trial_bests.duplicate(true)
	_check(records.has("gauntlet") and records.has("boss_rush"), "trial bests restored from disk")
	_check(SaveStore.save_game() == OK and SaveStore.load_game() == OK, "save/load round trip")
	_check(GameState.trial_bests == records, "trial bests survive the round trip")
	var old := _without_records(_disk_snapshot())
	_write_wrapper(old)
	_check(SaveStore.load_game() == OK, "a v2 save without trial bests loads")
	_check(GameState.trial_bests.is_empty(), "no bests after loading an old save")
	_check(not GameState.snapshot().has(TrialRecords.SNAPSHOT_KEY), "empty bests are not written")
	var legacy := old.duplicate(true)
	legacy["version"] = 1
	for key in ["flux_current", "flux_max", "flux_tanks", "active_flux_module", "flux_enabled"]:
		legacy.erase(key)
	_write_wrapper(legacy)
	_check(SaveStore.load_game() == OK, "a v1 save still loads")
	var broken := old.duplicate(true)
	broken[TrialRecords.SNAPSHOT_KEY] = {"gauntlet": {"time_ms": -4, "hits": 0}}
	_check(not GameState.validate_snapshot(broken), "invalid trial bests are rejected")
	var unknown := old.duplicate(true)
	unknown["trial_extras"] = {}
	_check(not GameState.validate_snapshot(unknown), "other unknown keys are still rejected")
