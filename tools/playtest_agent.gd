extends Node
## Playtest agent launch scene (docs/features/playtest-agent.md). Loads the real campaign in one
## room with a chosen kit and lets a policy play it through input events only, then writes a JSON
## and Markdown report. Campaign mode (--playtest-campaign=<route dir>) instead starts a new game
## in the start room with an empty kit and plays toward the ending along a planned route. Dev tool:
## it lives in tools/, refuses to run without --test-mode (so the player's save is never touched)
## and is never reached from normal play.
## godot --path . res://tools/playtest_agent.tscn -- --test-mode --playtest-room=fringe_03
##     --playtest-kit=beam [--playtest-policy=heuristic|random|external] (see the doc for all flags)

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const Loop = preload("res://tools/playtest_loop.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Report = preload("res://tools/playtest_report.gd")
const TrialsAdapter = preload("res://tools/playtest_trials.gd")
const Campaign = preload("res://tools/playtest_campaign.gd")
const Nav = preload("res://tools/playtest_nav.gd")
const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0
const PREFIX := "--playtest-"
const SETTLE_FRAMES := 20
const GOAL_GRACE := 1.0
## A pause no transition explains (a menu the inputs opened, such as the travel map an up-aim
## opens on a save shrine) is closed with Esc after this many guard ticks (1 s of game clock
## each) and ends the run as "stalled_paused" after PAUSE_LIMIT.
const PAUSE_ESCAPE_TICKS := 3
const PAUSE_LIMIT_TICKS := 60
## Wall-clock watchdog: no decision for --playtest-hang-ms (default 30 s) ends the run as "hung"
## and writes hang.json.
## A heartbeat (stdout line and heartbeat.txt) this often (wall clock), so the runner can tell a
## frozen process from a slow one (tools/playtest/run.py).
const HEARTBEAT_WALL_MS := 20000
const DEFAULTS := {
	"room": Rooms.START_ROOM,
	"spawn": "",
	"kit": "",
	"seed": "1",
	"seconds": "90",
	"policy": Policy.HEURISTIC,
	"port": "0",
	"timeout-ms": "1000",
	"out": "",
	"run-id": "",
	"goal": "auto",
	"max-deaths": "3",
	"breaks": "",
	"shots": "0",
	"trial": "",
	"campaign": "",
	"hang-ms": "30000",
}

var options: Dictionary = DEFAULTS.duplicate()
var _root: Node
var _loop: Loop
var _goal := "none"
var _goal_at := -1.0
var _running := false
var _paused_ticks := 0
## Menus the pause guard closed: {t, room, menu}.
var _menu_escapes: Array = []
var _seen_tick := -1
var _seen_tick_ms := 0
var _heartbeat_ms := 0
var _next_shot := 0.0
var _shots := 0
var _deaths_seen := 0


func _ready() -> void:
	# Run before the player so injected input lands in the same physics frame.
	process_physics_priority = -100
	var problem := parse_options(OS.get_cmdline_user_args())
	if (
		problem.is_empty()
		and not (OS.is_debug_build() and OS.get_cmdline_user_args().has("--test-mode"))
	):
		problem = "refusing to run without --test-mode (it would write to the real save)"
	if not problem.is_empty():
		printerr("playtest: " + problem)
		get_tree().quit(2)
		return
	call_deferred("_start")


## Reads --playtest-<name>=<value> arguments into `options`; returns an error message or "".
func parse_options(arguments: PackedStringArray) -> String:
	for argument in arguments:
		if not argument.begins_with(PREFIX):
			continue
		var pair := argument.trim_prefix(PREFIX).split("=", true, 1)
		if not DEFAULTS.has(pair[0]) or pair.size() != 2:
			return "unknown option %s" % argument
		options[pair[0]] = pair[1]
	if not options["campaign"].is_empty():
		if not (
			options["kit"].is_empty()
			and options["spawn"].is_empty()
			and options["trial"].is_empty()
		):
			return "campaign mode starts a new game: no kit, spawn or trial"
		options["room"] = Rooms.START_ROOM
		options["goal"] = "ending"
	if not options["trial"].is_empty():
		if not TrialCatalog.is_mode(StringName(options["trial"])):
			return "unknown trial %s" % options["trial"]
		options["room"] = "trials_%s" % options["trial"]
	elif not Rooms.ROOMS.has(options["room"]):
		return "unknown room %s" % options["room"]
	if not options["policy"] in Policy.NAMES:
		return "unknown policy %s (use %s)" % [options["policy"], ", ".join(Policy.NAMES)]
	if options["policy"] == Policy.EXTERNAL and int(options["port"]) <= 0:
		return "the external policy needs --playtest-port=<port>"
	if options["run-id"].is_empty():
		options["run-id"] = "%s-%s-s%s" % [options["room"], options["policy"], options["seed"]]
	if options["out"].is_empty():
		options["out"] = "user://playtest/%s" % options["run-id"]
	return ""


func _start() -> void:
	seed(int(options["seed"]))
	var room_id: String = options["room"]
	if not options["campaign"].is_empty():
		# A new game exactly as the start menu begins one (CampaignEntry.new_game without the
		# scene change): empty kit, the start room, the save slot written at the first shrine.
		CampaignEntry.prepare_new_game()
		_root = CAMPAIGN.instantiate()
	elif options["trial"].is_empty():
		var spawn := _spawn(room_id)
		GameState.reset_progress()
		_grant(kit())
		GameState.reset_health()
		# The campaign loads the checkpoint room, and deaths return here too.
		GameState.set_checkpoint(room_id, spawn)
		_root = CAMPAIGN.instantiate()
	else:
		# A trial equips its own fixed kit; --playtest-kit and --playtest-spawn do not apply.
		_root = TrialsAdapter.new(StringName(options["trial"]))
	add_child(_root)
	for _frame in SETTLE_FRAMES:
		await get_tree().physics_frame
	var player := _root.get("player") as Player
	_loop = Loop.new(
		_root, player, options["policy"], int(options["seed"]), _break_specs(options["breaks"])
	)
	_loop.timeout_ms = int(options["timeout-ms"])
	if not options["campaign"].is_empty() and not _start_campaign(player):
		return
	if options["policy"] == Policy.EXTERNAL:
		_loop.connect_external(int(options["port"]), {"run_id": options["run-id"], "room": room_id})
	_goal = _pick_goal()
	_running = true
	var guard := Timer.new()
	guard.wait_time = 1.0
	guard.process_mode = Node.PROCESS_MODE_ALWAYS
	guard.timeout.connect(_on_pause_guard)
	add_child(guard)
	guard.start()
	print("playtest: %s started (goal %s)" % [options["run-id"], _goal])


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_loop.physics_step(delta)
	var telemetry := _loop.telemetry
	_capture(telemetry)
	var reason := ""
	if telemetry.now >= float(options["seconds"]):
		reason = "time"
	elif telemetry.deaths.size() >= int(options["max-deaths"]):
		reason = "max_deaths"
	elif _loop.campaign != null:
		reason = _loop.campaign.update(telemetry.now, telemetry)
	elif _trial_result().has("cleared"):
		reason = "goal_trial" if _trial_result()["cleared"] else "trial_failed"
	elif _goal_reached(telemetry):
		if _goal_at < 0.0:
			_goal_at = telemetry.now
		elif telemetry.now - _goal_at >= GOAL_GRACE:
			reason = "goal_" + _goal
	if not reason.is_empty():
		_finish(reason)


func _start_campaign(player: Player) -> bool:
	var campaign := Campaign.new()
	var problem := campaign.setup(options["campaign"], _root, player)
	var directory := ProjectSettings.globalize_path(options["out"])
	DirAccess.make_dir_recursive_absolute(directory)
	if problem.is_empty() and not _loop.open_log(directory.path_join("decisions.jsonl")):
		problem = "cannot write %s" % directory.path_join("decisions.jsonl")
	if not problem.is_empty():
		printerr("playtest: " + problem)
		_root.queue_free()
		get_tree().quit(2)
		return false
	_loop.campaign = campaign
	return true


## Runs while the tree is paused too. Room fades, respawns, trips and the ending pause briefly and
## are left alone; anything else is a menu the agent's inputs opened. Also the wall-clock watchdog.
func _on_pause_guard() -> void:
	if _running:
		var idle := watch_hang()
		if idle >= 0:
			dump_hang(idle)
			_finish("hung")
			return
	var tree := get_tree()
	var expected: bool = (
		_root == null
		or _root.get("_busy") == true
		or _root.get("_respawning") == true
		or _root.get("_ending") == true
	)
	if not _running or not tree.paused or expected:
		_paused_ticks = 0
		return
	_paused_ticks += 1
	if _paused_ticks == PAUSE_ESCAPE_TICKS or _paused_ticks == PAUSE_ESCAPE_TICKS * 3:
		(
			_menu_escapes
			. append(
				{
					"t": snappedf(_loop.telemetry.now, 0.1),
					"room": String(_root.get("current_room_id")),
					"menu": _open_menu(),
				}
			)
		)
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_ESCAPE
			key.keycode = KEY_ESCAPE
			key.pressed = pressed
			Input.parse_input_event(key)
		Input.flush_buffered_events()
	elif _paused_ticks >= PAUSE_LIMIT_TICKS:
		_finish("stalled_paused")


## The wall time (ms) without a new decision once it reaches hang-ms, else -1: the run is hung,
## whatever the cause (a pause nothing explains, a transition that never finished, a program
## that never ends). Prints a heartbeat meanwhile.
func watch_hang() -> int:
	var now := Time.get_ticks_msec()
	if _loop.tick != _seen_tick:
		_seen_tick = _loop.tick
		_seen_tick_ms = now
	if now - _heartbeat_ms >= HEARTBEAT_WALL_MS:
		_heartbeat_ms = now
		var line := (
			"playtest: alive tick %d t %.1f room %s"
			% [_loop.tick, _loop.telemetry.now, String(_root.get("current_room_id"))]
		)
		print(line)
		# Piped stdout is block-buffered, so the runner watches this file's mtime instead.
		var directory := ProjectSettings.globalize_path(String(options["out"]))
		DirAccess.make_dir_recursive_absolute(directory)
		var file := FileAccess.open(directory.path_join("heartbeat.txt"), FileAccess.WRITE)
		if file != null:
			file.store_line(line)
			file.close()
	if now - _seen_tick_ms < int(options["hang-ms"]):
		return -1
	return now - _seen_tick_ms


## hang.json in the output directory: what the game and the driver were doing.
func dump_hang(idle_ms: int) -> void:
	var player := _root.get("player") as Player
	var pressed: Array = []
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_") and Input.is_action_pressed(action):
			pressed.append(String(action))
	var dump := {
		"idle_wall_ms": idle_ms,
		"tick": _loop.tick,
		"t": snappedf(_loop.telemetry.now, 0.01),
		"paused": get_tree().paused,
		"root_busy": _root.get("_busy"),
		"root_respawning": _root.get("_respawning"),
		"root_ending": _root.get("_ending"),
		"menu": _open_menu() if get_tree().paused else "",
		"current_scene": str(get_tree().current_scene.name) if get_tree().current_scene else "",
		"room": String(_root.get("current_room_id")),
		"health": GameState.health,
		"player_pos": [player.global_position.x, player.global_position.y] if player else [],
		"program": String(_loop.current.get("key", "")),
		"program_done": _loop.driver.done(),
		"driver_frame": _loop.driver.frame,
		"held": _loop.driver.held().map(func(a: StringName) -> String: return String(a)),
		"pressed_actions": pressed,
	}
	var directory := ProjectSettings.globalize_path(String(options["out"]))
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("hang.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(dump, "  "))
		file.close()
	printerr("playtest: no decision for %d ms; ending the run as hung" % idle_ms)


func _open_menu() -> String:
	var map = _root.get("map")
	if map != null and bool(map.get("visible")):
		return "travel_map" if bool(map.call("is_travel_mode")) else "map"
	var shrine = _root.get("shrine_menu")
	if shrine != null and bool(shrine.call("is_open")):
		return "shrine_menu"
	return "other"


## The parsed kit: ability ids and pickup kinds, "kind:count" for repeated pickups.
func kit() -> Array[String]:
	var result: Array[String] = []
	for item in String(options["kit"]).split(",", false):
		result.append(item.strip_edges())
	return result


func _grant(items: Array[String]) -> void:
	# Pickup ids must be unique per kind ("missiles" and "missile_tank:2" are three quivers).
	var granted: Dictionary = {}
	for item in items:
		var parts := item.split(":")
		var id := StringName(parts[0])
		var count := int(parts[1]) if parts.size() > 1 else 1
		if id == &"missiles":
			id = &"missile_tank"
		elif Catalog.is_ability(id):
			GameState.unlock_ability(id)
			continue
		for _index in count:
			var index := int(granted.get(id, 0))
			granted[id] = index + 1
			GameState.collect_pickup("playtest.%s.%d" % [id, index], id)


func _spawn(room_id: String) -> Vector2:
	var cell := String(options["spawn"]).split(",", false)
	if cell.size() == 2:
		return Vector2((float(cell[0]) + 0.5) * TILE, (float(cell[1]) + 1.0) * TILE)
	var saves: Array = Rooms.ROOMS[room_id]["saves"]
	if not saves.is_empty():
		return saves[0]
	var size := Vector2(Rooms.ROOMS[room_id]["size"]) * TILE
	return Vector2(size.x * 0.5, size.y * 0.5)


## "id:room:x:y" entries separated by ";" (tools/playtest/run.py fills them from
## tools/campaign_breaks.py).
static func _break_specs(text: String) -> Array:
	var specs: Array = []
	for entry in text.split(";", false):
		var parts := entry.split(":")
		if parts.size() == 4:
			specs.append(
				{"id": parts[0], "room": parts[1], "cell": Vector2i(int(parts[2]), int(parts[3]))}
			)
	return specs


func _pick_goal() -> String:
	if not options["trial"].is_empty():
		return "trial"
	if options["goal"] != "auto":
		return options["goal"]
	for node in get_tree().get_nodes_in_group(&"worldfx_ambush"):
		if (node as AmbushArena).state != AmbushArena.State.CLEARED:
			return "ambush"
	for node in get_tree().get_nodes_in_group(&"bosses"):
		if int(node.get("health")) > 0:
			return "boss"
	return "none"


func _goal_reached(telemetry: Telemetry) -> bool:
	match _goal:
		"ambush":
			return telemetry.ambushes.any(
				func(f: Dictionary) -> bool: return f["outcome"] == "cleared"
			)
		"boss":
			return telemetry.bosses.any(
				func(b: Dictionary) -> bool: return b["outcome"] == "defeated"
			)
	return false


## Windowed runs save a frame every --playtest-shots seconds and at each death.
func _capture(telemetry: Telemetry) -> void:
	var interval := float(options["shots"])
	if interval <= 0.0 or DisplayServer.get_name() == "headless":
		return
	var died := telemetry.deaths.size() > _deaths_seen
	_deaths_seen = telemetry.deaths.size()
	if telemetry.now < _next_shot and not died:
		return
	if not died:
		_next_shot = telemetry.now + interval
	var directory := ProjectSettings.globalize_path(String(options["out"]).path_join("shots"))
	DirAccess.make_dir_recursive_absolute(directory)
	var image := get_viewport().get_texture().get_image()
	var file_name := "t%06.1f%s.png" % [telemetry.now, "-death" if died else ""]
	if image != null and image.save_png(directory.path_join(file_name)) == OK:
		_shots += 1


## The Trials result once the trial ended ({mode, cleared, time_ms, hits}); empty otherwise.
func _trial_result() -> Dictionary:
	var result: Variant = _root.get("result") if _root is TrialsAdapter else null
	return result if result is Dictionary else {}


func _finish(reason: String) -> void:
	_running = false
	var telemetry := _loop.telemetry
	var campaign := _loop.campaign
	var where := Nav.Navigator.locate(_root, _root.get("player") as Player)
	var streamed := _loop.streaming()
	_loop.finish({"end_reason": reason, "seconds": telemetry.now})
	var record := {
		"meta":
		{
			"run_id": options["run-id"],
			"room": options["room"],
			"kit": kit(),
			"policy": options["policy"],
			"seed": int(options["seed"]),
			"seconds_limit": float(options["seconds"]),
			"goal": _goal,
			"end_reason": reason,
			"decisions": _loop.tick,
			"screenshots": _shots,
			"menu_escapes": _menu_escapes,
			"godot": Engine.get_version_info()["string"],
			"trial": _trial_result(),
		},
		"telemetry": telemetry.to_dict(),
	}
	if campaign != null:
		record["campaign"] = campaign.progress.finish(
			campaign.route, telemetry, campaign.ending(), reason, where
		)
		record["campaign"]["fast_travel"] = campaign.travel.trips
		record["campaign"]["route"] = options["campaign"]
	var directory: String = options["out"]
	var result := Report.write(record, directory)
	if not streamed:
		var log_file := FileAccess.open(
			ProjectSettings.globalize_path(directory.path_join("decisions.jsonl")), FileAccess.WRITE
		)
		if log_file != null:
			log_file.store_string("\n".join(_loop.decision_log) + "\n")
			log_file.close()
	if result == OK:
		print("PLAYTEST REPORT %s" % ProjectSettings.globalize_path(directory))
		for finding in record["findings"]:
			print("  - " + finding)
	else:
		printerr("playtest: could not write the report: %s" % error_string(result))
	_root.queue_free()
	await get_tree().physics_frame
	await TestShutdown.finish(get_tree(), 0 if result == OK else 1)
