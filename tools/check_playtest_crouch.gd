extends RefCounted
## Crouch shot case of the playtest agent check (tools/check_playtest_agent.gd runs it in its room):
## an armored guard held still on her floor is too low for a standing shot (its art is 134 px tall,
## the standing crossbow fires 161 px up), so the state marks it low, a crouched Harpoon is offered
## instead of the standing one, the heuristic takes it, and through real inputs it lands. Before
## the crouch shot the vaults_01 probe hit 0 of 3 standing Harpoons and the heuristic arena run
## never killed the guard. A spitter, tall enough to hit standing, keeps its standing shot.

const Loop = preload("res://tools/playtest_loop.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Actions = preload("res://tools/playtest_actions.gd")
const State = preload("res://tools/playtest_state.gd")
const DISTANCES := [256.0, 448.0]
const SHOT_FRAMES := 240
## The check room's PLAYER_CELL (tools/check_playtest_agent.gd): each case starts her there.
const START_CELL := Vector2i(4, 7)

var _host: Node
var _root: Node
var _player: Player


## `host` is the check scene: it owns `_check`, `_root` and `_player`.
func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	for distance in DISTANCES:
		await _test_low_guard(distance)
	await _test_tall_target()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame


func _reset_kit() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.unlock_ability(&"missiles")
	GameState.collect_pickup("crouch.quiver", &"missile_tank")
	GameState.reset_health()
	_player.reset_for_spawn(WorldFxTestbed.feet(_root.current_room, START_CELL))


## `id` on her floor `distance` px ahead, settled and then held still, its attack held back.
func _spawn(id: StringName, distance: float) -> Node2D:
	var enemy := EnemyFactory.create(id) as Node2D
	WorldFxTestbed.entities(_root.current_room).add_child(enemy)
	enemy.set("_attack_timer", 999.0)
	var at := _player.global_position + Vector2(distance, -40)
	enemy.global_position = at
	await _frames(20)
	enemy.set_physics_process(false)
	enemy.global_position.x = at.x
	await _frames(2)
	return enemy


func _enemy_entry(state: Dictionary, type: String) -> Dictionary:
	for enemy: Dictionary in state["enemies"]:
		if enemy["type"] == type:
			return enemy
	return {}


func _test_low_guard(distance: float) -> void:
	_reset_kit()
	await _frames(20)
	var guard: Node2D = await _spawn(&"armored_guard", distance)
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	var entry := _enemy_entry(state, "armored_guard")
	_check(
		bool(entry.get("low", false)),
		"a guard %d px ahead is below the standing shot (%s)" % [distance, entry.get("span_rel")]
	)
	var options := Actions.candidates(state, _player)
	var keys: Array = options.map(func(e: Dictionary) -> String: return e["key"])
	var crouch := "crouch_shot:%s:harpoon" % entry.get("id", "")
	_check(keys.has(crouch), "a crouched Harpoon is offered at the low guard (%s)" % [keys])
	_check(
		not keys.has("harpoon:%s:forward" % entry.get("id", "")),
		"no standing Harpoon that flies over it (%s)" % [keys]
	)
	var pick := Policy.new(1).heuristic(state, Actions.public(options), false)
	_check(pick == crouch, "the heuristic fires crouched at the guard (%s)" % pick)
	var loop := Loop.new(_root, _player, Policy.HEURISTIC, 5, [])
	var health := int(guard.get("health"))
	for _frame in SHOT_FRAMES:
		loop.physics_step(1.0 / 60.0)
		await _host.get_tree().physics_frame
		if int(guard.get("health")) < health:
			break
	loop.finish({})
	_check(
		int(guard.get("health")) < health,
		(
			"a crouched Harpoon through real inputs hits the guard %d px ahead (%d -> %d)"
			% [distance, health, guard.get("health")]
		)
	)
	guard.queue_free()
	await _frames(20)


## A spitter reaches above the standing shot: it is not low and keeps its standing bolt.
func _test_tall_target() -> void:
	_reset_kit()
	await _frames(20)
	var spitter: Node2D = await _spawn(&"spitter", 384.0)
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	var entry := _enemy_entry(state, "spitter")
	var keys: Array = Actions.candidates(state, _player).map(
		func(e: Dictionary) -> String: return e["key"]
	)
	_check(not bool(entry.get("low", true)), "a spitter is not low (%s)" % [entry.get("span_rel")])
	_check(
		keys.has("shoot:%s:forward" % entry.get("id", "")),
		"the spitter keeps its standing shot (%s)" % [keys]
	)
	spitter.queue_free()
	await _frames(20)
