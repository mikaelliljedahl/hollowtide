extends RefCounted
## Playtest agent input programs (docs/features/playtest-agent.md, "Candidates"): each builder
## returns one Array of held input actions per physics frame, and `Driver` plays a program through
## Input.parse_input_event, exactly like a pad, so the agent never moves the player or sets any
## state directly.

const Hazards = preload("res://tools/playtest_hazards.gd")
const STEP_FRAMES := 12
const JUMP_HOLD_FRAMES := 20
const JUMP_TAIL_FRAMES := 8
const NEAR_TARGET := 24.0
## A ceiling this close (px) above the head makes a jump toward a target above pointless; the
## steer looks this far (px) to either side for open sky instead.
const CEILING_PROBE := 96.0
const CEILING_SCAN := 512
const TILE_PX := 64
## How far ahead (px) the steer looks for floor lava or fire to jump.
const HAZARD_LOOK := 48.0
## Ball form rolls at most 580 px/s (PlayerConfig.ROLL_MAX), a little under 10 px per frame.
const ROLL_PX_PER_FRAME := 9.0
## Frames to wait for the 0.12 s Slipstream curl (PlayerConfig.SLIP_DURATION) to finish.
const SLIP_FRAMES := 9
## Frames a duck stays curled: a 380 px/s ember 300 px away has passed by then.
const DUCK_FRAMES := 45
## Presses the Driver sends after the player's physics step instead of before it. A press sent
## before the player counts twice for her: once as just pressed in that frame, and once more from
## her queued `_input` press in the next frame (measured in tools/check_playtest_round3.gd). Only
## the beam cycle has no cooldown to absorb the second one, so one tap would step two beams.
const LATE_PRESSES: Array[StringName] = [&"cycle_beam", &"jump"]
## Candidate kinds that need a standing body: a curled player stands up first (`StandFirst`).
const STANDING_KINDS := [
	"approach",
	"retreat",
	"shoot",
	"jump_shoot",
	"crouch_shot",
	"harpoon",
	"open_boss",
	"select_beam",
	"jump_over",
	"go_to_refill",
	"idle",
]


## A walking program toward `rel`, jumping when a wall blocks the way or the target is above.
static func steer(player: Player, rel: Vector2, running: bool) -> Array:
	var direction := _sign(rel.x) if absf(rel.x) > NEAR_TARGET else 0
	var blocked := (
		direction != 0 and player.test_move(player.global_transform, Vector2(direction * 24, 0))
	)
	var above := rel.y < -96.0 and absf(rel.x) < 420.0
	if player.is_on_floor() and above and not blocked:
		var out := _ceiling_exit(player, rel.x)
		if out != 0:
			return run(out, STEP_FRAMES)
	if player.is_on_floor() and (blocked or above or _floor_hazard_ahead(player, direction)):
		return jump(direction, JUMP_HOLD_FRAMES)
	if not player.is_on_floor() and player.is_on_wall() and rel.y < -64.0:
		return wall_jump(player.facing)
	if direction == 0:
		return idle()
	return run(direction, STEP_FRAMES) if running else walk(direction, STEP_FRAMES)


## True when the next step toward `direction` would put the body into lava or fire on the floor
## that it does not touch yet: the steer jumps it. Jev walked the kiln_03 refill trip through the
## two-tile lava pit each time (up to 27 damage per attempt).
static func _floor_hazard_ahead(player: Player, direction: int) -> bool:
	if direction == 0:
		return false
	var body := Hazards.body_rect(player)
	var ahead := Rect2(body.position + Vector2(direction * HAZARD_LOOK, 0), body.size)
	var tree := player.get_tree()
	for hazard in Hazards.near(tree, ahead, 0.0, true):
		if hazard["kind"] in ["lava", "fire"] and Hazards.gap(body, hazard["rect"]) > 0.0:
			return true
	return false


## Under a low ceiling a jump only bumps it: the side (-1 or 1) of the nearest open sky within
## CEILING_SCAN px, preferring the target's side on a tie; 0 when the sky is open or none is near.
static func _ceiling_exit(player: Player, toward: float) -> int:
	var at := player.global_transform
	if not player.test_move(at, Vector2(0, -CEILING_PROBE)):
		return 0
	var first := _sign(toward) if absf(toward) > NEAR_TARGET else 1
	for offset in range(TILE_PX, CEILING_SCAN + 1, TILE_PX):
		for side in [first, -first]:
			var shift := Vector2(side * offset, 0)
			if player.test_move(at, shift):
				continue
			if not player.test_move(at.translated(shift), Vector2(0, -CEILING_PROBE)):
				return side
	return 0


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


## Curl into ball form where she stands, stay curled while a shot passes over, stand up again.
static func duck() -> Array:
	var frames := hold([&"slipstream"], 2)
	frames.append_array(hold([], SLIP_FRAMES + DUCK_FRAMES))
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


## Stands a curled player up (one Slipstream tap, then the curl's frames) before `program`, which
## may be an Array or a live program. A curl whose stand-up tap came during a hit's input lock
## left her rolling in ball form, where no shot is offered, for 110 s in a Cinder Warden probe.
class StandFirst:
	extends RefCounted

	var finished := false
	var _program: Variant
	var _frame := 0

	func _init(program: Variant) -> void:
		_program = program

	func next() -> Array:
		_frame += 1
		if _frame <= 2:
			return [&"slipstream"]
		if _frame <= 2 + SLIP_FRAMES:
			return []
		var index := _frame - 3 - SLIP_FRAMES
		if _program is Array:
			finished = index >= (_program as Array).size() - 1
			return _program[index] if index < (_program as Array).size() else []
		var held: Array = _program.call(&"next")
		finished = bool(_program.get("finished"))
		return held


## Plays programs frame by frame: an Array of held-action sets, or a live program that decides
## each frame (an object with `next() -> Array` and a `finished` flag, as tools/playtest_nav.gd's
## Follow). Only presses and releases input actions.
class Driver:
	extends RefCounted

	var program: Variant = []
	var frame := 0
	var _held: Dictionary = {}

	func start(next: Variant) -> void:
		program = next
		frame = 0

	func done() -> bool:
		if program is Array:
			return frame >= (program as Array).size()
		return bool(program.get("finished"))

	## Applies the next frame's held set; call once per physics frame before the player runs.
	## `lean` (move_left or move_right) is added to a frame that holds no sideways move.
	func step(lean: StringName = &"") -> void:
		var wanted: Array = []
		if program is Array:
			wanted = program[frame] if frame < (program as Array).size() else []
		elif not bool(program.get("finished")):
			wanted = program.call(&"next")
		frame += 1
		if not lean.is_empty() and not wanted.has(&"move_left") and not wanted.has(&"move_right"):
			wanted = wanted + [lean]
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
