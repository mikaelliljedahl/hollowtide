class_name AmbushArena
extends Node2D
## Entering the arena seals its openings with slamming slabs and runs one or more waves of
## enemies; the slabs grind open when the last wave is dead, one refill drops, and the room is
## remembered as cleared (world flag), so the ambush never repeats. Every spawn is telegraphed and
## uses an authored point at a safe distance from the player (AmbushRules). Safety: only enemies
## the current kit can beat are spawned and an arena with none never seals; death, leaving the
## arena or a fight in which no enemy is hurt for `stall_seconds` aborts and re-arms it once the
## player has left the trigger; a failsafe clears after `max_seconds`; escaped enemies count as
## beaten. Position is the arena centre; spawn points and rectangles are relative to it.

signal sealed
signal cleared
signal aborted
signal telegraphed(at: Vector2)
signal spawned(enemy: Node2D)

enum State { ARMED, SEALING, FIGHTING, CLEARED, INTERMISSION }

const Assist = preload("res://scripts/progression/assist.gd")

const SPAWN_DELAY := 0.55
const SPAWN_STAGGER := 0.32
const TELEGRAPH_SECONDS := 0.5
const BREATHER_SECONDS := 0.8
const CRAWLER_SPEED := 110.0
const ESCAPE_MARGIN := 192.0
const ESCAPE_SECONDS := 2.0
## Arenas end on the floor line, and Rect2.has_point excludes that edge, so the enemy leash
## reaches a little below it; otherwise a player standing on the floor is outside every leash.
const LEASH_FLOOR_MARGIN := 16.0

@export var arena_size := Vector2(1280, 640)
## First wave.
@export var wave := PackedStringArray(["hopper", "hopper"])
## Later waves in order; each starts after the previous one is beaten and a short breather.
@export var extra_waves: Array[PackedStringArray] = []
## Authored spawn points; spawn i of all waves in order uses point i (wrapping).
@export var spawn_offsets := PackedVector2Array([Vector2(-256, -64), Vector2(256, -64)])
## Openings to seal, as rectangles relative to the arena centre.
@export var door_rects: Array[Rect2] = []
## Commit zone relative to the arena centre; an empty rectangle means the whole arena.
@export var trigger_rect := Rect2()
@export var local_id := "arena"
@export var flag_id := ""
@export var max_seconds := 120.0
## Aborts the fight when no ambush enemy loses health for this long.
@export var stall_seconds := 40.0
@export var area_override: StringName = &""
## False for arenas that are the whole point of the room (the Trials gauntlet): the skip-ambushes
## assist leaves them armed.
@export var assist_skippable := true

var state := State.ARMED
var enemies: Array = []
var slabs: Array[SealSlab] = []
var wave_index := 0
var reward_drops := 0
var _area: StringName = &"fringe"
var _flag := ""
var _timer := 0.0
var _elapsed := 0.0
var _stall := 0.0
var _clock := 0.0
var _plan: Array = []
var _queue: Array = []
var _health: Dictionary = {}
var _escape: Dictionary = {}
var _await_exit := false


## Abilities an enemy needs to be beaten; each inner array is alternatives (any one suffices).
static func requirements(enemy_id: StringName) -> Array:
	return AmbushRules.requirements(enemy_id)


## True when the current kit can beat every enemy of `wave_ids`.
static func can_defeat(wave_ids: PackedStringArray) -> bool:
	for id in wave_ids:
		if not AmbushRules.can_defeat_enemy(StringName(id)):
			return false
	return true


func _ready() -> void:
	add_to_group(&"worldfx_ambush")
	_area = WorldFx.area_for(self, area_override)
	_flag = WorldFx.flag_for(self, "ambush", local_id, flag_id)
	for rect in door_rects:
		var slab := SealSlab.new()
		slab.size = rect.size
		slab.area_id = _area
		slab.position = rect.get_center()
		add_child(slab)
		slabs.append(slab)
	if is_cleared_flag():
		state = State.CLEARED
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)


func _exit_tree() -> void:
	if GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.disconnect(_on_player_died)


func flag() -> String:
	return _flag


func is_cleared_flag() -> bool:
	return not _flag.is_empty() and GameState.has_world_flag(_flag)


func arena_rect_global() -> Rect2:
	return Rect2(global_position - arena_size * 0.5, arena_size)


func all_waves() -> Array[PackedStringArray]:
	var waves: Array[PackedStringArray] = [wave]
	waves.append_array(extra_waves)
	return waves


## The waves the current kit can win, as arrays of [enemy_id, spawn_index]; empty waves dropped.
func plan_waves() -> Array:
	var plan: Array = []
	var first := 0
	for ids in all_waves():
		var kept := AmbushRules.winnable_spawns(ids, first)
		if not kept.is_empty():
			plan.append(kept)
		first += ids.size()
	return plan


func authored_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for offset in spawn_offsets:
		points.append(global_position + offset)
	if points.is_empty():
		points.append(global_position)
	return points


func alive_count() -> int:
	var count := 0
	for enemy in enemies:
		if _is_alive(enemy):
			count += 1
	return count


