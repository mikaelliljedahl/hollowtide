extends Node
## Playtest agent harness (docs/features/playtest-agent.md): the state export has its keys and is
## JSON-safe, candidates are valid input programs, the heuristic agent kills a hopper in a small
## real room through input events only, telemetry records the kill and the damage source, the
## external bridge round-trips one decision with a stub server, and a silent or missing server
## falls back to the heuristic. Round 2 fixes: no shot at a target far below a grounded player, no
## exit while a boss lives, a surprise enemy's wind-up reads as a telegraph, kit pickups stack.
## godot --headless --path . res://tools/check_playtest_agent.tscn -- --test-mode

const Loop = preload("res://tools/playtest_loop.gd")
const Actions = preload("res://tools/playtest_actions.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Agent = preload("res://tools/playtest_agent.gd")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")
const STATE_KEYS := [
	"tick",
	"t",
	"room",
	"player",
	"kit",
	"enemies",
	"projectiles",
	"ambush",
	"exits",
	"pickups",
	"hazards"
]
const PLAYER_KEYS := [
	"pos",
	"cell",
	"vel",
	"health",
	"max_health",
	"grounded",
	"on_wall",
	"facing",
	"form",
	"dash_ready"
]
const ENEMY_KEYS := [
	"id",
	"type",
	"rel",
	"dist",
	"health",
	"max_health",
	"is_boss",
	"telegraph",
	"hurt_by",
	"visible"
]
const GRID := [
	"##############################",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"##############################",
]
const PLAYER_CELL := Vector2i(4, 7)
const HOPPER_CELL := Vector2i(20, 7)
const CLEAR_SECONDS := 20.0

var _failures: Array[String] = []
var _root: FakeRoot
var _player: Player


## Stands in for CampaignRoot: the loop only reads these two properties and the signal.
class FakeRoot:
	extends Node
	signal room_changed(room_id: String)

	var current_room: CampaignRoom
	var current_room_id := ""


## Minimal policy server on 127.0.0.1 in a thread: answers every decide with the second
## candidate (or stays silent), and stops on bye or after five seconds.
class StubServer:
	extends RefCounted

	var port := 0
	var received: Array = []
	var _reply := true
	var _server := TCPServer.new()
	var _thread := Thread.new()

	func start(reply: bool) -> bool:
		_reply = reply
		if _server.listen(0, "127.0.0.1") != OK:
			return false
		port = _server.get_local_port()
		_thread.start(_serve)
		return true

	func stop() -> void:
		_thread.wait_to_finish()
		_server.stop()

	func _serve() -> void:
		var deadline := Time.get_ticks_msec() + 5000
		while not _server.is_connection_available() and Time.get_ticks_msec() < deadline:
			OS.delay_msec(2)
		if not _server.is_connection_available():
			return
		var peer := _server.take_connection()
		var pending := ""
		while Time.get_ticks_msec() < deadline:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				return
			var available := peer.get_available_bytes()
			if available > 0:
				pending += peer.get_utf8_string(available)
			while pending.contains("\n"):
				var end := pending.find("\n")
				var message = JSON.parse_string(pending.substr(0, end))
				pending = pending.substr(end + 1)
				received.append(message)
				if message["type"] == "bye":
					peer.disconnect_from_host()
					return
				if message["type"] == "decide" and _reply:
					var reply := {
						"type": "action",
						"tick": message["tick"],
						"key": message["candidates"][1]["key"],
					}
					peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())
			OS.delay_msec(1)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_options()
	await _build()
	await _test_state_and_candidates()
	await _test_heuristic_clears_hopper()
	await _test_round_two_candidates()
	await _test_surprise_wind_up_is_telegraph()
	_test_kit_pickups_stack()
	await _test_bridge_round_trip()
	await _test_timeout_falls_back()
	await _test_missing_server_falls_back()
	_root.queue_free()
	await _frames(2)
	for failure in _failures:
		print("FAIL ", failure)
	print("playtest-agent: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


# --- setup ------------------------------------------------------------------------------------


func _build() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()
	_root = FakeRoot.new()
	add_child(_root)
	_root.current_room = WorldFxTestbed.build_room(_root, &"fringe", GRID, "playtest_test")
	_root.current_room_id = "playtest_test"
	_player = WorldFxTestbed.spawn_player(_root, _root.current_room, PLAYER_CELL)
	await _frames(20)


func _spawn_hopper() -> Node2D:
	var hopper := EnemyFactory.create(&"hopper")
	WorldFxTestbed.entities(_root.current_room).add_child(hopper)
	hopper.global_position = WorldFxTestbed.feet(_root.current_room, HOPPER_CELL)
	return hopper


## A loop whose decisions run before the player each physics frame, like the launch scene.
func _loop(policy: String) -> Loop:
	return Loop.new(_root, _player, policy, 7, [])


# --- cases ------------------------------------------------------------------------------------


func _test_options() -> void:
	var agent := Agent.new()
	_check(agent.parse_options(PackedStringArray()) == "", "default options parse")
	agent.options = Agent.DEFAULTS.duplicate()
	var bad_room := agent.parse_options(PackedStringArray(["--playtest-room=nowhere"]))
	_check(bad_room.begins_with("unknown room"), "an unknown room is refused (%s)" % bad_room)
	agent.options = Agent.DEFAULTS.duplicate()
	var no_port := agent.parse_options(PackedStringArray(["--playtest-policy=external"]))
	_check(no_port.contains("port"), "the external policy needs a port (%s)" % no_port)
	agent.free()


func _test_state_and_candidates() -> void:
	var hopper := _spawn_hopper()
	await _frames(10)
	var loop := _loop(Policy.HEURISTIC)
	var state := loop.exporter.snapshot(_root, _player, 1, 0.0)
	_check(STATE_KEYS.all(func(key: String) -> bool: return state.has(key)), "state has its keys")
	var me: Dictionary = state["player"]
	_check(PLAYER_KEYS.all(func(key: String) -> bool: return me.has(key)), "player block keys")
	_check(state["kit"]["abilities"] == ["beam"], "kit lists the beam (%s)" % state["kit"])
	var enemies: Array = state["enemies"]
	_check(enemies.size() == 1, "one enemy exported (%d)" % enemies.size())
	if enemies.size() == 1:
		var enemy: Dictionary = enemies[0]
		_check(ENEMY_KEYS.all(func(key: String) -> bool: return enemy.has(key)), "enemy keys")
		_check(enemy["type"] == "hopper" and enemy["visible"], "the hopper is seen (%s)" % enemy)
		_check(int(enemy["rel"][0]) > 0, "the hopper is to the right")
		_check(enemy["hurt_by"] == ["beam"], "the beam hurts it (%s)" % [enemy["hurt_by"]])
	var round_trip = JSON.parse_string(JSON.stringify(state))
	_check(round_trip is Dictionary and round_trip.size() == state.size(), "state is JSON-safe")
	var options := Actions.candidates(state, _player)
	_check(options.size() >= 6 and options.size() <= 12, "6-12 candidates (%d)" % options.size())
	_check(options[0]["key"] == "idle", "idle comes first")
	var keys := {}
	var valid := true
	for entry in options:
		keys[entry["key"]] = true
		valid = valid and not (entry["program"] as Array).is_empty()
		for held in entry["program"]:
			for action in held:
				valid = valid and action is StringName and InputMap.has_action(action)
	_check(keys.size() == options.size(), "candidate keys are unique")
	_check(valid, "every program holds only real input actions")
	for kind in ["approach", "retreat", "shoot", "jump"]:
		_check(options.any(func(e: Dictionary) -> bool: return e["kind"] == kind), "offers " + kind)
	loop.finish({})
	hopper.queue_free()
	await _frames(5)


func _test_heuristic_clears_hopper() -> void:
	GameState.reset_health()
	var hopper := _spawn_hopper()
	await _frames(5)
	var loop := _loop(Policy.HEURISTIC)
	var start := _player.global_position
	for _frame in int(CLEAR_SECONDS * 60):
		loop.physics_step(1.0 / 60.0)
		await get_tree().physics_frame
		if not is_instance_valid(hopper) or int(hopper.get("health")) <= 0:
			break
	await _frames(3)
	loop.physics_step(1.0 / 60.0)
	_check(
		not is_instance_valid(hopper) or int(hopper.get("health")) <= 0,
		"the heuristic agent kills the hopper with input events only"
	)
	_check(loop.telemetry.kills.get("hopper", 0) == 1, "telemetry records the kill")
	_check(loop.telemetry.decisions.has(Policy.HEURISTIC), "decisions are recorded")
	_check(_player.global_position != start or loop.tick > 0, "the agent acted")
	# A hostile shot at the chest once any hurt invulnerability is over: telemetry names its source.
	for _frame in 90:
		loop.telemetry.tick(1.0 / 60.0, false, "")
		await get_tree().physics_frame
	var chest := _player.global_position + Vector2(0.0, -80.0)
	var shot := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	_root.add_child(shot)
	shot.global_position = chest + Vector2(90.0, 0.0)
	shot.launch(Vector2.LEFT, 12)
	var health := GameState.health
	for _frame in 30:
		loop.telemetry.tick(1.0 / 60.0, false, "")
		await get_tree().physics_frame
	_check(GameState.health < health, "the shot hurts the player")
	var damage: Dictionary = loop.telemetry.damage
	_check(damage.has("shot:orb") and damage["shot:orb"] > 0, "damage is credited (%s)" % damage)
	loop.finish({})
	await _frames(40)


## A boss far below a grounded player gets no shot (no aim reaches it) and, while it lives, no
## exit is offered: vaults_03 round 1 emptied the quiver into the ledge and then left the room.
func _test_round_two_candidates() -> void:
	var loop := _loop(Policy.HEURISTIC)
	var state := loop.exporter.snapshot(_root, _player, 1, 0.0)
	loop.finish({})
	_check(Actions.aim_for(Vector2(900, 480), true) == "", "no aim at a target far below the feet")
	_check(Actions.aim_for(Vector2(900, 480), false) != "", "airborne, a diagonal aim reaches it")
	state["kit"] = {"abilities": ["beam", "missiles"], "beam": "base", "missiles": 5}
	state["exits"] = [{"id": "west:elsewhere", "rel": [-200, 0], "gated": false, "gate": ""}]
	var boss := {
		"id": "e1",
		"type": "stone_guardian",
		"rel": [900, 480],
		"dist": 1000,
		"health": 300,
		"max_health": 300,
		"is_boss": true,
		"telegraph": false,
		"ambush": false,
		"hurt_by": ["missile"],
		"visible": true,
	}
	state["enemies"] = [boss]
	var kinds := Actions.candidates(state, _player).map(
		func(e: Dictionary) -> String: return e["kind"]
	)
	_check(
		not kinds.has("shoot") and not kinds.has("harpoon"),
		"no shot at the boss below (%s)" % [kinds]
	)
	_check(not kinds.has("go_to_exit"), "no exit while the boss lives (%s)" % [kinds])
	state["enemies"] = []
	kinds = Actions.candidates(state, _player).map(func(e: Dictionary) -> String: return e["kind"])
	_check(kinds.has("go_to_exit"), "the exit returns once no boss is left")
	await _frames(1)


func _test_surprise_wind_up_is_telegraph() -> void:
	var spider := EnemyFactory.create(&"drop_spider") as Node2D
	var entities := WorldFxTestbed.entities(_root.current_room)
	# The spider takes its ceiling anchor from where it enters the tree.
	spider.position = entities.to_local(_player.global_position + Vector2(0, -330))
	entities.add_child(spider)
	var seen := false
	for _frame in 60:
		await _frames(1)
		if spider.call(&"presentation_state") == &"twitch":
			var loop := _loop(Policy.HEURISTIC)
			var state := loop.exporter.snapshot(_root, _player, 1, 0.0)
			loop.finish({})
			for enemy in state["enemies"]:
				seen = seen or (enemy["type"] == "drop_spider" and enemy["telegraph"])
			break
	_check(seen, "a twitching drop spider is exported as winding up")
	spider.queue_free()
	GameState.reset_health()
	await _frames(40)


## "missiles" and "missile_tank:2" are three Bolt Quivers, not two (the ids used to collide).
func _test_kit_pickups_stack() -> void:
	var agent := Agent.new()
	GameState.reset_progress()
	agent.options["kit"] = "missile_tank:1"
	agent._grant(agent.kit())
	var one := GameState.max_missiles
	GameState.reset_progress()
	agent.options["kit"] = "missiles,missile_tank:2"
	agent._grant(agent.kit())
	_check(
		one > 0 and GameState.max_missiles == one * 3,
		"three quivers granted (%d harpoons, one quiver holds %d)" % [GameState.max_missiles, one]
	)
	agent.free()
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()


func _test_bridge_round_trip() -> void:
	var stub := StubServer.new()
	_check(stub.start(true), "stub server listens")
	var loop := _loop(Policy.EXTERNAL)
	_check(loop.connect_external(stub.port, {"run_id": "check"}), "bridge connects")
	loop.physics_step(1.0 / 60.0)
	await get_tree().physics_frame
	loop.finish({"end_reason": "check"})
	stub.stop()
	var types := stub.received.map(func(message: Dictionary) -> String: return message["type"])
	_check(types == ["hello", "decide", "bye"], "wire messages in order (%s)" % [types])
	if types.size() >= 2:
		var decide: Dictionary = stub.received[1]
		_check(decide["candidates"].size() >= 2, "decide carries candidates")
		_check(decide["state"].has("player"), "decide carries the state")
		_check(
			loop.current["key"] == decide["candidates"][1]["key"], "the server's choice is played"
		)
	var record: Dictionary = loop.telemetry.decisions.get(Policy.EXTERNAL, {})
	_check(
		record.get("fallbacks", {"x": 1}).is_empty(), "no fallback on a good reply (%s)" % record
	)
	loop.driver.release_all()


func _test_timeout_falls_back() -> void:
	var stub := StubServer.new()
	stub.start(false)
	var loop := _loop(Policy.EXTERNAL)
	loop.timeout_ms = 150
	loop.connect_external(stub.port, {"run_id": "check"})
	var started := Time.get_ticks_msec()
	loop.physics_step(1.0 / 60.0)
	var waited := Time.get_ticks_msec() - started
	loop.finish({})
	stub.stop()
	var fallbacks: Dictionary = loop.telemetry.decisions[Policy.EXTERNAL]["fallbacks"]
	_check(fallbacks.get("timeout", 0) == 1, "a silent server times out (%s)" % fallbacks)
	_check(waited >= 140 and waited < 1500, "the wait is bounded by the timeout (%d ms)" % waited)
	_check(not loop.current.is_empty(), "the heuristic still picks an action")


func _test_missing_server_falls_back() -> void:
	var probe := TCPServer.new()
	probe.listen(0, "127.0.0.1")
	var closed_port := probe.get_local_port()
	probe.stop()
	var loop := _loop(Policy.EXTERNAL)
	_check(not loop.connect_external(closed_port, {}), "no server: connect fails")
	loop.physics_step(1.0 / 60.0)
	loop.finish({})
	var fallbacks: Dictionary = loop.telemetry.decisions[Policy.EXTERNAL]["fallbacks"]
	_check(fallbacks.get("not_connected", 0) == 1, "no server: heuristic fallback (%s)" % fallbacks)
