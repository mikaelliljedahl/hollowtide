extends SceneTree

## Screenshot helper for menus/HUD (working files only, never committed).
## godot --path . --windowed --resolution 1920x1080 --script tools/capture_ui.gd -- --out=<dir>

var _out := "user://ui_shots"
var _gs: Node
var _vp: SubViewport


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("/root/GameState")
	_vp = SubViewport.new()
	_vp.size = Vector2i(1920, 1080)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var menu: Control = load("res://scenes/ui/start_menu.tscn").instantiate()
	_vp.add_child(menu)
	await _wait(60)
	await _shot("01_start")
	menu.call("_show_settings")
	await _wait(10)
	await _shot("02_settings")
	var slot := menu.find_child("Bind_jump_0", true, false) as Button
	if slot != null:
		slot.grab_focus()
		slot.emit_signal("pressed")
	await _wait(10)
	await _shot("03_settings_rebind")
	menu.get_node("Settings").call("handle_back")
	menu.get_node("Settings").call("handle_back")
	menu.call("_show_help")
	await _wait(10)
	await _shot("04_controls")
	menu.call("_hide_help")
	menu.get_node("ConfirmNewGame").call(
		"ask", "Start a new game?", "Your saved progress will be overwritten.", "Overwrite Save"
	)
	await _wait(10)
	await _shot("05_confirm")
	menu.queue_free()
	await _wait(2)

	var level: Node = load("res://scenes/levels/level_01.tscn").instantiate()
	_vp.add_child(level)
	await _wait(90)
	_gs.reset_progress()
	await _wait(20)
	await _shot("10_hud_fresh")
	_gs.acquire_beam()
	_gs.acquire_missiles(15)
	_gs.collect_pickup("cap.e1", &"energy_tank")
	_gs.collect_pickup("cap.e2", &"energy_tank")
	_gs.apply_damage(113)
	for i in 8:
		_gs.spend_missile()
	await _wait(40)
	await _shot("11_hud_mid")
	_gs.reset_progress()
	_gs.acquire_beam()
	_gs.unlock_ability(&"wave_beam")
	_gs.set_active_beam(&"wave")
	_gs.unlock_ability(&"flux_shield")
	for i in 6:
		_gs.collect_pickup("cap.me%d" % i, &"energy_tank")
	for i in 12:
		_gs.collect_pickup("cap.mm%d" % i, &"missile_tank")
	for i in 4:
		_gs.collect_pickup("cap.mf%d" % i, &"flux_tank")
	_gs.set_active_flux_module(&"flux_shield")
	_gs.set_flux_enabled(true)
	_gs.apply_damage(150)
	_gs.pickup_feedback.emit("MISSILE TANK · 60 / 60")
	await _wait(40)
	await _shot("12_hud_max")
	_gs.apply_damage(_gs.health - 22)
	await _wait(40)
	await _shot("13_hud_low")
	var pause := root.find_child("PauseMenu", true, false)
	if pause != null:
		pause.call("open")
		await _wait(10)
		await _shot("20_pause")
		pause.call("_show_settings")
		await _wait(10)
		await _shot("21_pause_settings")
		pause.call("_back")
		pause.call("_ask_quit")
		await _wait(10)
		await _shot("22_pause_quit")
		pause.call("_back")
		pause.call("resume")
	else:
		push_error("no pause menu")
	_gs.reset_progress()
	level.queue_free()
	await _wait(2)
	var audio := root.get_node_or_null("Audio")
	if audio != null and audio.has_method("shutdown"):
		await audio.shutdown()
	quit(0)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("shot ", path)
