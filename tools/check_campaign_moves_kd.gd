extends Node

## Scripted-input playtest of every critical jump, climb and gate in the kiln and depths rooms,
## using the real player and the real generated rooms. Each case teleports to a feet cell, grants
## only the listed abilities/flags, drives Input actions frame by frame and asserts where the player
## ends up. Negative cases prove that ability gates hold. Common enemies are removed so the cases
## measure geometry, not combat.
## godot --headless --path . res://tools/check_campaign_moves_kd.tscn -- --test-mode [--case=name]

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"slipstream", &"fire_beam"
]
const BASE: Array[StringName] = [&"beam", &"slipstream", &"bombs", &"missiles"]
const BOSSES_DOWN: Array[String] = [
	"boss:stone_guardian",
	"regional:stone_guardian",
	"boss:furnace_mother",
	"regional:furnace_mother",
	"boss:tidal_heart",
]

var _root: Node
var _player: Player
var _failures: Array[String] = []
var _only := ""
var _trace := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			_only = argument.trim_prefix("--case=")
		elif argument == "--trace":
			_trace = true
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	GameState.set_checkpoint("kiln_01", _feet(Vector2i(4, 8)))
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(20)
	_player = _root.get("player") as Player
	_player.set("dev_invulnerable", true)
	await _case_kiln_01_entry_steps()
	await _case_kiln_01_pillar()
	await _case_kiln_01_crack()
	await _case_kiln_01_shrine_exit()
	await _case_kiln_02_drop()
	await _case_kiln_02_ladder()
	await _case_kiln_02_alcove()
	await _case_kiln_02_wave_door()
	await _case_kiln_03_platforms()
	await _case_kiln_03_moat()
	await _case_depths_01_chute()
	await _case_depths_01_shelf()
	await _case_depths_01_west_shaft()
	await _case_depths_01_ladder()
	await _case_depths_01_alcove()
	await _case_depths_01_undertow_door()
	await _case_depths_02_grate()
	await _case_depths_02_bridge()
	await _case_depths_02_exit()
	await _case_depths_03_climb()
	_release()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"campaign-moves-kd: %s (%d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()]
		)
	)
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


# --- kiln -------------------------------------------------------------------------------------


func _case_kiln_01_entry_steps() -> void:
	if not _wanted("kiln_01_entry"):
		return
	await _setup("kiln_01", Vector2i(8, 8), [])
	await _walk(1, Vector2i(11, 0))
	await _frames(40)
	var landed := _cell()
	_expect_true(
		"kiln_01 entrance ledge -> gallery (floor or return step)",
		landed.y in [10, 12] and landed.x >= 10 and landed.x <= 13
	)
	await _setup("kiln_01", Vector2i(14, 12), [])
	await _jump(-1, 13)
	_expect_row("kiln_01 gallery -> return step", "kiln_01", 10, 12, 13)
	await _jump(-1, 8)
	_expect_row("kiln_01 return step -> entrance ledge", "kiln_01", 8, 1, 9)


func _case_kiln_01_pillar() -> void:
	if not _wanted("kiln_01_pillar"):
		return
	await _setup("kiln_01", Vector2i(18, 12), [])
	await _jump(1, 20)
	_expect_row("kiln_01 floor -> west step", "kiln_01", 10, 20, 21)
	await _jump(1, 25)
	_expect_row("kiln_01 west step -> gargoyle pillar", "kiln_01", 7, 24, 27)
	await _setup("kiln_01", Vector2i(33, 12), [])
	await _jump(-1, 31)
	_expect_row("kiln_01 floor -> east step", "kiln_01", 10, 30, 31)
	await _jump(-1, 26)
	_expect_row("kiln_01 east step -> gargoyle pillar", "kiln_01", 7, 24, 27)


