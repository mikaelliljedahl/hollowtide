extends Node

## Real-input proof of the intended sequence breaks (docs/features/sequence-breaks.md): each break
## route is driven with Input actions on the real player in the real generated room, collects its
## reward, and the moves the intended route uses (plain jumps, the Updraft Cloak, its glide) are shown
## not to reach that reward. The graph solver (tools/campaign_breaks.py) proves the rewards are out of
## reach of every intended move in every progression stage; this check proves the breaks are real.
## godot --headless --path . res://tools/check_sequence_breaks.tscn -- --test-mode [--case=name]

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const TILE := 64.0
## Frames after a ground jump before the climb leans into the wall (clears a pillar's overhang).
const LEAN_DELAY_FRAMES := 8
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"run", &"dash"
]
## Break rewards: pickup id -> [room, cell]. Mirrors BREAKS in tools/campaign_breaks.py.
const REWARDS := {
	"fringe_01.missile_ledge": ["fringe_01", Vector2i(2, 6)],
	"vaults_02.energy_pillar": ["vaults_02", Vector2i(17, 21)],
	"depths_01.energy_corridor": ["depths_01", Vector2i(25, 19)],
}

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
	GameState.set_checkpoint("fringe_01", _feet(Vector2i(8, 13)))
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(20)
	_player = _root.get("player") as Player
	_player.set("dev_invulnerable", true)
	_check_reward_placement()
	await _case_breach_ledge()
	await _case_pillar_ledge()
	await _case_pillar_band()
	await _case_undertow_gap()
	_release()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"sequence-breaks: %s (%d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()]
		)
	)
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


# --- cases ------------------------------------------------------------------------------------


## Every reward is one generated pickup, in its break room only, at the break's cell.
func _check_reward_placement() -> void:
	for reward: String in REWARDS:
		var found: Array[String] = []
		for room_id: String in Rooms.ROOMS:
			for pickup: Dictionary in Rooms.ROOMS[room_id]["pickups"]:
				if pickup["id"] == reward:
					found.append("%s %s" % [room_id, pickup["cell"]])
		var expected := "%s %s" % [REWARDS[reward][0], REWARDS[reward][1]]
		_expect_true("%s placed once at %s" % [reward, expected], found == [expected])


func _case_breach_ledge() -> void:
	if not _wanted("breach_ledge"):
		return
	# Intended moves: a plain jump and the Updraft Cloak jump against the wall fall short.
	for abilities: Array[StringName] in [
		[] as Array[StringName], [&"high_jump"] as Array[StringName]
	]:
		await _setup("fringe_01", Vector2i(5, 13), abilities)
		await _hop_against(-1, 3)
		_expect_true(
			"fringe_01 ledge out of reach of a jump (abilities %s)" % [abilities],
			not _has("fringe_01.missile_ledge")
		)
	await _setup("fringe_01", Vector2i(5, 13), [])
	var reached := await _wall_climb(
		-1, 600, func() -> bool: return _has("fringe_01.missile_ledge")
	)
	_expect_true("fringe_01 single-wall climb reaches the ledge Bolt Quiver", reached)
	_expect_true(
		"fringe_01 ledge grants the Harpoon before the Seed Crossbow",
		GameState.has_missiles and not GameState.has_beam
	)
	await _frames(20)
	_expect_row("fringe_01 she stands in the ledge niche", "fringe_01", 6, 1, 4)


func _case_pillar_ledge() -> void:
	if not _wanted("pillar_ledge"):
		return
	for abilities: Array[StringName] in [
		[] as Array[StringName], [&"high_jump"] as Array[StringName]
	]:
		await _setup("vaults_02", Vector2i(16, 31), abilities)
		await _hop_against(1, 3)
		_expect_true(
			"vaults_02 pillar ledge out of reach of a jump (abilities %s)" % [abilities],
			not _has("vaults_02.energy_pillar")
		)
	await _setup("vaults_02", Vector2i(16, 31), [])
	var reached := await _wall_climb(1, 600, func() -> bool: return _has("vaults_02.energy_pillar"))
	_expect_true("vaults_02 west-face climb reaches the pillar Heart Pearl", reached)


func _case_pillar_band() -> void:
	if not _wanted("pillar_band"):
		return
	await _setup("vaults_02", Vector2i(21, 31), [&"beam", &"slipstream", &"missiles"])
	var reached := await _wall_climb(
		-1, 900, func() -> bool: return _player.is_on_floor() and _cell().y <= 14
	)
	_expect_true("vaults_02 east-face climb tops the chasm edge", reached)
	_expect_row("vaults_02 she stands on the upper band west of the chasm", "vaults_02", 14, 1, 20)
	await _walk(-1, Vector2i(6, 0))
	await _frames(30)
	_expect_true(
		"vaults_02 Updraft Cloak collected before the Bubble Snare",
		GameState.has_ability(&"high_jump") and not GameState.has_ability(&"ice_beam")
	)


