extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const BEAM_SCENE: PackedScene = preload("res://scenes/combat/beam_shot.tscn")
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/beam/beam_impact.tscn")
const MUZZLE_SCENE: PackedScene = preload("res://scenes/effects/beam/beam_muzzle.tscn")
const GLOW_MATERIAL_PATH := "res://resources/combat/beam_glow_add.tres"
const NEUTRAL_MATERIAL_PATH := "res://resources/combat/beam_neutral_ricochet.tres"
const PROOF_DIRECTORY := "res://proofs/beam_family"

var failures: Array[String] = []


class GateProbe:
	extends StaticBody2D

	var pass_count := 0

	func _ready() -> void:
		collision_layer = 1
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(10.0, 96.0)
		collision.shape = rectangle
		add_child(collision)

	func can_pass_projectile(kind: StringName) -> bool:
		return kind == &"wave"

	func allows_projectile(kind: StringName) -> bool:
		if kind != &"wave":
			return false
		pass_count += 1
		return true


class TargetProbe:
	extends StaticBody2D

	var vulnerable := true
	var hit_count := 0

	func _ready() -> void:
		collision_layer = 8
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(16.0, 48.0)
		collision.shape = rectangle
		add_child(collision)

	func is_vulnerable_to(_kind: StringName) -> bool:
		return vulnerable

	func take_damage(_amount: int, _kind: StringName) -> void:
		hit_count += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_asset_contract()
	await _test_core_alignment_and_rotation()
	await _test_wave_trail_uses_physics_points()
	await _test_grate_and_wall_same_tick()
	await _test_echo_ricochet_limit()
	await _test_impact_reactions()
	await _test_six_shot_stress()
	if DisplayServer.get_name() != "headless":
		await _capture_native_proofs()
	else:
		print("Beam family native proof skipped: headless display server")
	if failures.is_empty():
		print("PASS: authored beam family runtime, physics trail, reactions, and cleanup")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _test_asset_contract() -> void:
	var expected := {
		"res://assets/sprites/effects/base_core.png": Vector2i(384, 64),
		"res://assets/sprites/effects/ice_core.png": Vector2i(384, 64),
		"res://assets/sprites/effects/wave_core.png": Vector2i(768, 64),
		"res://assets/sprites/effects/base_impact.png": Vector2i(512, 128),
		"res://assets/sprites/effects/ice_impact.png": Vector2i(512, 128),
		"res://assets/sprites/effects/wave_impact.png": Vector2i(1024, 128),
		"res://assets/sprites/effects/wave_muzzle.png": Vector2i(512, 128),
	}
	for path in expected:
		var texture := load(path) as Texture2D
		_check(texture != null, "%s loads as runtime texture" % path)
		if texture != null:
			_check(
				Vector2i(texture.get_width(), texture.get_height()) == expected[path],
				"%s keeps contracted atlas dimensions" % path,
			)
	_check(ResourceLoader.exists(GLOW_MATERIAL_PATH), "shared additive beam material exists")
	_check(ResourceLoader.exists(NEUTRAL_MATERIAL_PATH), "shared neutral ricochet material exists")
	_check(_silhouette_difference() > 0.08, "Base and Ice retain distinct grayscale silhouettes")
	_check(
		_opaque_nose_advance("res://assets/sprites/effects/base_core.png", 4, 88) <= 2,
		"Base opaque nose does not lead collision"
	)
	_check(
		_opaque_nose_advance("res://assets/sprites/effects/ice_core.png", 4, 88) <= 2,
		"Ice opaque nose does not lead collision"
	)


