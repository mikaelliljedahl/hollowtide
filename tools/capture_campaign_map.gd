extends Node

## Screenshot tool for the campaign map and minimap (working files only, never committed).
## godot --path . --windowed --resolution 1920x1080 res://tools/capture_campaign_map.tscn -- \
##   --test-mode --out=/abs/dir

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const CAMPAIGN_SCENE := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0

## name, discovered rooms, collected pickups, world flags, player room, player local tile.
const SCENES := [
	[
		"early",
		["fringe_01", "fringe_02"],
		["fringe_02.slipstream"],
		[],
		"fringe_02",
		Vector2(17.5, 32)
	],
	[
		"mid",
		["fringe_01", "fringe_02", "fringe_03", "fringe_04", "fringe_05", "nexus_01", "nexus_02"],
		["fringe_02.slipstream", "fringe_03.beam", "fringe_03.missile_01", "fringe_04.bombs"],
		["fringe_03.gate.missile_1", "fringe_04.gate.bomb_1", "fringe_04.gate.floor"],
		"nexus_01",
		Vector2(17.5, 31),
	],
	[
		"late",
		[
			"fringe_01",
			"fringe_02",
			"fringe_03",
			"fringe_04",
			"fringe_05",
			"nexus_01",
			"nexus_02",
			"vaults_01",
			"vaults_02",
			"vaults_03",
			"kiln_01",
		],
		[
			"fringe_02.slipstream",
			"fringe_03.beam",
			"fringe_03.missile_01",
			"fringe_04.bombs",
			"vaults_02.ice_beam",
			"vaults_02.high_jump",
		],
		[
			"fringe_03.gate.missile_1",
			"fringe_04.gate.bomb_1",
			"fringe_04.gate.floor",
			"boss:stone_guardian",
			"regional:stone_guardian",
		],
		"kiln_01",
		Vector2(8.5, 14),
	],
]

var _out := ""
var _viewport: SubViewport


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	if _out.is_empty():
		_out = OS.get_cache_dir().path_join("hollowtide-map-shots")
	DirAccess.make_dir_recursive_absolute(_out)
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	GameState.set_checkpoint(Rooms.START_ROOM, Rooms.START_POSITION)
	# Render into a fixed 1920x1080 target whatever size the desktop gives the window.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var root := CAMPAIGN_SCENE.instantiate()
	_viewport.add_child(root)
	await get_tree().create_timer(0.3).timeout
	for scene in SCENES:
		GameState.discovered_rooms.clear()
		GameState.collected_pickup_ids.clear()
		GameState.world_flags.clear()
		for id in scene[1]:
			GameState.discover_room(id)
		for id in scene[2]:
			GameState.collected_pickup_ids.append(id)
		for flag in scene[3]:
			GameState.set_world_flag(flag)
		root.call("teleport", scene[4], scene[5] * TILE)
		await _settle(40)
		_save("%s_game.png" % scene[0])
		var map := root.get("map") as CanvasLayer
		map.call("open")
		await _settle(20)
		_save("%s_map.png" % scene[0])
		var room: Dictionary = Rooms.ROOMS[scene[4]]
		map.call("focus", Vector2(room["origin"]) + scene[5], 2.2)
		await _settle(10)
		_save("%s_map_zoom.png" % scene[0])
		map.call("close")
		await _settle(5)
	print("map capture: wrote shots to ", _out)
	await TestShutdown.finish(get_tree(), 0)


func _settle(frames: int) -> void:
	for frame in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(file_name: String) -> void:
	var image := _viewport.get_texture().get_image()
	image.save_png(_out.path_join(file_name))
