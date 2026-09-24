extends Node

## Ambush arena rules (docs/features/ambush-arenas.md): kit filter, authored-point spawns, waves
## with telegraphs and breathers, death/leave/stall aborts, the clear reward and the campaign
## placement in fringe_03. Testbed cases use a small real room with the real player.
## godot --headless --path . res://tools/check_ambush_rules.tscn -- --test-mode

const Testbed = preload("res://tools/worldfx_testbed.gd")
const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0
const FLAG := "fringe_03.ambush.beam_trial"
const CENTRE := Vector2(15 * TILE, 8 * TILE)

var _failures: Array[String] = []
var _room: CampaignRoom
var _player: Player
var _telegraphs: Array[Vector2] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--dev-mode" in OS.get_cmdline_user_args():
		await _dev_s3()
		await _finish()
		return
	_rules()
	await _waves_and_reward()
	await _class_relocation()
	await _kit_filter()
	await _death_abort()
	await _leave_abort()
	await _stall_abort()
	await _teardown()
	await _campaign_fringe_03()
	await _finish()


func _finish() -> void:
	for failure in _failures:
		print("FAIL ", failure)
	print("ambush-rules: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	_silence_world_audio()
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


# --- helpers ---------------------------------------------------------------------------------


func _check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _seconds(value: float) -> void:
	await _frames(int(ceil(value * 60.0)))


func _until(condition: Callable, seconds: float) -> bool:
	for _frame in int(seconds * 60.0):
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


## Stops every positional world sound and drops its stream so no playback outlives the mixer.
func _silence_world_audio() -> void:
	for node in get_tree().root.find_children("*", "AudioStreamPlayer2D", true, false):
		node.stop()
		node.stream = null
		if node.get_parent() == get_tree().root:
			node.queue_free()


func _teardown() -> void:
	for child in get_children():
		child.queue_free()
	_room = null
	_player = null
	for node in get_tree().get_nodes_in_group(&"transient"):
		node.queue_free()
	await _frames(2)


## A walled 22 x 14 tile arena with one three-tile door on each side at floor level.
func _arena(waves: Array, flag: String) -> AmbushArena:
	await _teardown()
	GameState.reset_progress()
	var grid: Array = []
	for row in 17:
		grid.append("#" + ".".repeat(28) + "#" if row in range(1, 15) else "#".repeat(30))
	for row in range(1, 12):
		grid[row] = "#####" + grid[row].substr(5, 20) + "#####"
	_room = Testbed.build_room(self, &"fringe", grid)
	_player = Testbed.spawn_player(self, _room, Vector2i(2, 14))
	var arena := AmbushArena.new()
	arena.arena_size = Vector2(22 * TILE, 14 * TILE)
	arena.wave = PackedStringArray(waves[0])
	for extra in waves.slice(1):
		arena.extra_waves.append(PackedStringArray(extra))
	# Point 0 sits on a player standing at cell (15, 14); points 1-3 are 289+ px away.
	arena.spawn_offsets = PackedVector2Array(
		[Vector2(32, 360), Vector2(-320, 384), Vector2(320, 384), Vector2(0, 0)]
	)
	arena.door_rects = [
		Rect2(Vector2(-11 * TILE, 4 * TILE), Vector2(TILE, 3 * TILE)),
		Rect2(Vector2(10 * TILE, 4 * TILE), Vector2(TILE, 3 * TILE)),
	]
	arena.flag_id = flag
	arena.position = CENTRE
	Testbed.entities(_room).add_child(arena)
	_telegraphs.clear()
	arena.telegraphed.connect(func(at: Vector2) -> void: _telegraphs.append(at))
	await _frames(4)
	return arena


func _enter() -> void:
	_player.global_position = Testbed.feet(_room, Vector2i(15, 14))
	_player.velocity = Vector2.ZERO


func _kill_all(arena: AmbushArena) -> void:
	for enemy in arena.enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy.call("take_damage", 999, &"beam")


func _ambush_enemies() -> int:
	var live := get_tree().get_nodes_in_group(&"worldfx_ambush_enemy")
	return live.filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).size()


