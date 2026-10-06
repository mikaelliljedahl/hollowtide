extends RefCounted
## Mini-boss cases of the playtest agent (docs/features/playtest-agent.md, section 29), run by
## tools/check_playtest_boss_rooms.gd in the real campaign rooms with the full kit. Before round 10
## the agent knew no mini-boss attack: it walked or shot through every telegraph, and in the probe
## standing still took Shard Drop and Needle Line at every spot. Now each case is one forced attack
## from a spot where standing still is hit, answered by the heuristic loop through real inputs: it
## picks `dodge:<attack>` and takes no damage. A real mini-boss also exports stage 2's punish
## window as its opener.

const Trial = preload("res://tools/playtest_mini_trial.gd")
const State = preload("res://tools/playtest_state.gd")
## [mini-boss, stage, attack, feet px from its spawn] from the probe's idle hits.
const CASES := [
	["tollwing", 1, &"shard_drop", -256.0],
	["tollwing", 1, &"swoop", -256.0],
	["rimeweaver", 1, &"needle_line", -256.0],
	["lanternjaw", 2, &"undertow_pull", -605.0],
]

var _host: Node
var _root: Node
var _player: Player


func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	await _test_mini_opener()
	for case: Array in CASES:
		await _test_dodge(case)


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _test_mini_opener() -> void:
	var trial := Trial.new(_root, _player, "fernmaw")
	_check(await trial.ensure_boss(), "Fernmaw spawns in fringe_08")
	if trial.boss == null:
		return
	trial.boss.call(&"set_test_stage", 2)
	_player.global_position = trial.floor_at(trial.home.x - 256.0)
	for _frame in 10:
		trial.boss.set("_attack_timer", 99.0)
		await _player.get_tree().physics_frame
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	var boss: Dictionary = {}
	for enemy: Dictionary in state["enemies"]:
		if enemy["is_boss"]:
			boss = enemy
	var opener = boss.get("opener")
	_check(
		opener is Dictionary and opener["via"] == "punish" and int(boss.get("stage", 0)) == 2,
		"a stage 2 mini-boss opens only in its punish window (%s)" % [opener]
	)
	trial.boss.call(&"set_test_stage", 1)


func _test_dodge(case: Array) -> void:
	var trial := Trial.new(_root, _player, case[0])
	if not await trial.ensure_boss():
		_check(false, "%s spawns" % case[0])
		return
	var spot = trial.floor_at(trial.home.x + float(case[3]))
	if not spot is Vector2:
		_check(false, "%s has a floor %d px from its spawn" % [case[0], case[3]])
		return
	var record: Dictionary = await trial.run(case[1], case[2], spot, "loop", 0.0)
	var label := "%s %s from %d px" % [case[0], case[2], case[3]]
	_check(record.get("released", false), "%s: the attack is released at her" % label)
	_check(
		(record.get("picks", []) as Array).has("dodge:%s" % case[2]),
		"%s: the loop answers with its dodge (%s)" % [label, record.get("picks")]
	)
	_check(record.get("damage", -1) == 0, "%s: no damage (%s)" % [label, record.get("damage")])
