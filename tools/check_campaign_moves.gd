extends Node

## Scripted-input playtest of the campaign's critical moves with the real player and real rooms.
## Every case teleports into a room, grants only the listed abilities, drives Input actions frame
## by frame and asserts where the player ends up. Negative cases prove ability gates hold.
## godot --headless --path . res://tools/check_campaign_moves.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const TILE := 64.0
const ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"jump",
	&"slipstream",
	&"fire_beam",
	&"run"
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
	GameState.set_checkpoint("fringe_01", Vector2(544, 896))
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(20)
	_player = _root.get("player") as Player
	_player.set("dev_invulnerable", true)
	await _case_fringe_02_steps()
	await _case_fringe_02_tunnel()
	await _case_fringe_03_ledges()
	await _case_fringe_04_steps()
	await _case_fringe_04_bomb_floor()
	await _case_nexus_steps()
	await _case_nexus_chimney_to_fringe()
	await _case_nexus_high_jump_crack()
	await _case_vaults_01_climb()
	await _case_vaults_02_floaters()
	await _case_vaults_02_chimney()
	await _case_vaults_02_high_jump_bay()
	await _case_vaults_03_steps()
	await _case_nexus_07_door_release()
	await _case_vaults_02_shaft_curb()
	await _case_floor_drops()
	await _case_route_threats()
	_release()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"campaign-moves: %s (%d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()]
		)
	)
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


# --- cases ------------------------------------------------------------------------------------


func _case_fringe_02_steps() -> void:
	if not _wanted("fringe_02_steps"):
		return
	await _setup("fringe_02", Vector2i(23, 31), [&"slipstream"])
	await _jump(1)
	_expect_cell("fringe_02 floor -> step block", "fringe_02", Vector2i(24, 28), 1)
	await _jump(-1)
	_expect_cell("fringe_02 block -> ledge 26", "fringe_02", Vector2i(22, 25), 3)
	await _jump(-1)
	_expect_row("fringe_02 zigzag -> ledge 23", "fringe_02", 22, 10, 16)


func _case_fringe_02_tunnel() -> void:
	if not _wanted("fringe_02_tunnel"):
		return
	await _setup("fringe_02", Vector2i(25, 28), [&"slipstream"])
	await _tap(&"slipstream")
	await _frames(20)
	await _hold([&"move_right"], 70)
	_expect_room("fringe_02 ball tunnel -> fringe_03", "fringe_03")
	await _setup("fringe_02", Vector2i(25, 28), [])
	await _hold([&"move_right"], 60)
	_expect_room("fringe_02 tunnel blocks standing player", "fringe_02")


func _case_fringe_03_ledges() -> void:
	if not _wanted("fringe_03_ledges"):
		return
	await _setup("fringe_03", Vector2i(8, 14), [&"beam"])
	await _jump(-1)
	_expect_row("fringe_03 floor -> ledge A", "fringe_03", 11, 4, 6)
	await _jump(1)
	_expect_row("fringe_03 ledge A -> ledge B", "fringe_03", 8, 8, 12)
	await _jump(1)
	_expect_row("fringe_03 ledge B -> gallery", "fringe_03", 7, 12, 40)


func _case_fringe_04_steps() -> void:
	if not _wanted("fringe_04_steps"):
		return
	await _setup("fringe_04", Vector2i(13, 31), [&"slipstream", &"beam"])
	await _jump(1)
	_expect_row("fringe_04 floor -> step 29", "fringe_04", 28, 15, 25)
	await _jump(-1)
	_expect_row("fringe_04 step 29 -> step 26", "fringe_04", 25, 5, 12)
	await _jump(1)
	_expect_row("fringe_04 step 26 -> step 23", "fringe_04", 22, 15, 25)
	await _setup("fringe_04", Vector2i(11, 7), [&"slipstream"])
	await _jump(1)
	_expect_row("fringe_04 top ledge -> bombs ledge", "fringe_04", 4, 15, 25)


func _case_fringe_04_bomb_floor() -> void:
	if not _wanted("fringe_04_bomb_floor"):
		return
	await _setup("fringe_04", Vector2i(15, 31), [&"slipstream", &"bombs"])
	await _tap(&"slipstream")
	await _frames(20)
	await _tap(&"fire_beam")
	await _frames(150)
	_expect_room("fringe_04 bombed floor -> nexus_01", "nexus_01")


func _case_nexus_steps() -> void:
	if not _wanted("nexus_steps"):
		return
	await _setup("nexus_01", Vector2i(19, 31), [&"beam"])
	await _jump(1)
	_expect_row("nexus floor -> P1", "nexus_01", 28, 22, 26)
	await _jump(1)
	_expect_row("nexus P1 -> P2", "nexus_01", 25, 29, 33)
	await _jump(-1)
	_expect_row("nexus P2 -> P3", "nexus_01", 22, 22, 26)


func _case_nexus_chimney_to_fringe() -> void:
	if not _wanted("nexus_chimney"):
		return
	await _setup("nexus_01", Vector2i(15, 8), [&"slipstream", &"bombs", &"beam"])
	GameState.set_world_flag("fringe_04.gate.floor")
	await _climb(-1, 600)
	_expect_room("nexus chimney wall-jump -> fringe_04", "fringe_04")


func _case_nexus_high_jump_crack() -> void:
	if not _wanted("nexus_high_jump"):
		return
	await _setup("nexus_01", Vector2i(41, 8), [&"beam"])
	await _climb(0, 240)
	_expect_room("nexus crack blocks normal jump", "nexus_01")
	await _setup("nexus_01", Vector2i(41, 8), [&"beam", &"high_jump"])
	await _climb(0, 600)
	_expect_room("nexus crack with High Jump -> nexus_02", "nexus_02")


func _case_vaults_01_climb() -> void:
	if not _wanted("vaults_01"):
		return
	await _setup("vaults_01", Vector2i(12, 14), [&"beam"])
	await _jump(1)
	_expect_row("vaults_01 floor -> step", "vaults_01", 11, 16, 21)
	await _jump(1)
	_expect_row("vaults_01 step -> shelf", "vaults_01", 8, 22, 28)


func _case_vaults_02_floaters() -> void:
	if not _wanted("vaults_02_floaters"):
		return
	await _setup("vaults_02", Vector2i(40, 14), [&"beam", &"high_jump"])
	Input.action_press(&"run")
	await _jump(-1)
	Input.action_release(&"run")
	await _frames(60)
	if _cell().x <= 20 and _cell().y <= 14:
		_failures.append("vaults_02: a running High Jump crossed the ice chasm")
	else:
		print("  ok  vaults_02 chasm blocks a running High Jump")
	await _setup("vaults_02", Vector2i(31, 14), [&"beam", &"ice_beam", &"slipstream"])
	_player.facing = -1
	var far := _floater_near(25)
	var near := _floater_near(28)
	if far == null or near == null:
		_failures.append("vaults_02: floaters missing")
		return
	await _freeze_when_centered(far, false)
	await _freeze_when_centered(near, true)
	for hop in 3:
		await _jump(-1)
	_expect_row("vaults_02 frozen floaters -> west hall", "vaults_02", 14, 1, 20)


func _case_vaults_02_chimney() -> void:
	if not _wanted("vaults_02_chimney"):
		return
	await _setup("vaults_02", Vector2i(37, 31), [&"beam"])
	await _climb(-1, 420, 14)
	_expect_row("vaults_02 chimney -> upper band", "vaults_02", 14, 30, 45)


func _case_vaults_02_high_jump_bay() -> void:
	if not _wanted("vaults_02_high_jump"):
		return
	await _setup("vaults_02", Vector2i(50, 31), [&"beam"])
	await _climb(0, 200, 22)
	_expect_row("vaults_02 bay crack blocks normal jump", "vaults_02", 31, 40, 58)
	await _setup("vaults_02", Vector2i(50, 31), [&"beam", &"high_jump"])
	await _climb(0, 360, 22)
	_expect_row("vaults_02 High Jump crack -> antechamber", "vaults_02", 22, 44, 58)


func _case_vaults_03_steps() -> void:
	if not _wanted("vaults_03"):
		return
	await _setup("vaults_03", Vector2i(5, 14), [&"beam"])
	await _jump(-1)
	_expect_row("vaults_03 floor -> low step", "vaults_03", 11, 1, 3)
	await _jump(1)
	_expect_row("vaults_03 low step -> mid step", "vaults_03", 8, 6, 8)
	await _jump(-1)
	_expect_row("vaults_03 mid step -> entry ledge", "vaults_03", 5, 1, 4)
	await _hold([&"move_left"], 60)
	_expect_room("vaults_03 ledge -> vaults_02 antechamber", "vaults_02")


## The north-door lift (campaign_root UP_ENTRY_SPEED) carries her up into nexus_01; letting go of
## jump right after the room change used to cut it to 40 % and drop her back into nexus_07.
func _case_nexus_07_door_release() -> void:
	if not _wanted("nexus_07_door"):
		return
	for steer in [-1, 1]:
		await _setup("nexus_07", Vector2i(33, 3), [&"beam", &"high_jump"])
		Input.action_press(&"jump")
		for frame in 150:
			if frame == 8:
				Input.action_press(&"move_right" if steer > 0 else &"move_left")
			if frame == 24:
				Input.action_release(&"jump")
			await get_tree().physics_frame
			if _room() == "nexus_01" and _player.is_on_floor():
				break
		_release()
		await _frames(12)
		var label := "nexus_07 -> nexus_01 with jump released after the door (steer %d)" % steer
		_expect_row(label, "nexus_01", 31, 0, 12)


