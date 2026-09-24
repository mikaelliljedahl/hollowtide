extends Node
## Developer screenshot tool for the enemies lane (not part of make check).
##   godot --path . --windowed --resolution 1920x1080 res://tools/capture_enemies.tscn -- \
##     --dev-mode --test-mode --test-save-root=/tmp/x --shots=surprise --shots-dir=/abs/dir
## Modes: rooms (each dev station), surprise (each D20 enemy in action), roster (old enemies).

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const FLOOR_Y := 1152.0

var _level: Node2D
var _player: Player
var _out := "user://enemy_shots/"
var _index := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots-dir="):
			_out = argument.trim_prefix("--shots-dir=")
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	# Tiling window managers resize the window; render at a fixed 1920x1080 regardless.
	var window := get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = Vector2i(1920, 1080)
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
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
	var wanted := _argument("--shots=", "surprise").split(",")
	if wanted.has("rooms"):
		await _capture_rooms()
	if wanted.has("surprise"):
		await _capture_surprise()
	if wanted.has("roster"):
		await _capture_roster()
	if wanted.has("natural"):
		await _capture_natural()
	print("capture_enemies: wrote %d shots to %s" % [_index, _out])
	get_tree().quit(0)


func _argument(prefix: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _shot(label: String, focus := Vector2.INF) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if focus.is_finite():
		var ratio := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
		var screen := get_viewport().get_canvas_transform() * focus * ratio
		var rect := Rect2i(Vector2i(screen) - Vector2i(400, 300), Vector2i(800, 520))
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


func _capture_rooms() -> void:
	for station in range(1, 10):
		_teleport(station, 1000.0)
		await _frames(30)
		var origin: Vector2 = _level.get("_room_origins")["S%d" % station]
		print(
			"S%d origin %s low ceiling local %s" % [station, origin, _low_ceiling(origin) - origin]
		)
		await _shot("room_S%d" % station)


func _spawn(id: StringName, at: Vector2, room: String, bounds: Rect2) -> Node2D:
	return _level.call("_spawn_enemy", id, at, room, bounds) as Node2D


func _capture_surprise() -> void:
	var room := int(_argument("--room=", "1"))
	var origin := _teleport(room, 300.0)
	_level.call("_clear_group", &"dev_enemy")
	var bounds := Rect2(origin + Vector2(80, 120), Vector2(1888, FLOOR_Y - 60))
	var floor_point := origin + Vector2(0, FLOOR_Y)
	# Bat swarm.
	var ceiling := _low_ceiling(origin)
	print("low ceiling at ", ceiling)
	var roost := _spawn(&"bat_swarm", ceiling + Vector2(0, 40), "S%d" % room, bounds)
	await _frames(20)
	await _shot("bat_roost_sleeping", roost.global_position + Vector2(0, 120))
	_player.global_position = Vector2(ceiling.x - 100, floor_point.y - 40)
	await _frames(12)
	await _shot("bat_roost_rustle", roost.global_position + Vector2(0, 120))
	await _frames(30)
	await _shot("bat_burst", roost.global_position + Vector2(0, 220))
	await _frames(50)
	await _shot("bat_swoop")
	await _frames(40)
	await _shot("bat_swoop_b")
	for bat in roost.get("bats"):
		if is_instance_valid(bat):
			bat.call("receive_hit", 0, &"ice", {})
			break
	await _frames(6)
	await _shot("bat_frozen")
	_level.call("_clear_group", &"dev_enemy")
	# Mimics.
	_player.global_position = floor_point + Vector2(300, -40)
	var rock := _spawn(&"mimic", floor_point + Vector2(900, -60), "S%d" % room, bounds)
	var lure := _spawn(&"mimic_lure", floor_point + Vector2(1400, -60), "S%d" % room, bounds)
	await _frames(40)
	await _shot("mimics_disguised", floor_point + Vector2(1150, -100))
	_player.global_position = rock.global_position + Vector2(-120, 20)
	await _frames(6)
	await _shot("mimic_reveal", rock.global_position)
	await _frames(22)
	await _shot("mimic_lunge", rock.global_position)
	await _frames(40)
	await _shot("mimic_scuttle", rock.global_position)
	_player.global_position = lure.global_position + Vector2(-90, 20)
	await _frames(8)
	await _shot("lure_reveal", lure.global_position)
	await _frames(24)
	await _shot("lure_lunge", lure.global_position)
	_level.call("_clear_group", &"dev_enemy")
	# Drop spider.
	_player.global_position = floor_point + Vector2(300, -40)
	var spider := _spawn(&"drop_spider", ceiling + Vector2(0, 60), "S%d" % room, bounds)
	await _frames(30)
	await _shot("spider_hidden", spider.global_position + Vector2(0, 200))
	_player.global_position = Vector2(spider.global_position.x + 20, floor_point.y - 40)
	await _frames(8)
	await _shot("spider_twitch", spider.global_position + Vector2(0, 200))
	await _frames(40)
	await _shot("spider_dangle")
	await _frames(60)
	await _shot("spider_climb")
	_level.call("_clear_group", &"dev_enemy")
	# Surface eel (on the floor line here; the campaign places it on lava/water).
	_player.global_position = floor_point + Vector2(300, -40)
	var eel := _spawn(&"surface_eel", floor_point + Vector2(1000, 0), "S%d" % room, bounds)
	await _frames(20)
	_player.global_position = floor_point + Vector2(1180, -40)
	for step in 9:
		await _frames(10)
		var sprite := eel.get_node("Sprite2D") as Sprite2D
		print(
			"eel ",
			step,
			" ",
			eel.call("presentation_state"),
			" rise ",
			eel.get("_rise"),
			" vis ",
			sprite.visible,
			" scale ",
			sprite.scale
		)
		await _shot("eel_%d_%s" % [step, eel.call("presentation_state")], eel.global_position)
	_level.call("_clear_group", &"dev_enemy")
	# Stalker.
	_player.global_position = floor_point + Vector2(1300, -40)
	var stalker := _spawn(&"stalker", floor_point + Vector2(600, -60), "S%d" % room, bounds)
	var windup_shot := false
	var pounce_shot := false
	for _i in 400:
		await get_tree().physics_frame
		var state := StringName(stalker.call("presentation_state"))
		if state == &"windup" and not windup_shot:
			await _frames(12)
			await _shot("stalker_windup", stalker.global_position)
			windup_shot = true
		elif state == &"pounce" and not pounce_shot:
			await _frames(8)
			await _shot("stalker_pounce", stalker.global_position)
			pounce_shot = true
		if windup_shot and pounce_shot:
			break
	await _shot("stalker_wide")
	_level.call("_clear_group", &"dev_enemy")
	# Chasm sniper.
	_player.global_position = floor_point + Vector2(300, -40)
	var sniper := _spawn(&"chasm_sniper", floor_point + Vector2(1150, -60), "S%d" % room, bounds)
	var track_shot := false
	var lock_shot := false
	for _i in 400:
		await get_tree().physics_frame
		var state := StringName(sniper.call("presentation_state"))
		if state == &"hidden" and _i == 30:
			await _shot("sniper_hidden", sniper.global_position)
		if state == &"track" and not track_shot:
			await _frames(30)
			await _shot("sniper_track")
			track_shot = true
		elif state == &"lock" and not lock_shot:
			await _frames(8)
			await _shot("sniper_lock")
			lock_shot = true
		if track_shot and lock_shot:
			break
	await _frames(12)
	await _shot("sniper_fired")
	_level.call("_clear_group", &"dev_enemy")


func _capture_roster() -> void:
	var origin := _teleport(1, 300.0)
	_level.call("_clear_group", &"dev_enemy")
	var bounds := Rect2(origin + Vector2(80, 120), Vector2(1888, FLOOR_Y - 60))
	var floor_point := origin + Vector2(0, FLOOR_Y)
	_player.global_position = floor_point + Vector2(700, -40)
	var guard := _spawn(&"armored_guard", floor_point + Vector2(1150, -40), "S1", bounds)
	for index in 3:
		_spawn(&"energy_parasite", origin + Vector2(1300 + index * 60, 700), "S1", bounds)
	var saw_windup := false
	var saw_charge := false
	for _i in 240:
		await get_tree().physics_frame
		var state := StringName(guard.get("_special_state"))
		if state == &"windup" and not saw_windup:
			saw_windup = true
			await _frames(10)
			await _shot("guard_windup", guard.global_position)
		elif state == &"charge" and not saw_charge:
			saw_charge = true
			await _frames(8)
			await _shot("guard_charge", guard.global_position)
		if saw_charge:
			break
	await _frames(20)
	await _shot("parasites_swarm")
	_level.call("_clear_group", &"dev_enemy")


## World point on the lowest ceiling above the room floor (for hanging enemies).
func _low_ceiling(origin: Vector2) -> Vector2:
	var best := origin + Vector2(1000, 500)
	var best_gap := INF
	var space := get_viewport().world_2d.direct_space_state
	for step in range(4, 30):
		var x := origin.x + float(step) * 64.0
		var from := Vector2(x, origin.y + FLOOR_Y - 60)
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters2D.create(from, from + Vector2(0, -760), 1)
		)
		if hit.is_empty():
			continue
		var gap: float = from.y - Vector2(hit["position"]).y
		if gap > 260.0 and gap < best_gap:
			best_gap = gap
			best = Vector2(hit["position"])
	return best


func _capture_natural() -> void:
	for spec in [[1, 400.0], [3, 400.0], [6, 300.0], [9, 300.0]]:
		_teleport(spec[0], spec[1])
		await _frames(40)
		await _shot("natural_S%d" % spec[0])
