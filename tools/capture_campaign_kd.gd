extends Node

## Screenshot tool for the kiln and depths campaign rooms (working files only, never committed).
## godot --path . --windowed --resolution 1920x1080 res://tools/capture_campaign_kd.tscn -- \
##   --out=/abs/dir [--rooms=kiln_01,depths_02] [--flags=boss:tidal_heart] [--spot=kiln_01:43,3]
## Writes <room>_overview.png (whole room) and <room>_NN.png (1:1 gameplay framing tiles).

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const CAMPAIGN_SCENE := preload("res://scenes/campaign/campaign.tscn")
const KD_ROOMS: Array[String] = [
	"kiln_01", "kiln_02", "kiln_03", "depths_01", "depths_02", "depths_03"
]
const ABILITIES: Array[StringName] = [
	&"beam", &"slipstream", &"bombs", &"pressure_seal", &"ice_beam", &"high_jump", &"wave_beam"
]

var _out := ""
var _rooms: Array[String] = []
var _spots := {}


func _ready() -> void:
	for ability in ABILITIES:
		GameState.unlock_ability(ability)
	GameState.collect_pickup("capture.missile", &"missile_tank")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--rooms="):
			for id in argument.trim_prefix("--rooms=").split(",", false):
				_rooms.append(id)
		elif argument.begins_with("--flags="):
			for flag in argument.trim_prefix("--flags=").split(",", false):
				GameState.set_world_flag(flag)
		elif argument.begins_with("--spot="):
			var parts := argument.trim_prefix("--spot=").split(":")
			var cell := parts[1].split(",")
			_spots[parts[0]] = Vector2(int(cell[0]) * 64 + 32, (int(cell[1]) + 1) * 64)
	if _rooms.is_empty():
		_rooms = KD_ROOMS.duplicate()
	if _out.is_empty():
		_out = OS.get_cache_dir().path_join("hollowtide-kd-shots")
	DirAccess.make_dir_recursive_absolute(_out)
	call_deferred("_run")


func _run() -> void:
	GameState.set_checkpoint(Rooms.START_ROOM, Rooms.START_POSITION)
	var root := CAMPAIGN_SCENE.instantiate()
	add_child(root)
	await get_tree().create_timer(0.3).timeout
	var player := root.get("player") as Node2D
	player.set("dev_invulnerable", true)
	var camera := Camera2D.new()
	root.add_child(camera)
	for room_id in _rooms:
		var data: Dictionary = Rooms.ROOMS[room_id]
		var size := Vector2(data["size"]) * 64.0
		root.call("teleport", room_id, _spot(room_id, data))
		var room := root.get("current_room") as Node2D
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
	print("capture-kd: wrote ", _rooms.size(), " rooms to ", _out)
	await TestShutdown.finish(get_tree(), 0)


func _spot(room_id: String, data: Dictionary) -> Vector2:
	if _spots.has(room_id):
		return _spots[room_id]
	var saves: Array = data["saves"]
	if not saves.is_empty():
		return saves[0]
	var refills: Array = data["refills"]
	if not refills.is_empty():
		return refills[0]
	return Vector2(96, float(data["size"].y) * 64.0 - 128.0)


func _settle() -> void:
	for frame in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(file_name: String) -> void:
	get_viewport().get_texture().get_image().save_png(_out.path_join(file_name))
