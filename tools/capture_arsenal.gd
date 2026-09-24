extends Node
## Developer screenshot tool for the D19 arsenal (not part of make check).
##   godot --path . --windowed --resolution 1920x1080 res://tools/capture_arsenal.tscn -- \
##     --dev-mode --test-mode --test-save-root=/tmp/x --shots-dir=/abs/out/dir
## Full-resolution crops around the action plus a half-size overview per ability.

const Catalog = preload("res://scripts/progression/content_catalog.gd")

var _level: Node2D
var _player: Player
var _out := "user://arsenal_shots/"
var _index := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots-dir="):
			_out = argument.trim_prefix("--shots-dir=")
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	_level = (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate() as Node2D
	add_child(_level)
	_player = _level.get_node("PlayerSpawn/Player") as Player
	_run.call_deferred()


func _run() -> void:
	await _frames(20)
	_unlock_everything()
	await _capture_harpoon()
	await _capture_bubble()
	await _capture_echo()
	await _capture_pulse()
	await _capture_dash()
	await _capture_tidal_bubble()
	print("capture_arsenal: wrote %d shots to %s" % [_index, _out])
	get_tree().quit(0)


func _unlock_everything() -> void:
	GameState.reset_progress()
	for ability_id in Catalog.ABILITY_IDS:
		GameState.unlock_ability(ability_id)
	for tank_index in Catalog.MAX_MISSILE_TANKS:
		GameState.collect_pickup("capture.missile_%02d" % (tank_index + 1), &"missile_tank")
	GameState.missile_count = GameState.max_missiles
	_player.dev_invulnerable = true


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _shot(label: String, focus := Vector2.INF) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_index += 1
	if focus.is_finite():
		var ratio := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
		var screen := get_viewport().get_canvas_transform() * focus * ratio
		var rect := Rect2i(Vector2i(screen) - Vector2i(400, 260), Vector2i(800, 520))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		image.get_region(rect).save_png(_out + "%02d_%s.png" % [_index, label])
		return
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	image.save_png(_out + "%02d_%s.png" % [_index, label])


func _teleport(station: int, local_x: float) -> Vector2:
	_level.call("_teleport_station", station)
	var origin: Vector2 = _level.get("_room_origins").get("S%d" % station, Vector2.ZERO)
	_player.reset_for_spawn(origin + Vector2(local_x, 1088.0))
	_player.dev_invulnerable = true
	var map := _level.get("_map") as CanvasLayer
	if map != null:
		map.visible = false
	return origin


func _fire(kind: StringName, direction: Vector2, beam: StringName = &"base") -> void:
	GameState.set_active_beam(beam)
	var origin := _player.global_position + Vector2(40.0 * signf(direction.x), -140.0)
	Weapons.fire(kind, origin, direction.normalized())


func _find_wall() -> Vector2:
	# Returns a horizontal direction toward plain rock within reach at chest height, or ZERO.
	var space := _player.get_world_2d().direct_space_state
	for side in [-1.0, 1.0]:
		var start := _player.global_position + Vector2(0.0, -140.0)
		var ray := PhysicsRayQueryParameters2D.create(start, start + Vector2(side * 1100.0, 0.0), 1)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty() and hit["collider"] is TileMapLayer:
			return Vector2(side, 0.0)
	return Vector2.ZERO


func _capture_harpoon() -> void:
	var direction := Vector2.ZERO
	for station in [1, 2, 4, 5, 7, 9]:
		for local_x in [300.0, 700.0, 1500.0, 1900.0]:
			_teleport(station, local_x)
			await _frames(12)
			direction = _find_wall()
			if direction != Vector2.ZERO:
				break
		if direction != Vector2.ZERO:
			break
	if direction == Vector2.ZERO:
		push_warning("no harpoon wall found")
		return
	_player.facing = int(direction.x)
	await _frames(10)
	_fire(&"missile", direction)
	await _frames(8)
	await _shot("harpoon_flight", _player.global_position + Vector2(direction.x * 260.0, -140))
	await _frames(60)
	var pegs := get_tree().get_nodes_in_group(&"harpoon_pegs")
	print("pegs after first shot: %d" % pegs.size())
	if pegs.is_empty():
		return
	var peg := pegs[0] as HarpoonPeg
	await _shot("harpoon_peg", peg.global_position)
	_player.velocity.y = -PlayerConfig.JUMP_VELOCITY * 0.6
	_fire(&"missile", direction)
	await _frames(40)
	_player.reset_for_spawn(peg.global_position + Vector2(float(peg.wall_side) * 34.0, -40.0))
	_player.dev_invulnerable = true
	await _frames(30)
	await _shot("harpoon_standing", peg.global_position)
	await _shot("harpoon_overview")
	Weapons.reset_runtime()
	await _frames(2)


func _capture_bubble() -> void:
	_teleport(7, 500.0)
	await _frames(40)
	var target: CombatEnemy = null
	var best := INF
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		var candidate := enemy as CombatEnemy
		if candidate == null or not candidate.freeze_capable or not candidate.visible:
			continue
		var distance := candidate.global_position.distance_to(_player.global_position)
		if distance < best:
			best = distance
			target = candidate
	if target == null:
		push_warning("no freezable enemy")
		return
	_player.reset_for_spawn(target.global_position + Vector2(-420.0, 0.0))
	_player.global_position.y = target.global_position.y + 60.0
	_player.dev_invulnerable = true
	await _frames(20)
	_fire(
		&"beam",
		target.global_position + Vector2(0, -40) - (_player.global_position + Vector2(40, -140)),
		&"ice"
	)
	await _frames(5)
	await _shot("bubble_shot", target.global_position)
	target.receive_hit(0, &"ice")
	await _frames(20)
	await _shot("bubble_trapped", target.global_position)
	await _frames(80)
	await _shot("bubble_drifted", target.global_position)
	await _shot("bubble_overview")
	await _frames(int(Catalog.FREEZE_SECONDS * 60.0) - 95)
	await _shot("bubble_popping", target.global_position)
	await _frames(12)
	await _shot("bubble_popped", target.global_position)


func _capture_echo() -> void:
	_teleport(1, 900.0)
	await _frames(30)
	_fire(&"beam", Vector2(1.0, 0.55), &"wave")
	await _frames(8)
	await _shot("echo_bounce_a")
	await _frames(5)
	await _shot("echo_bounce_b")
	await _frames(5)
	await _shot("echo_bounce_c")
	_teleport(2, 1300.0)
	await _frames(30)
	_player.facing = 1
	await _shot("echo_membrane_gate", _player.global_position + Vector2(300, -300))


func _capture_pulse() -> void:
	_teleport(3, 1200.0)
	await _frames(30)
	await _shot("pulse_crystal_block", _player.global_position + Vector2(220, -300))
	Weapons.fire(&"bomb", _player.global_position + Vector2(0, -28), Vector2.UP)
	await _frames(20)
	await _shot("pulse_charging", _player.global_position)
	await _frames(28)
	await _shot("pulse_burst", _player.global_position)
	await _frames(6)
	await _shot("pulse_burst_late", _player.global_position)


func _capture_dash() -> void:
	var origin := _teleport(6, 1250.0)
	await _frames(30)
	var gate_position := origin + Vector2(1480, 700)
	await _shot("undertow_barrier", gate_position)
	_player.reset_for_spawn(origin + Vector2(1400.0, 796.0))
	_player.dev_invulnerable = true
	await _frames(20)
	await _shot("dash_before", gate_position)
	_player.start_dash(1)
	await _frames(3)
	await _shot("dash_mid", gate_position)
	await _frames(4)
	await _shot("dash_through", gate_position)
	await _frames(30)
	await _shot("dash_after", gate_position)


func _capture_tidal_bubble() -> void:
	_teleport(8, 1230.0)
	await _frames(50)
	var boss: CombatBoss = null
	for candidate in get_tree().get_nodes_in_group(&"dev_boss"):
		if is_instance_valid(candidate) and candidate.get("enemy_id") == &"tidal_heart":
			boss = candidate
	if boss == null:
		return
	boss.receive_hit(0, &"ice")
	await _frames(10)
	await _shot("tidal_bubble_core", boss.global_position + Vector2(0, -150))
	await _shot("tidal_overview")
