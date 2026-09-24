extends Node

## Screenshots of every living-environment mechanic in action, per area look.
## godot --path . --windowed --resolution 1920x1080 res://tools/capture_worldfx.tscn -- --test-mode
##   [--out=<dir>] [--only=<name>]

const Testbed = preload("res://tools/worldfx_testbed.gd")
const TILE := 64.0
const ROOM := [
	"##############################",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"##############################",
	"##############################",
]

var _out := "user://worldfx_shots"
var _only := ""
var _room: CampaignRoom
var _player: Player
## Fixed 1920x1080 render target, independent of the (possibly tiled) window size.
var _view: SubViewport


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(_out)
	_view = SubViewport.new()
	_view.size = Vector2i(1920, 1080)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	call_deferred("_run")


func _run() -> void:
	for shot in [
		"ambush",
		"timed",
		"crumble",
		"stalactite_vaults",
		"stalactite_kiln",
		"crusher",
		"currents",
		"steam",
		"lava_shaft",
		"water_shaft",
	]:
		if _only.is_empty() or _only == shot:
			await call("_shot_" + shot)
	await _clear()
	get_tree().quit()


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _clear() -> void:
	for child in _view.get_children():
		child.queue_free()
	await _frames(2)


func _setup(area: StringName, grid: Array, cell: Vector2i) -> void:
	await _clear()
	GameState.reset_progress()
	GameState.acquire_beam()
	_room = Testbed.build_room(_view, area, grid)
	_player = Testbed.spawn_player(_view, _room, cell)
	await _frames(20)


func _add(node: Node2D, local: Vector2) -> Node2D:
	node.position = local
	Testbed.entities(_room).add_child(node)
	return node


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	_view.get_texture().get_image().save_png(path)
	print("saved ", path)


func _shot_ambush() -> void:
	var grid := ROOM.duplicate()
	for row in range(1, 12):
		grid[row] = "#####" + grid[row].substr(5, 20) + "#####"
	await _setup(&"fringe", grid, Vector2i(9, 14))
	var arena := AmbushArena.new()
	arena.arena_size = Vector2(22 * TILE, 14 * TILE)
	arena.wave = PackedStringArray(["hopper", "vent_flyer", "hopper"])
	arena.spawn_offsets = PackedVector2Array(
		[Vector2(-192, 300), Vector2(128, -64), Vector2(384, 300)]
	)
	arena.door_rects = [
		Rect2(Vector2(-11 * TILE, 4 * TILE), Vector2(TILE, 3 * TILE)),
		Rect2(Vector2(10 * TILE, 4 * TILE), Vector2(TILE, 3 * TILE)),
	]
	_add(arena, Vector2(15 * TILE, 8 * TILE))
	await _frames(10)
	_player.global_position = Testbed.feet(_room, Vector2i(12, 14))
	await _frames(26)
	await _save("ambush_sealed")
	await _frames(70)
	await _save("ambush_wave")


func _shot_timed() -> void:
	var grid := ROOM.duplicate()
	for row in range(1, 12):
		grid[row] = grid[row].substr(0, 18) + "#" + grid[row].substr(19)
	await _setup(&"nexus", grid, Vector2i(13, 14))
	var door := TimedDoor.new()
	door.seconds = 6.0
	door.switch_offsets = PackedVector2Array([Vector2(-448, -224)])
	_add(door, Vector2(18 * TILE + 32, 13 * TILE + 32))
	await _frames(10)
	await _save("timed_idle")
	door.switches[0].receive_hit(1, &"beam")
	await _frames(150)
	await _save("timed_counting")
	await _frames(130)
	await _save("timed_warning")


func _shot_crumble() -> void:
	var grid := ROOM.duplicate()
	grid[11] = "#.......######......##########"
	grid[12] = "#.......######......##########"
	await _setup(&"vaults", grid, Vector2i(12, 10))
	var bridge := CrumbleFloor.new()
	bridge.cells = 6
	_add(bridge, Vector2(14 * TILE, 11 * TILE))
	await _frames(10)
	await _save("crumble_idle")
	_player.global_position = Testbed.feet(_room, Vector2i(14, 10))
	Input.action_press(&"move_right")
	await _frames(22)
	Input.action_release(&"move_right")
	await _frames(12)
	await _save("crumble_breaking")


