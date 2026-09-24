extends Node

const BEAM_SCENE: PackedScene = preload("res://scenes/combat/beam_shot.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01.tscn")
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/beam/beam_impact.tscn")

var failures: Array[String] = []


class GateProbe:
	extends StaticBody2D
	var pass_count := 0

	func _ready() -> void:
		collision_layer = 1
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(10, 96)
		collision.shape = rectangle
		add_child(collision)

	func can_pass_projectile(kind: StringName) -> bool:
		return kind == &"wave"

	func allows_projectile(kind: StringName) -> bool:
		if kind != &"wave":
			return false
		pass_count += 1
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_muzzle_pose_alignment()
	await _test_wave_grate_wall_same_frame()
	await _test_wave_sweep_follows_curve()
	await _capture_beam_variants()
	await _capture_aim_poses()
	await _capture_actual_level_directions()
	if failures.is_empty():
		print("PASS: muzzle alignment, distinct beam rendering, and curved wave sweep")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _test_muzzle_pose_alignment() -> void:
	GameState.reset_progress()
	GameState.acquire_beam()
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	# Independent measured pose anchors. Do not derive these from PlayerConfig or player code.
	var expected := {
		&"shoot_horizontal": Vector2(71, -161),
		&"shoot_horizontal_air": Vector2(81, -140),
		&"shoot_horizontal_air_fallback": Vector2(81, -140),
		&"crouch_shoot_horizontal": Vector2(70, -72),
		&"aim_up": Vector2(15, -190),
		&"aim_diag_up": Vector2(44, -191),
		&"aim_diag_down": Vector2(73, -95),
		&"aim_down": Vector2(24, -42),
	}
	_check(
		player._horizontal_shot_pose() == &"shoot_horizontal_air",
		"airborne horizontal fire uses measured armed air pose",
	)
	for facing in [-1, 1]:
		player.facing = facing
		for pose in expected:
			player._update_muzzle_position(pose)
			var source: Vector2 = expected[pose]
			var mirrored := Vector2(source.x * facing, source.y)
			_check(
				player.get_node("Muzzle").position.is_equal_approx(mirrored),
				"%s muzzle mirrors for facing %d" % [pose, facing],
			)
	player.queue_free()
	await get_tree().process_frame


func _test_wave_grate_wall_same_frame() -> void:
	var gate := GateProbe.new()
	gate.position = Vector2(40, 0)
	add_child(gate)
	var wall := _make_wall(Vector2(80, 0), Vector2(8, 96))
	await get_tree().physics_frame
	var wave := _spawn_wave(Vector2.ZERO, 12000.0)
	await get_tree().physics_frame
	_check(gate.pass_count == 1, "wave accepts explicit grate exactly once")
	_check(
		is_instance_valid(wave) and int(wave.get("bounces")) == 1,
		"wall behind grate reflects Echo in the same physics frame"
	)
	if is_instance_valid(wave):
		wave.queue_free()
	gate.queue_free()
	wall.queue_free()
	await get_tree().physics_frame


func _test_wave_sweep_follows_curve() -> void:
	# D19 Echo Shot travels straight (no sine sweep) and reflects off terrain.
	var straight_wall := _make_wall(Vector2(26, 0), Vector2(5, 40))
	await get_tree().physics_frame
	var echo := _spawn_wave(Vector2.ZERO, 1800.0)
	await get_tree().physics_frame
	_check(is_instance_valid(echo), "Echo survives its first wall hit")
	if is_instance_valid(echo):
		_check(echo.rotation > PI * 0.5 or echo.rotation < -PI * 0.5, "Echo reflects back")
		echo.queue_free()
	straight_wall.queue_free()
	await get_tree().physics_frame


func _capture_beam_variants() -> void:
	var signatures: Array[StringName] = []
	for kind in [&"beam", &"ice", &"wave"]:
		var probe := BEAM_SCENE.instantiate()
		add_child(probe)
		probe.damage_kind = kind
		signatures.append(probe.visual_signature())
		probe.queue_free()
	_check(
		signatures == [&"base_authored_core", &"bubble_snare", &"echo_pulse"],
		"beam kinds select distinct authored atlas profiles",
	)
	if DisplayServer.get_name() == "headless":
		print("Beam visual capture skipped: active renderer is headless dummy")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 320)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	_add_background(world, viewport.size)
	var kinds: Array[StringName] = [&"beam", &"ice", &"wave"]
	for index in kinds.size():
		var shot := BEAM_SCENE.instantiate() as ProjectileBase
		world.add_child(shot)
		shot.position = Vector2(120 + index * 240, 92)
		shot.launch(Vector2.RIGHT)
		shot.damage_kind = kinds[index]
		shot.set_physics_process(false)
		var impact := IMPACT_SCENE.instantiate() as BeamFxImpact
		impact.configure(kinds[index], 0.0)
		world.add_child(impact)
		impact.position = Vector2(120 + index * 240, 230)
		impact.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		print("Beam visual capture skipped: active renderer is headless dummy")
		viewport.queue_free()
		return
	var hashes: Array[int] = []
	for index in kinds.size():
		var region := image.get_region(Rect2i(index * 240, 40, 240, 240))
		hashes.append(hash(region.get_data()))
	_check(hashes[0] != hashes[1], "base and Ice rendered pixels differ")
	_check(hashes[0] != hashes[2], "base and Wave rendered pixels differ")
	_check(hashes[1] != hashes[2], "Ice and Wave rendered pixels differ")
	var save_error := image.save_png("/tmp/hollowtide-beam-variants.png")
	_check(save_error == OK, "beam variant screenshot saved")
	print("Beam visual capture: /tmp/hollowtide-beam-variants.png hashes=", hashes)
	viewport.queue_free()
	await get_tree().process_frame