func _test_core_alignment_and_rotation() -> void:
	var expected_paths := {
		&"beam": "res://assets/sprites/effects/base_core.png",
		&"ice": "res://assets/sprites/effects/ice_core.png",
		&"wave": "res://assets/sprites/effects/wave_core.png",
	}
	for kind in expected_paths:
		var shot := _make_shot(Vector2.ZERO, Vector2.RIGHT, kind, 0.0)
		var core := shot.get_node("Core") as Sprite2D
		_check(
			shot.core_atlas_path() == expected_paths[kind], "%s selects explicit core atlas" % kind
		)
		_check(
			core.texture.resource_path == expected_paths[kind],
			"%s runtime sprite uses selected atlas" % kind
		)
		_check(
			core.hframes == (8 if kind == &"wave" else 4),
			"%s selects contracted frame count" % kind
		)
		_check(
			shot.core_kernel_local_position().length() <= 2.0,
			"%s kernel meets collision center" % kind
		)
		_check(core.scale.is_equal_approx(Vector2.ONE), "%s core remains unstretched" % kind)
		shot.queue_free()
	await get_tree().process_frame

	var directions: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.UP,
		Vector2(1.0, -1.0).normalized(),
	]
	for direction in directions:
		var shot := _make_shot(Vector2.ZERO, direction, &"beam", 0.0)
		_check(
			absf(angle_difference(shot.rotation, direction.angle())) < 0.0001,
			"right-facing atlas rotates to %s" % direction
		)
		shot.queue_free()
	await get_tree().process_frame

	var long_shot := _make_shot(Vector2.ZERO, Vector2.RIGHT, &"wave", 0.0)
	var original_scale := (long_shot.get_node("Core") as Sprite2D).scale
	var base_history := long_shot.trail_history_seconds()
	long_shot.set_long_beam_enabled(true)
	_check(long_shot.trail_history_seconds() > base_history, "Long slightly extends trail history")
	_check(
		(long_shot.get_node("Core") as Sprite2D).scale == original_scale,
		"Long never stretches core"
	)
	long_shot.queue_free()
	await get_tree().process_frame


func _test_echo_ricochet_limit() -> void:
	# Two parallel walls: Echo bounces three times, then the fourth wall hit consumes it.
	var left := _make_wall(Vector2(-40.0, 1100.0), Vector2(8.0, 96.0))
	var right := _make_wall(Vector2(120.0, 1100.0), Vector2(8.0, 96.0))
	await get_tree().physics_frame
	var echo := _make_shot(Vector2(40.0, 1100.0), Vector2.RIGHT, &"wave", 1800.0)
	echo.lifetime = 5.0
	var seen_bounces := 0
	for frame in 40:
		await get_tree().physics_frame
		if not is_instance_valid(echo):
			break
		seen_bounces = int(echo.get("bounces"))
	_check(
		seen_bounces == Catalog.ECHO_MAX_BOUNCES, "Echo ricochets exactly %d times" % seen_bounces
	)
	_check(not is_instance_valid(echo), "Echo is consumed after its last ricochet")
	left.queue_free()
	right.queue_free()
	await _clear_impacts()


func _test_wave_trail_uses_physics_points() -> void:
	var wave := _make_shot(Vector2(0.0, 240.0), Vector2.RIGHT, &"wave", 720.0)
	await _physics_frames(5)
	var traversed: PackedVector2Array = wave.traversed_physics_points()
	var trail: PackedVector2Array = wave.trail_physics_points()
	_check(trail.size() >= 2, "Wave trail records traversed path")
	_check(trail.size() <= BeamFxTrail.MAX_POINTS, "Wave trail caps at 16 points")
	for point in trail:
		_check(_contains_point(traversed, point), "Wave trail point came from physics sweep")
		_check(point.x <= wave.global_position.x + 0.01, "Wave trail never leads projectile")
	wave.queue_free()
	await get_tree().process_frame


func _test_grate_and_wall_same_tick() -> void:
	var gate := GateProbe.new()
	gate.position = Vector2(40.0, 480.0)
	add_child(gate)
	var wall := _make_wall(Vector2(80.0, 480.0), Vector2(8.0, 96.0))
	await get_tree().physics_frame
	var wave := _make_shot(Vector2(0.0, 480.0), Vector2.RIGHT, &"wave", 12000.0)
	await get_tree().physics_frame
	# D19 Echo Shot: passes the resonant grate, then ricochets off the wall behind it.
	_check(gate.pass_count == 1, "Echo grate activates once without consuming shot")
	_check(is_instance_valid(wave), "wall behind grate reflects Echo instead of consuming it")
	if is_instance_valid(wave):
		_check(int(wave.get("bounces")) == 1, "Echo counts one ricochet")
		_check(
			wave.global_position.x < 76.0 and wave.global_position.x > 56.0,
			"ricochet starts at wall physics hit position (%s)" % wave.global_position
		)
		wave.queue_free()
	gate.queue_free()
	wall.queue_free()
	await _clear_impacts()