## Curbs frame the floor shaft to vaults_04 next to the Bubble Snare: walking away stops at the
## curb, a running hop clears the pit, and stepping off the curb still drops her on purpose.
func _case_vaults_02_shaft_curb() -> void:
	if not _wanted("vaults_02_curb"):
		return
	await _setup("vaults_02", Vector2i(3, 31), [&"beam", &"ice_beam"])
	await _hold([&"move_right"], 90)
	_expect_row("vaults_02 walking from the Snare stops at the curb", "vaults_02", 31, 3, 6)
	await _jump(1)
	if _room() != "vaults_02" or _cell().x < 11 or not _player.is_on_floor():
		_failures.append("vaults_02 hop over the pit: in %s at %s" % [_room(), _cell()])
	else:
		print("  ok  vaults_02 hop clears the vaults_04 pit")
	await _setup("vaults_02", Vector2i(7, 30), [&"beam", &"ice_beam"])
	await _hold([&"move_right"], 60)
	await _frames(30)
	_expect_room("vaults_02 step off the curb -> vaults_04", "vaults_04")


## Every floor opening dropped through with no input, at both ends and the middle of the door:
## where she arrives, her standing body is never inside rock. r10: vaults_05 has rock in row 1
## under its north opening, the arrival put her upper body in it, and she hung frozen in the air
## for up to 3.5 s (the same shape in vaults_04 under the other vaults_02 shaft).
func _case_floor_drops() -> void:
	if not _wanted("floor_drops"):
		return
	# kiln_04's floor opening is the top of a steam shaft that lifts her up out of kiln_02 through
	# its stack door: no one drops down it (the steam holds her), and the closed door's slab, not
	# rock, is what a forced drop lands in.
	const UPDRAFT_ONLY := ["kiln_04"]
	var before := _failures.size()
	var drops := 0
	for room_id in Rooms.ROOMS:
		for door in Rooms.ROOMS[room_id]["doors"]:
			if door["edge"] != &"south" or room_id in UPDRAFT_ONLY:
				continue
			var height: float = Vector2(Rooms.ROOMS[room_id]["size"]).y * TILE
			var from: int = Vector2i(door["from"]).x
			var to: int = Vector2i(door["to"]).x
			for x in [from * TILE + 30.0, (from + to + 1) * TILE * 0.5, (to + 1) * TILE - 30.0]:
				_release()
				_root.call("teleport", room_id, Vector2(x, height - 4.0))
				var wedged := 0
				for _frame in 60:
					await get_tree().physics_frame
					if not get_tree().paused and _room() == door["target"] and _in_rock():
						wedged += 1
				drops += 1
				if wedged > 0:
					_failures.append(
						(
							"%s drop at x %d into %s: body in rock %d frames at %s"
							% [room_id, x, door["target"], wedged, _cell()]
						)
					)
	if _failures.size() == before:
		print("  ok  %d floor drops arrive clear of rock" % drops)


## True when the standing body overlaps a rock tile of the current room.
func _in_rock() -> bool:
	var room := _root.get("current_room") as CampaignRoom
	var feet := _player.global_position - room.global_position
	var half := PlayerConfig.STANDING_WIDTH * 0.5
	var top := feet.y - PlayerConfig.STANDING_HEIGHT
	for row in range(floori((top + 1.0) / TILE), floori((feet.y - 1.0) / TILE) + 1):
		for column in range(
			floori((feet.x - half + 1.0) / TILE), floori((feet.x + half - 1.0) / TILE) + 1
		):
			if row >= 0 and room.tiles().get_cell_source_id(Vector2i(column, row)) != -1:
				return true
	return false


## A threat reaches the player where she walks: standing on the route cell, some resident enemy
## comes within REACH px in time. fringe_01 and fringe_02 come before any weapon (crawlers she
## must jump); the corridor rooms on the lower vaults route and nexus_03 hold enemies her
## arrival kit beats.
func _case_route_threats() -> void:
	if not _wanted("route_threats"):
		return
	const REACH := 160.0
	var cases := [
		["fringe_01", Vector2i(24, 14), 15.0],
		["fringe_02", Vector2i(12, 22), 15.0],
		["vaults_04", Vector2i(12, 14), 6.0],
		["vaults_05", Vector2i(8, 14), 6.0],
		["vaults_09", Vector2i(8, 14), 6.0],
		["nexus_03", Vector2i(5, 15), 6.0],
	]
	for entry in cases:
		var room_id: String = entry[0]
		var cell: Vector2i = entry[1]
		_release()
		GameState.reset_progress()
		_root.call("teleport", room_id, _feet(cell))
		var nearest := INF
		for frame in int(float(entry[2]) * 60.0):
			await get_tree().physics_frame
			var center := _player.global_position - Vector2(0.0, PlayerConfig.STANDING_HEIGHT * 0.5)
			for enemy in get_tree().get_nodes_in_group(&"campaign_enemy"):
				nearest = minf(nearest, (enemy as Node2D).global_position.distance_to(center))
		if _room() != room_id or nearest > REACH:
			_failures.append(
				(
					"%s: no enemy came within %d px of %s in %.0f s (nearest %.0f)"
					% [room_id, REACH, cell, entry[2], nearest]
				)
			)
		else:
			print("  ok  %s threat reaches %s (%.0f px)" % [room_id, cell, nearest])