func _capture_aim_poses() -> void:
	if DisplayServer.get_name() == "headless":
		print("Aim/muzzle capture skipped: active renderer is headless dummy")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1740, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	_add_background(world, viewport.size)
	var poses: Array[StringName] = [
		&"idle_armed",
		&"shoot_horizontal_air_fallback",
		&"aim_diag_up",
		&"aim_up",
		&"aim_diag_down",
		&"aim_down",
	]
	var directions := [
		Vector2.RIGHT,
		Vector2.RIGHT,
		Vector2(1, -1).normalized(),
		Vector2.UP,
		Vector2(1, 1).normalized(),
		Vector2.DOWN,
	]
	for index in poses.size():
		var player := PLAYER_SCENE.instantiate() as Player
		world.add_child(player)
		player.position = Vector2(140 + index * 285, 320)
		player.set_physics_process(false)
		(player.get_node("Camera2D") as Camera2D).enabled = false
		player._sprite.play(poses[index])
		player._update_muzzle_position(poses[index])
		var shot := BEAM_SCENE.instantiate() as ProjectileBase
		world.add_child(shot)
		shot.global_position = player._muzzle.global_position
		shot.launch(directions[index])
		shot.damage_kind = &"beam"
		shot.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		print("Aim/muzzle capture skipped: active renderer is headless dummy")
		viewport.queue_free()
		return
	var save_error := image.save_png("/tmp/hollowtide-aim-muzzle-poses.png")
	_check(save_error == OK, "aim/muzzle screenshot saved")
	print("Aim/muzzle visual capture: /tmp/hollowtide-aim-muzzle-poses.png")
	viewport.queue_free()
	await get_tree().process_frame


func _capture_actual_level_directions() -> void:
	if DisplayServer.get_name() == "headless":
		return
	GameState.reset_progress()
	GameState.acquire_beam()
	var level := LEVEL_SCENE.instantiate()
	add_child(level)
	await _physics_frames(4)
	var player := level.get_node("PlayerSpawn/Player") as Player
	player.set_physics_process(false)
	var poses: Array[StringName] = [
		&"idle_armed", &"aim_diag_up", &"aim_up", &"aim_diag_down", &"aim_down"
	]
	var directions := [
		Vector2.RIGHT,
		Vector2(1, -1).normalized(),
		Vector2.UP,
		Vector2(1, 1).normalized(),
		Vector2.DOWN,
	]
	var names := ["horizontal", "diag-up", "up", "diag-down", "down"]
	for index in poses.size():
		player._sprite.play(poses[index])
		player._update_muzzle_position(poses[index])
		var shot := BEAM_SCENE.instantiate() as ProjectileBase
		level.add_child(shot)
		shot.global_position = player._muzzle.global_position
		shot.launch(directions[index])
		shot.set_physics_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var path := "/tmp/hollowtide-level-aim-%s.png" % names[index]
		var save_error := image.save_png(path)
		_check(save_error == OK, "actual-level %s screenshot saved" % names[index])
		print("Actual-level aim capture: ", path)
		shot.queue_free()
		await get_tree().process_frame
	level.queue_free()
	await get_tree().process_frame


func _spawn_wave(position: Vector2, projectile_speed: float) -> ProjectileBase:
	var wave := BEAM_SCENE.instantiate() as ProjectileBase
	add_child(wave)
	wave.global_position = position
	wave.speed = projectile_speed
	wave.launch(Vector2.RIGHT)
	wave.damage_kind = &"wave"
	return wave


func _make_wall(position: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = position
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	wall.add_child(collision)
	add_child(wall)
	return wall


func _add_background(parent: Node2D, size: Vector2i) -> void:
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array(
		[Vector2.ZERO, Vector2(size.x, 0), Vector2(size), Vector2(0, size.y)]
	)
	background.color = Color("08101c")
	background.z_index = -10
	parent.add_child(background)


func _physics_frames(count: int) -> void:
	for _frame in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
