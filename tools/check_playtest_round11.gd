extends RefCounted
## Round 11 cases of the playtest agent (docs/features/playtest-agent.md, "Harness round 11"), run
## by tools/check_playtest_boss_rooms.gd in the real campaign rooms with the kit the route brings
## there (no Updraft Cloak).
## kiln_02: r8-full-s2 spent 150 s at cells 13 to 17, 31 switching between `go_to_ambush` and
## `go_to_objective`. Each `go_to_ambush` now walks to the trigger's floor until the arena seals,
## so one pick between two route steps starts the fight.
## kiln_03: the round 8 Cinder Warden death came from a `go_to_refill` run past the boss outside
## any attack. The jump over the patrolling Warden now waits for an arc its predicted path clears.
## depths_02: the minimum-kit runs lost a Tidal Heart attempt to stage 4's Crosscurrent then Surge
## Lance. The lanes of the first link still fly through the Lance and after it; the loop now sees
## them and answers them on the way off the Lance's line (the old loop was hit at columns 36 and
## 37; the cases run in this order, each from where the last left the Heart).

const Actions = preload("res://tools/playtest_actions.gd")
const Loop = preload("res://tools/playtest_loop.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const State = preload("res://tools/playtest_state.gd")
const TILE := 64.0
const KIT: Array[StringName] = [&"beam", &"slipstream", &"bombs", &"missiles", &"pressure_seal"]
## kiln_02 floor cells west of the antechamber trigger (columns 18 to 25) and of the rock block
## over columns 16 to 20.
const KILN_CELLS := [Vector2i(13, 31), Vector2i(15, 31)]
## Picks of `go_to_ambush`, each followed by the route's pull back west for ROUTE_FRAMES.
const AMBUSH_PICKS := 4
const ROUTE_FRAMES := 30
const PROGRAM_LIMIT := 400
## kiln_03 floor columns west of the Warden and the stages tried; the run's frame budget, and how
## close (px) to the boss's centre a hit counts as its body (the trip's lava pit lies far east).
const WARDEN_COLUMNS := [12, 24, 27]
const WARDEN_STAGES := [1, 4]
const REFILL_FRAMES := 600
const BODY_HIT := 220.0
## The Heart's kit adds these; floor columns of depths_02 (feet on row 14) and the frame cap.
const HEART_KIT: Array[StringName] = [&"wave_beam", &"ice_beam", &"undertow_dash"]
const HEART_COLUMNS := [8, 10, 12, 14, 16, 31, 34, 35, 36, 37, 38]
const HEART_FRAMES := 360

var _host: Node
var _root: Node
var _player: Player


func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	GameState.reset_progress()
	for id in KIT:
		GameState.unlock_ability(id)
	GameState.collect_pickup("round11.quiver", &"missile_tank")
	for cell: Vector2i in KILN_CELLS:
		await _test_ambush_picks(cell)
	for stage: int in WARDEN_STAGES:
		for column: int in WARDEN_COLUMNS:
			await _test_refill_past_warden(stage, column)
	for id in HEART_KIT:
		GameState.unlock_ability(id)
	for column: int in HEART_COLUMNS:
		await _test_heart_chain(column)
	await _test_heart_refill()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _test_ambush_picks(cell: Vector2i) -> void:
	_root.call("teleport", "kiln_02", Vector2((cell.x + 0.5) * TILE, (cell.y + 1) * TILE))
	await _frames(60)
	var arena := _player.get_tree().get_first_node_in_group(&"worldfx_ambush") as AmbushArena
	if arena == null:
		_check(false, "the kiln_02 antechamber arena exists")
		return
	arena.rearm()
	var route := [{"key": "go_to_objective", "kind": "go_to_objective", "label": "", "program": []}]
	var driver := Programs.Driver.new()
	var picks := 0
	for _pick in AMBUSH_PICKS:
		var state := State.new().snapshot(_root, _player, 1, 0.0)
		var offered: Array = Actions.candidates(state, _player, route).filter(
			func(entry: Dictionary) -> bool: return entry["kind"] == "go_to_ambush"
		)
		if offered.is_empty() or arena.state != AmbushArena.State.ARMED:
			break
		picks += 1
		driver.start(offered[0]["program"])
		for _frame in PROGRAM_LIMIT:
			if driver.done():
				break
			driver.step()
			await _player.get_tree().physics_frame
		driver.start(Programs.walk(-1, ROUTE_FRAMES))
		while not driver.done() and arena.state == AmbushArena.State.ARMED:
			driver.step()
			await _player.get_tree().physics_frame
	driver.release_all()
	_check(
		arena.state != AmbushArena.State.ARMED,
		"kiln_02 %s: go_to_ambush between route steps seals the arena (%d picks)" % [cell, picks]
	)
	arena.rearm()
	await _frames(10)


func _test_refill_past_warden(stage: int, column: int) -> void:
	GameState.reset_health()
	_root.call("teleport", "kiln_03", Vector2((column + 0.5) * TILE, 15 * TILE))
	await _frames(30)
	var boss := _player.get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	if boss == null:
		_check(false, "the kiln_03 Cinder Warden spawned")
		return
	boss.call(&"set_test_stage", stage)
	while GameState.spend_missile():
		pass
	var driver := Programs.Driver.new()
	var contact := 0
	var health := GameState.health
	var refilled := false
	for _frame in REFILL_FRAMES:
		if boss.get("_attack_state") == &"idle":
			boss.set("_attack_timer", 99.0)
		if driver.done():
			driver.release_all()
			if GameState.missile_count > 0:
				refilled = true
				break
			var state := State.new().snapshot(_root, _player, 1, 0.0)
			var runs: Array = Actions.candidates(state, _player).filter(
				func(entry: Dictionary) -> bool: return entry["kind"] == "go_to_refill"
			)
			driver.start(runs[0]["program"] if not runs.is_empty() else Programs.idle())
		driver.step()
		await _player.get_tree().physics_frame
		if (
			GameState.health < health
			and _player.global_position.distance_to(boss.global_position) < BODY_HIT
		):
			contact += 1
		health = GameState.health
	driver.release_all()
	var label := "kiln_03 stage %d from column %d" % [stage, column]
	_check(contact == 0, "%s: the refill run past the Warden meets no body (%d)" % [label, contact])
	_check(refilled, "%s: the refill run reaches the quiver refill" % label)


func _test_heart_chain(column: int) -> void:
	if String(_root.get("current_room_id")) != "depths_02":
		_root.call("teleport", "depths_02", Vector2(26.5 * TILE, 15 * TILE))
		await _frames(60)
	var boss := _player.get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	if boss == null:
		_check(false, "the depths_02 Tidal Heart spawned")
		return
	var home: Vector2 = boss.get("_home_position")
	var room := _root.get("current_room") as Node2D
	boss.set("health", boss.get("max_health"))
	boss.call(&"set_test_stage", 4)
	_player.global_position = room.global_position + Vector2((column + 0.5) * TILE, 15 * TILE)
	_player.velocity = Vector2.ZERO
	for _frame in 40:
		boss.global_position = home
		boss.set("_attack_timer", 99.0)
		await _player.get_tree().physics_frame
	for shot in _player.get_tree().get_nodes_in_group(&"enemy_shot"):
		shot.queue_free()
	GameState.reset_health()
	var health := GameState.health
	var chain: Array[StringName] = [&"crosscurrent", &"surge_lance"]
	boss.set("_attack_chain", chain)
	boss.call(&"_start_telegraph")
	var loop := Loop.new(_root, _player, "heuristic", 1, [])
	for _frame in HEART_FRAMES:
		loop.physics_step(1.0 / 60.0)
		await _player.get_tree().physics_frame
		var lance_over: bool = (
			boss.get("_attack_id") == &"surge_lance" and boss.get("_attack_state") == &"idle"
		)
		if lance_over and _player.get_tree().get_nodes_in_group(&"enemy_shot").is_empty():
			break
		if boss.get("_attack_id") not in [&"crosscurrent", &"surge_lance"]:
			break
	loop.finish({})
	_check(
		GameState.health == health,
		(
			"depths_02 column %d: stage 4 Crosscurrent then Surge Lance costs nothing (%d)"
			% [column, health - GameState.health]
		)
	)


## r11-min-s1: at 25 health in stage 4 the Heart chains attacks back to back, and with no refill
## run during a telegraph she stood 500 s on an empty quiver. A line attack leaves it to the dodge.
func _test_heart_refill() -> void:
	var boss := _player.get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	if boss == null:
		return
	var room := _root.get("current_room") as Node2D
	_player.global_position = room.global_position + Vector2(14.5 * TILE, 15 * TILE)
	_player.velocity = Vector2.ZERO
	await _frames(20)
	while GameState.spend_missile():
		pass
	var chain: Array[StringName] = [&"crosscurrent"]
	boss.set("_attack_chain", chain)
	boss.call(&"_start_telegraph")
	await _frames(2)
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	var kinds: Array = Actions.candidates(state, _player).map(
		func(entry: Dictionary) -> String: return entry["kind"]
	)
	_check(
		kinds.has("go_to_refill"),
		"an empty quiver in a Tidal Heart telegraph offers the refill run (%s)" % [kinds]
	)


func _frames(count: int) -> void:
	for _index in count:
		await _player.get_tree().physics_frame
