extends RefCounted
## Playtest agent input programs (docs/features/playtest-agent.md, "Candidates"): each builder
## returns one Array of held input actions per physics frame, and `Driver` plays a program through
## Input.parse_input_event, exactly like a pad, so the agent never moves the player or sets any
## state directly.

const STEP_FRAMES := 12
const JUMP_HOLD_FRAMES := 20
const JUMP_TAIL_FRAMES := 8
const NEAR_TARGET := 24.0
## Ball form rolls at most 580 px/s (PlayerConfig.ROLL_MAX), a little under 10 px per frame.
const ROLL_PX_PER_FRAME := 9.0
## Frames to wait for the 0.12 s Slipstream curl (PlayerConfig.SLIP_DURATION) to finish.
const SLIP_FRAMES := 9
## Presses the Driver sends after the player's physics step instead of before it. A press sent
## before the player counts twice for her: once as just pressed in that frame, and once more from
## her queued `_input` press in the next frame (measured in tools/check_playtest_round3.gd). Only
## the beam cycle has no cooldown to absorb the second one, so one tap would step two beams.
const LATE_PRESSES: Array[StringName] = [&"cycle_beam"]


## A walking program toward `rel`, jumping when a wall blocks the way or the target is above.
static func steer(player: Player, rel: Vector2, running: bool) -> Array:
	var direction := _sign(rel.x) if absf(rel.x) > NEAR_TARGET else 0
	var blocked := (
		direction != 0 and player.test_move(player.global_transform, Vector2(direction * 24, 0))
	)
	var above := rel.y < -96.0 and absf(rel.x) < 420.0
	if player.is_on_floor() and (blocked or above):
		return jump(direction, JUMP_HOLD_FRAMES)
	if not player.is_on_floor() and player.is_on_wall() and rel.y < -64.0:
		return wall_jump(player.facing)
	if direction == 0:
		return idle()
	return run(direction, STEP_FRAMES) if running else walk(direction, STEP_FRAMES)


## Face `direction`, hold the aim and tap `fire` once (three frames down, three up).
static func shoot(direction: int, aim: String, fire: StringName, facing: int) -> Array:
	var frames: Array = []
	var move := move_action(direction)
	if direction != 0 and direction != facing:
		frames.append_array(hold([move], 2))
	var held: Array = []
	match aim:
		"up":
			held = [&"move_up"]
		"diag_up":
			held = [&"move_up", move]
		"down":
			held = [&"move_down"]
		"diag_down":
			held = [&"move_down", move]
	frames.append_array(hold(held + [fire], 3))
	frames.append_array(hold(held, 3))
	return frames


## Face `direction`, jump, and tap `fire_beam` level at `fire_frame` (see Aim.jump_fire_frame).
static func jump_shoot(direction: int, fire_frame: int, facing: int) -> Array:
	var frames: Array = []
	if direction != facing:
		frames.append_array(hold([move_action(direction)], 2))
	frames.append_array(hold([&"jump"], fire_frame - 1))
	frames.append_array(hold([&"jump", &"fire_beam"], 3))
	frames.append_array(hold([&"jump"], 3))
	return frames


## Tap `cycle_beam` `steps` times (mod `count`): three frames down, three up per tap.
static func cycle_beam(steps: int, count: int) -> Array:
	var frames: Array = []
	for _tap in posmod(steps, count):
		frames.append_array(hold([&"cycle_beam"], 3))
		frames.append_array(hold([], 3))
	return frames


## Curl into Slipstream form, roll toward the target `dx` px away, drop a Resonance Pulse
## (`fire_beam` in ball form), roll back out of its reach and stand up again.
static func pulse(dx: float, in_ball: bool) -> Array:
	var toward := _sign(dx)
	var frames: Array = []
	if not in_ball:
		frames.append_array(hold([&"slipstream"], 2))
		frames.append_array(hold([], SLIP_FRAMES))
	var roll := clampi(int((absf(dx) - 64.0) / ROLL_PX_PER_FRAME), 0, 30)
	frames.append_array(hold([move_action(toward)], roll))
	frames.append_array(hold([&"fire_beam"], 3))
	frames.append_array(hold([move_action(-toward)], 24))
	frames.append_array(hold([&"slipstream"], 2))
	frames.append_array(hold([], SLIP_FRAMES))
	return frames


static func idle() -> Array:
	return hold([], 6)


static func walk(direction: int, frames: int) -> Array:
	return hold([move_action(direction)], frames)


static func run(direction: int, frames: int) -> Array:
	if direction == 0:
		return idle()
	return hold([move_action(direction), &"run"], frames)


static func jump(direction: int, hold: int) -> Array:
	var held: Array = [&"jump"]
	if direction != 0:
		held.append(move_action(direction))
	var frames := hold(held, hold)
	frames.append_array(hold([move_action(direction)] if direction != 0 else [], JUMP_TAIL_FRAMES))
	return frames


static func dash(direction: int) -> Array:
	var move := move_action(direction)
	var frames := hold([move, &"dash"], 3)
	frames.append_array(hold([move], 9))
	return frames


## Push into the wall being clung to, then jump away from it and steer back toward it.
static func wall_jump(facing: int) -> Array:
	var wall := -facing
	var frames := hold([move_action(wall)], 3)
	frames.append_array(hold([&"jump", move_action(-wall)], 8))
	frames.append_array(hold([&"jump", move_action(wall)], 10))
	return frames


static func move_action(direction: int) -> StringName:
	return &"move_left" if direction < 0 else &"move_right"


static func hold(held: Array, count: int) -> Array:
	var frames: Array = []
	for _index in count:
		frames.append(held.duplicate())
	return frames


static func _sign(value: float) -> int:
	return -1 if value < 0.0 else 1


## Plays programs frame by frame. Only presses and releases input actions.
class Driver:
	extends RefCounted

	var program: Array = []
	var frame := 0
	var _held: Dictionary = {}

	func start(next: Array) -> void:
		program = next
		frame = 0

	func done() -> bool:
		return frame >= program.size()

	## Applies the next frame's held set; call once per physics frame before the player runs.
	func step() -> void:
		var wanted: Array = program[frame] if frame < program.size() else []
		frame += 1
		for action in _held.keys():
			if not wanted.has(action):
				_send(action, false)
		for action in wanted:
			if _held.has(action):
				continue
			if action in LATE_PRESSES:
				# Deferred calls run when the physics step ends, after the player has moved.
				_held[action] = true
				_send_late.call_deferred(action)
			else:
				_send(action, true)
		Input.flush_buffered_events()

	func release_all() -> void:
		for action in _held.keys():
			_send(action, false)
		Input.flush_buffered_events()
		program = []
		frame = 0

	func held() -> Array:
		return _held.keys()

	func _send_late(action: StringName) -> void:
		if _held.has(action):
			_send(action, true)
			Input.flush_buffered_events()

	func _send(action: StringName, pressed: bool) -> void:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		if pressed:
			_held[action] = true
		else:
			_held.erase(action)