## Refills lying at the arena's reward point (the authored point nearest the player); enemy
## defeat drops elsewhere are ignored.
func _loot(arena: AmbushArena) -> Array:
	var center := WorldFx.player_rect(_player).get_center()
	var at := arena.authored_points()[0]
	for point in arena.authored_points():
		if point.distance_to(center) < at.distance_to(center):
			at = point
	var found: Array = []
	for node in get_tree().get_nodes_in_group(&"transient"):
		if node is CombatLoot and not node.is_queued_for_deletion():
			if node.global_position.distance_to(at) < 1.0:
				found.append(node)
	return found


func _fighting(arena: AmbushArena, index: int) -> Callable:
	return func() -> bool:
		return arena.state == AmbushArena.State.FIGHTING and arena.wave_index == index


func _solid_at(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return not get_viewport().world_2d.direct_space_state.intersect_point(query, 1).is_empty()


# --- cases -----------------------------------------------------------------------------------


func _rules() -> void:
	print("rules")
	GameState.reset_progress()
	_check(not AmbushRules.can_defeat_enemy(&"hopper"), "no weapon beats nothing")
	GameState.unlock_ability(&"beam")
	_check(AmbushRules.can_defeat_enemy(&"hopper"), "beam beats common enemies")
	_check(not AmbushRules.can_defeat_enemy(&"crawler"), "crawler needs missiles")
	_check(not AmbushRules.can_defeat_enemy(&"armored_guard"), "guard needs missiles or bombs")
	var kept := AmbushRules.winnable_spawns(
		PackedStringArray(["hopper", "armored_guard", "crawler", "vent_flyer"]), 3
	)
	_check(kept == [[&"hopper", 3], [&"vent_flyer", 6]], "filter drops single spawns: %s" % [kept])
	GameState.reset_progress()
	GameState.unlock_ability(&"slipstream")
	GameState.unlock_ability(&"bombs")
	_check(AmbushRules.can_defeat_enemy(&"armored_guard"), "bombs alone beat the guard")
	_check(not AmbushRules.can_defeat_enemy(&"crawler"), "bombs do not beat the crawler")
	_check(AmbushRules.can_defeat_enemy(&"hopper"), "bombs count as any damage")
	GameState.collect_pickup("ambush_rules.missile", &"missile_tank")
	_check(AmbushRules.can_defeat_enemy(&"crawler"), "missiles beat the crawler")
	_check(not AmbushRules.can_defeat_enemy(&"lava_monster"), "lava monster never spawns")
	_check(not AmbushRules.can_defeat_enemy(&"stone_guardian"), "bosses never spawn")
	var points := PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(600, 0)])
	_check(
		AmbushRules.resolve_spawn(points, 0, Vector2(1000, 0)) == Vector2(0, 0),
		"a far spawn stays on its authored point"
	)
	_check(
		AmbushRules.resolve_spawn(points, 0, Vector2(10, 0)) == Vector2(300, 0),
		"a close spawn moves to the nearest far authored point"
	)
	var tight := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(150, 0)])
	_check(
		AmbushRules.resolve_spawn(tight, 2, Vector2(160, 0)) == Vector2(0, 0),
		"with none far enough the farthest authored point wins"
	)
	var mixed := PackedVector2Array(
		[Vector2(0, 0), Vector2(300, -200), Vector2(600, 0), Vector2(900, -200)]
	)
	var ids := PackedStringArray(["hopper", "vent_flyer", "hopper", "vent_flyer"])
	_check(
		AmbushRules.resolve_spawn(mixed, 0, Vector2(10, 0), ids) == Vector2(600, 0),
		"a relocated walker skips the nearer flyer point"
	)
	_check(
		AmbushRules.resolve_spawn(mixed, 1, Vector2(300, -200), ids) == Vector2(900, -200),
		"a relocated flyer skips the nearer walker point"
	)
	_check(
		AmbushRules.resolve_spawn(mixed, 2, Vector2(610, 0), ids) == Vector2(0, 0),
		"a walker only ever moves to a walker point"
	)
	var lone := PackedStringArray(["hopper", "vent_flyer"])
	_check(
		AmbushRules.resolve_spawn(tight, 0, Vector2(0, 0), lone) == Vector2(0, 0),
		"a class with only its own point keeps it"
	)
	_check(AmbushRules.reward_kind() == &"energy_refill", "full missiles reward energy")
	GameState.missile_count = 0
	_check(AmbushRules.reward_kind() == &"missile_refill", "missing missiles reward missiles")


