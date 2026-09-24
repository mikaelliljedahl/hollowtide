class_name CampaignRoot
extends Node2D

## Owns the player, HUD, map and fade layer for the campaign and swaps hand-authored rooms.
## Rooms abut on a shared tile map; leaving through a boundary opening enters the neighbour at
## the same world cell, so doors need no ids. Death returns to the last save in memory (no disk
## load). Save shrines double as fast-travel stations (docs/features/fast-travel.md) and Tide
## Glyph sockets (docs/features/tide-modules.md), both reached through one shrine menu.
## Debug-only launch flags: --campaign-room=<id>, --campaign-grant=<ability,...>.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const MAP_SCRIPT = preload("res://scripts/campaign/campaign_map.gd")
const MINIMAP_SCRIPT = preload("res://scripts/campaign/campaign_minimap.gd")
const FastTravel = preload("res://scripts/campaign/fast_travel.gd")
const TIDE_HOOK_SCRIPT = preload("res://scripts/campaign/tide_hook.gd")
const SHRINE_MENU_SCRIPT = preload("res://scripts/ui/shrine_menu.gd")
## Code toggle for the top-right HUD minimap.
const SHOW_MINIMAP := true
const CREDITS_PATH := "res://scenes/campaign/credits.tscn"
const TILE := 64.0
const FADE_SECONDS := 0.16
const TRAVEL_FADE_SECONDS := 0.4
## Travel refusal reasons (see travel_blocker).
const BLOCK_AMBUSH := &"ambush"
const BLOCK_BOSS := &"boss"
const BLOCK_HAZARD := &"hazard"
const BLOCK_BUSY := &"busy"
const DEATH_WAIT := 0.45
const SIDE_EXIT := 20.0
const TOP_EXIT := 40.0
const BOTTOM_EXIT := 8.0
const SIDE_ENTRY := 72.0
const TOP_ENTRY := 200.0
const BOTTOM_ENTRY := 24.0
const UP_ENTRY_SPEED := 1180.0

signal room_changed(room_id: String)

var current_room: CampaignRoom
var current_room_id := ""
var player: Player
var map: CanvasLayer
var minimap: CanvasLayer
var tide_hook: Node
var shrine_menu: CanvasLayer
var _shrine_from := ""
var _world: Node2D
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _busy := false
var _respawning := false
var _ending := false
var _generation := 0


func _ready() -> void:
	add_to_group(&"campaign_root")
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	# The HUD instances the shared pause menu itself (ui lane).
	add_child(HUD_SCENE.instantiate())
	map = MAP_SCRIPT.new()
	map.name = "CampaignMap"
	add_child(map)
	minimap = MINIMAP_SCRIPT.new()
	minimap.name = "CampaignMinimap"
	minimap.set("enabled", SHOW_MINIMAP)
	add_child(minimap)
	tide_hook = TIDE_HOOK_SCRIPT.new()
	add_child(tide_hook)
	shrine_menu = SHRINE_MENU_SCRIPT.new()
	shrine_menu.name = "ShrineMenu"
	add_child(shrine_menu)
	shrine_menu.chosen.connect(_on_shrine_chosen)
	_build_fade()
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)
	get_tree().paused = false
	if not Rooms.ROOMS.has(String(GameState.checkpoint.get("room", ""))):
		# Launched directly (not through CampaignEntry): continue the slot when one exists.
		if OS.get_cmdline_user_args().has("--campaign-new") or not CampaignEntry.prepare_continue():
			CampaignEntry.prepare_new_game()
	_apply_debug_arguments()
	var checkpoint: Dictionary = GameState.checkpoint
	var room_id := String(checkpoint.get("room", ""))
	var spawn := Vector2(float(checkpoint.get("x", 0.0)), float(checkpoint.get("y", 0.0)))
	if not Rooms.ROOMS.has(room_id):
		room_id = Rooms.START_ROOM
		spawn = Rooms.START_POSITION
		GameState.set_checkpoint(room_id, spawn)
	# Saves from before fast travel: the shrine the slot was written at counts as activated.
	var resumed := FastTravel.station_near(room_id, spawn)
	if not resumed.is_empty():
		GameState.activate_station(resumed)
	var requested := _debug_room()
	if Rooms.ROOMS.has(requested):
		room_id = requested
		spawn = Vector2(-1, -1)
	_load_room(room_id)
	if spawn.x < 0.0:
		spawn = (
			current_room.start_position()
			if current_room.has_node("Entities/Start")
			else _first_save(room_id)
		)
	_place_player(spawn, true)
	_fade.color.a = 1.0
	_fade_to(0.0, FADE_SECONDS * 2.0)


func _exit_tree() -> void:
	if GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.disconnect(_on_player_died)


func _physics_process(_delta: float) -> void:
	if _busy or _respawning or _ending or current_room == null or player == null:
		return
	if GameState.health <= 0:
		return
	var local := player.global_position - current_room.global_position
	var size := current_room.size_px()
	var edge := &""
	if local.x < SIDE_EXIT:
		edge = &"west"
	elif local.x > size.x - SIDE_EXIT:
		edge = &"east"
	elif local.y < TOP_EXIT:
		edge = &"north"
	elif local.y > size.y - BOTTOM_EXIT:
		edge = &"south"
	if edge != &"":
		_leave_room(edge, local)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _ending:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_M, KEY_TAB]:
			if map != null and (map.visible or not get_tree().paused):
				map.call("toggle")
				get_viewport().set_input_as_handled()


## Called by save shrines. Position is local to the current room (player feet).
func save_at(local_position: Vector2) -> bool:
	if current_room_id.is_empty():
		return false
	var station := FastTravel.station_near(current_room_id, local_position)
	if not station.is_empty():
		GameState.activate_station(station)
	GameState.set_checkpoint(current_room_id, local_position)
	var result := _save()
	GameState.pickup_feedback.emit("PROGRESS SAVED" if result == OK else "SAVE FAILED")
	return result == OK


## Why fast travel is refused right now, or &"" when allowed: a transition or death in progress,
## a sealed or fighting ambush arena, a living boss with the player in its arena, or a rising
## flood that is not at rest. Rooms are freed on every change, so the groups hold the current room.
func travel_blocker() -> StringName:
	if _busy or _respawning or _ending or current_room == null or GameState.health <= 0:
		return BLOCK_BUSY
	var tree := get_tree()
	for node in tree.get_nodes_in_group(&"worldfx_ambush"):
		var arena := node as AmbushArena
		if (
			arena != null
			and arena.state not in [AmbushArena.State.ARMED, AmbushArena.State.CLEARED]
		):
			return BLOCK_AMBUSH
	for node in tree.get_nodes_in_group(&"campaign_boss"):
		var boss := node as CombatBoss
		if boss == null or boss.health <= 0:
			continue
		if boss._in_arena(player.global_position):
			return BLOCK_BOSS
	for node in tree.get_nodes_in_group(&"worldfx_rising_shaft"):
		var shaft := node as RisingShaft
		if shaft != null and shaft.state != RisingShaft.State.ARMED:
			return BLOCK_HAZARD
	return &""


## Travel targets from an activated shrine in the current room, limited to discovered rooms;
## empty while travel is blocked.
func travel_targets(from_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if FastTravel.station(from_id).get("room", "") != current_room_id or travel_blocker() != &"":
		return result
	for entry in FastTravel.targets(GameState.activated_stations, from_id):
		if GameState.discovered_rooms.has(entry["room"]):
			result.append(entry)
	return result


## Opens the map in travel mode at shrine `from_id` (called by the shrine). False when there is
## nowhere to go or travel is blocked.
func open_travel(from_id: String) -> bool:
	var targets := travel_targets(from_id)
	if targets.is_empty() or map == null or map.visible:
		return false
	map.call("open_travel", from_id, targets)
	return true


## What the save shrine `from_id` in the current room offers right now, in menu order:
## travel while a target exists and nothing blocks it (travel_targets), Tide Sockets while a glyph
## is owned. Tide Sockets ignore ambushes and bosses, as the socket screen always did; only a
## transition, death or the ending refuses them.
func shrine_options(from_id: String) -> Array[StringName]:
	var result: Array[StringName] = []
	if FastTravel.station(from_id).get("room", "") != current_room_id:
		return result
	if not travel_targets(from_id).is_empty():
		result.append(SHRINE_MENU_SCRIPT.TRAVEL)
	if not GameState.tide.owned.is_empty() and travel_blocker() != BLOCK_BUSY:
		result.append(SHRINE_MENU_SCRIPT.TIDE)
	return result


## Called by a save shrine on move_up: opens the shrine menu when it offers both options, the one
## screen directly when it offers one, nothing when it offers none.
func open_shrine(from_id: String) -> bool:
	var offered := shrine_options(from_id)
	if offered.is_empty() or map.visible or shrine_menu.call("is_open"):
		return false
	_shrine_from = from_id
	if offered.size() == 1:
		_on_shrine_chosen(offered[0])
	else:
		shrine_menu.call("open", offered)
	return true


func _on_shrine_chosen(option: StringName) -> void:
	match option:
		SHRINE_MENU_SCRIPT.TRAVEL:
			open_travel(_shrine_from)
		SHRINE_MENU_SCRIPT.TIDE:
			var shrine := FastTravel.station(_shrine_from)
			tide_hook.call("open_at", shrine.get("position", Vector2.ZERO))


## Fades out, loads the target shrine's room, stands the player on it, then refills, moves the
## checkpoint there and saves, exactly like resting at that shrine. Refused unless both shrines
## are activated, `from_id` is in the current room and nothing blocks travel.
func travel_to(from_id: String, to_id: String) -> bool:
	if not travel_targets(from_id).any(
		func(entry: Dictionary) -> bool: return entry["id"] == to_id
	):
		return false
	_travel(FastTravel.station(to_id))
	return true


func _travel(target: Dictionary) -> void:
	_busy = true
	_generation += 1
	var generation := _generation
	get_tree().paused = true
	await _fade_to(1.0, TRAVEL_FADE_SECONDS)
	if generation != _generation:
		return
	_load_room(target["room"])
	_place_player(target["position"], true)
	GameState.refill()
	GameState.set_checkpoint(target["room"], target["position"])
	var result := _save()
	if result != OK:
		push_warning("Campaign: travel save failed: %s" % error_string(result))
	await get_tree().process_frame
	get_tree().paused = false
	await _fade_to(0.0, TRAVEL_FADE_SECONDS)
	_busy = false


func on_boss_defeated(_boss_id: StringName) -> bool:
	var result := _save()
	if result != OK:
		push_warning("Campaign: boss autosave failed: %s" % error_string(result))
	return result == OK


func play_ending() -> void:
	if _ending:
		return
	_ending = true
	_fade.color = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "color:a", 1.0, 3.0)
	await tween.finished
	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file(CREDITS_PATH)


## Loads a room directly and places the player (tools and debug launch only).
func teleport(room_id: String, local_position: Vector2) -> void:
	if not Rooms.ROOMS.has(room_id):
		return
	_generation += 1
	_busy = false
	_respawning = false
	get_tree().paused = false
	_fade.color.a = 0.0
	_load_room(room_id)
	_place_player(local_position, true)


func room_rect_world(room_id: String) -> Rect2i:
	var data: Dictionary = Rooms.ROOMS[room_id]
	return Rect2i(data["origin"], data["size"])


func _save() -> Error:
	var store := get_node_or_null("/root/SaveStore")
	if store == null:
		return ERR_UNAVAILABLE
	return store.call("save_game")


func _leave_room(edge: StringName, local: Vector2) -> void:
	var data: Dictionary = Rooms.ROOMS[current_room_id]
	var origin: Vector2 = Vector2(data["origin"]) * TILE
	var world := origin + local
	var probe := local
	match edge:
		&"west", &"east":
			probe.y -= 40.0
		_:
			pass
	var cell := Vector2i(floori(probe.x / TILE), floori(probe.y / TILE))
	var target := ""
	var best := INF
	for door in data["doors"]:
		if door["edge"] != edge:
			continue
		var from: Vector2i = door["from"]
		var to: Vector2i = door["to"]
		var distance := 0.0
		if edge in [&"west", &"east"]:
			distance = maxf(0.0, maxf(from.y - cell.y, cell.y - to.y))
		else:
			distance = maxf(0.0, maxf(from.x - cell.x, cell.x - to.x))
		if distance < best:
			best = distance
			target = door["target"]
	if target.is_empty() or best > 2.0:
		# No door here (should not happen with validated layouts): push back inside.
		player.global_position = (
			current_room.global_position
			+ local.clamp(
				Vector2(SIDE_EXIT + 4, TOP_EXIT + 4),
				current_room.size_px() - Vector2(SIDE_EXIT + 4, 64)
			)
		)
		player.velocity = Vector2.ZERO
		return
	var target_data: Dictionary = Rooms.ROOMS[target]
	var target_size := Vector2(target_data["size"]) * TILE
	var entry := world - Vector2(target_data["origin"]) * TILE
	match edge:
		&"east":
			entry.x = SIDE_ENTRY
		&"west":
			entry.x = target_size.x - SIDE_ENTRY
		&"south":
			entry.y = TOP_ENTRY
		&"north":
			entry.y = target_size.y - BOTTOM_ENTRY
			player.velocity.y = minf(player.velocity.y, -UP_ENTRY_SPEED)
	_transition(target, entry)