func _stalactite_room(area: StringName) -> void:
	await _setup(area, ROOM, Vector2i(8, 14))
	for x in [11, 14, 17, 20]:
		var spike := Stalactite.new()
		spike.width = 110.0 if x % 2 == 0 else 84.0
		_add(spike, Vector2(x * TILE + 32, 1 * TILE))
	await _frames(10)
	await _save("stalactite_%s_idle" % area)
	_player.global_position = Testbed.feet(_room, Vector2i(14, 14))
	await _frames(40)
	await _save("stalactite_%s_falling" % area)
	await _frames(14)
	await _save("stalactite_%s_shatter" % area)


func _shot_stalactite_vaults() -> void:
	await _stalactite_room(&"vaults")


func _shot_stalactite_kiln() -> void:
	await _stalactite_room(&"kiln")


func _shot_crusher() -> void:
	var grid := ROOM.duplicate()
	grid[1] = "#########...####...###########"
	grid[2] = grid[1]
	await _setup(&"kiln", grid, Vector2i(6, 14))
	var first := Crusher.new()
	_add(first, Vector2(10.5 * TILE, 1 * TILE))
	var second := Crusher.new()
	second.phase_offset = 1.5
	_add(second, Vector2(17.5 * TILE, 1 * TILE))
	await _frames(20)
	_player.global_position = Testbed.feet(_room, Vector2i(13, 14))
	await _frames(40)
	await _save("crusher_a")
	await _frames(30)
	await _save("crusher_b")
	await _frames(40)
	await _save("crusher_c")


func _shot_currents() -> void:
	await _setup(&"depths", ROOM, Vector2i(6, 14))
	var water := PushCurrent.new()
	water.zone_size = Vector2(1280, 320)
	water.direction = Vector2.RIGHT
	water.strength = 260.0
	water.kind = &"water"
	_add(water, Vector2(15 * TILE, 12.5 * TILE))
	var wind := PushCurrent.new()
	wind.zone_size = Vector2(1280, 256)
	wind.direction = Vector2.LEFT
	wind.strength = 220.0
	wind.kind = &"wind"
	_add(wind, Vector2(15 * TILE, 5 * TILE))
	await _frames(60)
	await _save("currents")


func _shot_steam() -> void:
	await _setup(&"kiln", ROOM, Vector2i(10, 14))
	var steam := PushCurrent.new()
	steam.zone_size = Vector2(192, 832)
	steam.direction = Vector2.UP
	steam.strength = 700.0
	steam.kind = &"steam"
	_add(steam, Vector2(14 * TILE, 8.5 * TILE))
	await _frames(20)
	_player.global_position = Testbed.feet(_room, Vector2i(14, 14))
	await _frames(28)
	await _save("steam_updraft")


func _shaft_grid() -> Array:
	return [
		"##############################",
		"##########.......#############",
		"##########.......#############",
		"##########.......#############",
		"##########.....###############",
		"##########.......#############",
		"##########.......#############",
		"############.....#############",
		"##########.......#############",
		"##########.......#############",
		"#..............###############",
		"#................#############",
		"#................#############",
		"############.....#############",
		"##########.......#############",
		"##########.......#############",
		"##############################",
	]


func _shaft(area: StringName, kind: StringName, name: String) -> void:
	await _setup(area, _shaft_grid(), Vector2i(5, 12))
	var shaft := RisingShaft.new()
	shaft.shaft_size = Vector2(7 * TILE, 15 * TILE)
	shaft.safe_line = 3 * TILE
	shaft.speed = 110.0
	shaft.kind = kind
	_add(shaft, Vector2(10 * TILE, TILE))
	await _frames(10)
	await _save(name + "_idle")
	_player.global_position = Testbed.feet(_room, Vector2i(15, 9))
	await _frames(60 + 150)
	await _save(name + "_rising")


func _shot_lava_shaft() -> void:
	await _shaft(&"kiln", &"lava", "shaft_lava")


func _shot_water_shaft() -> void:
	await _shaft(&"depths", &"water", "shaft_water")
