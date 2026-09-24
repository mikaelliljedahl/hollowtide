extends Node

## Living-environment mechanics (D21): crumble floor, stalactite, crusher, push currents, rising
## shaft, timed door and ambush arena. Each case builds a small real room with the real player.
## godot --headless --path . res://tools/check_worldfx.tscn -- --test-mode

const Testbed = preload("res://tools/worldfx_testbed.gd")
const TILE := 64.0
const FLAT := [
	"##############################",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"##############################",
	"##############################",
]

var _failures: Array[String] = []
var _room: CampaignRoom
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _crumble()
	await _stalactite()
	await _crusher()
	await _currents()
	await _rising_shaft()
	await _timed_door()
	await _ambush()
	await _teardown()
	await _silence_audio()
	for failure in _failures:
		print("FAIL ", failure)
	print("worldfx: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	get_tree().quit(0 if _failures.is_empty() else 1)


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


func _setup(area: StringName, grid: Array, player_cell: Vector2i) -> void:
	await _teardown()
	GameState.reset_progress()
	_room = Testbed.build_room(self, area, grid)
	_player = Testbed.spawn_player(self, _room, player_cell)
	await _frames(3)


func _teardown() -> void:
	for child in get_children():
		child.queue_free()
	_room = null
	_player = null
	for node in get_tree().get_nodes_in_group(&"transient"):
		node.queue_free()
	await _frames(2)


## Stops every live voice and drops its stream, then lets the audio server release the
## playbacks, so no AudioStreamWAV is still referenced by the mixer at exit.
func _silence_audio() -> void:
	for node in get_tree().root.find_children("*", "", true, false):
		if node is AudioStreamPlayer2D or node is AudioStreamPlayer:
			node.stop()
			node.stream = null
			if node.get_parent() == get_tree().root:
				node.queue_free()
	await Audio.shutdown()
	# The mixer runs on wall-clock time, not the fixed test clock: wait real milliseconds.
	var until := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		OS.delay_msec(5)


func _add(node: Node2D, local: Vector2) -> Node2D:
	node.position = local
	Testbed.entities(_room).add_child(node)
	return node


func _overlaps_terrain(player: Player) -> bool:
	var probe := RectangleShape2D.new()
	probe.size = Vector2(50, 170)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	query.transform = Transform2D(0.0, player.global_position + Vector2(0, -88))
	return not player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- cases -----------------------------------------------------------------------------------


func _crumble() -> void:
	print("crumble floor")
	var grid := FLAT.duplicate()
	# A brittle bridge at row 12, cells 16-18, over a pit.
	grid[12] = "#.........######...###########"
	await _setup(&"vaults", grid, Vector2i(14, 11))
	var floor := CrumbleFloor.new()
	floor.cells = 3
	_add(floor, Vector2(16 * TILE, 12 * TILE))
	var permanent := CrumbleFloor.new()
	permanent.cells = 1
	permanent.permanent = true
	permanent.respawn_seconds = 0.5
	_add(permanent, Vector2(24 * TILE, 5 * TILE))
	await _frames(4)
	_check(floor.is_solid(0) and floor.is_solid(1), "tiles start solid")
	_player.global_position = Testbed.feet(_room, Vector2i(16, 11))
	await _frames(6)
	_check(floor.state_of(0) == CrumbleFloor.State.SHAKING, "standing on a tile starts the shake")
	_check(floor.state_of(2) == CrumbleFloor.State.SOLID, "untouched tile stays solid")
	await _seconds(0.3)
	_check(floor.is_solid(0), "tile still holds during the 0.6 s warning")
	await _seconds(0.45)
	_check(floor.state_of(0) == CrumbleFloor.State.GONE, "tile crumbles after the delay")
	var y_before := _player.global_position.y
	await _seconds(0.5)
	_check(_player.global_position.y > y_before + 40.0, "player falls through the gap")
	_player.global_position = Testbed.feet(_room, Vector2i(5, 14))
	await _seconds(4.2)
	_check(
		floor.state_of(0) in [CrumbleFloor.State.REFORMING, CrumbleFloor.State.SOLID],
		"tile reforms after the respawn time"
	)
	await _seconds(0.6)
	_check(floor.is_solid(0), "reformed tile is solid again")
	# Permanent tile never comes back.
	_player.global_position = Testbed.feet(_room, Vector2i(24, 4))
	_player.velocity = Vector2.ZERO
	await _seconds(1.0)
	_check(permanent.state_of(0) == CrumbleFloor.State.GONE, "permanent tile crumbles")
	await _seconds(1.5)
	_check(permanent.state_of(0) == CrumbleFloor.State.GONE, "permanent tile stays gone")
	# A tile does not reform inside the player.
	floor.respawn_seconds = 0.3
	_player.global_position = Testbed.feet(_room, Vector2i(18, 11))
	_player.velocity = Vector2.ZERO
	await _seconds(1.0)
	_check(floor.state_of(2) == CrumbleFloor.State.GONE, "last tile crumbles under the player")
	_player.set_physics_process(false)
	_player.global_position = Testbed.feet(_room, Vector2i(18, 12))
	await _seconds(1.0)
	_check(floor.state_of(2) == CrumbleFloor.State.GONE, "tile never reforms inside the player")
	_player.set_physics_process(true)
	_player.global_position = Testbed.feet(_room, Vector2i(5, 14))
	await _seconds(1.0)
	_check(floor.is_solid(2), "tile reforms once the player is clear")


func _stalactite() -> void:
	print("stalactite")
	await _setup(&"kiln", FLAT, Vector2i(4, 14))
	var spike := Stalactite.new()
	_add(spike, Vector2(15 * TILE + 32, 1 * TILE))
	var high := Stalactite.new()
	_add(high, Vector2(25 * TILE + 32, 1 * TILE))
	await _frames(6)
	_check(spike.state == Stalactite.State.ARMED, "spike starts armed")
	await _seconds(1.0)
	_check(spike.state == Stalactite.State.ARMED, "spike ignores a player who is not beneath it")
	var health := GameState.health
	_player.global_position = Testbed.feet(_room, Vector2i(15, 14))
	await _frames(4)
	_check(spike.state == Stalactite.State.SHAKING, "passing beneath starts the rattle")
	await _seconds(0.6)
	_check(
		spike.state in [Stalactite.State.FALLING, Stalactite.State.GONE],
		"spike falls after the rattle"
	)
	await _seconds(1.0)
	_check(GameState.health < health, "falling spike damages the player below")
	_check(GameState.health > 0, "spike never kills from full health")
	_check(spike.state == Stalactite.State.GONE, "spike shatters")
	_player.global_position = Testbed.feet(_room, Vector2i(5, 14))
	await _seconds(6.2)
	_check(spike.state == Stalactite.State.ARMED, "spike regrows and re-arms")
	# Shooting it drops it early; it shatters on the floor without a player below.
	high.receive_hit(1, &"beam")
	_check(high.state == Stalactite.State.FALLING, "a shot knocks the spike loose")
	await _seconds(1.2)
	_check(high.state == Stalactite.State.GONE, "shot spike shatters on the floor")


func _crusher() -> void:
	print("crusher")
	var grid := FLAT.duplicate()
	grid[1] = "##############..##############"
	grid[2] = "##############..##############"
	await _setup(&"kiln", grid, Vector2i(4, 14))
	var crusher := Crusher.new()
	crusher.width = 128
	crusher.block_height = 128
	_add(crusher, Vector2(15 * TILE, 1 * TILE))
	await _frames(4)
	_check(crusher.travel > 700.0, "crusher detects its floor (travel %.0f)" % crusher.travel)
	# Standing beside the column is safe for a whole cycle.
	var health := GameState.health
	_player.global_position = Testbed.feet(_room, Vector2i(12, 14))
	await _seconds(crusher.cycle_seconds() + 0.2)
	_check(GameState.health == health, "standing beside the crusher is safe")
	# Standing under it: heavy damage and ejected to free space, never inside rock.
	var hits := 0
	var inside_rock := false
	var in_column := false
	_player.global_position = Testbed.feet(_room, Vector2i(15, 14))
	for _frame in int(crusher.cycle_seconds() * 60.0) + 20:
		await get_tree().physics_frame
		if GameState.health < health:
			hits = 1
		if hits == 0:
			# Hold the player under the block until it lands on her.
			_player.global_position.x = clampf(
				_player.global_position.x, 14 * TILE + 40, 16 * TILE - 40
			)
		if _overlaps_terrain(_player) and not inside_rock:
			inside_rock = true
			print(
				(
					"    inside rock: phase=%d block=%s player=%s hits=%d"
					% [crusher.phase, crusher.block_rect_global(), _player.global_position, hits]
				)
			)
		if (
			crusher.phase == Crusher.Phase.HOLD
			and absf(_player.global_position.x - 15 * TILE) < 64.0 + 28.0
		):
			in_column = true
	_check(hits == 1, "crusher hits a player caught beneath")
	_check(health - GameState.health >= crusher.damage - 1, "crusher damage is heavy")
	_check(not inside_rock, "player is never left inside rock")
	_check(not in_column, "player is ejected out of the column")
	_check(GameState.health > 0, "crusher does not kill from full health")
	# Rider on top is carried, not crushed.
	GameState.reset_health()
	await _seconds(1.2)
	var rider_health := GameState.health
	_player.global_position = crusher.block_rect_global().position + Vector2(64, -2)
	_player.velocity = Vector2.ZERO
	await _seconds(crusher.cycle_seconds())
	_check(GameState.health == rider_health, "standing on top of the crusher is safe")


func _currents() -> void:
	print("push currents")
	await _setup(&"depths", FLAT, Vector2i(6, 14))
	var water := PushCurrent.new()
	water.zone_size = Vector2(1024, 384)
	water.direction = Vector2.RIGHT
	water.strength = 240.0
	water.kind = &"water"
	_add(water, Vector2(12 * TILE, 13 * TILE))
	await _frames(6)
	var x0 := _player.global_position.x
	await _seconds(1.0)
	_check(water.player_inside(), "player detected in the current")
	_check(_player.global_position.x - x0 > 160.0, "water current drifts the player downstream")
	_check(_player.global_position.x - x0 < 320.0, "drift stays at the tuned strength")
	# Walking upstream is slower but possible.
	_player.global_position = Testbed.feet(_room, Vector2i(18, 14))
	await _frames(4)
	var x1 := _player.global_position.x
	Input.action_press(&"move_left")
	await _seconds(1.0)
	Input.action_release(&"move_left")
	var upstream := x1 - _player.global_position.x
	_check(
		upstream > 60.0 and upstream < 420.0,
		"walking upstream works but slowly (%.0f px/s)" % upstream
	)
	water.queue_free()
	var steam := PushCurrent.new()
	steam.zone_size = Vector2(192, 768)
	steam.direction = Vector2.UP
	steam.strength = 700.0
	steam.kind = &"steam"
	_add(steam, Vector2(24 * TILE, 9 * TILE))
	await _frames(4)
	_player.global_position = Testbed.feet(_room, Vector2i(24, 14))
	_player.velocity = Vector2.ZERO
	var y0 := _player.global_position.y
	await _seconds(0.6)
	_check(y0 - _player.global_position.y > 150.0, "steam updraft lifts the player")


func _rising_shaft() -> void:
	print("rising shaft")
	var grid := [
		"##############################",
		"##########.......#############",
		"##########.......#############",
		"##########.......#############",
		"##########.....###############",
		"##########.......#############",
		"##########.......#############",
		"############.....#############",
		"##########.......#############",
		"##########.......#############",
		"#..............###############",
		"#................#############",
		"#................#############",
		"############.....#############",
		"##########.......#############",
		"##########.......#############",
		"##############################",
	]
	await _setup(&"kiln", grid, Vector2i(5, 12))
	var shaft := RisingShaft.new()
	shaft.shaft_size = Vector2(7 * TILE, 15 * TILE)
	shaft.safe_line = 3 * TILE
	shaft.speed = 220.0
	_add(shaft, Vector2(10 * TILE, TILE))
	await _frames(4)
	_check(shaft.state == RisingShaft.State.ARMED, "shaft starts armed")
	var rest := shaft.surface_y
	# Step into the shaft onto the low ledge.
	_player.global_position = Testbed.feet(_room, Vector2i(11, 12))
	await _frames(6)
	_check(shaft.state == RisingShaft.State.WARNING, "entering the shaft triggers the warning")
	await _seconds(1.2)
	_check(shaft.state == RisingShaft.State.RISING, "liquid starts rising")
	_check(shaft.surface_y < rest, "surface moves up")
	var health := GameState.health
	var boosted := false
	for _frame in 240:
		await get_tree().physics_frame
		if _player.velocity.y < -1000.0:
			boosted = true
		if GameState.health < health:
			break
	await _frames(2)
	_check(GameState.health < health, "touching the liquid hurts")
	_check(GameState.health > 0, "one touch is not an instant kill")
	_check(boosted or _player.velocity.y < -200.0, "touching the liquid throws the player upward")
	# Climb to the top ledge (the safe line) and wait for the flood to peak.
	_player.global_position = Testbed.feet(_room, Vector2i(15, 3))
	_player.velocity = Vector2.ZERO
	var peak_health := GameState.health
	await _seconds(5.0)
	_check(GameState.health == peak_health, "standing above the safe line is safe")
	_check(shaft.surface_y >= shaft.stop_y() - 0.5, "liquid never rises past the safe line")
	_check(
		shaft.state in [RisingShaft.State.STOPPED, RisingShaft.State.RISING],
		"flood holds while player stays"
	)
	# Leaving the shaft drains and re-arms it.
	GameState.reset_health()
	_player.global_position = Testbed.feet(_room, Vector2i(5, 12))
	_player.velocity = Vector2.ZERO
	await _seconds(3.0)
	_check(shaft.state == RisingShaft.State.ARMED, "leaving the shaft drains and re-arms it")
	_check(is_equal_approx(shaft.surface_y, rest), "surface back at the resting pool")
	# Death resets it too.
	_player.global_position = Testbed.feet(_room, Vector2i(11, 12))
	await _seconds(1.5)
	GameState.apply_damage(9999)
	await _frames(2)
	_check(
		shaft.state in [RisingShaft.State.DRAINING, RisingShaft.State.ARMED],
		"death resets the flood"
	)
	_check(is_equal_approx(shaft.surface_y, rest), "death drops the liquid back to rest")
	GameState.reset_health()
	_player.reset_for_spawn(Testbed.feet(_room, Vector2i(5, 12)))
	await _frames(4)


func _timed_door() -> void:
	print("timed door")
	var grid := FLAT.duplicate()
	for row in range(1, 12):
		grid[row] = grid[row].substr(0, 15) + "#" + grid[row].substr(16)
	await _setup(&"nexus", grid, Vector2i(10, 14))
	var door := TimedDoor.new()
	door.door_size = Vector2(64, 192)
	door.seconds = 3.0
	door.switch_offsets = PackedVector2Array([Vector2(-320, -160)])
	door.flag_id = "worldfx_test.timed.door"
	_add(door, Vector2(15 * TILE + 32, 13 * TILE + 32))
	await _frames(4)
	_check(not door.is_open and not door.is_latched, "door starts shut")
	_check(
		_blocked(Testbed.feet(_room, Vector2i(14, 14)), Vector2(128, 0)),
		"shut door blocks the passage"
	)
	door.switches[0].receive_hit(1, &"beam")
	await _frames(2)
	_check(door.is_open, "shooting the switch opens the door")
	_check(
		not _blocked(Testbed.feet(_room, Vector2i(14, 14)), Vector2(128, 0)),
		"open door lets the player through"
	)
	await _seconds(3.3)
	_check(not door.is_open, "door closes when the countdown ends")
	# Standing in the doorway holds it open.
	door.switches[0].receive_hit(1, &"beam")
	await _frames(2)
	_player.global_position = Testbed.feet(_room, Vector2i(15, 14))
	await _seconds(3.6)
	_check(door.is_open, "door never closes on the player")
	# Passing through latches it for good and persists.
	_player.global_position = Testbed.feet(_room, Vector2i(18, 14))
	await _frames(4)
	_check(door.is_latched, "passing through latches the door open")
	_check(
		GameState.has_world_flag("worldfx_test.timed.door"), "latched door is saved as a world flag"
	)
	await _seconds(4.0)
	_check(door.is_open, "latched door stays open")
	var again := TimedDoor.new()
	again.flag_id = "worldfx_test.timed.door"
	again.switch_offsets = PackedVector2Array()
	_add(again, Vector2(15 * TILE + 32, 13 * TILE + 32))
	await _frames(2)
	_check(again.is_latched and again.is_open, "reloaded door with its flag starts open")


func _ambush() -> void:
	print("ambush arena")
	var grid := FLAT.duplicate()
	for row in range(1, 12):
		grid[row] = "#####" + grid[row].substr(5, 20) + "#####"
	await _setup(&"fringe", grid, Vector2i(2, 14))
	var arena := AmbushArena.new()
	arena.arena_size = Vector2(22 * TILE, 14 * TILE)
	arena.wave = PackedStringArray(["hopper", "hopper", "vent_flyer"])
	arena.spawn_offsets = PackedVector2Array([Vector2(-320, 256), Vector2(320, 256), Vector2(0, 0)])
	arena.door_rects = [
		Rect2(Vector2(-11 * TILE, 4 * TILE), Vector2(TILE, 3 * TILE)),
		Rect2(Vector2(10 * TILE, 4 * TILE), Vector2(TILE, 3 * TILE)),
	]
	arena.flag_id = "worldfx_test.ambush.arena"
	_add(arena, Vector2(15 * TILE, 8 * TILE))
	await _frames(4)
	# Without the beam it never seals (the wave could not be beaten).
	_player.global_position = Testbed.feet(_room, Vector2i(15, 14))
	await _seconds(0.5)
	_check(arena.state == AmbushArena.State.ARMED, "no seal without a weapon that can win")
	_player.global_position = Testbed.feet(_room, Vector2i(2, 14))
	GameState.acquire_beam()
	await _frames(4)
	_check(arena.state == AmbushArena.State.ARMED, "standing outside does not trigger")
	_player.global_position = Testbed.feet(_room, Vector2i(5, 14))
	await _frames(4)
	_check(arena.state == AmbushArena.State.ARMED, "standing in the doorway does not trigger")
	_player.global_position = Testbed.feet(_room, Vector2i(15, 14))
	await _frames(4)
	_check(arena.state == AmbushArena.State.SEALING, "entering the arena seals it")
	await _seconds(0.4)
	_check(arena.slabs[0].is_closed and arena.slabs[1].is_closed, "both openings are sealed")
	_check(
		_blocked(Testbed.feet(_room, Vector2i(6, 14)), Vector2(-128, 0)),
		"sealed door blocks the exit"
	)
	await _seconds(1.6)
	_check(arena.state == AmbushArena.State.FIGHTING, "wave released")
	_check(arena.enemies.size() == 3 and arena.alive_count() == 3, "every wave enemy spawned")
	# Death mid-fight resets the arena and removes the wave.
	GameState.apply_damage(9999)
	await _frames(3)
	_check(arena.state == AmbushArena.State.ARMED, "death resets the ambush")
	_check(not arena.slabs[0].is_closed, "death reopens the slabs")
	GameState.reset_health()
	_player.reset_for_spawn(Testbed.feet(_room, Vector2i(2, 14)))
	await _frames(20)
	_check(
		(
			get_tree()
			. get_nodes_in_group(&"worldfx_ambush_enemy")
			. filter(func(n): return not n.is_queued_for_deletion())
			. is_empty()
		),
		"reset wave is removed"
	)
	# Fight again and win.
	_player.global_position = Testbed.feet(_room, Vector2i(15, 14))
	await _seconds(2.2)
	_check(arena.state == AmbushArena.State.FIGHTING, "ambush fires again after a reset")
	for enemy in arena.enemies:
		if is_instance_valid(enemy):
			enemy.call("take_damage", 999, &"beam")
	await _frames(4)
	_check(arena.state == AmbushArena.State.CLEARED, "beating the wave clears the arena")
	_check(GameState.has_world_flag("worldfx_test.ambush.arena"), "cleared arena is saved")
	await _seconds(1.0)
	_check(
		(
			not arena.slabs[0].is_closed
			and not _blocked(Testbed.feet(_room, Vector2i(6, 14)), Vector2(-128, 0))
		),
		"slabs reopen"
	)
	var again := AmbushArena.new()
	again.arena_size = arena.arena_size
	again.flag_id = "worldfx_test.ambush.arena"
	_add(again, Vector2(15 * TILE, 8 * TILE))
	await _frames(4)
	_check(again.state == AmbushArena.State.CLEARED, "a cleared ambush never repeats")
	# Armoured guards need missiles or bombs.
	_check(
		not AmbushArena.can_defeat(PackedStringArray(["armored_guard"])),
		"guards need missiles or bombs"
	)
	GameState.collect_pickup("worldfx_test.missile", &"missile_tank")
	_check(
		AmbushArena.can_defeat(PackedStringArray(["armored_guard"])),
		"missiles make guards beatable"
	)


func _blocked(from: Vector2, motion: Vector2) -> bool:
	var start := Transform2D(0.0, from + Vector2(0, -2))
	return _player.test_move(start, motion)