func _case_kiln_01_crack() -> void:
	if not _wanted("kiln_01_crack"):
		return
	await _setup("kiln_01", Vector2i(46, 12), [])
	var reached := await _climb_to(3, -1, 260, 1)
	_expect_true("kiln_01 crack blocks normal jump", not reached)
	await _setup("kiln_01", Vector2i(46, 12), [&"high_jump"])
	reached = await _climb_to(3, -1, 420, 1)
	_expect_true("kiln_01 crack with High Jump reaches the pocket", reached)
	_expect_true(
		"kiln_01 pocket energy tank collected",
		GameState.collected_pickup_ids.has("kiln_01.energy_01")
	)


func _case_kiln_01_shrine_exit() -> void:
	if not _wanted("kiln_01_shrine"):
		return
	await _setup("kiln_01", Vector2i(48, 12), [])
	await _walk(1, Vector2i(54, 0))
	await _frames(30)
	_expect_true("kiln_01 Pressure Seal shrine pickup", GameState.has_ability(&"pressure_seal"))
	await _jump(1)
	await _hold([&"move_right"], 50)
	_expect_room("kiln_01 shrine pit -> kiln_02", "kiln_02")


func _case_kiln_02_drop() -> void:
	if not _wanted("kiln_02_drop"):
		return
	await _setup("kiln_02", Vector2i(4, 13), [&"pressure_seal"])
	await _walk(1, Vector2i(13, 0))
	await _frames(40)
	_expect_row("kiln_02 cool ledge -> first hot ledge", "kiln_02", 16, 11, 20)
	await _walk(1, Vector2i(21, 0))
	await _hold([&"move_right"], 6)
	await _frames(60)
	_expect_row("kiln_02 drop column -> cool floor", "kiln_02", 31, 20, 23)


func _case_kiln_02_ladder() -> void:
	if not _wanted("kiln_02_ladder"):
		return
	await _setup("kiln_02", Vector2i(13, 31), [&"pressure_seal"])
	await _jump(1)
	_expect_row("kiln_02 floor -> A", "kiln_02", 28, 16, 20)
	await _jump(1)
	_expect_row("kiln_02 A -> B", "kiln_02", 25, 23, 28)
	await _jump(-1)
	_expect_row("kiln_02 B -> C", "kiln_02", 22, 11, 20)
	await _jump(1)
	_expect_row("kiln_02 C -> D", "kiln_02", 19, 23, 28)
	await _jump(-1)
	_expect_row("kiln_02 D -> E'", "kiln_02", 16, 11, 20)
	await _jump(-1)
	_expect_row("kiln_02 E' -> cool entry ledge", "kiln_02", 13, 1, 10)


func _case_kiln_02_alcove() -> void:
	if not _wanted("kiln_02_alcove"):
		return
	await _setup("kiln_02", Vector2i(13, 22), [&"pressure_seal"])
	await _walk(-1, Vector2i(11, 0))
	await _shoot()
	await _hold([&"move_left"], 60)
	_expect_row("kiln_02 alcove grate holds without Wave", "kiln_02", 22, 11, 13)
	await _setup("kiln_02", Vector2i(13, 22), [&"pressure_seal", &"wave_beam"])
	await _walk(-1, Vector2i(11, 0))
	await _shoot()
	await _hold([&"move_left"], 60)
	_expect_true(
		"kiln_02 Wave opens the alcove missile tank",
		GameState.collected_pickup_ids.has("kiln_02.missile_01")
	)


func _case_kiln_02_wave_door() -> void:
	if not _wanted("kiln_02_wave_door"):
		return
	await _setup("kiln_02", Vector2i(5, 31), [&"pressure_seal"], BOSSES_DOWN)
	await _walk(-1, Vector2i(4, 0))
	await _shoot()
	await _hold([&"move_left"], 60)
	_expect_room("kiln_02 wave door holds without Wave", "kiln_02")
	await _setup("kiln_02", Vector2i(5, 31), [&"pressure_seal", &"wave_beam"], BOSSES_DOWN)
	await _walk(-1, Vector2i(4, 0))
	await _shoot()
	await _hold([&"move_left"], 60)
	_expect_room("kiln_02 Wave opens the door -> kiln_03", "kiln_03")


