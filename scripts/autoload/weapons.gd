extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TideModules = preload("res://scripts/progression/tide_modules.gd")
const BEAM_SHOT_SCENE: PackedScene = preload("res://scenes/combat/beam_shot.tscn")
const CrossbowSnapFx = preload("res://scripts/combat/crossbow_snap_fx.gd")
const HARPOON_SHOT_SCENE: PackedScene = preload("res://scenes/combat/harpoon_shot.tscn")
const BOMB_SCENE: PackedScene = preload("res://scenes/combat/bomb.tscn")
const FLUX_BURST_SCENE: PackedScene = preload("res://scenes/combat/flux_burst_projectile.tscn")

const BEAM_COOLDOWN := 0.12
const MISSILE_COOLDOWN := 0.35
const BOMB_COOLDOWN := 0.18

var _cooldown_remaining := {
	&"beam": 0.0,
	&"missile": 0.0,
	&"bomb": 0.0,
	&"flux_burst": 0.0,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(delta: float) -> void:
	for kind in _cooldown_remaining:
		_cooldown_remaining[kind] = maxf(float(_cooldown_remaining[kind]) - delta, 0.0)


func fire(kind: StringName, origin: Vector2, direction: Vector2) -> void:
	if kind == &"beam":
		_fire_beam(origin, direction)
	elif kind == &"missile":
		_fire_missile(origin, direction)
	elif kind == &"bomb":
		_fire_bomb(origin)


func can_flux_burst_fire(origin: Vector2, direction: Vector2) -> bool:
	return (
		GameState.has_ability(&"burst_beam")
		and GameState.active_flux_module == &"burst_beam"
		and GameState.flux_enabled
		and GameState.flux_current > 0
		and not direction.is_zero_approx()
		and _flux_burst_origin_clear(origin)
	)


func fire_flux_burst(origin: Vector2, direction: Vector2) -> bool:
	if not can_flux_burst_fire(origin, direction) or not _ready_to_fire(&"flux_burst"):
		return false
	var shot := _spawn_projectile(FLUX_BURST_SCENE, origin, direction, &"beam")
	if shot == null:
		return false
	shot.damage_amount = Catalog.BURST_BEAM_DAMAGE
	shot.lifetime = Catalog.BURST_BEAM_RANGE / shot.speed
	_cooldown_remaining[&"flux_burst"] = Catalog.BURST_BEAM_CADENCE
	return true


func reset_runtime() -> void:
	for kind in _cooldown_remaining:
		_cooldown_remaining[kind] = 0.0
	var runtime_nodes := get_tree().get_nodes_in_group(&"transient")
	for effect in get_tree().get_nodes_in_group(&"beam_fx"):
		if not runtime_nodes.has(effect):
			runtime_nodes.append(effect)
	for transient in runtime_nodes:
		if is_instance_valid(transient):
			transient.queue_free()


func _fire_beam(origin: Vector2, direction: Vector2) -> void:
	if not GameState.has_beam or direction.is_zero_approx() or not _ready_to_fire(&"beam"):
		return
	var beam_kind: StringName = GameState.active_beam
	if not Catalog.is_beam(beam_kind):
		beam_kind = &"base"
	var projectile_kind: StringName = beam_kind if beam_kind != &"base" else &"beam"
	var shot := _spawn_projectile(BEAM_SHOT_SCENE, origin, direction, projectile_kind)
	if shot == null:
		return
	# Tide Glyph multipliers (GameState.tide) are all 1.0 while nothing is socketed.
	var tide: TideModules = GameState.tide
	var base_damage := int(Catalog.WEAPON_DATA[beam_kind]["damage"])
	shot.damage_amount = tide.scale_int(&"crossbow_damage", base_damage)
	shot.speed *= tide.multiplier(&"crossbow_speed")
	var has_long_beam := GameState.has_ability(&"long_beam")
	var range_multiplier := Catalog.LONG_RANGE_MULTIPLIER if has_long_beam else 1.0
	range_multiplier *= tide.multiplier(&"crossbow_range")
	shot.lifetime = Catalog.BEAM_RANGE * range_multiplier / shot.speed
	shot.set_long_beam_enabled(has_long_beam)
	_cooldown_remaining[&"beam"] = BEAM_COOLDOWN * tide.multiplier(&"crossbow_reload")
	# Every bolt leaves the Seed Crossbow: string snap, plus leaves for the base seed-bolt.
	_spawn_crossbow_snap(origin, direction, false, beam_kind == &"base")
	match beam_kind:
		&"wave":
			_spawn_ring_muzzle(origin, Color(0.72, 0.62, 1.0, 0.9))
			GameJuice.play_sfx(&"echo_fire", &"wave_fire")
		&"ice":
			_spawn_ring_muzzle(origin, Color(0.72, 0.95, 1.0, 0.8))
			GameJuice.play_sfx(&"bubble_fire", &"beam_fire")
		_:
			_play_known_sfx(&"beam_fire")


func _fire_missile(origin: Vector2, direction: Vector2) -> void:
	if direction.is_zero_approx() or not _ready_to_fire(&"missile"):
		return
	var tide: TideModules = GameState.tide
	var bolts := 1 + tide.add(&"harpoon_bolt_add")
	if not GameState.has_missiles or GameState.missile_count < bolts:
		return
	var shot := _spawn_projectile(HARPOON_SHOT_SCENE, origin, direction)
	if shot == null or not GameState.spend_missile():
		if shot != null:
			shot.queue_free()
		return
	for _extra in bolts - 1:
		GameState.spend_missile()
	shot.damage_amount = tide.scale_int(&"harpoon_damage", shot.damage_amount)
	_cooldown_remaining[&"missile"] = MISSILE_COOLDOWN
	_spawn_crossbow_snap(origin, direction, true, true)
	GameJuice.play_sfx(&"harpoon_fire", &"missile_fire")


func _fire_bomb(origin: Vector2) -> void:
	if not GameState.has_ability(&"bombs") or not _ready_to_fire(&"bomb"):
		return
	if get_tree().get_nodes_in_group(&"bombs").size() >= Catalog.MAX_ACTIVE_BOMBS:
		return
	var bomb := BOMB_SCENE.instantiate() as Bomb
	if bomb == null:
		return
	var tide: TideModules = GameState.tide
	bomb.damage_amount = tide.scale_int(&"pulse_damage", Catalog.BOMB_DAMAGE)
	bomb.fuse_seconds = Catalog.BOMB_FUSE_SECONDS * tide.multiplier(&"pulse_fuse")
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(bomb)
	bomb.global_position = origin
	_cooldown_remaining[&"bomb"] = BOMB_COOLDOWN
	GameJuice.play_sfx(&"pulse_charge", &"bomb_place")


func _spawn_projectile(
	scene: PackedScene,
	origin: Vector2,
	direction: Vector2,
	projectile_kind: StringName = &"",
) -> ProjectileBase:
	var shot := scene.instantiate() as ProjectileBase
	if shot == null:
		return null
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(shot)
	shot.global_position = origin
	if not projectile_kind.is_empty():
		shot.damage_kind = projectile_kind
	shot.launch(direction)
	if not shot.can_spawn_at(origin):
		shot.queue_free()
		return null
	return shot


func _spawn_crossbow_snap(origin: Vector2, direction: Vector2, heavy: bool, leaves: bool) -> void:
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	CrossbowSnapFx.spawn(parent, origin, direction.normalized(), heavy, leaves)


func _spawn_ring_muzzle(origin: Vector2, tint: Color) -> void:
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	ArsenalFx.spawn_rings(parent, origin, 26.0, tint, 0.18, 1)


func _ready_to_fire(kind: StringName) -> bool:
	return float(_cooldown_remaining.get(kind, 0.0)) <= 0.0


func _flux_burst_origin_clear(origin: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = 7.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, origin)
	query.collision_mask = 9
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return false
	for hit in player.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var target := hit.get("collider") as Node
		if (
			target != null
			and (target.has_method(&"take_damage") or target.has_method(&"can_pass_projectile"))
		):
			continue
		return false
	return true


func _play_known_sfx(kind: StringName) -> void:
	if Audio.has_method(&"play_sfx"):
		Audio.play_sfx(kind)