func _waves_and_reward() -> void:
	print("waves, telegraphs, reward")
	var arena := await _arena(
		[["hopper", "hopper"], ["hopper", "vent_flyer"]], "ambush_rules.waves"
	)
	GameState.unlock_ability(&"beam")
	_enter()
	await _frames(2)
	_check(arena.state == AmbushArena.State.SEALING, "entering seals the arena")
	await _until(func() -> bool: return not _telegraphs.is_empty(), 1.0)
	_check(
		_telegraphs.size() == 1 and arena.enemies.is_empty(), "the first spawn is telegraphed first"
	)
	var points := arena.authored_points()
	_check(
		_telegraphs[0] == points[2] if not _telegraphs.is_empty() else false,
		"a spawn on the player moves to the nearest far authored point"
	)
	_check(await _until(_fighting(arena, 0), 2.0), "wave 1 released")
	_check(arena.alive_count() == 2, "wave 1 spawned two enemies")
	var feet := _player.global_position
	_check(
		arena.enemies.all(func(enemy: Node) -> bool: return enemy.call("_in_arena", feet)),
		"ambush enemies target a player standing on the floor line"
	)
	_kill_all(arena)
	await _frames(3)
	_check(arena.state == AmbushArena.State.INTERMISSION, "beating wave 1 starts the breather")
	await _seconds(0.5)
	_check(arena.enemies.size() == 2, "no spawn during the breather")
	_check(await _until(_fighting(arena, 1), 2.0), "wave 2 released after the breather")
	_check(arena.alive_count() == 2, "wave 2 spawned two enemies")
	var on_points := _telegraphs.all(func(at: Vector2) -> bool: return at in points)
	_check(_telegraphs.size() == 4 and on_points, "every spawn used an authored point")
	_kill_all(arena)
	await _frames(3)
	_check(arena.state == AmbushArena.State.CLEARED, "beating the last wave clears the arena")
	_check(GameState.has_world_flag("ambush_rules.waves"), "clear flag saved")
	var loot := _loot(arena)
	_check(
		loot.size() == 1 and loot[0].kind == &"energy_refill", "one energy refill drops on clear"
	)
	await _seconds(1.0)
	_check(arena.reward_drops == 1, "the reward drops exactly once")
	_check(not arena.slabs[0].is_closed and not arena.slabs[1].is_closed, "seals open on clear")


## The kiln_02 case: a perched gargoyle authored next to the trigger must move to the other floor
## point, never onto the flyer's air point that happens to be nearer.
func _class_relocation() -> void:
	print("class-aware relocation")
	var arena := await _arena([["shooting_gargoyle", "hopper", "vent_flyer"]], "ambush_rules.class")
	GameState.unlock_ability(&"beam")
	_enter()
	await _until(func() -> bool: return not _telegraphs.is_empty(), 1.5)
	var points := arena.authored_points()
	_check(
		not _telegraphs.is_empty() and _telegraphs[0] == points[1],
		"the gargoyle on the player moves to the floor point, not the nearer air point"
	)


func _kit_filter() -> void:
	print("kit filter")
	var arena := await _arena(
		[["armored_guard", "crawler", "hopper"], ["crawler"]], "ambush_rules.filter"
	)
	_enter()
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.ARMED, "no weapon: never seals")
	_check(not arena.slabs[0].is_closed, "no weapon: seals stay open")
	GameState.unlock_ability(&"beam")
	_check(await _until(_fighting(arena, 0), 2.5), "beam only: the fight starts")
	await _seconds(0.3)
	var ids := arena.enemies.map(func(enemy: Node) -> StringName: return enemy.get("enemy_id"))
	_check(ids == [&"hopper"], "beam only: no guard or crawler spawned (%s)" % [ids])
	_check(arena.plan_waves().size() == 1, "the crawler-only wave is skipped")
	GameState.collect_pickup("ambush_rules.filter.missile", &"missile_tank")
	GameState.missile_count = 1
	_player.global_position = Testbed.feet(_room, Vector2i(9, 14))
	await _frames(2)
	_kill_all(arena)
	await _frames(3)
	_check(arena.state == AmbushArena.State.CLEARED, "the filtered ambush clears")
	var loot := _loot(arena)
	_check(
		loot.size() == 1 and loot[0].kind == &"missile_refill",
		"missiles owned and not full: the reward is a missile refill"
	)
	var guards := await _arena([["armored_guard", "crawler"]], "ambush_rules.unwinnable")
	GameState.unlock_ability(&"beam")
	_enter()
	await _seconds(0.5)
	_check(guards.state == AmbushArena.State.ARMED, "beam only vs guard + crawler: never seals")