func _case_kiln_03_platforms() -> void:
	if not _wanted("kiln_03_platforms"):
		return
	await _setup("kiln_03", Vector2i(12, 14), [], BOSSES_DOWN)
	await _jump(-1, 10)
	_expect_row("kiln_03 floor -> west bounce step", "kiln_03", 12, 9, 10)
	await _jump(1, 14)
	_expect_row("kiln_03 west step -> dodge platform", "kiln_03", 10, 13, 18)
	await _setup("kiln_03", Vector2i(47, 14), [], BOSSES_DOWN)
	await _jump(1, 49)
	_expect_row("kiln_03 floor -> east bounce step", "kiln_03", 12, 49, 50)
	await _jump(-1, 45)
	_expect_row("kiln_03 east step -> dodge platform", "kiln_03", 10, 41, 46)


func _case_kiln_03_moat() -> void:
	if not _wanted("kiln_03_moat"):
		return
	# Walking straight in through either door stops at the lip before the lava (kiln_03 sweep).
	for walk_in in [[Vector2i(58, 14), &"move_left"], [Vector2i(1, 14), &"move_right"]]:
		await _setup("kiln_03", walk_in[0], [], BOSSES_DOWN)
		var health := GameState.health
		await _hold([walk_in[1]], 90)
		_expect_true(
			"kiln_03 walk-in from %s stops at the lip unhurt" % walk_in[0],
			GameState.health == health and _cell().y == 14
		)
	await _setup("kiln_03", Vector2i(57, 14), [], BOSSES_DOWN)
	await _jump(-1)
	var landed := _cell()
	_expect_true(
		"kiln_03 east moat jump clears the lava",
		_room() == "kiln_03" and landed.x <= 51 and landed.y in [12, 14]
	)
	await _setup("kiln_03", Vector2i(10, 12), [], BOSSES_DOWN)
	await _walk(-1, Vector2i(8, 0))
	await _jump(-1)
	_expect_row("kiln_03 west moat jump", "kiln_03", 14, 1, 4)
	await _hold([&"move_left"], 60)
	_expect_room("kiln_03 opened shortcut -> nexus_01", "nexus_01")


# --- depths -----------------------------------------------------------------------------------


func _case_depths_01_chute() -> void:
	if not _wanted("depths_01_chute"):
		return
	await _setup("depths_01", Vector2i(15, 3), [&"high_jump"])
	await _frames(60)
	_expect_row("depths_01 hub chute -> landing shelf", "depths_01", 9, 12, 18)
	for flag in BOSSES_DOWN:
		GameState.set_world_flag(flag)
	var reached := await _climb_to(-1, 0, 420, 1)
	_expect_true("depths_01 shelf -> chute climb back to the hub", reached)


func _case_depths_01_shelf() -> void:
	if not _wanted("depths_01_shelf"):
		return
	await _setup("depths_01", Vector2i(25, 13), [])
	await _jump(-1, 22)
	_expect_row("depths_01 floor -> step", "depths_01", 11, 21, 22)
	await _jump(-1, 17)
	_expect_row("depths_01 step -> landing shelf", "depths_01", 9, 12, 18)


func _case_depths_01_west_shaft() -> void:
	if not _wanted("depths_01_west_shaft"):
		return
	await _setup("depths_01", Vector2i(7, 13), [&"high_jump"])
	await _walk(-1, Vector2i(3, 0))
	await _frames(80)
	_expect_row("depths_01 west shaft drop -> lower chamber", "depths_01", 31, 1, 8)
	# Its mouth is 10 rows above the lower floor: the way back up is the east ladder, or a skilled
	# single-wall climb up the room wall into the shaft (the real wall jump allows it).
	await _setup("depths_01", Vector2i(3, 31), [&"high_jump"])
	var reached := await _climb_to(13, 1, 420, -1)
	_expect_true("depths_01 west shaft: skilled wall climb back up", reached)
	_expect_row("depths_01 west shaft exit -> upper floor", "depths_01", 13, 5, 12)


