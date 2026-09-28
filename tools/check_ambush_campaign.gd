extends Node

## Campaign ambushes outside the Fringe (docs/features/ambush-arenas.md): one arena each in the
## nexus, vaults, kiln and depths. Per arena: the kit the campaign move tests grant never seals it,
## the arrival kit seals every opening, both waves clear when their enemies are killed, and the clear
## flag survives a room reload. A save shrine inside an arena neither refills nor saves until the
## clear, and the vaults_01 wave-2 turret stays on the pit floor.
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
		"pit_floor": Vector2(13.5, 15),
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


## Sweep 2026-09-24: a shard turret perched on the cache shelf covered the whole sealed pit. Every
## authored spawn lies on the pit floor, and the player stands mid-pit (where the relocation rule
## used to lift the turret onto the shelf) while wave 2 spawns.
func _check_pit_spawns(room: String, arena: AmbushArena, pit_floor: Vector2) -> void:
	var feet := (arena.get_parent() as Node2D).to_global(pit_floor * TILE)
	var lifted: Array[Vector2] = []
	for point in arena.authored_points():
		if absf(point.y - feet.y) >= TILE:
			lifted.append(point)
	_check(
		lifted.is_empty(),
		"%s: every spawn point is on the pit floor (above it: %s)" % [room, lifted]
	)
	var player := _root.get("player") as Player
	player.global_position = feet
	player.velocity = Vector2.ZERO


## The save shrine inside `arena`, if the layout puts one there.
func _shrine_in(arena: AmbushArena) -> Area2D:
	for node in get_tree().get_nodes_in_group(&"campaign_station"):
		var station := node as Area2D
		if (
			station.get("station_kind") == &"save"
			and arena.arena_rect_global().has_point(station.global_position)
		):
			return station
	return null


func _shrine_floor(shrine: Area2D) -> Vector2:
	return shrine.global_position + Vector2(0, float(shrine.get("FLOOR_OFFSET_Y")))


## Mid-fight the shrine gives back nothing and writes no checkpoint, however often she steps on.
func _shrine_dormant(room: String, shrine: Area2D) -> void:
	var player := _root.get("player") as Player
	var checkpoint := GameState.checkpoint.duplicate(true)
	GameState.health = 10
	GameState.missile_count = 0
	for _visit in 2:
		player.global_position = _shrine_floor(shrine)
		player.velocity = Vector2.ZERO
		await _seconds(1.5)
		player.global_position.x -= 3 * TILE
		await _seconds(0.3)
	_check(
		GameState.health == 10 and GameState.missile_count == 0,
		(
			"%s: the save shrine refills nothing mid-fight (health %d, Harpoons %d)"
			% [room, GameState.health, GameState.missile_count]
		)
	)
	_check(GameState.checkpoint == checkpoint, "%s: the save shrine does not save mid-fight" % room)


## After the clear the same shrine refills and saves again.
func _shrine_awake(room: String, shrine: Area2D) -> void:
	var player := _root.get("player") as Player
	player.global_position.x = shrine.global_position.x - 4 * TILE
	await _seconds(1.3)
	player.global_position = _shrine_floor(shrine)
	player.velocity = Vector2.ZERO
	await _seconds(0.5)
	_check(
		(
			GameState.health == GameState.max_health
			and GameState.missile_count == GameState.max_missiles
		),
		"%s: the save shrine refills after the clear" % room
	)
	_check(
		GameState.checkpoint.get("room", "") == room,
		"%s: the save shrine saves after the clear" % room
	)


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
	var shrine := _shrine_in(arena)
	if shrine != null:
		await _shrine_dormant(room, shrine)
	if case.has("pit_floor"):
		_check_pit_spawns(room, arena, case["pit_floor"])
	var waves := 0
	var turret_y := -INF
	for _frame in 60 * 40:
		if arena.state == AmbushArena.State.CLEARED:
			break
		if arena.state == AmbushArena.State.FIGHTING:
			waves = maxi(waves, arena.wave_index + 1)
			for enemy in arena.enemies:
				if is_instance_valid(enemy) and enemy.get("enemy_id") == &"shard_turret":
					turret_y = maxf(turret_y, (enemy as Node2D).global_position.y)
		_kill_all(arena)
		await get_tree().physics_frame
	_check(arena.state == AmbushArena.State.CLEARED and waves == 2, "%s: both waves clear" % room)
	if case.has("pit_floor"):
		var floor_y := (
			(arena.get_parent() as Node2D).to_global((case["pit_floor"] as Vector2) * TILE).y
		)
		_check(
			absf(turret_y - floor_y) < TILE,
			(
				"%s: the wave-2 turret stands on the pit floor (y %.0f, floor %.0f)"
				% [room, turret_y, floor_y]
			)
		)
	if shrine != null:
		await _shrine_awake(room, shrine)
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
