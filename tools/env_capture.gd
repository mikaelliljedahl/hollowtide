extends Node
## Env-lane screenshot tool: teleports the player to each dev station and saves a PNG.
## Usage: godot --path . --windowed --resolution 1920x1080 res://tools/env_capture.tscn --
##   --dev-mode --test-mode --test-save-root=/tmp/x --out=/abs/dir [--stations=0,1,6]

const SETTLE_FRAMES := 45

var _out_dir := ""
var _stations: Array[int] = []
var _points: Array[Vector2] = []


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out_dir = argument.trim_prefix("--out=")
		elif argument.begins_with("--at="):
			for part in argument.trim_prefix("--at=").split(","):
				var xy := part.split(":")
				_points.append(Vector2(float(xy[0]), float(xy[1])))
		elif argument.begins_with("--stations="):
			for part in argument.trim_prefix("--stations=").split(","):
				_stations.append(int(part))
	if _stations.is_empty() and _points.is_empty():
		for index in 11:
			_stations.append(index)
	if _out_dir == "":
		push_error("env_capture requires --out=<dir>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	# Render into a fixed 1920x1080 SubViewport so captures do not depend on the window manager.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var level := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	viewport.add_child(level)
	for frame in 10:
		await get_tree().process_frame
	for index in _stations:
		level.call("_teleport_station", index)
		for frame in SETTLE_FRAMES:
			await get_tree().process_frame
		var map = level.get("_map")
		if map is CanvasLayer:
			map.visible = false
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := "%s/S%d.png" % [_out_dir, index]
		image.save_png(path)
		print("saved ", path)
	var player := level.get_node_or_null("PlayerSpawn/Player") as Node2D
	for point in _points:
		if player != null and player.has_method("reset_for_spawn"):
			player.call("reset_for_spawn", point)
		for frame in SETTLE_FRAMES:
			await get_tree().process_frame
		var point_map = level.get("_map")
		if point_map is CanvasLayer:
			point_map.visible = false
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shot := viewport.get_texture().get_image()
		var shot_path := "%s/at_%d_%d.png" % [_out_dir, int(point.x), int(point.y)]
		shot.save_png(shot_path)
		print("saved ", shot_path)
	level.queue_free()
	await get_tree().process_frame
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("shutdown"):
		await audio.call("shutdown")
	get_tree().quit(0)
