extends RefCounted
## Boss dodge cases of the playtest agent check (tools/check_playtest_agent.gd runs them in its
## room): a real Stone Guardian is forced into one stage 3 attack, and a real Tidal Heart into one
## stage 4 attack, and the heuristic loop answers through real inputs. Jev round 3 (jev-r1) lost
## 15 Stone Guardian attempts with the minimum kit, taking 408 damage from Fault Slam and 196 from
## Rockfall while it retreated into the wall; without `dodge` the same loop is hit here.

const Loop = preload("res://tools/playtest_loop.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Actions = preload("res://tools/playtest_actions.gd")
const Dodge = preload("res://tools/playtest_dodge.gd")
const Tide = preload("res://tools/playtest_tide.gd")
const State = preload("res://tools/playtest_state.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const BOSS_OFFSET := Vector2(416, -92)
## The Tidal Heart floats 330 px above her feet and 250 px ahead, as in the depths_02 probe.
const TIDAL_OFFSET := Vector2(250, -330)
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
	await _test_retreat_reach()
	_test_walk_into_arena()
	await _test_stands_up_first()
	await _test_guard_charge()
	for attack in Tide.ATTACKS:
		await _test_tidal(attack)
	_test_attacks_landed()


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


## Retreat is offered from a near threat only, and never into a wall: at 10 health Jev retreated
## from a bat 500 px away into the vaults_02 east wall for 500 s (jev-r2).
func _test_retreat_reach() -> void:
	_reset_kit()
	await _frames(20)
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	var bat := {
		"id": "e7",
		"type": "bat",
		"rel": [-500, -40],
		"dist": 502,
		"health": 6,
		"max_health": 6,
		"is_boss": false,
		"telegraph": false,
		"ambush": false,
		"hurt_by": ["beam"],
		"switch_to": "",
		"visible": true,
	}
	state["enemies"] = [bat]
	var keys := Actions.candidates(state, _player).map(
		func(e: Dictionary) -> String: return e["key"]
	)
	_check(not keys.has("retreat"), "no retreat from a bat 500 px away (%s)" % [keys])
	bat["rel"] = [-300, -40]
	bat["dist"] = 303
	keys = Actions.candidates(state, _player).map(func(e: Dictionary) -> String: return e["key"])
	_check(keys.has("retreat"), "a bat 300 px away offers the retreat")
	bat["rel"] = [300, -40]
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 400)
	shape.shape = box
	wall.add_child(shape)
	WorldFxTestbed.entities(_root.current_room).add_child(wall)
	wall.global_position = _player.global_position + Vector2(-50, -200)
	await _frames(2)
	keys = Actions.candidates(state, _player).map(func(e: Dictionary) -> String: return e["key"])
	_check(not keys.has("retreat"), "no retreat into the wall behind her (%s)" % [keys])
	wall.queue_free()
	await _frames(2)


## Outside its arena a boss neither fights nor takes damage, so the heuristic walks in even when it
## is closer than its spacing (cw-j1 idled 268 s 28 px outside the kiln_03 arena).
func _test_walk_into_arena() -> void:
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	state["enemies"] = [
		{
			"id": "e1",
			"type": "furnace_mother",
			"rel": [344, -92],
			"dist": 356,
			"health": 67,
			"max_health": 360,
			"is_boss": true,
			"telegraph": false,
			"ambush": false,
			"hurt_by": [],
			"switch_to": "",
			"visible": true,
			"engaged": false,
			"arena_rel": [28, -768, 2716, 0],
			"attack": "",
			"attack_state": "idle",
		}
	]
	var options := Actions.public(Actions.candidates(state, _player))
	var pick := Policy.new(1).heuristic(state, options, false)
	_check(pick == "approach:e1", "the heuristic walks into a disengaged boss's arena (%s)" % pick)


## A curled player stands up before a move that needs her standing: after a missed stand-up tap
## she rolled around for 110 s in a Cinder Warden probe, where no shot is ever offered.
func _test_stands_up_first() -> void:
	_reset_kit()
	await _frames(20)
	Input.action_press(&"slipstream")
	await _frames(2)
	Input.action_release(&"slipstream")
	await _frames(20)
	_check(_player.is_ball, "the player is curled for the case")
	var loop := Loop.new(_root, _player, Policy.HEURISTIC, 5, [])
	for _frame in 40:
		loop.physics_step(1.0 / 60.0)
		await _host.get_tree().physics_frame
	loop.finish({})
	_check(not _player.is_ball, "the agent stands her up before its next move (%s)" % loop.current)


## An armored guard 384 px away winds up its charge: the loop, deciding from the wind-up on,
## jumps over it through real inputs (standing or curling is hit, 9 of 9 in the vaults_01 probe).
func _test_guard_charge() -> void:
	_reset_kit()
	await _frames(20)
	var guard := EnemyFactory.create(&"armored_guard") as Node2D
	WorldFxTestbed.entities(_root.current_room).add_child(guard)
	guard.global_position = _player.global_position + Vector2(384, -40)
	var loop := Loop.new(_root, _player, Policy.HEURISTIC, 5, [])
	var health := GameState.health
	var first := ""
	var winding := false
	for _frame in 300:
		winding = winding or guard.get("_special_state") == &"windup"
		if winding:
			loop.physics_step(1.0 / 60.0)
			if first.is_empty():
				first = String(loop.current.get("key", ""))
		await _host.get_tree().physics_frame
		if winding and guard.get("_special_state") == &"recover":
			break
	loop.finish({})
	_check(first.begins_with("dodge:"), "a winding-up guard is answered with a dodge (%s)" % first)
	_check(
		GameState.health == health,
		"the jump over the guard's charge takes no damage (%d -> %d)" % [health, GameState.health]
	)
	guard.queue_free()
	await _frames(20)


## A real Tidal Heart forced into a desperation `attack`: the state carries its locked lines, and
## the heuristic loop answers with its dodge and takes no damage through real inputs (curling under
## the lines, stepping off the lance, jumping the low Crosscurrent lane). Without the dodge the loop
## is hit by every one of them here.
func _test_tidal(attack: StringName) -> void:
	_reset_kit()
	# The previous case may end with her still curled under its lines.
	if _player.is_ball:
		Input.action_press(&"slipstream")
		await _frames(2)
		Input.action_release(&"slipstream")
	await _frames(30)
	var boss := EnemyFactory.create(&"tidal_heart") as Node2D
	WorldFxTestbed.entities(_root.current_room).add_child(boss)
	boss.global_position = _player.global_position + TIDAL_OFFSET
	var room: Node2D = _root.current_room
	var size: Vector2 = room.call("size_px")
	boss.call(
		&"configure_arena", Rect2(room.global_position + Vector2(64, 64), size - Vector2(128, 128))
	)
	await _frames(2)
	boss.call(&"set_test_stage", 4)
	var chain: Array[StringName] = [attack]
	boss.set("_attack_chain", chain)
	boss.call(&"_start_telegraph")
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	var lines: Array = []
	for enemy: Dictionary in state["enemies"]:
		if enemy["is_boss"]:
			lines = enemy.get("shots_rel", [])
	_check(
		not lines.is_empty(), "a telegraphing %s exports its lines (%d)" % [attack, lines.size()]
	)
	var loop := Loop.new(_root, _player, Policy.HEURISTIC, 5, [])
	var health := GameState.health
	var first := ""
	for _frame in ATTACK_FRAMES * 3:
		loop.physics_step(1.0 / 60.0)
		if first.is_empty():
			first = String(loop.current.get("key", ""))
		await _host.get_tree().physics_frame
		if boss.get("_attack_state") == &"recover":
			boss.set_physics_process(false)
			if _host.get_tree().get_nodes_in_group(&"enemy_shot").is_empty():
				break
	loop.finish({})
	_check(
		first == "dodge:%s" % attack,
		"a Tidal Heart %s is answered with its dodge (%s)" % [attack, first]
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


## The Jev critic's "attacks seen vs escaped": an attack that hits twice lands once, the next one
## counts again, and an attack started before this fight counts nothing.
func _test_attacks_landed() -> void:
	var telemetry := Telemetry.new()
	var boss := Node.new()
	telemetry.set(
		"_boss", {"start": 10.0, "attacks_landed": {}, "attack_landed": false, "node": boss}
	)
	var attacks: Dictionary = telemetry.get("_boss_attacks")
	attacks[boss.get_instance_id()] = {"attack": "rockfall", "t": 4.0}
	telemetry.call("_note_boss_attack_landed")
	var landed: Dictionary = telemetry.get("_boss")["attacks_landed"]
	_check(landed.is_empty(), "an attack from before the fight is not counted (%s)" % landed)
	attacks[boss.get_instance_id()] = {"attack": "fault_slam", "t": 12.0}
	telemetry.call("_note_boss_attack_landed")
	telemetry.call("_note_boss_attack_landed")
	_check(landed.get("fault_slam") == 1, "two hits of one attack land once (%s)" % landed)
	telemetry.get("_boss")["attack_landed"] = false
	telemetry.call("_note_boss_attack_landed")
	_check(landed.get("fault_slam") == 2, "the next attack counts again (%s)" % landed)
	boss.free()
