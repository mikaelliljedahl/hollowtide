extends Node2D
## Windowed capture of every armed pose plus a fired Seed Crossbow bolt at each shooting pose.
## godot --path . --windowed --fixed-fps 60 res://tools/capture_crossbow.tscn -- --out=<dir>

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const OUT_ARG := "--out="

# [animation, frame, fire direction or ZERO]
var poses := [
	[&"idle_armed", 0, Vector2.ZERO],
	[&"run_armed", 0, Vector2.ZERO],
	[&"run_armed", 3, Vector2.ZERO],
	[&"sprint_armed", 0, Vector2.ZERO],
	[&"sprint_armed", 4, Vector2.ZERO],
	[&"jump_armed", 0, Vector2.ZERO],
	[&"jump_armed", 2, Vector2.ZERO],
	[&"spin_armed", 0, Vector2.ZERO],
	[&"spin_armed", 3, Vector2.ZERO],
	[&"spin_armed", 6, Vector2.ZERO],
	[&"wall_slide_armed", 0, Vector2.ZERO],
	[&"wall_jump_armed", 0, Vector2.ZERO],
	[&"crouch_armed", 0, Vector2.ZERO],
	[&"jump_armed", 1, Vector2.ZERO],
	[&"shoot_horizontal", 0, Vector2.RIGHT],
	[&"shoot_horizontal_air", 0, Vector2.RIGHT],
	[&"crouch_shoot_horizontal", 0, Vector2.RIGHT],
	[&"aim_up", 0, Vector2.UP],
	[&"aim_diag_up", 0, Vector2(1, -1).normalized()],
	[&"aim_diag_down", 0, Vector2(1, 1).normalized()],
	[&"aim_down", 0, Vector2.DOWN],
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := OS.get_user_data_dir() + "/crossbow_capture"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			out = arg.trim_prefix(OUT_ARG)
	DirAccess.make_dir_recursive_absolute(out)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	var background := ColorRect.new()
	background.color = Color(0.09, 0.11, 0.12)
	background.size = Vector2(1920, 1080)
	world.add_child(background)
	GameState.reset_progress()
	GameState.acquire_beam()
	for index in poses.size():
		var pose: Array = poses[index]
		var player := PLAYER_SCENE.instantiate() as Player
		world.add_child(player)
		player.position = Vector2(150 + (index % 7) * 270, 330 + int(index / 7) * 360)
		player.set_physics_process(false)
		player.set_process(false)
		(player.get_node("Camera2D") as Camera2D).enabled = false
		player._sprite.play(pose[0])
		player._sprite.pause()
		player._sprite.frame = pose[1]
		var direction: Vector2 = pose[2]
		if direction != Vector2.ZERO:
			player._aim_direction = direction
			player._update_muzzle_position(pose[0])
			Weapons._cooldown_remaining[&"beam"] = 0.0
			Weapons.fire(&"beam", player._muzzle.global_position, direction)
			for child in get_tree().current_scene.get_children():
				if child is ProjectileBase or child is CrossbowSnapFx:
					child.get_parent().remove_child(child)
					world.add_child(child)
					child.set_physics_process(false)
	for frame in 4:
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	image.save_png(out + "/poses.png")
	for row in 3:
		image.get_region(Rect2i(0, row * 360, 1920, 360)).save_png(out + "/row%d.png" % row)
	var zoom := image.get_region(Rect2i(0, 720, 1920, 360))
	zoom.resize(3840, 720, Image.INTERPOLATE_NEAREST)
	zoom.get_region(Rect2i(0, 0, 1920, 720)).save_png(out + "/shoot_zoom_a.png")
	zoom.get_region(Rect2i(1920, 0, 1920, 720)).save_png(out + "/shoot_zoom_b.png")
	for child in world.get_children():
		if child is ProjectileBase:
			child.visible = false
	await get_tree().process_frame
	var snap := viewport.get_texture().get_image().get_region(Rect2i(0, 720, 960, 360))
	snap.resize(1920, 720, Image.INTERPOLATE_NEAREST)
	snap.save_png(out + "/snap_zoom.png")
	print("saved ", out)
	get_tree().quit()
