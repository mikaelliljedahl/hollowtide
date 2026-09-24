extends RefCounted
## Round 3 cases of the playtest agent check (tools/check_playtest_agent.gd runs them in its room):
## beam switching and boss openers, the Resonance Pulse, ammo truth and refills, lava and falling
## spikes in the state and the damage record, the jump shot, and boss-room bounds. The real-input
## cases play candidate programs through the Driver against the real player.

const Actions = preload("res://tools/playtest_actions.gd")
const Aim = preload("res://tools/playtest_aim.gd")
const Boss = preload("res://tools/playtest_boss.gd")
const Loop = preload("res://tools/playtest_loop.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const State = preload("res://tools/playtest_state.gd")
const STATION_SCRIPT = preload("res://scripts/campaign/station.gd")
const FAR_CELL := Vector2i(26, 7)
const STATION_CELL := Vector2i(11, 7)

var _host: Node
var _root: Node
var _player: Player


## `host` is the check scene: it owns `_check`, `_frames`, `_root` and `_player`.
func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	await _test_beam_switch_and_opener()
	await _test_real_boss_facts()
	await _test_pulse()
	await _test_ammo_truth_and_refill()
	await _test_hazards()
	await _test_jump_shot()
	_test_boss_room_bounds()
	_reset_kit()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame


func _state() -> Dictionary:
	return State.new().snapshot(_root, _player, 1, 0.0)


func _pick(state: Dictionary) -> String:
	return Policy.new(1).heuristic(state, Actions.public(Actions.candidates(state, _player)), false)


func _keys(state: Dictionary) -> Array:
	return Actions.candidates(state, _player).map(func(e: Dictionary) -> String: return e["key"])


## Plays `program` through the Driver, one entry per physics frame; returns the feet's rise in
## px at the first frame that holds `watch` (0 when none does).
func _play(program: Array, watch: StringName = &"") -> float:
	var driver := Programs.Driver.new()
	driver.start(program)
	var start := _player.global_position
	var rise := 0.0
	while not driver.done():
		var held: Array = program[driver.frame]
		driver.step()
		await _host.get_tree().physics_frame
		if rise == 0.0 and not watch.is_empty() and held.has(watch):
			rise = start.y - _player.global_position.y
	driver.release_all()
	await _frames(20)
	return rise


func _reset_kit(abilities: Array[StringName] = [&"beam"]) -> void:
	GameState.reset_progress()
	for id in abilities:
		GameState.unlock_ability(id)
	GameState.reset_health()


static func _boss(rel: Vector2, open: bool, opener: Variant, hurt_by: Array) -> Dictionary:
	return {
		"id": "e9",
		"type": "tidal_heart",
		"rel": [roundi(rel.x), roundi(rel.y)],
		"dist": roundi(rel.length()),
		"health": 400,
		"max_health": 400,
		"is_boss": true,
		"telegraph": false,
		"ambush": false,
		"hurt_by": hurt_by,
		"switch_to": "",
		"visible": true,
		"stage": 1,
		"attack": "",
		"attack_state": "idle",
		"engaged": true,
		"phase": 1,
		"open": open,
		"opener": opener,
		"arena_rel": null,
	}


static func _enemy(id: String, type: String, rel: Vector2, hurt_by: Array) -> Dictionary:
	var boss := _boss(rel, true, null, hurt_by)
	boss.merge({"id": id, "type": type, "is_boss": false, "health": 40, "max_health": 40}, true)
	return boss


# --- cases ------------------------------------------------------------------------------------


## The Tidal Heart's Snare opener: switch to the Snare through `cycle_beam`, then fire it.
func _test_beam_switch_and_opener() -> void:
	_reset_kit([&"beam", &"ice_beam", &"wave_beam"])
	var state := _state()
	var kit: Dictionary = state["kit"]
	_check(
		kit["beams"] == ["base", "ice", "wave"] and kit["beam"] == "wave",
		"kit lists the owned beams and the equipped one (%s)" % kit
	)
	var opener := {"beam": "ice", "via": "body", "owned": true, "point_rel": [300, -320]}
	var boss := _boss(Vector2(300, -320), false, opener, [])
	state["enemies"] = [boss]
	var select := Actions.find(Actions.candidates(state, _player), "select_beam:ice")
	_check(
		not select.is_empty() and String(select.get("label", "")).contains("opens"),
		"a closed boss offers the Snare, labelled as its opener (%s)" % select.get("label")
	)
	_check(_pick(state) == "select_beam:ice", "the heuristic switches to the opener's beam")
	await _play(select.get("program", []))
	_check(
		GameState.active_beam == &"ice",
		"cycle_beam taps equip the Snare (%s)" % GameState.active_beam
	)
	state = _state()
	state["enemies"] = [boss]
	var keys := _keys(state)
	_check(
		keys.has("open_boss:e9:diag_up"),
		"with the Snare equipped the opener is offered (%s)" % [keys]
	)
	_check(_pick(state) == "open_boss:e9:diag_up", "the heuristic fires the opener")
	_check(
		not keys.any(func(k: String) -> bool: return k.begins_with("jump_over")),
		"no jump into a floating boss"
	)
	var approach := Actions.find(Actions.candidates(state, _player), "approach:e9")
	var jumps := (approach.get("program", []) as Array).filter(
		func(h: Array) -> bool: return h.has(&"jump")
	)
	_check(not approach.is_empty() and jumps.is_empty(), "approaching a floating boss never jumps")
	boss["open"] = true
	boss["hurt_by"] = []
	state["enemies"] = [boss]
	_check(
		not _keys(state).any(func(k: String) -> bool: return k.begins_with("harpoon")),
		"no harpoon while no bolt is left, even with the shell open"
	)


## A real Tidal Heart exports its phase, closed shell and Snare opener; its grate is found.
func _test_real_boss_facts() -> void:
	_reset_kit([&"beam", &"ice_beam"])
	var boss := EnemyFactory.create(&"tidal_heart") as Node2D
	var entities := WorldFxTestbed.entities(_root.current_room)
	boss.position = entities.to_local(
		WorldFxTestbed.feet(_root.current_room, FAR_CELL) - Vector2(0, 300)
	)
	entities.add_child(boss)
	var grate := WaveGrate.new()
	entities.add_child(grate)
	grate.set_relay(boss)
	await _frames(2)
	var found: Array = _state()["enemies"].filter(func(e: Dictionary) -> bool: return e["is_boss"])
	var entry: Dictionary = found[0] if not found.is_empty() else {}
	var opener = entry.get("opener")
	_check(
		(
			entry.get("phase") == 1
			and entry.get("open") == false
			and opener is Dictionary
			and opener["beam"] == "ice"
			and opener["via"] == "body"
			and opener["owned"]
		),
		"a real Tidal Heart reads closed with the Snare as opener (%s)" % entry
	)
	_check(
		entry.get("hurt_by") == [],
		"nothing the kit holds hurts it closed (%s)" % [entry.get("hurt_by")]
	)
	_check(Boss.grate_of(boss) == grate, "its Echo grate is found through the relay")
	boss.queue_free()
	grate.queue_free()
	await _frames(2)


## An armored guard that only the pulse hurts: the pulse is offered, chosen and really placed.
func _test_pulse() -> void:
	_reset_kit([&"beam", &"slipstream", &"bombs"])
	var state := _state()
	state["enemies"] = [_enemy("e7", "armored_guard", Vector2(300, 0), ["bomb"])]
	var pulse := Actions.find(Actions.candidates(state, _player), "pulse:e7")
	_check(not pulse.is_empty(), "a Resonance Pulse is offered at a pulse-only enemy")
	_check(_pick(state) == "pulse:e7", "the heuristic lays the pulse")
	var placed := false
	var driver := Programs.Driver.new()
	driver.start(pulse.get("program", []))
	while not driver.done():
		driver.step()
		await _host.get_tree().physics_frame
		placed = placed or not _host.get_tree().get_nodes_in_group(&"bombs").is_empty()
	driver.release_all()
	await _frames(60)
	_check(placed, "the pulse program places a Resonance Pulse through inputs")
	_check(not _player.is_ball, "and stands the player up again")


## No Harpoon in `hurt_by` without bolts; an empty quiver walks to a known refill and refills.
func _test_ammo_truth_and_refill() -> void:
	_reset_kit()
	GameState.collect_pickup("round3.quiver", &"missile_tank")
	var hopper := EnemyFactory.create(&"hopper") as Node2D
	WorldFxTestbed.entities(_root.current_room).add_child(hopper)
	hopper.global_position = WorldFxTestbed.feet(_root.current_room, FAR_CELL)
	await _frames(2)
	_check(State.hurt_by(hopper).has("missile"), "with bolts the Harpoon hurts the hopper")
	while GameState.spend_missile():
		pass
	_check(not State.hurt_by(hopper).has("missile"), "with no bolt left the Harpoon is not listed")
	hopper.queue_free()
	var station := STATION_SCRIPT.new()
	station.set("station_kind", &"missilerefill")
	var entities := WorldFxTestbed.entities(_root.current_room)
	station.position = entities.to_local(WorldFxTestbed.feet(_root.current_room, STATION_CELL))
	entities.add_child(station)
	await _frames(45)
	var state := _state()
	var refills: Array = state["refills"]
	_check(
		(
			not refills.is_empty()
			and refills[0]["kind"] == "missilerefill"
			and refills[0]["restores"] == ["harpoons"]
		),
		"the room's refill shrine is exported (%s)" % [refills]
	)
	_check(_pick(state) == "go_to_refill:missilerefill", "an empty quiver heads for the refill")
	for _step in 30:
		var entry := Actions.find(
			Actions.candidates(_state(), _player), "go_to_refill:missilerefill"
		)
		if entry.is_empty() or GameState.missile_count > 0:
			break
		await _play(entry["program"])
	_check(
		GameState.missile_count > 0,
		"walking there refills the Harpoons (%d)" % GameState.missile_count
	)
	_check(
		not _keys(_state()).any(func(k: String) -> bool: return k.begins_with("go_to_refill")),
		"a full quiver offers no refill"
	)
	state["player"]["health"] = 20
	state["kit"]["missiles"] = 5
	state["refills"] = [{"kind": "refill", "restores": ["health", "harpoons"], "rel": [600, 0]}]
	_check(_keys(state).has("go_to_refill:refill"), "low health offers the health refill")
	station.queue_free()
	await _frames(2)


## Lava and a falling spike are in the state and name themselves in the damage record.
func _test_hazards() -> void:
	_reset_kit()
	var loop := Loop.new(_root, _player, Policy.HEURISTIC, 3, [])
	var entities := WorldFxTestbed.entities(_root.current_room)
	var lava := DevHazard.new()
	lava.configure_profile(&"lava_surface", Vector2(256, 64), 12)
	lava.position = entities.to_local(_player.global_position + Vector2(0, -32))
	entities.add_child(lava)
	await _frames(1)
	var hazards: Array = _state()["hazards"]
	_check(
		not hazards.is_empty() and hazards[0]["kind"] == "lava" and hazards[0]["gap"] == 0,
		"lava under the player is in the state (%s)" % [hazards]
	)
	await _tick_until_hit(loop)
	_check(
		loop.telemetry.damage.has("hazard:lava"),
		"lava damage is credited to lava (%s)" % loop.telemetry.damage
	)
	lava.queue_free()
	GameState.reset_health()
	await _tick(loop, 90)
	var spike := Stalactite.new()
	var column := Vector2i(floori(_player.global_position.x / 64.0), 0)
	spike.position = entities.to_local(WorldFxTestbed.feet(_root.current_room, column))
	entities.add_child(spike)
	await _frames(1)
	hazards = _state()["hazards"]
	_check(
		hazards.any(func(h: Dictionary) -> bool: return h["kind"] == "stalactite"),
		"a spike overhead is in the state (%s)" % [hazards]
	)
	await _tick_until_hit(loop)
	_check(
		loop.telemetry.damage.has("hazard:stalactite"),
		"a falling spike is credited (%s)" % loop.telemetry.damage
	)
	loop.finish({})
	spike.queue_free()
	GameState.reset_health()
	await _frames(90)


func _tick(loop: Loop, count: int) -> void:
	for _frame in count:
		loop.telemetry.tick(1.0 / 60.0, false, "")
		await _host.get_tree().physics_frame


func _tick_until_hit(loop: Loop) -> void:
	var health := GameState.health
	for _frame in 240:
		await _tick(loop, 1)
		if GameState.health < health:
			return


## A turret 232 px up at range (vaults_01): no level shot, a jump shot that fires at the height.
func _test_jump_shot() -> void:
	_reset_kit()
	await _frames(30)
	var frame := Aim.jump_fire_frame(132.0)
	_check(frame >= 6 and frame <= 9, "a 132 px rise fires on frame 6 to 9 (%d)" % frame)
	var state := _state()
	state["enemies"] = [_enemy("e6", "shard_turret", Vector2(600, -232), ["beam"])]
	var keys := _keys(state)
	_check(
		(
			keys.has("jump_shoot:e6")
			and not keys.any(func(k: String) -> bool: return k.begins_with("shoot:"))
		),
		"a high target gets a jump shot instead of a level shot (%s)" % [keys]
	)
	_check(_pick(state) == "jump_shoot:e6", "the heuristic takes the jump shot")
	var program := Programs.jump_shoot(1, frame, _player.facing)
	var rise := await _play(program, &"fire_beam")
	_check(absf(rise - 132.0) <= 40.0, "the bolt leaves about 132 px up (%.0f)" % rise)


## A live boss's arena bounds the retreat; the plain jumps always close the list.
func _test_boss_room_bounds() -> void:
	var state := _state()
	var boss := _boss(
		Vector2(300, 0),
		false,
		{"beam": "", "via": "punish", "owned": true, "point_rel": [300, 0]},
		[]
	)
	boss["arena_rel"] = [-100, -600, 1500, 100]
	state["enemies"] = [boss]
	var options := Actions.candidates(state, _player)
	var keys := options.map(func(e: Dictionary) -> String: return e["key"])
	_check(not keys.has("retreat"), "no retreat out of a live boss's arena (%s)" % [keys])
	_check(_pick(state) != "retreat", "the heuristic keeps its spacing inside")
	_check(
		(
			options.size() <= Actions.MAX_CANDIDATES
			and keys[-1] == "jump:right"
			and keys[-2] == "jump:left"
		),
		"at most 14 candidates, the plain jumps last"
	)
	boss["arena_rel"] = [-600, -600, 1500, 100]
	_check(_keys(state).has("retreat"), "with room behind, the retreat returns")
