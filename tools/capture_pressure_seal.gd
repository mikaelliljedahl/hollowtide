extends Node
## Developer screenshot tool for the Pressure Seal overlay (not part of make check).
##   godot --path . --windowed --resolution 1920x1080 res://tools/capture_pressure_seal.tscn -- \
##     --dev-mode --test-mode --test-save-root=/tmp/x --shots-dir=/abs/out/dir
## Writes one contact sheet per pose group: top row without the seal, bottom row with it.

const POSES := [
	&"idle",
	&"idle_armed",
	&"run",
	&"sprint_armed",
	&"jump",
	&"jump_armed",
	&"crouch",
	&"aim_up",
	&"aim_diag_down",
	&"shoot_horizontal",
	&"wall_slide",
	&"spin",
	&"ball_roll",
]

var _player: Player
var _out := "user://seal_shots/"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots-dir="):
			_out = argument.trim_prefix("--shots-dir=")
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	var level := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate() as Node2D
	add_child(level)
	_player = level.get_node("PlayerSpawn/Player") as Player
	_run.call_deferred()


func _run() -> void:
	await _frames(20)
	GameState.reset_progress()
	_player.set_physics_process(false)
	var sprite := _player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var sheet := Image.create(POSES.size() * 280, 2 * 300, false, Image.FORMAT_RGBA8)
	for row in 2:
		if row == 1:
			GameState.unlock_ability(&"pressure_seal")
		for i in POSES.size():
			var pose: StringName = POSES[i]
			if not sprite.sprite_frames.has_animation(pose):
				continue
			sprite.play(pose)
			sprite.frame = 1 if sprite.sprite_frames.get_frame_count(pose) > 1 else 0
			sprite.pause()
			await _frames(4)
			var shot := get_viewport().get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			shot.resize(1920, 1080)
			var center := _player.get_global_transform_with_canvas().origin
			var region := Rect2i(int(center.x) - 140, int(center.y) - 260, 280, 300)
			sheet.blit_rect(shot, region, Vector2i(i * 280, row * 300))
	sheet.save_png(_out + "seal_sheet.png")
	sprite.play(&"idle")
	var zone := Area2D.new()
	zone.set_script(load("res://scripts/campaign/heat_zone.gd"))
	zone.global_position = _player.global_position
	add_child(zone)
	zone.set("_player", _player)
	await _frames(40)
	var heat := get_viewport().get_texture().get_image()
	heat.resize(1920, 1080)
	var at := _player.get_global_transform_with_canvas().origin
	heat.get_region(Rect2i(int(at.x) - 200, int(at.y) - 300, 400, 340)).save_png(_out + "heat.png")
	print("capture_pressure_seal: wrote ", _out)
	get_tree().quit(0)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