func _case_undertow_gap() -> void:
	if not _wanted("undertow_gap"):
		return
	var base: Array[StringName] = [&"beam", &"slipstream", &"missiles", &"high_jump"]
	await _setup("depths_01", Vector2i(7, 19), base)
	await _gap_run(false, true)
	_expect_true(
		"depths_01 a running hop and Cloak glide fall into the gap",
		not _has("depths_01.energy_corridor") and _cell().y > 19
	)
	var with_dash: Array[StringName] = base.duplicate()
	with_dash.append(&"undertow_dash")
	await _setup("depths_01", Vector2i(7, 19), with_dash)
	await _gap_run(true, false)
	_expect_row(
		"depths_01 hop and air Undertow Dash (no glide) land on the far ledge",
		"depths_01",
		19,
		23,
		26
	)
	await _walk(1, Vector2i(26, 0))
	_expect_true(
		"depths_01 far ledge holds the corridor Heart Pearl", _has("depths_01.energy_corridor")
	)


# --- movement bots ----------------------------------------------------------------------------


## Jump `hops` times while holding toward a wall, never wall-jumping: the intended moves only.
func _hop_against(direction: int, hops: int) -> void:
	Input.action_press(&"move_right" if direction > 0 else &"move_left")
	for hop in hops:
		Input.action_press(&"jump")
		for frame in 90:
			await get_tree().physics_frame
			if frame > 4 and _player.is_on_floor():
				break
		Input.action_release(&"jump")
		await _frames(2)
	_release()
	await _frames(20)


## Single-wall climb as a player does it: jump straight up beside the wall, lean into it once the
## head clears any overhang at its foot; while touching it near the apex or on the way down,
## wall-jump. The input lock pushes her out, then she steers back and repeats. Over the wall top
## the held direction carries her onto the ledge. Stops when `done`.
func _wall_climb(wall_direction: int, max_frames: int, done: Callable) -> bool:
	var toward := &"move_right" if wall_direction > 0 else &"move_left"
	var cooldown := 0
	var since_ground_jump := 0
	Input.action_press(&"jump")
	var reached := false
	for frame in max_frames:
		await get_tree().physics_frame
		if done.call():
			reached = true
			break
		cooldown = maxi(cooldown - 1, 0)
		since_ground_jump += 1
		if since_ground_jump == LEAN_DELAY_FRAMES:
			Input.action_press(toward)
		var wall := int(_player.get("_wall_side"))
		var airborne := not _player.is_on_floor()
		if cooldown == 0 and airborne and wall == wall_direction and _player.velocity.y > -250.0:
			cooldown = 12
			Input.action_release(&"jump")
			await get_tree().physics_frame
			Input.action_press(&"jump")
		elif not airborne and frame > 10 and cooldown == 0:
			cooldown = 12
			since_ground_jump = 0
			Input.action_release(toward)
			Input.action_release(&"jump")
			await get_tree().physics_frame
			Input.action_press(&"jump")
		if _trace:
			print("    w%d cell=%s vel=%s wall=%d" % [frame, _cell(), _player.velocity, wall])
	_release()
	await _frames(20)
	return reached or done.call()


## Run east along the depths corridor runway and hop at the edge (coyote time). With `glide` jump
## stays held through the flight (the Cloak glide), else it is let go after the hop; with `dash`,
## the Undertow Dash is tapped right after takeoff.
func _gap_run(dash: bool, glide: bool) -> void:
	Input.action_press(&"run")
	Input.action_press(&"move_right")
	for frame in 120:
		await get_tree().physics_frame
		if not _player.is_on_floor():
			break
	Input.action_press(&"jump")
	for frame in 150:
		await get_tree().physics_frame
		if dash and frame == 3:
			Input.action_press(&"dash")
		elif frame == 5:
			Input.action_release(&"dash")
			if not glide:
				Input.action_release(&"jump")
		if _trace:
			print("    g%d cell=%s vel=%s" % [frame, _cell(), _player.velocity])
		if frame > 6 and _player.is_on_floor():
			break
	_release()
	await _frames(30)


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
	# The breaks are movement routes; enemies are removed so the cases measure geometry.
	for enemy in get_tree().get_nodes_in_group(&"campaign_enemy"):
		enemy.queue_free()
	await _frames(26)


func _has(pickup_id: String) -> bool:
	return GameState.collected_pickup_ids.has(pickup_id)


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


## Walk until the feet cell x reaches target.x (or the player stops).
func _walk(direction: int, target: Vector2i) -> void:
	var move := &"move_right" if direction > 0 else &"move_left"
	Input.action_press(move)
	for frame in 180:
		await get_tree().physics_frame
		var x := _cell().x
		if (direction > 0 and x >= target.x) or (direction < 0 and x <= target.x):
			break
	_release()
	await _frames(12)


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