func _death_abort() -> void:
	print("death abort")
	var arena := await _arena([["hopper", "hopper"]], "ambush_rules.death")
	GameState.unlock_ability(&"beam")
	_enter()
	_check(await _until(_fighting(arena, 0), 2.5), "fight started")
	GameState.apply_damage(9999)
	await _frames(3)
	_check(arena.state == AmbushArena.State.ARMED, "death aborts the fight")
	_check(not arena.slabs[0].is_closed and not arena.slabs[1].is_closed, "death opens the seals")
	GameState.reset_health()
	_player.reset_for_spawn(Testbed.feet(_room, Vector2i(15, 14)))
	await _frames(10)
	_check(_ambush_enemies() == 0, "death removes the ambush enemies")
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.ARMED, "no re-seal before the player leaves")
	_player.global_position = Testbed.feet(_room, Vector2i(2, 14))
	await _frames(4)
	_enter()
	await _frames(4)
	_check(arena.state == AmbushArena.State.SEALING, "re-armed after leaving and returning")


func _leave_abort() -> void:
	print("leave abort")
	var arena := await _arena([["hopper", "hopper"]], "ambush_rules.leave")
	GameState.unlock_ability(&"beam")
	var aborted := [false]
	arena.aborted.connect(func() -> void: aborted[0] = true)
	_enter()
	_check(await _until(_fighting(arena, 0), 2.5), "fight started")
	_player.global_position = Testbed.feet(_room, Vector2i(2, 14))
	await _frames(3)
	_check(aborted[0] and arena.state == AmbushArena.State.ARMED, "leaving the arena aborts")
	_check(not arena.slabs[0].is_closed, "leaving opens the seals")
	await _frames(10)
	_check(_ambush_enemies() == 0, "leaving removes the ambush enemies")
	_check(not GameState.has_world_flag("ambush_rules.leave"), "an aborted fight is not a clear")


func _stall_abort() -> void:
	print("stall abort")
	var arena := await _arena([["hopper", "hopper"]], "ambush_rules.stall")
	arena.stall_seconds = 1.5
	GameState.unlock_ability(&"beam")
	_player.dev_invulnerable = true
	_enter()
	_check(await _until(_fighting(arena, 0), 2.5), "fight started")
	await _seconds(1.0)
	arena.enemies[0].call("take_damage", 1, &"beam")
	await _seconds(1.0)
	_check(arena.state == AmbushArena.State.FIGHTING, "damage resets the stall timer")
	await _seconds(1.8)
	_check(arena.state == AmbushArena.State.ARMED, "a stalled fight aborts")
	_check(not arena.slabs[0].is_closed, "the stall abort opens the seals")
	await _frames(10)
	_check(_ambush_enemies() == 0, "the stall abort removes the ambush enemies")