func _test_impact_reactions() -> void:
	for vulnerable in [true, false]:
		var target := TargetProbe.new()
		target.vulnerable = vulnerable
		target.position = Vector2(100.0, 680.0)
		add_child(target)
		await get_tree().physics_frame
		_make_shot(Vector2(0.0, 680.0), Vector2.RIGHT, &"beam", 7200.0)
		await get_tree().physics_frame
		var expected_reaction: StringName = &"vulnerable" if vulnerable else &"immune"
		var impact := _find_impact(expected_reaction)
		_check(impact != null, "%s target selects matching reaction" % expected_reaction)
		_check(target.hit_count == 1, "%s target receives one damage call" % expected_reaction)
		if impact != null:
			_check(
				absf(impact.global_position.x - 92.0) <= 1.0,
				"%s impact stays at physics hit" % expected_reaction
			)
			if not vulnerable:
				_check(
					impact.get_node("Sprite2D").material.resource_path == NEUTRAL_MATERIAL_PATH,
					"immune ricochet uses neutral shared material"
				)
		target.queue_free()
		await _clear_impacts()

	var wall := _make_wall(Vector2(100.0, 780.0), Vector2(8.0, 64.0))
	await get_tree().physics_frame
	_make_shot(Vector2(0.0, 780.0), Vector2.RIGHT, &"beam", 7200.0)
	await get_tree().physics_frame
	var impact := _find_impact(&"wall")
	_check(impact != null, "terrain chooses wall reaction")
	if impact != null:
		_check(
			absf(angle_difference(impact.rotation, PI)) < 0.01,
			"wall impact orients to collision normal"
		)
		_check(impact.scale.y < impact.scale.x, "wall impact flattens along surface")
	wall.queue_free()
	await _clear_impacts()


func _test_six_shot_stress() -> void:
	var shots: Array[ProjectileBase] = []
	for index in 6:
		var kind: StringName = [&"beam", &"ice", &"wave"][index % 3]
		var shot := _make_shot(Vector2(40.0, 900.0 + index * 24.0), Vector2.RIGHT, kind, 0.0)
		shots.append(shot)
	await get_tree().process_frame
	var light_count := 0
	var particle_count := 0
	for shot in shots:
		light_count += shot.find_children("*", "PointLight2D", true, false).size()
		particle_count += shot.find_children("*", "GPUParticles2D", true, false).size()
	_check(light_count == 0, "six-shot stress creates no per-projectile lights")
	_check(particle_count == 0, "six-shot stress keeps particle count capped at zero")
	await _physics_frames(26)
	for shot in shots:
		_check(not is_instance_valid(shot), "stress projectile self-cleans")
	_check(
		get_tree().get_nodes_in_group(&"transient").is_empty(), "stress transients fully clean up"
	)


