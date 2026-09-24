extends Node
## Developer screenshot tool for the Slipstream form (not part of make check).
##   godot --path . --windowed --resolution 1920x1080 res://tools/capture_slipstream.tscn -- \
##     --dev-mode --test-mode --test-save-root=/tmp/x --shots-dir=/abs/out/dir

const Catalog = preload("res://scripts/progression/content_catalog.gd")

var _level: Node2D
var _player: Player
var _out := "user://slipstream_shots/"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots-dir="):
			_out = argument.trim_prefix("--shots-dir=") + "/"
	DirAccess.make_dir_recursive_absolute(_out)
	_level = (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate() as Node2D
	add_child(_level)
	_player = _level.get_node("PlayerSpawn/Player") as Player
	_run.call_deferred()


func _run() -> void:
	await _frames(20)
	GameState.reset_progress()
	for ability_id in Catalog.ABILITY_IDS:
		GameState.unlock_ability(ability_id)
	_player.dev_invulnerable = true
	var tunnel := _find_tunnel()
	print("capture_slipstream: tunnel at ", tunnel)
	_player.global_position = tunnel + Vector2(-300, 0)
	if OS.get_cmdline_user_args().has("--pickup"):
		_player.global_position = Vector2(560, 1152)
	_player.velocity = Vector2.ZERO
	await _frames(20)
	await _shot("0_standing")
	Input.action_press(&"slipstream")
	await _frames(1)
	Input.action_release(&"slipstream")
	await _frames(3)
	await _shot("1_pour")
	await _frames(20)
	await _shot("2_idle")
	Input.action_press(&"move_right")
	for i in 6:
		await _frames(10)
		await _shot("3_move_%d" % i)
	Input.action_release(&"move_right")
	Input.action_press(&"jump")
	await _frames(8)
	Input.action_release(&"jump")
	await _frames(10)
	await _shot("4_air")
	await _frames(40)
	Input.action_press(&"move_left")
	await _frames(25)
	await _shot("5_left")
	Input.action_press(&"move_left")
	await _frames(40)
	Input.action_release(&"move_left")
	await _frames(20)
	Input.action_press(&"slipstream")
	await _frames(1)
	Input.action_release(&"slipstream")
	for i in 3:
		await _shot("6_exit_%d" % i)
		await _frames(2)
	get_tree().quit(0)


func _find_tunnel() -> Vector2:
	var run := 0
	var last := Vector2.ZERO
	for x in range(200, 20000, 64):
		var p := _tunnel_at(x)
		if p != Vector2.ZERO and (run == 0 or absf(p.y - last.y) < 8.0):
			run += 1
			last = p
			if run == 4:
				return p - Vector2(64 * 2, 0)
		else:
			run = 0
	return Vector2(800, 1152)


func _tunnel_at(x: int) -> Vector2:
	var space := _player.get_world_2d().direct_space_state
	var y := 0.0
	while y < 4000.0:
		var down := PhysicsRayQueryParameters2D.create(Vector2(x, y), Vector2(x, 4000))
		down.collision_mask = 1
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			break
		var top: Vector2 = hit.position
		# Find the ceiling directly above this floor contact.
		var up := PhysicsRayQueryParameters2D.create(top - Vector2(0, 2), top - Vector2(0, 140))
		up.collision_mask = 1
		var ceil := space.intersect_ray(up)
		if (
			not ceil.is_empty()
			and top.y - ceil.position.y < 90.0
			and top.y - ceil.position.y > 56.0
		):
			return top
		y = top.y + 70.0
	return Vector2.ZERO


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var ratio := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var screen := _player.get_global_transform_with_canvas().origin * ratio
	var box := Vector2i(Vector2(480, 260) * ratio.x * 0.5)
	var crop := image.get_region(Rect2i(Vector2i(screen) - Vector2i(box.x / 2, box.y * 3 / 4), box))
	crop.resize(box.x * 3, box.y * 3, Image.INTERPOLATE_LANCZOS)
	crop.save_png(_out + name + "_zoom.png")
	image.resize(image.get_width() / 2, image.get_height() / 2)
	image.save_png(_out + name + ".png")


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
