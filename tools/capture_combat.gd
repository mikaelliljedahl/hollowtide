extends Node
## Developer screenshot tool for the combat lane (not part of make check).
## Run windowed:
##   godot --path . --windowed --resolution 1920x1080 res://tools/capture_combat.tscn -- \
##     --dev-mode --test-mode --test-save-root=/tmp/x --shots=bosses,enemies,player \
##     --shots-dir=/abs/out/dir
## Saves half-resolution PNGs so they are cheap to review.

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const DEFAULT_OUT := "user://combat_shots/"
const FLOOR_Y := 1152.0

var _level: Node2D
var _player: Player
var _out := DEFAULT_OUT
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
	var wanted := _argument("--shots=", "bosses,enemies,player").split(",")
	if wanted.has("bosses"):
		await _capture_tidal()
		await _capture_stone()
		await _capture_furnace()
	if wanted.has("enemies"):
		await _capture_enemies()
	if wanted.has("player"):
		await _capture_player()
	if wanted.has("world"):
		await _capture_world()
	print("capture_combat: wrote %d shots to %s" % [_index, _out])
	get_tree().quit(0)


func _argument(prefix: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


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
	if focus.is_finite():
		# Full-resolution crop around a world point for close inspection.
		var ratio := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
		var screen := get_viewport().get_canvas_transform() * focus * ratio
		var rect := Rect2i(Vector2i(screen) - Vector2i(320, 220), Vector2i(640, 360))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		_index += 1
		image.get_region(rect).save_png(_out + "%02d_%s.png" % [_index, label])
		return
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	_index += 1
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


func _boss(id: StringName) -> CombatBoss:
	for boss in get_tree().get_nodes_in_group(&"dev_boss"):
		if is_instance_valid(boss) and boss.get("enemy_id") == id:
			return boss as CombatBoss
	return null


func _fire_at(kind: StringName, target: Vector2, beam: StringName = &"base") -> void:
	GameState.set_active_beam(beam)
	var origin := _player.global_position + Vector2(0.0, -120.0)
	var direction := (target - origin).normalized()
	Weapons.reset_runtime()
	await _frames(1)
	Weapons.fire(kind, origin, direction)


func _hold_boss(boss: CombatBoss, position: Vector2) -> void:
	boss.global_position = position
	boss.velocity = Vector2.ZERO


func _capture_tidal() -> void:
	_teleport(8, 1230.0)
	var boss := _boss(&"tidal_heart")
	if boss == null:
		push_warning("no tidal heart")
		return
	await _frames(50)
	await _shot("tidal_p1_protected")
	await _fire_at(&"beam", boss.global_position + Vector2(0, -150), &"base")
	await _frames(9)
	await _shot("tidal_p1_beam_ping")
	await _frames(20)
	await _fire_at(&"beam", boss.global_position + Vector2(0, -150), &"ice")
	await _frames(12)
	await _shot("tidal_p1_ice_open")
	await _frames(25)
	await _shot("tidal_p1_open_later")
	await _fire_at(&"missile", boss.global_position + Vector2(0, -150))
	await _frames(12)
	await _shot("tidal_p1_missile_hurt")
	boss.set_test_phase(2)
	await _frames(40)
	await _shot("tidal_p2_shield")
	boss.call("open_wave_window")
	await _frames(4)
	await _shot("tidal_p2_wave_open")
	await _frames(30)
	await _shot("tidal_p2_open_later")
	boss.health = 1
	await _fire_at(&"missile", boss.global_position + Vector2(0, -150))
	for step in 5:
		await _frames(10)
		await _shot("tidal_death_%d" % step)


func _capture_stone() -> void:
	_teleport(5, 1230.0)
	var boss := _boss(&"stone_guardian")
	if boss == null:
		push_warning("no stone guardian")
		return
	await _frames(40)
	await _shot("stone_p1")
	await _fire_at(&"beam", boss.global_position + Vector2(0, -120), &"base")
	await _frames(8)
	await _shot("stone_p1_beam_ping")
	await _fire_at(&"missile", boss.global_position + Vector2(0, -120))
	await _frames(10)
	await _shot("stone_p1_missile")
	boss.set_test_phase(2)
	await _frames(20)
	await _shot("stone_p2_a")
	await _frames(70)
	await _shot("stone_p2_b")
	await _frames(70)
	await _shot("stone_p2_c")


func _capture_furnace() -> void:
	_teleport(7, 1230.0)
	var boss := _boss(&"furnace_mother")
	if boss == null:
		push_warning("no furnace mother")
		return
	await _frames(40)
	await _shot("furnace_p1")
	await _fire_at(&"missile", boss.global_position + Vector2(0, -100))
	await _frames(10)
	await _shot("furnace_p1_missile")
	boss.set_test_phase(2)
	await _frames(20)
	await _shot("furnace_p2_a")
	await _frames(70)
	await _shot("furnace_p2_b")
	await _frames(70)
	await _shot("furnace_p2_c")


func _capture_enemies() -> void:
	var room := int(_argument("--lineup-room=", "1"))
	var ids: Array = Catalog.ENEMY_IDS.duplicate()
	ids.erase(&"crawler")
	for batch in 2:
		var origin := _teleport(room, 1000.0)
		_level.call("_clear_group", &"dev_boss")
		_level.call("_clear_group", &"dev_enemy")
		var spawned: Array[Node2D] = []
		for slot in 6:
			var runtime_id: StringName = ids[batch * 6 + slot]
			var flying := (
				runtime_id
				in [&"ceiling_diver", &"vent_flyer", &"frost_floater", &"energy_parasite"]
			)
			var location := origin + Vector2(150.0 + float(slot) * 330.0, FLOOR_Y - 25.0)
			if flying:
				location.y = FLOOR_Y - 330.0
			# Bounds exclude the player so enemies idle in place for a clean lineup.
			var bounds := Rect2(location - Vector2(120, 500), Vector2(240, 560))
			var enemy := (
				_level.call("_spawn_enemy", runtime_id, location, "S%d" % room, bounds) as Node2D
			)
			if enemy != null:
				spawned.append(enemy)
		_player.global_position = origin + Vector2(1000.0, 700.0)
		await _frames(40)
		await _shot("enemies%d_lineup" % batch)
		for enemy in spawned:
			if enemy.has_method("receive_hit"):
				enemy.call("receive_hit", 10, &"beam", {"position": enemy.global_position})
		await _frames(2)
		await _shot("enemies%d_hit_flash" % batch)
		await _frames(30)
		for enemy in spawned:
			if is_instance_valid(enemy) and enemy.has_method("receive_hit"):
				enemy.call("receive_hit", 10, &"ice", {"position": enemy.global_position})
		await _frames(10)
		await _shot("enemies%d_frozen" % batch)
		await _frames(200)
		await _shot("enemies%d_thaw_warning" % batch)
		for enemy in spawned:
			if is_instance_valid(enemy) and enemy.has_method("receive_hit"):
				enemy.call("receive_hit", 999, &"missile", {"position": enemy.global_position})
		await _frames(3)
		await _shot("enemies%d_death_a" % batch)
		await _frames(10)
		await _shot("enemies%d_death_b" % batch)


func _capture_player() -> void:
	_teleport(1, 400.0)
	_level.call("_clear_group", &"dev_enemy")
	await _frames(30)
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await _frames(25)
	for step in 4:
		await _frames(5)
		await _shot("player_run_%d" % step, _player.global_position)
	Input.action_press(&"jump")
	await _frames(8)
	Input.action_release(&"jump")
	await _frames(30)
	await _shot("player_air")
	for _i in 40:
		await _frames(1)
		if _player.is_on_floor():
			break
	await _frames(2)
	await _shot("player_land", _player.global_position)
	Input.action_release(&"move_right")
	Input.action_release(&"run")
	_player.dev_invulnerable = false
	_player.take_damage(10, _player.global_position + Vector2(40, 0))
	await _frames(3)
	await _shot("player_hurt", _player.global_position)
	await _frames(20)
	await _shot("player_hurt_blink", _player.global_position)
	await _fire_at(&"missile", _player.global_position + Vector2(800, -120))
	await _frames(2)
	await _shot("player_missile_fire", _player.global_position)
	await _frames(12)
	await _shot("player_missile_flight")


func _capture_world() -> void:
	# Natural encounters: [station, player local x, label].
	var spots := [
		[2, 700.0, "s2_gargoyle"],
		[3, 800.0, "s3_grasshopper"],
		[6, 1200.0, "s6_lava"],
		[7, 300.0, "s7_gallery"],
	]
	for spot in spots:
		_teleport(int(spot[0]), float(spot[1]))
		await _frames(50)
		await _shot(String(spot[2]) + "_a")
		await _frames(45)
		await _shot(String(spot[2]) + "_b")
