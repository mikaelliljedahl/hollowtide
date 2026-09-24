class_name TrialsRoot
extends Node2D
## Runs one trial (docs/features/trials.md): the Gauntlet (one sealed D21 AmbushArena with six
## escalating waves) or the Boss Rush (the three campaign bosses in their area art, with a breather
## and one refill between them). Clocks the clear in physics time, counts hits taken, and shows the
## results panel. Death, or an arena abort, ends the run without a record.
## Debug launch: godot --path . res://scenes/trials/trials.tscn -- --trial=boss_rush

signal run_finished(result: Dictionary)

enum Phase { READY, RUNNING, BREATHER, DONE }

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const BOSS_SPAWN_SCRIPT = preload("res://scripts/trials/trial_boss_spawn.gd")
const RESULTS_SCRIPT = preload("res://scripts/trials/trial_results_panel.gd")
const DEATH_WAIT := 0.45
const RESULTS_DELAY := 1.2
const FADE_SECONDS := 0.3

var mode: StringName = TrialCatalog.GAUNTLET
var phase := Phase.READY
var player: Player
var room: CampaignRoom
var arena: AmbushArena
var boss_index := -1
var boss_spawn: Marker2D
var elapsed := 0.0
var hits := 0
var result: Dictionary = {}
var results_panel: Control
var _hud: CanvasLayer
var _last_health := 0
var _fade: ColorRect


func _ready() -> void:
	add_to_group(&"trials_root")
	get_tree().paused = false
	mode = _requested_mode()
	if TrialsEntry.campaign_snapshot.is_empty():
		# Launched without the menu: nothing is saved, but the kit is the same.
		TrialsEntry.apply_kit()
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	_hud = HUD_SCENE.instantiate() as CanvasLayer
	add_child(_hud)
	_build_overlays()
	_last_health = GameState.health
	GameState.health_changed.connect(_on_health_changed)
	GameState.player_died.connect(_on_player_died)
	if mode == TrialCatalog.BOSS_RUSH:
		_load_boss_room(0)
	else:
		_build_gauntlet()


func _exit_tree() -> void:
	if GameState.health_changed.is_connected(_on_health_changed):
		GameState.health_changed.disconnect(_on_health_changed)
	if GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.disconnect(_on_player_died)


func _physics_process(delta: float) -> void:
	if phase in [Phase.RUNNING, Phase.BREATHER]:
		elapsed += delta


func elapsed_ms() -> int:
	return roundi(elapsed * 1000.0)


# --- Gauntlet ----------------------------------------------------------------------------------


func _build_gauntlet() -> void:
	room = TrialRoomBuilder.build(
		self, TrialCatalog.GAUNTLET_AREA, TrialCatalog.GAUNTLET_GRID, "trials_gauntlet"
	)
	arena = AmbushArena.new()
	arena.name = "GauntletArena"
	arena.position = TrialCatalog.GAUNTLET_ARENA_CENTRE
	arena.arena_size = TrialCatalog.GAUNTLET_ARENA_SIZE
	arena.trigger_rect = TrialCatalog.GAUNTLET_TRIGGER
	arena.wave = PackedStringArray(TrialCatalog.WAVES[0])
	for extra in TrialCatalog.WAVES.slice(1):
		arena.extra_waves.append(PackedStringArray(extra))
	arena.spawn_offsets = gauntlet_spawn_offsets()
	arena.local_id = "gauntlet"
	arena.flag_id = "trials.gauntlet"
	# A gauntlet never clears itself: only beating every wave ends it.
	arena.max_seconds = 3600.0
	arena.assist_skippable = false
	arena.spawned.connect(_on_gauntlet_spawned)
	arena.sealed.connect(_start_clock)
	arena.cleared.connect(_complete)
	arena.aborted.connect(_fail)
	TrialRoomBuilder.entities(room).add_child(arena)
	_place_player()
	_play_area(TrialCatalog.GAUNTLET_AREA)


## Spawn offset i belongs to spawn i (AmbushRules class-aware relocation): flyers cycle through
## the air points, everything else through the floor points.
static func gauntlet_spawn_offsets() -> PackedVector2Array:
	var offsets := PackedVector2Array()
	var floor_points := TrialCatalog.GAUNTLET_FLOOR_POINTS
	var air_points := TrialCatalog.GAUNTLET_AIR_POINTS
	var floor_index := 0
	var air_index := 0
	for id in TrialCatalog.all_spawn_ids():
		if AmbushRules.is_air(StringName(id)):
			offsets.append(air_points[air_index % air_points.size()])
			air_index += 1
		else:
			offsets.append(floor_points[floor_index % floor_points.size()])
			floor_index += 1
	return offsets


func _on_gauntlet_spawned(enemy: Node2D) -> void:
	if arena.wave_index in TrialCatalog.ELITE_WAVES:
		EnemyElite.apply(enemy)


# --- Boss Rush ---------------------------------------------------------------------------------


