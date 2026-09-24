extends SceneTree


func _initialize():
	_capture.call_deferred()


func _capture():
	var scene = load("res://scenes/levels/level_01.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var visuals = load("res://scripts/world/cave_visuals.gd").new()
	scene.add_child(visuals)
	visuals.configure(scene.get_node("CaveTiles"))
	for frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var result = root.get_texture().get_image().save_png(
		"res://.agent-reports/devmode-cave-preview.png"
	)
	print("HD cave preview: ", error_string(result))
	scene.queue_free()
	await process_frame
	await root.get_node("Audio").shutdown()
	quit(result)