func _campaign_fringe_03() -> void:
	print("campaign fringe_03")
	GameState.reset_progress()
	GameState.set_checkpoint("fringe_01", Vector2(544, 896))
	var root := CAMPAIGN.instantiate()
	add_child(root)
	await _frames(20)
	var player := root.get("player") as Player
	player.dev_invulnerable = true
	var inside := Vector2(15.5 * TILE, 15 * TILE)
	root.call("teleport", "fringe_03", inside)
	await _frames(30)
	var arena := get_tree().get_first_node_in_group(&"worldfx_ambush") as AmbushArena
	_check(arena != null and arena.slabs.size() == 2, "fringe_03 has the beam_trial arena")
	if arena == null or arena.slabs.size() != 2:
		root.queue_free()
		return
	_telegraphs.clear()
	arena.telegraphed.connect(func(at: Vector2) -> void: _telegraphs.append(at))
	var doors := arena.slabs.map(func(slab: SealSlab) -> Vector2: return slab.global_position)
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.ARMED, "no seal without the beam")
	_check(not _solid_at(doors[0]) and not _solid_at(doors[1]), "both openings are air")
	GameState.unlock_ability(&"beam")
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.SEALING, "with the beam the arena seals")
	_check(
		_solid_at(doors[0]) and _solid_at(doors[1]), "Ball tunnel and east door are both blocked"
	)
	var points := arena.authored_points()
	var first_id := arena.get_instance_id()
	var waves := 0
	for _frame in 60 * 12:
		if arena.state == AmbushArena.State.CLEARED:
			break
		if arena.state == AmbushArena.State.FIGHTING:
			waves = maxi(waves, arena.wave_index + 1)
			_kill_all(arena)
		await get_tree().physics_frame
	_check(arena.state == AmbushArena.State.CLEARED and waves == 2, "both waves clear")
	_check(
		_telegraphs.size() == 5 and _telegraphs.all(func(at: Vector2) -> bool: return at in points),
		"all five spawns landed on authored points"
	)
	_check(GameState.has_world_flag(FLAG), "clear flag %s saved" % FLAG)
	await _seconds(1.2)
	_check(not _solid_at(doors[0]) and not _solid_at(doors[1]), "seals open after the clear")
	root.call("teleport", "fringe_02", Vector2(14.5 * TILE, 32 * TILE))
	await _frames(20)
	root.call("teleport", "fringe_03", inside)
	await _frames(30)
	var again := get_tree().get_first_node_in_group(&"worldfx_ambush") as AmbushArena
	_check(
		(
			again != null
			and again.get_instance_id() != first_id
			and again.state == AmbushArena.State.CLEARED
		),
		"the clear persists across a room reload"
	)
	await _seconds(0.5)
	_check(again != null and not again.slabs[0].is_closed, "a reloaded cleared arena stays open")
	root.queue_free()
	await _frames(2)


func _dev_s3() -> void:
	print("dev S3")
	GameState.reset_progress()
	var level := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	await _frames(4)
	var arenas := get_tree().get_nodes_in_group(&"dev_ambush")
	_check(arenas.size() == 1, "exactly one S3 dev arena (%d)" % arenas.size())
	if arenas.size() != 1:
		level.queue_free()
		return
	var arena := arenas[0] as AmbushArena
	var origins: Dictionary = level.get("_room_origins")
	var player := level.get_node("PlayerSpawn/Player") as Player
	player.dev_invulnerable = true
	var doors := arena.slabs.map(func(slab: SealSlab) -> Vector2: return slab.global_position)
	_check(doors.size() == 2, "the S3 arena seals both doorways")
	var blocked := Array(arena.authored_points()).filter(
		func(at: Vector2) -> bool: return _solid_at(at)
	)
	_check(blocked.is_empty(), "every S3 spawn point is open space (%s)" % [blocked])
	player.global_position = origins["S3"] + Vector2(960, 1152)
	player.velocity = Vector2.ZERO
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.ARMED, "no seal without a weapon")
	GameState.unlock_ability(&"beam")
	await _seconds(0.3)
	_check(arena.state == AmbushArena.State.SEALING, "with the beam the S3 arena seals")
	_check(doors.all(func(at: Vector2) -> bool: return _solid_at(at)), "both doorways are blocked")
	var waves := 0
	for _frame in 60 * 15:
		if arena.state == AmbushArena.State.CLEARED:
			break
		if arena.state == AmbushArena.State.FIGHTING:
			waves = maxi(waves, arena.wave_index + 1)
			_kill_all(arena)
		await get_tree().physics_frame
	_check(arena.state == AmbushArena.State.CLEARED, "the S3 ambush clears (%d waves)" % waves)
	_check(waves == 3, "all three S3 waves ran (the guard is filtered, the flyers remain)")
	_check(GameState.has_world_flag("dev:S3:ambush"), "the S3 clear is saved")
	await _seconds(1.2)
	_check(not doors.any(func(at: Vector2) -> bool: return _solid_at(at)), "S3 doorways reopen")
	level.queue_free()
	await _frames(2)
