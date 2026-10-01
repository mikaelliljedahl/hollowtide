extends Node
## Boss room cases of the playtest agent (docs/features/playtest-agent.md, "Harness round 8"), in
## the real campaign rooms with the minimum route kit and the boss's attacks held, so only its
## body and her moves decide a case.
## Tidal Heart: in r7-min-s1h 26 of its 42 hits (260 of 412 damage) were body contact while the
## approach climbed from the floor under it to the nearest Echo spot, the ledge end east of the
## grate. The Heart cannot pass its grate, so the ledge west of it is out of its reach: the state
## names a spot there, the approach walks under the ledge and climbs at its far end, and the Echo
## from there opens the shell, with no contact on the way.
## Stone Guardian: in r7-min-s1i the approach's firing step lay in the vaults_03 west alcove, under
## a roof too low to stand, so she rolled to and fro there curled through five stage 4 punish
## windows and fired nothing. The approach now stops where she can stand.

const Actions = preload("res://tools/playtest_actions.gd")
const Boss = preload("res://tools/playtest_boss.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const State = preload("res://tools/playtest_state.gd")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const CAMPAIGN_SCENE := preload("res://scenes/campaign/campaign.tscn")
const KIT: Array[StringName] = [
	&"beam",
	&"slipstream",
	&"bombs",
	&"ice_beam",
	&"high_jump",
	&"pressure_seal",
	&"wave_beam",
	&"undertow_dash",
	&"missiles",
]
## The r7-min-s1h climb start (room-local feet) and the time the approach gets.
const START := Vector2(2084, 960)
const LIMIT_FRAMES := 1500
## r7-min-s1i: curled in the vaults_03 west alcove (room-local feet), whose roof ends at x 256.
const ALCOVE := Vector2(116, 960)
const ALCOVE_ROOF_END := 256.0
## Where its pursuit stops short of that roof (body centre, room-local).
const GUARDIAN_STOP := Vector2(476, 868)
const ALCOVE_FRAMES := 240
const POCKET_FRAMES := 180

var _failures: Array[String] = []
var _root: Node
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	for id in KIT:
		GameState.unlock_ability(id)
	GameState.collect_pickup("round8.heart_quiver", &"missile_tank")
	GameState.set_active_beam(&"wave")
	GameState.reset_health()
	GameState.set_checkpoint(Rooms.START_ROOM, Rooms.START_POSITION)
	_root = CAMPAIGN_SCENE.instantiate()
	add_child(_root)
	await _frames(20)
	_player = _root.get("player") as Player
	_root.call("teleport", "depths_02", START)
	await _frames(60)
	var boss := get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	_check(boss != null, "the depths_02 Tidal Heart spawned")
	if boss != null:
		await _test_heart_spot(boss)
	_root.call("teleport", "vaults_03", Vector2(ALCOVE_ROOF_END + 96.0, ALCOVE.y))
	await _frames(60)
	boss = get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	_check(boss != null, "the vaults_03 Stone Guardian spawned")
	if boss != null:
		await _test_guardian_alcove(boss)
	for failure in _failures:
		print("FAIL ", failure)
	print("playtest-boss-rooms: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _test_heart_spot(boss: Node2D) -> void:
	boss.call(&"set_test_stage", 3)
	await _frames(2)
	var grate := Boss.grate_of(boss)
	var opener: Dictionary = _boss_entry(_state()).get("opener", {})
	var spot: Array = opener.get("spot_rel", [])
	_check(
		spot.size() == 2 and _player.global_position.x + float(spot[0]) < grate.global_position.x,
		(
			"the firing spot lies past the grate from the Heart (%s, grate x %d)"
			% [opener, roundi(grate.global_position.x - _player.global_position.x)]
		)
	)
	var driver := Programs.Driver.new()
	var hits := 0
	var health := GameState.health
	var fired := false
	var opened := false
	for _frame in LIMIT_FRAMES:
		boss.set("_attack_timer", 99.0)
		if driver.done():
			driver.release_all()
			if fired:
				break
			var entry := _pick(_state())
			if entry.is_empty():
				break
			fired = String(entry["kind"]) == "open_boss"
			driver.start(entry["program"])
		driver.step()
		await get_tree().physics_frame
		opened = opened or boss.get("_branch_open") == true
		if GameState.health < health:
			hits += 1
		health = GameState.health
	driver.release_all()
	for _frame in 40:
		await get_tree().physics_frame
		opened = opened or boss.get("_branch_open") == true
	_check(fired, "the approach reaches a spot the Echo is offered from")
	_check(hits == 0, "no contact on the way (%d hits)" % hits)
	_check(opened, "the Echo from that spot opens the shell")


func _test_guardian_alcove(boss: Node2D) -> void:
	boss.call(&"set_test_stage", 4)
	boss.set("_attack_timer", 99.0)
	Input.action_press(&"slipstream")
	await _held(boss, 2)
	Input.action_release(&"slipstream")
	await _held(boss, 20)
	var room := _root.get("current_room") as Node2D
	_player.global_position = room.global_position + ALCOVE
	boss.global_position = room.global_position + GUARDIAN_STOP
	await _held(boss, 10)
	_check(_player.is_ball, "she is curled in the west alcove for the case")
	GameState.reset_health()
	var driver := Programs.Driver.new()
	var hits := 0
	var health := GameState.health
	for _frame in ALCOVE_FRAMES:
		boss.set("_attack_timer", 99.0)
		if driver.done():
			driver.release_all()
			var approach := {}
			for entry: Dictionary in Actions.candidates(_state(), _player):
				if String(entry["kind"]) == "approach":
					approach = entry
					break
			if approach.is_empty():
				break
			# As the loop does (tools/playtest_loop.gd): a curled player stands up first.
			if _player.is_ball:
				driver.start(Programs.StandFirst.new(approach["program"]))
			else:
				driver.start(approach["program"])
		driver.step()
		await get_tree().physics_frame
		if GameState.health < health:
			hits += 1
		health = GameState.health
	driver.release_all()
	var x := _player.global_position.x - room.global_position.x
	_check(
		x - PlayerConfig.STANDING_WIDTH * 0.5 >= ALCOVE_ROOF_END,
		"the approach leaves the alcove for room to stand (feet x %d)" % roundi(x)
	)
	_check(
		x < boss.global_position.x - room.global_position.x,
		(
			"she stays on her side of the Guardian (%d)"
			% roundi(boss.global_position.x - room.global_position.x)
		)
	)
	_check(hits == 0, "no contact on the way out (%d hits)" % hits)
	await _test_pocket_cache(boss, room)


## Game layout: standing and jumping in place on the west pocket's Quiver Cache with the Guardian
## at its pursuit stop must not touch it. At cell (5, 14) her body reached 16 px into its contact area: all three
## round 7 minimum-kit and full runs took 2 contact hits (48 of 100 health) on that cell.
func _test_pocket_cache(boss: Node2D, room: Node2D) -> void:
	var cache_x := INF
	for refill: Vector2 in Rooms.ROOMS["vaults_03"]["refills"]:
		cache_x = minf(cache_x, refill.x)
	GameState.reset_health()
	var health := GameState.health
	_player.global_position = room.global_position + Vector2(cache_x, ALCOVE.y)
	boss.global_position = room.global_position + GUARDIAN_STOP
	await _held(boss, POCKET_FRAMES)
	# Jumping in place on the cache refills (boss-rework.md, section 5).
	GameState.missile_count = 0
	Input.action_press(&"jump")
	await _held(boss, 12)
	Input.action_release(&"jump")
	await _held(boss, POCKET_FRAMES)
	_check(not _player.is_ball, "she stands on the pocket cache")
	_check(
		GameState.health == health,
		(
			"standing on the pocket cache (x %d) with the Guardian stopped at x %d is not contact"
			% [roundi(cache_x), roundi(boss.global_position.x - room.global_position.x)]
		)
	)
	_check(GameState.missile_count > 0, "the pocket cache refills her Harpoons")


## The Echo once offered, else the approach to the Heart.
func _pick(state: Dictionary) -> Dictionary:
	var approach := {}
	for entry: Dictionary in Actions.candidates(state, _player):
		if String(entry["kind"]) == "open_boss":
			return entry
		if String(entry["kind"]) == "approach" and approach.is_empty():
			approach = entry
	return approach


func _boss_entry(state: Dictionary) -> Dictionary:
	for enemy: Dictionary in state["enemies"]:
		if enemy["is_boss"]:
			return enemy
	return {}


func _state() -> Dictionary:
	return State.new().snapshot(_root, _player, 1, 0.0)


func _check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


## `count` physics frames with the boss's next attack held off.
func _held(boss: Node2D, count: int) -> void:
	for _index in count:
		boss.set("_attack_timer", 99.0)
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame
