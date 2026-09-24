extends RefCounted
## Playtest agent macro actions (docs/features/playtest-agent.md). `candidates()` offers 6 to 12
## labelled options for the current state; each carries a program: one Array of held input
## actions per physics frame. `Driver` plays a program through Input.parse_input_event, exactly
## like a pad, so the agent never moves the player or sets any state directly.

const MAX_CANDIDATES := 12
const STEP_FRAMES := 12
const JUMP_HOLD_FRAMES := 20
const JUMP_TAIL_FRAMES := 8
const NEAR_TARGET := 24.0
const SHOT_RANGE := 1100.0
const THREAT_RANGE := 420.0
const PROJECTILE_ALERT := 420.0
const MAX_EXITS := 3
## Kinds that are movement, for stuck detection: choosing one of these means "I want to move".
const MOVING_KINDS := ["approach", "retreat", "go_to_exit", "go_to_ambush", "pick_up", "jump"]


## Returns [{key, kind, label, program}] for `state` (from playtest_state.gd). The first entry is
## always `idle`; the rest follow a fixed priority so the list is deterministic.
static func candidates(state: Dictionary, player: Player) -> Array:
	var result: Array = [_entry("idle", "idle", "stand still", _idle())]
	if state.get("room") == null:
		return result
	var me: Dictionary = state["player"]
	var kit: Dictionary = state["kit"]
	var abilities: Array = kit["abilities"]
	var enemies: Array = state["enemies"]
	var target := primary_target(enemies)
	if not target.is_empty():
		var rel := _vec(target["rel"])
		var toward := _sign(rel.x)
		result.append(
			_entry(
				"approach:%s" % target["id"],
				"approach",
				"approach enemy %s (%s)" % [target["id"], target["type"]],
				steer(player, rel, false)
			)
		)
		result.append(
			_entry(
				"retreat",
				"retreat",
				"run away from %s" % target["type"],
				_run(-toward, STEP_FRAMES)
			)
		)
		if abilities.has("beam") and rel.length() <= SHOT_RANGE:
			var aim := aim_for(rel, bool(me["grounded"]))
			result.append(
				_entry(
					"shoot:%s:%s" % [target["id"], aim],
					"shoot",
					"fire the crossbow %s at %s" % [aim.replace("_", " "), target["type"]],
					shoot(toward, aim, &"fire_beam", int(me["facing"]))
				)
			)
		var harpoon := _harpoon_target(enemies, int(kit["missiles"]))
		if not harpoon.is_empty():
			var hrel := _vec(harpoon["rel"])
			var haim := aim_for(hrel, bool(me["grounded"]))
			result.append(
				_entry(
					"harpoon:%s:%s" % [harpoon["id"], haim],
					"harpoon",
					"fire a harpoon %s at %s" % [haim.replace("_", " "), harpoon["type"]],
					shoot(_sign(hrel.x), haim, &"fire_missile", int(me["facing"]))
				)
			)
		if bool(me["grounded"]) and rel.length() <= THREAT_RANGE:
			result.append(
				_entry(
					"jump_over:%s" % target["id"],
					"jump_over",
					"jump over %s" % target["type"],
					_jump(toward, JUMP_HOLD_FRAMES)
				)
			)
	var shot := incoming_projectile(state)
	if not shot.is_empty() and abilities.has("undertow_dash") and bool(me["dash_ready"]):
		result.append(
			_entry(
				"dash_through",
				"dash_through",
				"dash into the incoming %s shot" % shot["style"],
				_dash(_sign(float(shot["rel"][0])))
			)
		)
	if bool(me["on_wall"]):
		result.append(
			_entry("wall_jump_up", "wall_jump", "wall jump up", _wall_jump(int(me["facing"])))
		)
	var arena = state["ambush"]
	if arena != null and arena["state"] == "armed" and not _near(_vec(arena["trigger_rel"])):
		result.append(
			_entry(
				"go_to_ambush",
				"go_to_ambush",
				"walk into the arena",
				steer(player, _vec(arena["trigger_rel"]), false)
			)
		)
	for pickup in (state["pickups"] as Array).slice(0, 2):
		result.append(
			_entry(
				"pick_up:%s" % pickup["id"],
				"pick_up",
				"collect %s" % pickup["kind"],
				steer(player, _vec(pickup["rel"]), false)
			)
		)
	var exits := 0
	for door in state["exits"]:
		if bool(door["gated"]) or exits >= MAX_EXITS:
			continue
		exits += 1
		result.append(
			_entry(
				"go_to_exit:%s" % door["id"],
				"go_to_exit",
				"head for the %s exit" % door["id"],
				steer(player, _vec(door["rel"]), true)
			)
		)
	result.append(_entry("jump:left", "jump", "jump left", _jump(-1, JUMP_HOLD_FRAMES)))
	result.append(_entry("jump:right", "jump", "jump right", _jump(1, JUMP_HOLD_FRAMES)))
	return result.slice(0, MAX_CANDIDATES)