func _transition(target: String, entry: Vector2) -> void:
	_busy = true
	_generation += 1
	var generation := _generation
	get_tree().paused = true
	await _fade_to(1.0, FADE_SECONDS)
	if generation != _generation:
		return
	_load_room(target)
	_place_player(entry, false)
	await get_tree().process_frame
	get_tree().paused = false
	await _fade_to(0.0, FADE_SECONDS)
	_busy = false


func _load_room(room_id: String) -> void:
	if current_room != null:
		_world.remove_child(current_room)
		current_room.queue_free()
		current_room = null
	for node in get_tree().get_nodes_in_group(&"transient"):
		if is_instance_valid(node):
			node.queue_free()
	var weapons := get_node_or_null("/root/Weapons")
	if weapons != null and weapons.has_method("reset_runtime"):
		weapons.call("reset_runtime")
	var scene := load(String(Rooms.ROOMS[room_id]["scene"])) as PackedScene
	current_room = scene.instantiate() as CampaignRoom
	current_room_id = room_id
	_world.add_child(current_room)
	GameState.discover_room(room_id)
	_configure_camera()
	_play_area(current_room.area_id)
	if map != null:
		map.call("set_current", room_id)
	room_changed.emit(room_id)


func _place_player(local_position: Vector2, reset: bool) -> void:
	var target := current_room.global_position + local_position
	if reset:
		player.reset_for_spawn(target)
	else:
		player.global_position = target
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
		camera.force_update_scroll()


func _configure_camera() -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	var rect := Rect2(current_room.global_position, current_room.size_px())
	camera.limit_left = int(rect.position.x)
	camera.limit_top = int(rect.position.y)
	camera.limit_right = int(rect.end.x)
	camera.limit_bottom = int(rect.end.y)


func _play_area(area: StringName) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio == null:
		return
	if audio.has_method("play_area"):
		audio.call("play_area", area)
	elif audio.has_method("play_music"):
		audio.call("play_music", area)


func _on_player_died() -> void:
	if _respawning or _ending:
		return
	_respawning = true
	await get_tree().create_timer(DEATH_WAIT, false).timeout
	await _fade_to(1.0, FADE_SECONDS * 2.0)
	var checkpoint: Dictionary = GameState.checkpoint
	var room_id := String(checkpoint.get("room", ""))
	var spawn := Vector2(float(checkpoint.get("x", 0.0)), float(checkpoint.get("y", 0.0)))
	if not Rooms.ROOMS.has(room_id):
		room_id = Rooms.START_ROOM
		spawn = Rooms.START_POSITION
	_load_room(room_id)
	GameState.reset_health()
	_place_player(spawn, true)
	await get_tree().process_frame
	await _fade_to(0.0, FADE_SECONDS * 2.0)
	_respawning = false


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 90
	_fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)


func _fade_to(alpha: float, seconds: float) -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "color:a", alpha, seconds)
	await tween.finished


func _first_save(room_id: String) -> Vector2:
	var saves: Array = Rooms.ROOMS[room_id]["saves"]
	if not saves.is_empty():
		return saves[0]
	var size := Vector2(Rooms.ROOMS[room_id]["size"]) * TILE
	return Vector2(size.x * 0.5, size.y * 0.5)


func _debug_enabled() -> bool:
	return OS.is_debug_build()


func _debug_room() -> String:
	if not _debug_enabled():
		return ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--campaign-room="):
			return argument.trim_prefix("--campaign-room=")
	return ""


func _apply_debug_arguments() -> void:
	if not _debug_enabled():
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--campaign-grant="):
			for id in argument.trim_prefix("--campaign-grant=").split(",", false):
				if id == "missiles":
					GameState.collect_pickup("debug.missile_tank", &"missile_tank")
				else:
					GameState.unlock_ability(StringName(id))