func _capture_native_proofs() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_2d = World2D.new()
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("08101c")
	background.size = Vector2(viewport.size)
	viewport.add_child(background)
	var world := Node2D.new()
	viewport.add_child(world)

	var kinds: Array[StringName] = [&"beam", &"ice", &"wave"]
	for index in kinds.size():
		var shot := BEAM_SCENE.instantiate() as ProjectileBase
		world.add_child(shot)
		shot.global_position = Vector2(190.0, 135.0 + index * 145.0)
		shot.damage_kind = kinds[index]
		shot.launch(Vector2.RIGHT)
		shot.set_physics_process(false)
		var muzzle := MUZZLE_SCENE.instantiate() as BeamFxMuzzle
		muzzle.configure(kinds[index], Vector2.RIGHT)
		world.add_child(muzzle)
		muzzle.position = Vector2(75.0, 135.0 + index * 145.0)
		muzzle.set_process(false)
		var reaction_kinds: Array[StringName] = [&"wall", &"vulnerable", &"immune", &"grate"]
		for reaction_index in reaction_kinds.size():
			var effect := IMPACT_SCENE.instantiate() as BeamFxImpact
			effect.configure(kinds[index], 0.0, reaction_kinds[reaction_index], Vector2.LEFT)
			world.add_child(effect)
			effect.position = Vector2(485.0 + reaction_index * 165.0, 135.0 + index * 145.0)
			effect.set_process(false)

	var direction_vectors: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	for index in direction_vectors.size():
		var direction := direction_vectors[index]
		var shot := BEAM_SCENE.instantiate() as ProjectileBase
		world.add_child(shot)
		shot.position = Vector2(1040.0 + (index % 2) * 120.0, 540.0 + (index / 2) * 105.0)
		shot.damage_kind = &"ice"
		shot.launch(direction)
		shot.set_physics_process(false)

	var moving_wave := BEAM_SCENE.instantiate() as ProjectileBase
	world.add_child(moving_wave)
	moving_wave.position = Vector2(100.0, 620.0)
	moving_wave.damage_kind = &"wave"
	moving_wave.speed = 1800.0
	moving_wave.launch(Vector2.RIGHT)
	await _physics_frames(5)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	var absolute_directory := ProjectSettings.globalize_path(PROOF_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	var proof_path := "%s/native_compatibility.png" % PROOF_DIRECTORY
	var save_error := image.save_png(ProjectSettings.globalize_path(proof_path))
	_check(save_error == OK, "native Compatibility proof saves")
	var trail_path := "%s/native_wave_trail.png" % PROOF_DIRECTORY
	var trail_image := image.get_region(Rect2i(0, 520, 420, 200))
	_check(
		trail_image.save_png(ProjectSettings.globalize_path(trail_path)) == OK,
		"native Wave trail proof saves",
	)
	var reactions_path := "%s/native_reactions.png" % PROOF_DIRECTORY
	var reactions_image := image.get_region(Rect2i(400, 50, 760, 450))
	_check(
		reactions_image.save_png(ProjectSettings.globalize_path(reactions_path)) == OK,
		"native impact reaction proof saves",
	)
	print("Beam family proofs: ", [proof_path, trail_path, reactions_path])
	viewport.queue_free()
	await get_tree().process_frame


func _make_shot(
	position: Vector2, direction: Vector2, kind: StringName, shot_speed: float
) -> BeamShot:
	var shot := BEAM_SCENE.instantiate() as BeamShot
	add_child(shot)
	shot.global_position = position
	shot.damage_kind = kind
	shot.speed = shot_speed
	shot.launch(direction)
	return shot


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


func _find_impact(reaction: StringName) -> BeamFxImpact:
	for transient in get_tree().get_nodes_in_group(&"transient"):
		if transient is BeamFxImpact and transient.reaction == reaction:
			return transient
	return null


func _clear_impacts() -> void:
	for transient in get_tree().get_nodes_in_group(&"transient"):
		if transient is BeamFxImpact:
			transient.queue_free()
	await get_tree().process_frame


func _contains_point(points: PackedVector2Array, expected: Vector2) -> bool:
	for point in points:
		if point.is_equal_approx(expected):
			return true
	return false


func _silhouette_difference() -> float:
	var base := (load("res://assets/sprites/effects/base_core.png") as Texture2D).get_image()
	var ice := (load("res://assets/sprites/effects/ice_core.png") as Texture2D).get_image()
	var different := 0
	var compared := 0
	for y in 64:
		for x in 96:
			var base_alpha := base.get_pixel(x, y).a
			var ice_alpha := ice.get_pixel(x, y).a
			if maxf(base_alpha, ice_alpha) < 0.1:
				continue
			compared += 1
			if absf(base_alpha - ice_alpha) > 0.2:
				different += 1
	return float(different) / float(maxi(compared, 1))


func _opaque_nose_advance(path: String, frame_count: int, anchor_x: int) -> int:
	var image := (load(path) as Texture2D).get_image()
	var furthest := anchor_x
	for frame in frame_count:
		for y in image.get_height():
			for x in 96:
				if image.get_pixel(frame * 96 + x, y).a >= 0.90:
					furthest = maxi(furthest, x)
	return furthest - anchor_x


func _physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
