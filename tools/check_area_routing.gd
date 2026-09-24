extends Node

const LEVEL_SCENE = preload("res://scenes/levels/level_01.tscn")
const EXPECTED_AREAS: Dictionary[String, StringName] = {
	"S0": &"fringe",
	"S1": &"fringe",
	"S2": &"nexus",
	"S3": &"nexus",
	"S4": &"vaults",
	"S5": &"vaults",
	"S6": &"kiln",
	"S7": &"kiln",
	"S8": &"depths",
	"S9": &"depths",
	"S10": &"depths",
}

var _failures: Array[String] = []
var _level: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _is_dev_enabled():
		await _run_normal_boot()
		return
	if not _is_isolated_dev_test():
		_fail("run requires --dev-mode, --test-mode and --test-save-root=<absolute path>")
		await _finish()
		return
	var packed := LEVEL_SCENE as PackedScene
	if packed == null:
		_fail("level_01.tscn could not be loaded")
		await _finish()
		return
	_level = packed.instantiate()
	get_tree().root.add_child(_level)
	await get_tree().process_frame
	await get_tree().process_frame
	var controller := _level
	var room_runtime := controller.get("_room_runtime") as RefCounted
	if room_runtime == null:
		_fail("DevRuntimeRoom was not configured")
		await _finish()
		return
	for room_id in EXPECTED_AREAS:
		var area: StringName = room_runtime.call("area_for_room", room_id)
		if area != EXPECTED_AREAS[room_id]:
			_fail("%s routes to %s instead of %s" % [room_id, area, EXPECTED_AREAS[room_id]])
	if room_runtime.call("area_for_room", "prototype") != &"fringe":
		_fail("prototype compatibility route is not fringe")
	var initial_routes: int = room_runtime.get("route_count")
	var audio := get_node_or_null("/root/Audio")
	for route in [
		["S2", &"nexus", true],
		["S3", &"nexus", false],
		["S4", &"vaults", true],
		["S5", &"vaults", false]
	]:
		var before: int = room_runtime.get("route_count")
		controller.call("_on_room_entered", route[0])
		await get_tree().process_frame
		if room_runtime.call("current_area") != route[1]:
			_fail("%s did not set current area %s" % [route[0], route[1]])
		if audio == null or not audio.call("music_is_playing", route[1]):
			_fail("%s did not play routed %s melody" % [route[0], route[1]])
		var delta: int = int(room_runtime.get("route_count")) - before
		if delta != (1 if route[2] else 0):
			_fail("%s restarted or skipped its area route" % route[0])
	controller.call("_on_room_entered", "S8")
	var depths_routes: int = room_runtime.get("route_count")
	controller.call("_on_room_entered", "S8")
	if room_runtime.get("route_count") != depths_routes:
		_fail("re-entering S8 restarted music route")
	if room_runtime.call("current_area") != &"depths":
		_fail("S8 current area is not depths")
	if depths_routes <= initial_routes:
		_fail("S8 room transition did not route music")
	if audio == null or not audio.call("music_is_playing", &"depths"):
		_fail("S8 did not play routed depths melody")
	controller.call("_on_panel_action", &"station", {"index": 8})
	controller.call("_on_panel_action", &"save", {})
	controller.call("_on_panel_action", &"station", {"index": 0})
	controller.call("_on_panel_action", &"load", {})
	if room_runtime.call("current_area") != &"depths":
		_fail("load did not restore S8 music route")
	if String(controller.get("_current_room")) != "S8":
		_fail("load did not restore S8 room route")
	await _finish()


func _run_normal_boot() -> void:
	var packed := LEVEL_SCENE as PackedScene
	if packed == null:
		_fail("level_01.tscn could not be loaded for normal boot")
		await _finish()
		return
	_level = packed.instantiate()
	get_tree().root.add_child(_level)
	await get_tree().process_frame
	await get_tree().process_frame
	var room_runtime := _level.get("_room_runtime") as RefCounted
	if room_runtime == null or room_runtime.call("current_area") != &"fringe":
		_fail("normal prototype boot did not route fringe music")
	if get_tree().get_nodes_in_group("dev_room").size() != 0:
		_fail("normal boot built dev rooms")
	await _finish()


func _is_dev_enabled() -> bool:
	var arguments := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return arguments.has("--dev-mode")


func _is_isolated_dev_test() -> bool:
	var arguments := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var has_mode := arguments.has("--dev-mode") and arguments.has("--test-mode")
	for argument in arguments:
		if argument.begins_with("--test-save-root="):
			return has_mode and argument.trim_prefix("--test-save-root=").is_absolute_path()
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_level):
		_level.free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("check_area_routing: PASS")
		await TestShutdown.finish(get_tree(), 0)
		return
	for failure in _failures:
		push_error("check_area_routing: " + failure)
	await TestShutdown.finish(get_tree(), 1)