func _case_depths_01_ladder() -> void:
	if not _wanted("depths_01_ladder"):
		return
	await _setup("depths_01", Vector2i(27, 31), [])
	await _jump(1)
	_expect_row("depths_01 floor -> La", "depths_01", 28, 29, 33)
	await _jump(1)
	_expect_row("depths_01 La -> Lb", "depths_01", 25, 36, 40)
	await _jump(-1)
	_expect_row("depths_01 Lb -> Lc", "depths_01", 22, 29, 33)
	await _jump(1)
	_expect_row("depths_01 Lc -> Ld", "depths_01", 19, 36, 40)
	await _jump(-1)
	_expect_row("depths_01 Ld -> Le", "depths_01", 16, 29, 33)
	await _jump(1)
	_expect_row("depths_01 Le -> upper floor east", "depths_01", 13, 36, 40)


func _case_depths_01_alcove() -> void:
	if not _wanted("depths_01_alcove"):
		return
	await _setup("depths_01", Vector2i(38, 19), [&"high_jump"])
	await _jump(1)
	await _hold([&"move_right"], 30)
	_expect_true(
		"depths_01 undertow barrier holds without Undertow Dash",
		not GameState.collected_pickup_ids.has("depths_01.missile_01")
	)
	await _setup("depths_01", Vector2i(38, 19), [&"high_jump", &"undertow_dash"])
	await _jump(1)
	await _dash_hold(1, 30)
	_expect_true(
		"depths_01 Undertow Dash opens the alcove",
		GameState.collected_pickup_ids.has("depths_01.missile_01")
	)


func _case_depths_01_undertow_door() -> void:
	if not _wanted("depths_01_undertow_door"):
		return
	await _setup("depths_01", Vector2i(37, 31), [&"high_jump"], BOSSES_DOWN)
	await _jump(1)
	await _hold([&"move_right"], 60)
	_expect_room("depths_01 undertow door holds without Undertow Dash", "depths_01")
	await _setup("depths_01", Vector2i(37, 31), [&"high_jump", &"undertow_dash"], BOSSES_DOWN)
	await _jump(1)
	await _dash_hold(1, 60)
	_expect_room("depths_01 Undertow Dash opens the door -> depths_02", "depths_02")


func _case_depths_02_grate() -> void:
	if not _wanted("depths_02_grate"):
		return
	await _setup("depths_02", Vector2i(5, 14), [])
	await _frames(10)
	var grate := get_tree().get_first_node_in_group(&"projectile_grate") as Node2D
	var room := _root.get("current_room") as Node2D
	if grate == null:
		_failures.append("depths_02 relay grate missing")
		return
	var local := grate.global_position - room.global_position
	var size: Vector2 = grate.get("grate_size")
	var bottom := local.y + size.y * 0.5
	_expect_true(
		"depths_02 relay grate stands on the bridge (bottom %.0f)" % bottom,
		absf(bottom - 11.0 * TILE) < 2.0 and local.x > 22.0 * TILE and local.x < 30.0 * TILE
	)


func _case_depths_02_bridge() -> void:
	if not _wanted("depths_02_bridge"):
		return
	await _setup("depths_02", Vector2i(15, 14), [], BOSSES_DOWN)
	await _jump(1, 18)
	_expect_row("depths_02 floor -> west step", "depths_02", 12, 18, 19)
	await _jump(1, 23)
	_expect_row("depths_02 west step -> relay bridge", "depths_02", 10, 22, 29)
	await _setup("depths_02", Vector2i(37, 14), [], BOSSES_DOWN)
	await _jump(-1, 34)
	_expect_row("depths_02 floor -> east step", "depths_02", 12, 33, 34)
	await _jump(-1, 28)
	_expect_row("depths_02 east step -> relay bridge", "depths_02", 10, 22, 29)