## The enemy the fight candidates aim at: the nearest visible one the kit can hurt (bosses always
## count), else the nearest visible one, else the nearest one; {} without enemies.
static func primary_target(enemies: Array) -> Dictionary:
	for enemy in enemies:
		if enemy["visible"] and (enemy["is_boss"] or not (enemy["hurt_by"] as Array).is_empty()):
			return enemy
	for enemy in enemies:
		if enemy["visible"]:
			return enemy
	return enemies[0] if not enemies.is_empty() else {}


## Candidates without programs, as sent to a policy.
static func public(candidates_list: Array) -> Array:
	return candidates_list.map(
		func(entry: Dictionary) -> Dictionary:
			return {"key": entry["key"], "kind": entry["kind"], "label": entry["label"]}
	)


static func find(candidates_list: Array, key: String) -> Dictionary:
	for entry in candidates_list:
		if entry["key"] == key:
			return entry
	return {}


## Nearest enemy shot flying at the player, or {}.
static func incoming_projectile(state: Dictionary) -> Dictionary:
	for shot in state.get("projectiles", []):
		var rel := _vec(shot["rel"]) + Vector2(0, 90)
		var velocity := _vec(shot["vel"])
		if rel.length() <= PROJECTILE_ALERT and velocity.dot(-rel) > 0.0:
			return shot
	return {}


## Aim name for a target at `rel` from the feet: the crossbow fires from about 100 px up.
static func aim_for(rel: Vector2, grounded: bool) -> String:
	var offset := rel + Vector2(0, 100)
	if offset.y < -absf(offset.x) * 2.2:
		return "up"
	if offset.y < -absf(offset.x) * 0.45:
		return "diag_up"
	if not grounded and offset.y > absf(offset.x) * 2.2:
		return "down"
	if not grounded and offset.y > absf(offset.x) * 0.45:
		return "diag_down"
	return "forward"


## A walking program toward `rel`, jumping when a wall blocks the way or the target is above.
static func steer(player: Player, rel: Vector2, run: bool) -> Array:
	var direction := _sign(rel.x) if absf(rel.x) > NEAR_TARGET else 0
	var blocked := (
		direction != 0 and player.test_move(player.global_transform, Vector2(direction * 24, 0))
	)
	var above := rel.y < -96.0 and absf(rel.x) < 420.0
	if player.is_on_floor() and (blocked or above):
		return _jump(direction, JUMP_HOLD_FRAMES)
	if not player.is_on_floor() and player.is_on_wall() and rel.y < -64.0:
		return _wall_jump(player.facing)
	if direction == 0:
		return _idle()
	return _run(direction, STEP_FRAMES) if run else _walk(direction, STEP_FRAMES)


## Face `direction`, hold the aim and tap `fire` once (three frames down, three up).
static func shoot(direction: int, aim: String, fire: StringName, facing: int) -> Array:
	var frames: Array = []
	var move := _move(direction)
	if direction != 0 and direction != facing:
		frames.append_array(_repeat([move], 2))
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
	frames.append_array(_repeat(held + [fire], 3))
	frames.append_array(_repeat(held, 3))
	return frames


static func _harpoon_target(enemies: Array, missiles: int) -> Dictionary:
	if missiles <= 0:
		return {}
	for enemy in enemies:
		var kinds: Array = enemy["hurt_by"]
		if kinds.has("missile") and (enemy["is_boss"] or not _beam_hurts(kinds)):
			return enemy
	return {}


static func _beam_hurts(kinds: Array) -> bool:
	return kinds.has("beam") or kinds.has("ice") or kinds.has("wave")


static func _entry(key: String, kind: String, label: String, program: Array) -> Dictionary:
	return {"key": key, "kind": kind, "label": label, "program": program}


static func _idle() -> Array:
	return _repeat([], 6)


static func _walk(direction: int, frames: int) -> Array:
	return _repeat([_move(direction)], frames)


static func _run(direction: int, frames: int) -> Array:
	if direction == 0:
		return _idle()
	return _repeat([_move(direction), &"run"], frames)


static func _jump(direction: int, hold: int) -> Array:
	var held: Array = [&"jump"]
	if direction != 0:
		held.append(_move(direction))
	var frames := _repeat(held, hold)
	frames.append_array(_repeat([_move(direction)] if direction != 0 else [], JUMP_TAIL_FRAMES))
	return frames


static func _dash(direction: int) -> Array:
	var move := _move(direction)
	var frames := _repeat([move, &"dash"], 3)
	frames.append_array(_repeat([move], 9))
	return frames


## Push into the wall being clung to, then jump away from it and steer back toward it.
static func _wall_jump(facing: int) -> Array:
	var wall := -facing
	var frames := _repeat([_move(wall)], 3)
	frames.append_array(_repeat([&"jump", _move(-wall)], 8))
	frames.append_array(_repeat([&"jump", _move(wall)], 10))
	return frames


static func _move(direction: int) -> StringName:
	return &"move_left" if direction < 0 else &"move_right"


static func _repeat(held: Array, count: int) -> Array:
	var frames: Array = []
	for _index in count:
		frames.append(held.duplicate())
	return frames


static func _sign(value: float) -> int:
	return -1 if value < 0.0 else 1


static func _near(rel: Vector2) -> bool:
	return absf(rel.x) < 48.0 and absf(rel.y) < 160.0


static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


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
			if not _held.has(action):
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
