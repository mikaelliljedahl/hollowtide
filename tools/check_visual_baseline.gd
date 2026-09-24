extends SceneTree


func _initialize():
	_capture.call_deferred()


func _capture():
	root.size = Vector2i(1920, 1080)
	var scene = load("res://scenes/levels/level_01.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	var result = image.save_png("res://.agent-reports/devmode-before.png")
	print("Baseline screenshot: ", error_string(result))
	scene.queue_free()
	await process_frame
	quit(result)
