extends Node

## Campaign ambushes outside the Fringe (docs/features/ambush-arenas.md): one arena each in the
## nexus, vaults, kiln and depths. Per arena: the kit the campaign move tests grant never seals it,
## the arrival kit seals every opening, both waves clear when their enemies are killed, and the clear
## flag survives a room reload.
## godot --headless --path . res://tools/check_ambush_campaign.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0
const AWAY_ROOM := "nexus_01"
const AWAY_FEET := Vector2(8.5 * TILE, 32 * TILE)
## room, local id, feet inside the trigger (room tiles), seals, kit that must not seal, arrival kit.
const CASES := [
	{
		"room": "nexus_02",
		"id": "loft",
		"cell": Vector2(5.5, 10),
		"seals": 1,
		"idle_kit": [&"high_jump"],
		"kit": [&"beam", &"slipstream", &"missiles", &"ice_beam", &"high_jump"],
	},
	{
		"room": "vaults_01",
		"id": "threshold",
		"cell": Vector2(7.5, 15),
		"seals": 2,
		"idle_kit": [&"slipstream"],
		"kit": [&"beam", &"slipstream", &"bombs", &"missiles"],
	},
	{
		"room": "kiln_02",
		"id": "antechamber",
		"cell": Vector2(25.5, 32),
		"seals": 2,
		"idle_kit": [&"pressure_seal"],
		"kit": [&"beam", &"slipstream", &"missiles", &"pressure_seal"],
	},
	{
		"room": "depths_01",
		"id": "undertow_hall",
		"cell": Vector2(5.5, 32),
		"seals": 2,
		"idle_kit": [&"high_jump"],
		"kit": [&"beam", &"slipstream", &"bombs", &"missiles", &"high_jump", &"pressure_seal"],
	},
]

var _failures: Array[String] = []
var _root: Node
var _telegraphs: Array[Vector2] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	GameState.set_checkpoint("fringe_01", Vector2(544, 896))
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(20)
	(_root.get("player") as Player).dev_invulnerable = true
	for case in CASES:
		await _case(case)
	_root.queue_free()
	await _frames(2)
	await _finish()


func _finish() -> void:
	for failure in _failures:
		print("FAIL ", failure)
	print("ambush-campaign: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
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


## Stops every positional world sound and drops its stream so no playback outlives the mixer.
func _silence_world_audio() -> void:
	for node in get_tree().root.find_children("*", "AudioStreamPlayer2D", true, false):
		node.stop()
		node.stream = null
		if node.get_parent() == get_tree().root:
			node.queue_free()


func _solid_at(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return not get_viewport().world_2d.direct_space_state.intersect_point(query, 1).is_empty()


func _grant(kit: Array) -> void:
	for ability in kit:
		if ability == &"missiles":
			GameState.collect_pickup("ambush_campaign_missiles", &"missile_tank")
		else:
			GameState.unlock_ability(ability)


## Resets progress to `kit`, places the player in `room` at `cell` (feet, room tiles) and returns
## the live arena whose clear flag is `flag`.
func _enter(room: String, cell: Vector2, kit: Array, flag: String) -> AmbushArena:
	GameState.reset_progress()
	_grant(kit)
	_root.call("teleport", room, cell * TILE)
	await _frames(30)
	return _arena(flag)


func _arena(flag: String) -> AmbushArena:
	for node in get_tree().get_nodes_in_group(&"worldfx_ambush"):
		if not node.is_queued_for_deletion() and (node as AmbushArena).flag() == flag:
			return node as AmbushArena
	return null


func _slab_points(arena: AmbushArena) -> Array:
	return arena.slabs.map(func(slab: SealSlab) -> Vector2: return slab.global_position)


func _all_solid(points: Array) -> bool:
	return points.all(func(point: Vector2) -> bool: return _solid_at(point))


func _none_solid(points: Array) -> bool:
	return points.all(func(point: Vector2) -> bool: return not _solid_at(point))


func _kill_all(arena: AmbushArena) -> void:
	for enemy in arena.enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy.call("receive_hit", 999, &"missile", {})


# --- cases -----------------------------------------------------------------------------------


func _case(case: Dictionary) -> void:
	var room: String = case["room"]
	var flag := "%s.ambush.%s" % [room, case["id"]]
	print("campaign %s" % flag)
	var arena := await _enter(room, case["cell"], case["idle_kit"], flag)
	_check(arena != null and arena.flag() == flag, "%s has the %s arena" % [room, case["id"]])
	if arena == null or arena.flag() != flag:
		return
	_check(arena.slabs.size() == case["seals"], "%s seals %d openings" % [room, case["seals"]])
	var doors := _slab_points(arena)
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.ARMED, "%s: no seal with %s" % [room, case["idle_kit"]])
	_check(_none_solid(doors), "%s: every opening is air before the fight" % room)
	_telegraphs.clear()
	arena.telegraphed.connect(func(at: Vector2) -> void: _telegraphs.append(at))
	_grant(case["kit"])
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.SEALING, "%s: the arrival kit seals it" % room)
	_check(_all_solid(doors), "%s: every opening is blocked" % room)
	var points := arena.authored_points()
	var spawns := 0
	for ids in arena.all_waves():
		spawns += ids.size()
	var first_id := arena.get_instance_id()
	var waves := 0
	for _frame in 60 * 40:
		if arena.state == AmbushArena.State.CLEARED:
			break
		if arena.state == AmbushArena.State.FIGHTING:
			waves = maxi(waves, arena.wave_index + 1)
		_kill_all(arena)
		await get_tree().physics_frame
	_check(arena.state == AmbushArena.State.CLEARED and waves == 2, "%s: both waves clear" % room)
	_check(
		(
			_telegraphs.size() == spawns
			and _telegraphs.all(func(at: Vector2) -> bool: return at in points)
		),
		"%s: all %d spawns landed on authored points (%d)" % [room, spawns, _telegraphs.size()]
	)
	_check(GameState.has_world_flag(flag), "%s: clear flag saved" % flag)
	await _seconds(1.2)
	_check(_none_solid(doors), "%s: seals open after the clear" % room)
	_root.call("teleport", AWAY_ROOM, AWAY_FEET)
	await _frames(20)
	_root.call("teleport", room, (case["cell"] as Vector2) * TILE)
	await _frames(30)
	var again := _arena(flag)
	_check(
		(
			again != null
			and again.get_instance_id() != first_id
			and again.state == AmbushArena.State.CLEARED
		),
		"%s: the clear persists across a room reload" % room
	)
	await _seconds(0.5)
	_check(
		again != null and _none_solid(_slab_points(again)), "%s: reloaded arena stays open" % room
	)