# --- helpers ----------------------------------------------------------------------------------


func _wanted(name: String) -> bool:
	return _only.is_empty() or _only == name


func _setup(room_id: String, cell: Vector2i, abilities: Array[StringName]) -> void:
	_release()
	GameState.reset_progress()
	for ability in abilities:
		GameState.unlock_ability(ability)
	_root.call("teleport", room_id, _feet(cell))
	await _frames(4)
	# Movement cases isolate the geometry: only the frost floaters (platforms) stay.
	for enemy in get_tree().get_nodes_in_group(&"campaign_enemy"):
		if StringName(enemy.get("enemy_id")) != &"frost_floater":
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


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)


## Run toward `direction` until the player walks off an edge or is stopped by a wall, jump right
## there (coyote time covers the edge case), keep steering until landing, then let go.
func _jump(direction: int, jump_frames: int = 26) -> void:
	var move := &"move_right" if direction > 0 else &"move_left"
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
		if _trace:
			print(
				(
					"    f%d pos=%s vel=%s floor=%s"
					% [frame, _player.global_position, _player.velocity, _player.is_on_floor()]
				)
			)
		if not _player.is_on_floor():
			airborne = true
		elif airborne:
			break
	_release()
	await _frames(12)


## Walk until the feet cell x reaches target.x.
func _walk(direction: int, target: Vector2i) -> void:
	var move := &"move_right" if direction > 0 else &"move_left"
	Input.action_press(move)
	for frame in 120:
		await get_tree().physics_frame
		var x := _cell().x
		if (direction > 0 and x >= target.x) or (direction < 0 and x <= target.x):
			break
	_release()
	await _frames(12)


## Chimney climbing bot: jump, lean into a wall, wall-jump whenever touching one on the way down
## or near the apex. Stops when the room changes.
func _climb(first_direction: int, max_frames: int, stop_row := -1) -> void:
	var start_room := _room()
	var direction := first_direction
	var cooldown := 0
	Input.action_press(&"jump")
	await _frames(2)
	for frame in max_frames:
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
		if _room() != start_room and _player.is_on_floor():
			# Keep climbing after an upward room change until she stands in the new room;
			# stopping mid-rise can drop her straight back through the shaft.
			break
		if stop_row >= 0 and _player.is_on_floor() and _cell().y <= stop_row:
			break
		if _player.is_on_floor() and frame > 20:
			Input.action_release(&"jump")
			await get_tree().physics_frame
			Input.action_press(&"jump")
	_release()
	await _frames(30)


func _expect_cell(label: String, room_id: String, cell: Vector2i, tolerance: int) -> void:
	var actual := _cell()
	if _room() != room_id or absi(actual.x - cell.x) > tolerance or actual.y != cell.y:
		_failures.append(
			"%s: in %s at %s, expected %s at %s" % [label, _room(), actual, room_id, cell]
		)
	else:
		print("  ok  ", label)


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


func _floater_near(cell_x: int) -> Node2D:
	for enemy in get_tree().get_nodes_in_group(&"campaign_enemy"):
		if StringName(enemy.get("enemy_id")) != &"frost_floater":
			continue
		var home: Vector2 = enemy.get("_home_position")
		var room := _root.get("current_room") as Node2D
		if absf((home.x - room.global_position.x) / TILE - (cell_x + 0.5)) < 0.6:
			return enemy
	return null


## Fire the equipped Ice Beam (standing or crouched) once the floater bobs near its home spot.
func _freeze_when_centered(floater: Node2D, crouch: bool) -> void:
	var home: Vector2 = floater.get("_home_position")
	for attempt in 6:
		for frame in 240:
			if floater.global_position.distance_to(home) < 16.0:
				break
			await get_tree().physics_frame
		if crouch:
			Input.action_press(&"move_down")
			await _frames(4)
		await _tap(&"fire_beam")
		await _frames(14)
		Input.action_release(&"move_down")
		if bool(floater.get("is_frozen")):
			return
	_failures.append("vaults_02: could not freeze floater at %s" % floater.global_position)