func _physics_process(delta: float) -> void:
	if state == State.CLEARED:
		return
	var player := WorldFx.player_of(self)
	if state == State.ARMED:
		if player == null or GameState.health <= 0 or _skipped_by_assist():
			return
		if not _player_committed(player):
			_await_exit = false
			return
		if not _await_exit:
			_plan = plan_waves()
			if not _plan.is_empty():
				_seal()
		return
	_elapsed += delta
	if (
		player != null
		and not arena_rect_global().has_point(WorldFx.player_rect(player).get_center())
	):
		_abort()
		return
	match state:
		State.SEALING:
			_check_escapes(delta)
			_tick_spawns(delta)
		State.INTERMISSION:
			_timer -= delta
			if _timer <= 0.0:
				_start_wave(wave_index + 1)
		State.FIGHTING:
			_check_escapes(delta)
			if _stalled(delta):
				_abort()
				return
			if alive_count() == 0:
				if wave_index + 1 < _plan.size():
					state = State.INTERMISSION
					_timer = BREATHER_SECONDS
				else:
					_clear()
					return
	if _elapsed >= max_seconds:
		_clear()


## True when the whole body is inside the trigger (or the arena) and clear of every opening, so a
## slab can never land on the player.
func _player_committed(player: Node2D) -> bool:
	var body := WorldFx.player_rect(player)
	var zone := arena_rect_global().grow_individual(-64.0, 0.0, -64.0, 0.0)
	if trigger_rect.has_area():
		zone = Rect2(global_position + trigger_rect.position, trigger_rect.size)
	if not zone.encloses(body):
		return false
	for rect in door_rects:
		var door := Rect2(global_position + rect.position, rect.size).grow(96.0)
		if door.intersects(body):
			return false
	return true


func _seal() -> void:
	enemies.clear()
	_health.clear()
	_escape.clear()
	_elapsed = 0.0
	for slab in slabs:
		slab.close(true)
	if slabs.is_empty():
		WorldFx.shake(self, 5.0, 0.25)
	WorldFx.play(self, &"world_rumble", global_position, -2.0, 0.85)
	_start_wave(0)
	sealed.emit()


func _start_wave(index: int) -> void:
	wave_index = index
	state = State.SEALING
	_clock = 0.0
	_stall = 0.0
	_queue.clear()
	var due := SPAWN_DELAY if index == 0 else 0.0
	for spawn in _plan[index]:
		_queue.append({"id": spawn[0], "index": spawn[1], "due": due, "shown": false})
		due += SPAWN_STAGGER


## Telegraphs each queued spawn at its resolved point, then spawns it TELEGRAPH_SECONDS later.
func _tick_spawns(delta: float) -> void:
	_clock += delta
	var pending := false
	for item in _queue:
		if item.get("done", false):
			continue
		if not item["shown"]:
			if _clock < float(item["due"]):
				pending = true
				continue
			_telegraph(item)
		if _clock >= float(item["due"]) + TELEGRAPH_SECONDS:
			_spawn(item["id"], item["index"], item["at"])
			item["done"] = true
		else:
			pending = true
	if not pending:
		state = State.FIGHTING


func _telegraph(item: Dictionary) -> void:
	var player := WorldFx.player_of(self)
	var player_at := WorldFx.player_rect(player).get_center() if player != null else Vector2.INF
	var spawn_ids := PackedStringArray()
	for ids in all_waves():
		spawn_ids.append_array(ids)
	var at := AmbushRules.resolve_spawn(authored_points(), int(item["index"]), player_at, spawn_ids)
	item["at"] = at
	item["shown"] = true
	var colors := WorldFx.palette(_area)
	WorldFx.dust(get_parent(), at, Vector2(24, 8), colors["dust"], 10, 90.0)
	_emerge_flash(at, colors["accent"], 8)
	_telegraph_ring(at, colors["accent"])
	telegraphed.emit(at)


## A ground ring that tightens and brightens until the enemy appears, readable against busy cave art.
func _telegraph_ring(at: Vector2, accent: Color) -> void:
	var ring := Node2D.new()
	ring.z_index = 7
	ring.set_meta(&"progress", 0.0)
	ring.draw.connect(
		func() -> void:
			var t: float = ring.get_meta(&"progress")
			var color := Color(accent, 0.45 + 0.5 * t)
			ring.draw_arc(Vector2.ZERO, 64.0 * (1.5 - 0.7 * t), 0.0, TAU, 40, color, 6.0, true)
			ring.draw_circle(Vector2.ZERO, 10.0 + 12.0 * t, color)
	)
	get_parent().add_child(ring)
	ring.global_position = at
	var tween := ring.create_tween()
	tween.tween_method(
		func(t: float) -> void:
			ring.set_meta(&"progress", t)
			ring.queue_redraw(),
		0.0,
		1.0,
		TELEGRAPH_SECONDS
	)
	tween.tween_callback(ring.queue_free)