func _case_depths_02_exit() -> void:
	if not _wanted("depths_02_exit"):
		return
	var flags: Array[String] = ["boss:stone_guardian", "boss:furnace_mother"]
	await _setup("depths_02", Vector2i(38, 14), [], flags)
	await _hold([&"move_right"], 60)
	_expect_room("depths_02 sealed until the Tidal Heart falls", "depths_02")
	await _setup("depths_02", Vector2i(38, 14), [], BOSSES_DOWN)
	await _hold([&"move_right"], 120)
	_expect_room("depths_02 opened seal -> depths_03", "depths_03")


func _case_depths_03_climb() -> void:
	if not _wanted("depths_03_climb"):
		return
	await _setup("depths_03", Vector2i(20, 31), [&"high_jump"], BOSSES_DOWN)
	await _jump(1)
	_expect_row("depths_03 floor -> A", "depths_03", 28, 22, 28)
	await _jump(-1)
	_expect_row("depths_03 A -> B", "depths_03", 25, 12, 19)
	await _jump(1)
	_expect_row("depths_03 B -> C", "depths_03", 22, 22, 28)
	await _jump(-1)
	_expect_row("depths_03 C -> D", "depths_03", 19, 12, 19)
	# Start the throat climb centred under it (a player lines up the same way).
	await _setup("depths_03", Vector2i(15, 19), [&"high_jump"], BOSSES_DOWN)
	var reached := await _climb_to(7, 1, 480, 1)
	_expect_true("depths_03 throat climb -> surface grotto", reached)
	await _frames(20)
	_expect_row("depths_03 throat exit -> grotto floor", "depths_03", 7, 17, 20)
	await _jump(1)
	await _hold([&"move_right"], 30)
	_expect_true("depths_03 light altar starts the ending", bool(_root.get("_ending")))


# --- helpers ----------------------------------------------------------------------------------


func _wanted(name: String) -> bool:
	return _only.is_empty() or name.begins_with(_only) or _only == name


func _setup(
	room_id: String, cell: Vector2i, abilities: Array[StringName], flags: Array[String] = []
) -> void:
	_release()
	GameState.reset_progress()
	for ability in BASE + abilities:
		GameState.unlock_ability(ability)
	GameState.collect_pickup("moves_kd.missile", &"missile_tank")
	for flag in flags:
		GameState.set_world_flag(flag)
	_root.call("teleport", room_id, _feet(cell))
	await _frames(4)
	for enemy in get_tree().get_nodes_in_group(&"campaign_enemy"):
		enemy.queue_free()
	await _frames(26)


func _feet(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)


func _cell() -> Vector2i:
	var room := _root.get("current_room") as Node2D
	var local := _player.global_position - room.global_position
	return Vector2i(floori(local.x / TILE), floori((local.y - 1.0) / TILE))


func _room() -> String:
	return String(_root.get("current_room_id"))


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame


func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func _hold(actions: Array[StringName], frames: int) -> void:
	for action in actions:
		Input.action_press(action)
	await _frames(frames)
	for action in actions:
		Input.action_release(action)


## Walk toward `direction` and tap the Undertow Dash every few frames (D19 undertow barriers).
func _dash_hold(direction: int, frames: int) -> void:
	var move := &"move_right" if direction > 0 else &"move_left"
	Input.action_press(move)
	for frame in frames:
		if frame % 12 == 0:
			Input.action_press(&"dash")
		elif frame % 12 == 1:
			Input.action_release(&"dash")
		await get_tree().physics_frame
	Input.action_release(&"dash")
	Input.action_release(move)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)


func _shoot() -> void:
	await _tap(&"fire_beam")
	await _frames(40)


