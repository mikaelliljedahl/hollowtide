extends Node2D
## Manual capture: saves jump/glide screenshots of the Updraft Cloak. Not a regression suite.
## Usage: godot --path . --windowed res://tools/capture_updraft.tscn -- <output_dir/>

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6000.0, 64.0)
	shape.shape = rect
	body.position = Vector2(0.0, 932.0)
	body.add_child(shape)
	var floor_vis := ColorRect.new()
	floor_vis.color = Color(0.3, 0.3, 0.32)
	floor_vis.position = Vector2(-3000.0, -32.0)
	floor_vis.size = Vector2(6000.0, 64.0)
	body.add_child(floor_vis)
	add_child(body)
	GameState.reset_progress()
	GameState.unlock_ability(&"high_jump")
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector2(0.0, 900.0)
	for f in 20:
		await get_tree().physics_frame
	await _shot("idle")
	Input.action_press("move_right")
	for f in 20:
		await get_tree().physics_frame
	await _shot("run")
	Input.action_press("jump")
	for f in 12:
		await get_tree().physics_frame
	await _shot("rise")
	for f in 40:
		await get_tree().physics_frame
	await _shot("glide")
	Input.action_release("move_right")
	Input.action_press("move_left")
	for f in 12:
		await get_tree().physics_frame
	await _shot("glide_left")
	Input.action_release("move_left")
	Input.action_release("jump")
	get_tree().quit(0)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir() + label + ".png")


func _out_dir() -> String:
	var args := OS.get_cmdline_user_args()
	return args[0] if not args.is_empty() else "user://"