func _load_boss_room(index: int) -> void:
	boss_index = index
	var boss_id: StringName = TrialCatalog.BOSSES[index]
	var area: StringName = TrialCatalog.BOSS_AREAS[boss_id]
	if room != null:
		remove_child(room)
		room.queue_free()
	for node in get_tree().get_nodes_in_group(&"transient"):
		node.queue_free()
	var weapons := get_node_or_null("/root/Weapons")
	if weapons != null and weapons.has_method("reset_runtime"):
		weapons.call("reset_runtime")
	room = TrialRoomBuilder.build(self, area, TrialCatalog.BOSS_GRID, "trials_%s" % boss_id)
	_place_player()
	_play_area(area)
	await get_tree().create_timer(TrialCatalog.BOSS_INTRO_SECONDS, false).timeout
	if phase == Phase.DONE or boss_index != index or not is_inside_tree():
		return
	boss_spawn = BOSS_SPAWN_SCRIPT.new()
	boss_spawn.name = "BossSpawn"
	boss_spawn.set("boss_id", boss_id)
	boss_spawn.set("arena", TrialCatalog.BOSS_ARENA)
	boss_spawn.position = TrialCatalog.BOSS_POSITIONS[boss_id]
	boss_spawn.connect("boss_defeated", _on_boss_defeated)
	TrialRoomBuilder.entities(room).add_child(boss_spawn)
	if phase == Phase.READY:
		_start_clock()
	else:
		phase = Phase.RUNNING


func current_boss() -> Node2D:
	if not is_instance_valid(boss_spawn):
		return null
	var boss: Variant = boss_spawn.get("boss")
	return boss if is_instance_valid(boss) else null


func _on_boss_defeated(_id: StringName) -> void:
	if phase != Phase.RUNNING:
		return
	if boss_index + 1 >= TrialCatalog.BOSSES.size():
		_complete()
		return
	phase = Phase.BREATHER
	GameState.refill()
	var next := boss_index + 1
	await get_tree().create_timer(TrialCatalog.BREATHER_SECONDS - FADE_SECONDS * 2.0, false).timeout
	if phase != Phase.BREATHER:
		return
	await _fade_to(1.0)
	if phase != Phase.BREATHER:
		return
	_load_boss_room(next)
	await _fade_to(0.0)


# --- Run flow ----------------------------------------------------------------------------------


func _start_clock() -> void:
	if phase != Phase.READY:
		return
	elapsed = 0.0
	hits = 0
	_last_health = GameState.health
	phase = Phase.RUNNING


func _complete() -> void:
	if phase in [Phase.READY, Phase.DONE]:
		return
	phase = Phase.DONE
	var time_ms := elapsed_ms()
	result = {"mode": mode, "cleared": true, "time_ms": time_ms, "hits": hits}
	result.merge(TrialsEntry.record(mode, time_ms, hits))
	_finish()


func _fail() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	result = {"mode": mode, "cleared": false, "time_ms": elapsed_ms(), "hits": hits}
	_finish()


func _finish() -> void:
	run_finished.emit(result)
	await get_tree().create_timer(RESULTS_DELAY, false).timeout
	if not is_inside_tree():
		return
	get_tree().paused = true
	# The HUD would show the restored campaign state behind the panel.
	_hud.hide()
	results_panel.call("present", result)


func _on_health_changed(current: int, _maximum: int) -> void:
	if phase in [Phase.RUNNING, Phase.BREATHER] and current < _last_health:
		hits += 1
	_last_health = current


func _on_player_died() -> void:
	if phase == Phase.DONE:
		return
	await get_tree().create_timer(DEATH_WAIT, false).timeout
	_fail()


func _retry() -> void:
	TrialsEntry.apply_kit()
	get_tree().paused = false
	get_tree().change_scene_to_file(TrialCatalog.SCENE)


# --- Helpers -----------------------------------------------------------------------------------


func _requested_mode() -> StringName:
	if OS.is_debug_build():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--trial="):
				var requested := StringName(argument.trim_prefix("--trial="))
				if TrialCatalog.is_mode(requested):
					return requested
	return TrialsEntry.mode


func _place_player() -> void:
	player.reset_for_spawn(TrialRoomBuilder.feet(room, TrialCatalog.START_CELL))
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = int(room.global_position.x)
	camera.limit_top = int(room.global_position.y)
	camera.limit_right = int(room.global_position.x + room.size_px().x)
	camera.limit_bottom = int(room.global_position.y + room.size_px().y)
	camera.reset_smoothing()
	camera.force_update_scroll()


func _play_area(area: StringName) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play_area"):
		audio.call("play_area", area)


func _build_overlays() -> void:
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 90
	fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(_fade)
	var results_layer := CanvasLayer.new()
	results_layer.layer = 95
	results_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(results_layer)
	results_panel = RESULTS_SCRIPT.new()
	results_panel.name = "TrialResults"
	results_layer.add_child(results_panel)
	results_panel.connect("retry_pressed", _retry)
	results_panel.connect("title_pressed", TrialsEntry.leave_to_title)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_SECONDS)
	await tween.finished
