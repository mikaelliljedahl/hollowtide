extends RefCounted
## One forced mini-boss attack in its real room, answered through real inputs (docs/features/
## playtest-agent.md, section 29): by a fixed response started `delay` seconds into the telegraph,
## or by the heuristic loop itself. Shared by the probe (tools/playtest_mini_probe.gd) and the
## check (tools/check_playtest_mini.gd). Setup moves the boss and the player and forces the attack
## (test-only, like the other boss room checks); the answer is inputs only.

const Loop = preload("res://tools/playtest_loop.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const Boss = preload("res://tools/playtest_boss.gd")
const TILE := 64.0
## Mini-boss -> [room, the arena's return cell] (scenes/campaign/layouts).
const MINIS := {
	"fernmaw": ["fringe_08", Vector2i(3, 15)],
	"tollwing": ["nexus_09", Vector2i(3, 15)],
	"rimeweaver": ["vaults_08", Vector2i(22, 10)],
	"emberkite": ["kiln_08", Vector2i(3, 14)],
	"lanternjaw": ["depths_08", Vector2i(3, 13)],
}
const RESPONSES := ["idle", "jump", "run_away", "run_toward", "curl", "dash_away"]
const SETTLE_FRAMES := 40
const TRIAL_LIMIT := 330

var mini := ""
var boss: Node2D
## The boss's spawn point (global), where every trial starts it.
var home := Vector2.ZERO
var _root: Node
var _player: Player


func _init(root: Node, player: Player, mini_id: String) -> void:
	_root = root
	_player = player
	mini = mini_id


## Loads the mini-boss's room (again, after a run left it) and finds the boss; false when absent.
func ensure_boss() -> bool:
	var room_id: String = MINIS[mini][0]
	if String(_root.get("current_room_id")) == room_id and is_instance_valid(boss):
		return true
	var cell: Vector2i = MINIS[mini][1]
	_root.call("teleport", room_id, Vector2((cell.x + 0.5) * TILE, (cell.y + 1) * TILE))
	await _frames(60)
	boss = _player.get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	if boss == null or String(boss.get("enemy_id")) != mini:
		return false
	home = boss.get("_home_position")
	return true


## The feet spot on the lowest floor of the arena where a standing body fits at `x`, or null.
func floor_at(x: float) -> Variant:
	var arena: Rect2 = boss.get("arena_bounds")
	var space := boss.get_world_2d().direct_space_state
	var y := arena.end.y + TILE
	while y > arena.position.y + TILE * 3.0:
		if Boss._stands(space, Vector2(x, y)):
			return Vector2(x, y)
		y -= TILE
	return null


## True when standing at `spot` for two seconds, the boss frozen at home, costs no health (no
## lava, no heat): only such spots tell an attack's damage apart.
func quiet(spot: Vector2) -> bool:
	boss.global_position = home
	boss.set_physics_process(false)
	_player.global_position = spot
	_player.velocity = Vector2.ZERO
	await _frames(20)
	GameState.reset_health()
	var health := GameState.health
	await _frames(120)
	boss.set_physics_process(true)
	return GameState.health >= health


## One forced attack from `spot`: {damage, released, engaged, feet, picks (the loop's keys and
## its dodge labels)}; {} when the room could not be loaded.
func run(
	stage: int, attack: StringName, spot: Vector2, response: String, delay: float
) -> Dictionary:
	if not await ensure_boss():
		return {}
	var fighter := boss
	# The loop's shots must not carry the boss into another stage between trials.
	fighter.set("health", fighter.get("max_health"))
	fighter.call(&"set_test_stage", stage)
	fighter.global_position = home
	fighter.set("velocity", Vector2.ZERO)
	_player.global_position = spot
	_player.velocity = Vector2.ZERO
	if _player.is_ball:
		Input.action_press(&"slipstream")
		await _held(2)
		Input.action_release(&"slipstream")
	await _held(SETTLE_FRAMES)
	fighter.global_position = home
	GameState.reset_health()
	GameState.missile_count = GameState.max_missiles
	var health := GameState.health
	var engaged: bool = fighter.get("_player_engaged")
	var feet := _player.global_position - home
	var chain: Array[StringName] = [attack]
	fighter.set("_attack_chain", chain)
	fighter.call(&"_start_telegraph")
	var loop: Loop = null
	var driver := Programs.Driver.new()
	if response == "loop":
		loop = Loop.new(_root, _player, "heuristic", 1, [])
	var start := roundi(delay * 60.0)
	var away := -1 if fighter.global_position.x > _player.global_position.x else 1
	var picks: Array = []
	var released := false
	for frame in TRIAL_LIMIT:
		if loop != null:
			loop.physics_step(1.0 / 60.0)
			var key := String(loop.current.get("key", ""))
			if picks.is_empty() or picks[-1] != key:
				picks.append(key)
				if key.begins_with("dodge"):
					picks.append(String(loop.current.get("label", "")))
		else:
			if frame == start:
				driver.start(program(response, away))
			driver.step()
		await _player.get_tree().physics_frame
		if not is_instance_valid(fighter) or String(_root.get("current_room_id")) != MINIS[mini][0]:
			break
		released = released or fighter.get("_attack_state") in [&"active", &"recover"]
		if frame > 30 and fighter.get("_attack_state") == &"idle":
			break
	if loop != null:
		loop.finish({})
	driver.release_all()
	return {
		"mini": mini,
		"attack": String(attack),
		"stage": stage,
		"offset": roundi(spot.x - home.x),
		"response": response,
		"delay": delay,
		"damage": health - GameState.health,
		"released": released,
		"engaged": engaged,
		"feet": [roundi(feet.x), roundi(feet.y)],
		"picks": picks.slice(0, 8),
	}


## A fixed response; `away` is the side away from the boss.
static func program(response: String, away: int) -> Array:
	match response:
		"jump":
			return Programs.jump(0, 40)
		"run_away":
			return Programs.run(away, 60)
		"run_toward":
			return Programs.run(-away, 30)
		"curl":
			var frames := Programs.hold([&"slipstream"], 2)
			frames.append_array(Programs.hold([], 70))
			frames.append_array(Programs.hold([&"slipstream"], 2))
			return frames
		"dash_away":
			return Programs.dash(away)
	return Programs.idle()


func _held(count: int) -> void:
	for _index in count:
		boss.set("_attack_timer", 99.0)
		await _player.get_tree().physics_frame


func _frames(count: int) -> void:
	for _index in count:
		await _player.get_tree().physics_frame
