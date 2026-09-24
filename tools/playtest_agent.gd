extends Node
## Playtest agent launch scene (docs/features/playtest-agent.md). Loads the real campaign in one
## room with a chosen kit and lets a policy play it through input events only, then writes a JSON
## and Markdown report. Dev tool: it lives in tools/, refuses to run without --test-mode (so the
## player's save is never touched) and is never reached from normal play.
## godot --path . res://tools/playtest_agent.tscn -- --test-mode --playtest-room=fringe_03
##     --playtest-kit=beam [--playtest-policy=heuristic|random|external] (see the doc for all flags)

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const Loop = preload("res://tools/playtest_loop.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Report = preload("res://tools/playtest_report.gd")
const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0
const PREFIX := "--playtest-"
const SETTLE_FRAMES := 20
const GOAL_GRACE := 1.0
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
}

var options: Dictionary = DEFAULTS.duplicate()
var _root: Node
var _loop: Loop
var _goal := "none"
var _goal_at := -1.0
var _running := false
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
	if not Rooms.ROOMS.has(options["room"]):
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
	var spawn := _spawn(room_id)
	GameState.reset_progress()
	_grant(kit())
	GameState.reset_health()
	# The campaign loads the checkpoint room, and deaths return here too.
	GameState.set_checkpoint(room_id, spawn)
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	for _frame in SETTLE_FRAMES:
		await get_tree().physics_frame
	var player := _root.get("player") as Player
	_loop = Loop.new(
		_root, player, options["policy"], int(options["seed"]), _break_specs(options["breaks"])
	)
	_loop.timeout_ms = int(options["timeout-ms"])
	if options["policy"] == Policy.EXTERNAL:
		_loop.connect_external(int(options["port"]), {"run_id": options["run-id"], "room": room_id})
	_goal = _pick_goal()
	_running = true
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
	elif _goal_reached(telemetry):
		if _goal_at < 0.0:
			_goal_at = telemetry.now
		elif telemetry.now - _goal_at >= GOAL_GRACE:
			reason = "goal_" + _goal
	if not reason.is_empty():
		_finish(reason)


## The parsed kit: ability ids and pickup kinds, "kind:count" for repeated pickups.
func kit() -> Array[String]:
	var result: Array[String] = []
	for item in String(options["kit"]).split(",", false):
		result.append(item.strip_edges())
	return result


func _grant(items: Array[String]) -> void:
	for item in items:
		var parts := item.split(":")
		var id := StringName(parts[0])
		var count := int(parts[1]) if parts.size() > 1 else 1
		if id == &"missiles":
			id = &"missile_tank"
		elif Catalog.is_ability(id):
			GameState.unlock_ability(id)
			continue
		for index in count:
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


func _finish(reason: String) -> void:
	_running = false
	var telemetry := _loop.telemetry
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
			"godot": Engine.get_version_info()["string"],
		},
		"telemetry": telemetry.to_dict(),
	}
	var directory: String = options["out"]
	var result := Report.write(record, directory)
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