## Run toward `direction` until the player walks off an edge or is stopped by a wall, jump right
## there (coyote time covers the edge case), keep steering until landing, then let go. With
## `stop_x` the bot stops steering and brakes once the feet pass that column (short targets).
func _jump(direction: int, stop_x: int = -1, jump_frames: int = 26) -> void:
	var move := &"move_right" if direction > 0 else &"move_left"
	var brake := &"move_left" if direction > 0 else &"move_right"
	if direction != 0:
		Input.action_press(move)
		var blocked := 0
		for frame in 90:
			await get_tree().physics_frame
			if not _player.is_on_floor():
				break
			blocked = blocked + 1 if absf(_player.velocity.x) < 1.0 and frame > 4 else 0
			if blocked > 2:
				break
	Input.action_press(&"jump")
	var airborne := false
	for frame in 150:
		await get_tree().physics_frame
		if frame == jump_frames:
			Input.action_release(&"jump")
		if stop_x >= 0 and direction != 0:
			var past := _cell().x >= stop_x if direction > 0 else _cell().x <= stop_x
			if past:
				# Over the target: let go and brake so the landing is on the ledge, as a player would.
				Input.action_release(move)
				if absf(_player.velocity.x) > 60.0 and signf(_player.velocity.x) == direction:
					Input.action_press(brake)
				else:
					Input.action_release(brake)
		if _trace:
			print("    f%d cell=%s vel=%s" % [frame, _cell(), _player.velocity])
		if not _player.is_on_floor():
			airborne = true
		elif airborne:
			break
	_release()
	await _frames(12)


## Walk until the feet cell x reaches target.x (or the player stops).
func _walk(direction: int, target: Vector2i) -> void:
	var move := &"move_right" if direction > 0 else &"move_left"
	Input.action_press(move)
	for frame in 150:
		await get_tree().physics_frame
		var x := _cell().x
		if (direction > 0 and x >= target.x) or (direction < 0 and x <= target.x):
			break
	_release()
	await _frames(12)


## Chimney-climbing bot: jump straight up, lean toward `lean` near the apex, wall-jump whenever touching a wall on the
## way down or near the apex. Once the feet reach `target_row` (or the room changes) it steers toward
## `exit_direction` to step off onto the ledge. Returns whether the target row was reached.
func _climb_to(target_row: int, exit_direction: int, max_frames: int, lean := 0) -> bool:
	var start_room := _room()
	var direction := 0
	var cooldown := 0
	var reached := false
	Input.action_press(&"jump")
	await _frames(2)
	for frame in max_frames:
		if frame == 12 and direction == 0:
			direction = lean
		if _room() != start_room or _cell().y <= target_row:
			reached = true
			break
		var wall := int(_player.get("_wall_side"))
		Input.action_release(&"move_left")
		Input.action_release(&"move_right")
		cooldown = maxi(cooldown - 1, 0)
		if (
			cooldown == 0
			and wall != 0
			and _player.velocity.y > -250.0
			and not _player.is_on_floor()
		):
			cooldown = 10
			Input.action_release(&"jump")
			await get_tree().physics_frame
			Input.action_press(&"jump")
			direction = -wall
		if direction != 0:
			Input.action_press(&"move_right" if direction > 0 else &"move_left")
		await get_tree().physics_frame
		if _trace:
			print("    c%d cell=%s vel=%s wall=%d" % [frame, _cell(), _player.velocity, wall])
		if _player.is_on_floor() and frame > 20:
			Input.action_release(&"jump")
			await get_tree().physics_frame
			Input.action_press(&"jump")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if reached and exit_direction != 0:
		await _hold([&"move_right" if exit_direction > 0 else &"move_left"], 40)
	_release()
	await _frames(30)
	return reached


func _expect_true(label: String, condition: bool) -> void:
	if condition:
		print("  ok  ", label)
	else:
		_failures.append("%s: in %s at %s" % [label, _room(), _cell()])


func _expect_row(label: String, room_id: String, row: int, min_x: int, max_x: int) -> void:
	var actual := _cell()
	if _room() != room_id or actual.y != row or actual.x < min_x or actual.x > max_x:
		_failures.append(
			(
				"%s: in %s at %s, expected %s row %d x %d..%d"
				% [label, _room(), actual, room_id, row, min_x, max_x]
			)
		)
	else:
		print("  ok  ", label)


func _expect_room(label: String, room_id: String) -> void:
	if _room() != room_id:
		_failures.append("%s: in %s at %s, expected %s" % [label, _room(), _cell(), room_id])
	else:
		print("  ok  ", label)
