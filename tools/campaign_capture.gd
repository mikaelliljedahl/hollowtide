extends Node

## Screenshot tool for campaign rooms (working files only, never committed).
## godot --path . --windowed --resolution 1920x1080 res://tools/campaign_capture.tscn -- \
##   --out=/abs/dir [--rooms=fringe_01,fringe_02] [--detail] [--grant=slipstream,beam]

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const CAMPAIGN_SCENE := preload("res://scenes/campaign/campaign.tscn")

var _out := ""
var _rooms: Array[String] = []
var _detail := false
var _map := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--rooms="):
			for id in argument.trim_prefix("--rooms=").split(",", false):
				_rooms.append(id)
		elif argument == "--map":
			_map = true
		elif argument == "--detail":
			_detail = true
		elif argument.begins_with("--grant="):
			for id in argument.trim_prefix("--grant=").split(",", false):
				if id == "missiles":
					GameState.collect_pickup("capture.missile", &"missile_tank")
				else:
					GameState.unlock_ability(StringName(id))
	if _rooms.is_empty():
		for id in Rooms.ROOMS:
			_rooms.append(id)
	if _out.is_empty():
		_out = OS.get_cache_dir().path_join("hollowtide-campaign-shots")
	DirAccess.make_dir_recursive_absolute(_out)
	call_deferred("_run")


func _run() -> void:
	GameState.set_checkpoint(Rooms.START_ROOM, Rooms.START_POSITION)
	var root := CAMPAIGN_SCENE.instantiate()
	add_child(root)
	await get_tree().create_timer(0.3).timeout
	var player := root.get("player") as Node2D
	if _map:
		for id in _rooms:
			GameState.discover_room(id)
		root.call("teleport", "nexus_01", Vector2(17.5 * 64.0, 32 * 64.0))
		await _settle()
		root.get("map").call("open")
		await _settle()
		_save("map.png")
		root.get("map").call("close")
		await TestShutdown.finish(get_tree(), 0)
		return
	var camera := Camera2D.new()
	root.add_child(camera)
	for room_id in _rooms:
		var data: Dictionary = Rooms.ROOMS[room_id]
		var saves: Array = data["saves"]
		var spot: Vector2 = saves[0] if not saves.is_empty() else Vector2(-1, -1)
		root.call("teleport", room_id, spot if spot.x >= 0.0 else _fallback_spot(data))
		var room := root.get("current_room") as Node2D
		var size := Vector2(data["size"]) * 64.0
		camera.limit_left = -100000
		camera.limit_top = -100000
		camera.limit_right = 100000
		camera.limit_bottom = 100000
		camera.make_current()
		var zoom := minf(1920.0 / size.x, 1080.0 / size.y)
		camera.zoom = Vector2(zoom, zoom)
		camera.global_position = room.global_position + size * 0.5
		await _settle()
		_save("%s_overview.png" % room_id)
		if _detail:
			camera.zoom = Vector2.ONE
			var index := 0
			for y in range(0, int(ceil(size.y / 1080.0))):
				for x in range(0, int(ceil(size.x / 1920.0))):
					var center := Vector2(
						minf(960.0 + x * 1920.0, size.x - 960.0),
						minf(540.0 + y * 1080.0, size.y - 540.0)
					)
					camera.global_position = room.global_position + center
					await _settle()
					index += 1
					_save("%s_%02d.png" % [room_id, index])
		if player != null:
			player.set_physics_process(true)
	print("campaign capture: wrote ", _rooms.size(), " rooms to ", _out)
	await TestShutdown.finish(get_tree(), 0)


func _fallback_spot(data: Dictionary) -> Vector2:
	var size := Vector2(data["size"]) * 64.0
	return Vector2(size.x * 0.5, size.y * 0.5)


func _settle() -> void:
	for frame in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(file_name))
