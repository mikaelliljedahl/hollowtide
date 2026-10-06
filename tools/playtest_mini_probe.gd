extends Node
## Mini-boss dodge probe of the playtest agent (docs/features/playtest-agent.md, section 29). In
## each mini-boss's real room, with the full kit, every attack is forced from several spots on the
## arena floor and answered through real inputs (tools/playtest_mini_trial.gd): by fixed responses
## started at several delays after the telegraph begins, and by the heuristic loop itself. It
## prints the damage each response took and writes every trial to --probe-out. Dev tool: refuses
## to run without --test-mode.
## godot --headless --path . --fixed-fps 60 res://tools/playtest_mini_probe.tscn -- --test-mode
##     --test-save-root=<dir> [--probe-mini=fernmaw] [--probe-out=<file.json>]
##     [--probe-responses=idle,jump] [--probe-delays=0,0.6] (the loop always runs)

const Trial = preload("res://tools/playtest_mini_trial.gd")
const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const CAMPAIGN_SCENE := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0
const KIT: Array[StringName] = [
	&"beam",
	&"slipstream",
	&"bombs",
	&"ice_beam",
	&"high_jump",
	&"pressure_seal",
	&"wave_beam",
	&"undertow_dash",
]
## Player spots: px from the boss along the floor, and the two arena pockets (POCKET inside the
## arena's edge).
const OFFSETS: Array[float] = [-512.0, -256.0, 256.0, 512.0]
const POCKET := 80.0
## Seconds after the telegraph starts at which a fixed response starts.
const DELAYS: Array[float] = [0.0, 0.3, 0.6, 0.9, 1.2]

var _root: Node
var _player: Player
var _trials: Array = []
var _trial: Trial
var _responses: Array = Trial.RESPONSES
var _delays: Array = DELAYS


func _ready() -> void:
	process_physics_priority = -100
	if not (OS.is_debug_build() and OS.get_cmdline_user_args().has("--test-mode")):
		printerr("mini-probe: refusing to run without --test-mode")
		get_tree().quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var only := _option("mini")
	if not _option("responses").is_empty():
		_responses = Array(_option("responses").split(",", false))
	if not _option("delays").is_empty():
		_delays = Array(_option("delays").split(",", false)).map(
			func(d: String) -> float: return float(d)
		)
	GameState.reset_progress()
	for id in KIT:
		GameState.unlock_ability(id)
	for index in 4:
		GameState.collect_pickup("probe.quiver.%d" % index, &"missile_tank")
	GameState.reset_health()
	# With a checkpoint set the campaign keeps this kit; without one it starts a new game.
	GameState.set_checkpoint(Rooms.START_ROOM, Rooms.START_POSITION)
	_root = CAMPAIGN_SCENE.instantiate()
	add_child(_root)
	await _frames(20)
	_player = _root.get("player") as Player
	for mini: String in Trial.MINIS:
		if only.is_empty() or only == mini:
			await _probe(mini)
	var out := _option("out")
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(_trials))
		file.close()
	print("mini-probe: done, %d trials" % _trials.size())
	await TestShutdown.finish(get_tree(), 0)


func _probe(mini: String) -> void:
	_trial = Trial.new(_root, _player, mini)
	if not await _trial.ensure_boss():
		print("mini-probe: %s did not spawn in %s" % [mini, Trial.MINIS[mini][0]])
		return
	var spots: Array = await _spots()
	await _scan_engagement()
	for stage in [1, 2]:
		var attacks: Array = Patterns.attacks_in_stage(StringName(mini), stage)
		for attack: StringName in attacks:
			if stage == 2 and Patterns.attacks_in_stage(StringName(mini), 1).has(attack):
				continue
			for spot: Vector2 in spots:
				await _attack_from(stage, attack, spot)


## Quiet floor spots (`Trial.quiet`) where a standing body fits: OFFSETS from the boss and both
## pockets, the lowest floor first.
func _spots() -> Array:
	var arena: Rect2 = _trial.boss.get("arena_bounds")
	var xs: Array = OFFSETS.map(func(offset: float) -> float: return _trial.home.x + offset)
	xs.append_array([arena.position.x + POCKET, arena.end.x - POCKET])
	var spots: Array = []
	for x: float in xs:
		if x < arena.position.x + POCKET or x > arena.end.x - POCKET:
			continue
		var spot = _trial.floor_at(x)
		if not spot is Vector2:
			continue
		if await _trial.quiet(spot):
			spots.append(spot)
		else:
			print("mini-probe: %s spot %s hurts with no attack; left out" % [_trial.mini, spot])
	return spots


## Stands her on the arena's lowest floor every tile across it and reports where the boss engages
## (the arena rectangle against the floor she really stands on).
func _scan_engagement() -> void:
	var boss := _trial.boss
	var arena: Rect2 = boss.get("arena_bounds")
	var outside: Array = []
	var count := 0
	var x := arena.position.x + TILE * 0.5
	while x < arena.end.x:
		var spot = _trial.floor_at(x)
		if spot is Vector2:
			_player.global_position = spot
			_player.velocity = Vector2.ZERO
			for _frame in 12:
				boss.set("_attack_timer", 99.0)
				await get_tree().physics_frame
			count += 1
			if not bool(boss.get("_player_engaged")):
				var feet := _player.global_position - arena.position
				outside.append([roundi(feet.x), roundi(feet.y - arena.size.y)])
		x += TILE
	print(
		(
			"mini-probe: %s engages on %d of %d floor spots; outside (x, feet below the arena): %s"
			% [_trial.mini, count - outside.size(), count, outside]
		)
	)


func _attack_from(stage: int, attack: StringName, spot: Vector2) -> void:
	var summary := {}
	for response: String in _responses:
		var cleared := 0
		for delay: float in _delays:
			var record: Dictionary = await _trial.run(stage, attack, spot, response, delay)
			_trials.append(record)
			cleared += int(record.get("damage", -1) == 0)
		summary[response] = "%d/%d" % [cleared, _delays.size()]
	var loop: Dictionary = await _trial.run(stage, attack, spot, "loop", 0.0)
	_trials.append(loop)
	summary["loop"] = "hit %d" % loop.get("damage", -1) if loop.get("damage", -1) != 0 else "clear"
	print(
		(
			"mini-probe: %s %s stage %d at %s (engaged %s, released %s): %s %s"
			% [
				_trial.mini,
				attack,
				stage,
				loop.get("feet"),
				loop.get("engaged"),
				loop.get("released"),
				summary,
				loop.get("picks")
			]
		)
	)


func _option(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-%s=" % name):
			return argument.split("=", true, 1)[1]
	return ""


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame
