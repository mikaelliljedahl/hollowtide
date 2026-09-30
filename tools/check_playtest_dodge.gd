extends RefCounted
## Boss dodge cases of the playtest agent check (tools/check_playtest_agent.gd runs them in its
## room): a real Stone Guardian is forced into one stage 3 attack and the heuristic loop answers
## through real inputs. Jev round 3 (jev-r1) lost 15 Stone Guardian attempts with the minimum
## kit, taking 408 damage from Fault Slam and 196 from Rockfall while it retreated into the wall;
## without `dodge` the same loop is hit here.

const Loop = preload("res://tools/playtest_loop.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Actions = preload("res://tools/playtest_actions.gd")
const Dodge = preload("res://tools/playtest_dodge.gd")
const State = preload("res://tools/playtest_state.gd")
const BOSS_OFFSET := Vector2(416, -92)
const ATTACK_FRAMES := 240

var _host: Node
var _root: Node
var _player: Player


## `host` is the check scene: it owns `_check`, `_frames`, `_root` and `_player`.
func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	for attack in [&"fault_slam", &"rockfall", &"boulder_volley"]:
		await _test_attack(attack)
	await _test_headroom()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame


func _reset_kit() -> void:
	GameState.reset_progress()
	for id in [&"beam", &"slipstream", &"high_jump"]:
		GameState.unlock_ability(id)
	GameState.reset_health()


## The Stone Guardian 416 px ahead on the same floor, fighting in an arena that spans the room.
func _spawn_boss() -> Node2D:
	var boss := EnemyFactory.create(&"stone_guardian") as Node2D
	WorldFxTestbed.entities(_root.current_room).add_child(boss)
	boss.global_position = _player.global_position + BOSS_OFFSET
	var room: Node2D = _root.current_room
	var size: Vector2 = room.call("size_px")
	boss.call(
		&"configure_arena", Rect2(room.global_position + Vector2(64, 64), size - Vector2(128, 128))
	)
	return boss


## The heuristic loop, deciding every time a program ends, from the telegraph until the boss
## recovers: the key it chose first and the damage taken.
func _test_attack(attack: StringName) -> void:
	_reset_kit()
	await _frames(30)
	var boss := _spawn_boss()
	await _frames(2)
	boss.call(&"set_test_stage", 3)
	var chain: Array[StringName] = [attack]
	boss.set("_attack_chain", chain)
	boss.call(&"_start_telegraph")
	var loop := Loop.new(_root, _player, Policy.HEURISTIC, 5, [])
	var health := GameState.health
	var first := ""
	for _frame in ATTACK_FRAMES:
		loop.physics_step(1.0 / 60.0)
		if first.is_empty():
			first = String(loop.current.get("key", ""))
		await _host.get_tree().physics_frame
		if boss.get("_attack_state") == &"recover":
			# Only this attack counts; the boss would walk on after its punish window.
			boss.set_physics_process(false)
			if _host.get_tree().get_nodes_in_group(&"enemy_shot").is_empty():
				break
	loop.finish({})
	_check(
		first == "dodge:%s" % attack,
		"a %s telegraph is answered with its dodge (%s)" % [attack, first]
	)
	_check(
		GameState.health == health,
		(
			"the %s dodge through real inputs takes no damage (%d -> %d)"
			% [attack, health, GameState.health]
		)
	)
	boss.queue_free()
	for shot in _host.get_tree().get_nodes_in_group(&"enemy_shot"):
		shot.queue_free()
	await _frames(40)


## A refill beyond the boss is run to with a jump over it under open sky, and walked to (no jump
## over) under a low roof over the boss.
func _test_headroom() -> void:
	_reset_kit()
	await _frames(20)
	var rel := BOSS_OFFSET
	_check(Dodge.headroom(_player, rel), "open sky over the boss leaves room to jump it")
	var roof := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(320, 40)
	shape.shape = box
	roof.add_child(shape)
	WorldFxTestbed.entities(_root.current_room).add_child(roof)
	roof.global_position = _player.global_position + rel - Vector2(0, 92 + 120)
	await _frames(2)
	_check(not Dodge.headroom(_player, rel), "a roof just over the boss leaves no room")
	roof.queue_free()
	await _frames(2)
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	state["kit"].merge({"missiles": 0, "max_missiles": 5}, true)
	state["enemies"] = [
		{
			"id": "e9",
			"type": "stone_guardian",
			"rel": [roundi(rel.x), roundi(rel.y)],
			"dist": roundi(rel.length()),
			"is_boss": true,
			"engaged": true,
			"hurt_by": [],
			"visible": true,
		}
	]
	state["refills"] = [{"kind": "missilerefill", "restores": ["harpoons"], "rel": [900, 0]}]
	var refill := Actions._refill(state, _player)
	_check(
		refill.get("program") is Dodge.JumpOver, "the refill run jumps over the boss (%s)" % refill
	)
	await _frames(2)