func _spawn(enemy_id: StringName, index: int, at: Vector2) -> void:
	var enemy := EnemyFactory.create(enemy_id)
	if enemy == null:
		push_warning("Ambush: could not create enemy %s" % enemy_id)
		return
	enemy.position = get_parent().to_local(at) if get_parent() is Node2D else at
	if enemy_id == &"crawler":
		enemy.set("travel_direction", 1 if index % 2 == 0 else -1)
		enemy.set("move_speed", CRAWLER_SPEED)
	get_parent().add_child(enemy)
	if enemy.has_method("configure_arena"):
		enemy.call(
			"configure_arena",
			arena_rect_global().grow_individual(0.0, 0.0, 0.0, LEASH_FLOOR_MARGIN)
		)
	enemy.add_to_group(&"worldfx_ambush_enemy")
	enemies.append(enemy)
	_health[enemy.get_instance_id()] = enemy.get("health")
	_stall = 0.0
	var colors := WorldFx.palette(_area)
	WorldFx.dust(get_parent(), enemy.global_position, Vector2(30, 30), colors["dust"], 24, 200.0)
	_emerge_flash(enemy.global_position, colors["accent"], 18)
	WorldFx.play(self, &"world_emerge", enemy.global_position, -3.0, randf_range(0.9, 1.1))
	spawned.emit(enemy)


func _skipped_by_assist() -> bool:
	return assist_skippable and Assist.skip_ambushes()


func _emerge_flash(at: Vector2, accent: Color, amount: int) -> void:
	var ring := CPUParticles2D.new()
	ring.one_shot = true
	ring.explosiveness = 1.0
	ring.amount = amount
	ring.lifetime = 0.5
	ring.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	ring.emission_sphere_radius = 8.0
	ring.direction = Vector2.UP
	ring.spread = 180.0
	ring.gravity = Vector2.ZERO
	ring.initial_velocity_min = 220.0
	ring.initial_velocity_max = 320.0
	ring.damping_min = 300.0
	ring.damping_max = 400.0
	ring.scale_amount_min = 3.0
	ring.scale_amount_max = 6.0
	var fade := Gradient.new()
	fade.set_color(0, Color(accent, 0.9))
	fade.set_color(1, Color(accent, 0.0))
	ring.color_ramp = fade
	ring.z_index = 7
	get_parent().add_child(ring)
	ring.global_position = at
	ring.emitting = true
	ring.finished.connect(ring.queue_free)


func _is_alive(enemy) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree() or enemy.is_queued_for_deletion():
		return false
	var health: Variant = enemy.get("health")
	if health is int and int(health) <= 0:
		return false
	var dying: Variant = enemy.get("_dying")
	return not (dying is bool and dying)


## Stall backstop: true once no ambush enemy has lost health (or died) for `stall_seconds`.
func _stalled(delta: float) -> bool:
	_stall += delta
	for key in _health.keys():
		var enemy := instance_from_id(key)
		if enemy == null or not _is_alive(enemy):
			_health.erase(key)
			_stall = 0.0
			continue
		var health: Variant = enemy.get("health")
		var last: Variant = _health[key]
		if health is int and last is int and int(health) < int(last):
			_stall = 0.0
		_health[key] = health
	return _stall >= stall_seconds


func _check_escapes(delta: float) -> void:
	var bounds := arena_rect_global().grow(ESCAPE_MARGIN)
	for enemy in enemies:
		if not _is_alive(enemy):
			continue
		if bounds.has_point(enemy.global_position):
			_escape.erase(enemy.get_instance_id())
			continue
		var outside: float = float(_escape.get(enemy.get_instance_id(), 0.0)) + delta
		_escape[enemy.get_instance_id()] = outside
		if outside >= ESCAPE_SECONDS:
			enemy.queue_free()


func _clear() -> void:
	state = State.CLEARED
	_queue.clear()
	if not _flag.is_empty():
		GameState.set_world_flag(_flag)
	for slab in slabs:
		slab.open(true)
	_drop_reward()
	WorldFx.play(self, &"world_unlock", global_position, -3.0)
	WorldFx.play(self, &"world_rumble", global_position, -8.0, 1.2)
	cleared.emit()


## One guaranteed refill at the authored spawn point nearest the player.
func _drop_reward() -> void:
	var player := WorldFx.player_of(self)
	var points := authored_points()
	var at := points[0]
	if player != null:
		var center := WorldFx.player_rect(player).get_center()
		for point in points:
			if point.distance_to(center) < at.distance_to(center):
				at = point
	var loot := CombatLoot.new()
	loot.configure(AmbushRules.reward_kind(), at)
	loot.position = get_parent().to_local(at) if get_parent() is Node2D else at
	get_parent().add_child(loot)
	reward_drops += 1


## Removes the ambush enemies, opens the seals and re-arms once the player has left the trigger.
func _abort(animate := true) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	_health.clear()
	_queue.clear()
	_escape.clear()
	for slab in slabs:
		slab.open(animate)
	state = State.ARMED
	_await_exit = true
	aborted.emit()


func _on_player_died() -> void:
	if state not in [State.ARMED, State.CLEARED]:
		_abort(false)


## Test hook: resets a cleared or running arena back to armed (does not clear the world flag).
func rearm() -> void:
	_on_player_died()
	for slab in slabs:
		slab.open(false)
	state = State.ARMED
	_await_exit = false
