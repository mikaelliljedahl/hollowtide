class_name CombatEnemy extends CharacterBody2D

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")
const DefeatRewardsScript = preload("res://scripts/enemies/defeat_rewards.gd")
const VisualProfiles = preload("res://scripts/enemies/effects/runtime_visual_profiles.gd")
const ProjectileHurtboxScript = preload("res://scripts/enemies/projectile_hurtbox.gd")
const Placement = preload("res://scripts/enemies/effects/enemy_placement.gd")
const HitResult = preload("res://scripts/combat/hit_result.gd")
const SPRITE_FX_SHADER = preload("res://resources/combat/sprite_fx.gdshader")
const ART_OVERRIDE_DIR := "res://assets/sprites/combat/"
const THAW_WARNING_SECONDS := 0.8
const BUBBLE_ANCHORED_IDS: Array[StringName] = [&"frost_floater"]
const BLOCK_FLASH_SECONDS := 0.09
## Art faces right; these ids turn toward their movement, those in FACE_PLAYER_IDS toward the player.
const FACE_MOTION_IDS := [
	&"hopper", &"armored_guard", &"grasshopper", &"lava_monster", &"vent_flyer"
]
const FACE_PLAYER_IDS := [&"spitter", &"shard_turret", &"shooting_gargoyle", &"burrower"]
## Walkers keep gravity even while idle and are only clamped horizontally, so they settle
## on the real floor instead of hovering at a spawn point or arena edge.
const GROUND_WALKERS := [&"hopper", &"grasshopper", &"armored_guard"]
const GROUND_GRAVITY := 1800.0
const PROJECTILE_STYLES := {
	&"spitter": &"acid",
	&"shard_turret": &"shard",
	&"shooting_gargoyle": &"bolt",
}
const MAX_TELEGRAPH_SECONDS := 0.7
const HIT_FLASH_SECONDS := 0.12
## D20 aggression pass: faster movers, short telegraphed charges/lunges and pursuit when the
## player is near. Damage numbers are unchanged; every attack keeps a wind-up glow first.
const HOPPER_TRACK_SPEED := 320.0
const HOPPER_TRACK_ACCEL := 1100.0
const HOPPER_JUMP_INTERVAL := 0.72
const HOPPER_JUMP_SPEED := -620.0
const DIVER_DIVE := Vector2(420.0, 760.0)
const DIVER_RETURN_SPEED := 520.0
const DIVER_COOLDOWN := 1.6
const SPITTER_COOLDOWN := 1.0
const SHARD_TURRET_COOLDOWN := 1.3
const BURROWER_TRACK_SPEED := 170.0
const GRASSHOPPER_SKITTER_SPEED := 400.0
const GRASSHOPPER_LEAP := Vector2(620.0, -720.0)
const GRASSHOPPER_GRAVITY := 2200.0
const GRASSHOPPER_LEAP_INTERVAL := 0.85
const GARGOYLE_SHOT_COOLDOWN := 1.2
const LAVA_ACTIVE_SECONDS := 1.2
const LAVA_STALK_SPEED := 200.0

@export var runtime_id: StringName = &"hopper"

var enemy_id: StringName = &""
var health := 1
var max_health := 1
var is_frozen := false
var freeze_capable := false
var contact_damage := 1
var _freeze_remaining := 0.0
var _age := 0.0
var _attack_timer := 0.0
var _telegraph_remaining := 0.0
var _telegraph_action: StringName = &""
var _pending_attack_direction := Vector2.RIGHT
var _skip_ai_once := false
var _jump_timer := 0.0
var _dying := false
var _patrol_sign := -1.0
var _home_position := Vector2.ZERO
var _burrow_phase: StringName = &"mound"
var _burrow_timer := 0.8
var _special_state: StringName = &""
var _special_timer := 0.0
var _dive_target_y := 0.0
var _player_detector: Area2D
var _sprite: Sprite2D
var _projectile_hurtbox: EnemyProjectileHurtbox
var _has_art := false
var _visual_base_position := Vector2.ZERO
var _visual_base_scale := Vector2.ONE
var _hit_flash_remaining := 0.0
var _block_flash_remaining := 0.0
var _recoil := Vector2.ZERO
var _squash := 0.0
var _facing := 1.0
var _fx: ShaderMaterial
var _open_texture: Texture2D
var _closed_texture: Texture2D
var _ice_shape := PackedVector2Array()
## Bubble Snare state (D19): the "frozen" status is an air bubble that drifts slowly upward.
var _bubble_rect := Rect2()
var _bubble_rise := 0.0
var _bubble_visual: BubbleVisual
var _placement_frames := 3
var arena_bounds := Rect2()


func _ready() -> void:
	enemy_id = runtime_id
	var data: Dictionary = Catalog.ENEMY_DATA.get(enemy_id, Catalog.ENEMY_DATA[&"hopper"])
	max_health = int(data["max_health"])
	health = max_health
	contact_damage = int(data["contact_damage"])
	freeze_capable = bool(data["freeze_capable"])
	add_to_group(&"enemies")
	add_to_group(&"damageable")
	_home_position = global_position
	collision_layer = 8
	collision_mask = 3
	_player_detector = get_node_or_null("PlayerDetector") as Area2D
	_configure_collision_profile()
	_initialize_special_state()
	if _player_detector != null:
		_player_detector.body_entered.connect(_on_player_detector_body_entered)
	_load_optional_sprite()
	_configure_projectile_hurtbox()
	if enemy_id == &"lava_monster":
		_set_lava_surface_active(false)
	queue_redraw()


func configure_arena(bounds: Rect2) -> void:
	arena_bounds = bounds
	_home_position = _clamp_to_arena(global_position)
	global_position = _home_position


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_age += delta
	if _placement_frames > 0:
		_placement_frames -= 1
		if _placement_frames == 0:
			if enemy_id == &"ceiling_diver":
				Placement.snap_to_ceiling(self)
			elif enemy_id == &"shooting_gargoyle":
				Placement.snap_to_perch(self)
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	_block_flash_remaining = maxf(_block_flash_remaining - delta, 0.0)
	_recoil *= exp(-16.0 * delta)
	_squash = maxf(_squash - delta * 7.0, 0.0)
	if is_frozen:
		_freeze_remaining -= delta
		_drift_bubble(delta)
		if is_instance_valid(_bubble_visual):
			_bubble_visual.warning = clampf(
				1.0 - _freeze_remaining / THAW_WARNING_SECONDS, 0.0, 1.0
			)
		if _freeze_remaining <= 0.0:
			if _player_overlaps_body():
				_freeze_remaining = 0.1
			else:
				_thaw()
		_update_visual_presentation()
		queue_redraw()
		return
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	var was_telegraphing := _telegraph_remaining > 0.0
	_telegraph_remaining = maxf(_telegraph_remaining - delta, 0.0)
	_jump_timer = maxf(_jump_timer - delta, 0.0)
	if was_telegraphing and _telegraph_remaining == 0.0:
		_perform_telegraph_action()
	if _skip_ai_once:
		_skip_ai_once = false
	else:
		_run_ai(delta)
	move_and_slide()
	_constrain_to_arena()
	_update_visual_presentation()
	queue_redraw()


func receive_hit(amount: int, kind: StringName, hit_context := {}) -> HitResult.Reaction:
	if _dying or amount < 0:
		return HitResult.Reaction.PASS
	var impact := _impact_position(hit_context)
	var direction := _hit_direction(hit_context, impact)
	if enemy_id == &"shooting_gargoyle" and _special_state in [&"folded", &"waking"]:
		_spawn_blocked_hit(impact, direction)
		return HitResult.Reaction.BLOCKED
	if enemy_id == &"lava_monster" and _special_state in [&"submerged", &"bubbling"]:
		return HitResult.Reaction.PASS
	if kind == &"ice":
		if freeze_capable:
			_freeze()
			return HitResult.Reaction.FREEZE
		_spawn_blocked_hit(impact, direction)
		return HitResult.Reaction.BLOCKED
	if amount <= 0:
		return HitResult.Reaction.PASS
	if enemy_id == &"lava_monster" and kind == &"undertow" and not is_frozen:
		_spawn_blocked_hit(impact, direction)
		return HitResult.Reaction.BLOCKED
	if not is_vulnerable_to(kind):
		_spawn_blocked_hit(impact, direction)
		return HitResult.Reaction.BLOCKED
	health = maxi(health - amount, 0)
	_telegraph_remaining = 0.0
	_telegraph_action = &""
	var heavy := kind in [&"missile", &"bomb"]
	if health == 0:
		CombatFeedback.spawn_hit(_effect_parent(), impact, is_frozen, direction, true)
		GameJuice.hit_stop(self, 0.04)
		GameJuice.shake(self, 6.0 if heavy else 3.5, 0.2)
		_die()
	else:
		_hit_flash_remaining = HIT_FLASH_SECONDS
		_recoil = direction * (16.0 if heavy else 8.0)
		_squash = 1.0
		CombatFeedback.spawn_hit(_effect_parent(), impact, is_frozen, direction, heavy)
		if heavy:
			GameJuice.shake(self, 3.0, 0.14)
		GameJuice.play_sfx(&"enemy_hit", &"missile_hit" if heavy else &"")
	return HitResult.Reaction.DAMAGE


func take_damage(amount: int, kind: StringName) -> void:
	receive_hit(amount, kind)


func is_vulnerable_to(kind: StringName) -> bool:
	if enemy_id == &"shooting_gargoyle" and _special_state in [&"folded", &"waking"]:
		return false
	if enemy_id == &"lava_monster":
		if _special_state in [&"submerged", &"bubbling"]:
			return false
		if kind == &"undertow" and not is_frozen:
			return false
	if (
		enemy_id == &"burrower"
		and arena_bounds.size != Vector2.ZERO
		and _burrow_phase != &"exposed"
	):
		return false
	if kind == &"ice":
		return freeze_capable
	if enemy_id == &"armored_guard" and kind in [&"beam", &"wave", &"undertow"]:
		return false
	if enemy_id == &"energy_parasite" and kind == &"undertow":
		return false
	return kind in [&"beam", &"wave", &"missile", &"bomb", &"undertow"]


func allows_projectile(_kind: StringName) -> bool:
	return false


func reset_runtime() -> void:
	_dying = false
	health = max_health
	velocity = Vector2.ZERO
	_thaw()
	_attack_timer = 0.0
	_telegraph_remaining = 0.0
	_telegraph_action = &""
	_skip_ai_once = false
	_burrow_phase = &"mound"
	_burrow_timer = 0.8
	_hit_flash_remaining = 0.0
	global_position = _home_position
	_initialize_special_state()
	if enemy_id == &"lava_monster":
		_set_lava_surface_active(false)
	else:
		collision_layer = 8
		if _projectile_hurtbox != null:
			_projectile_hurtbox.set_enabled(true)
		if _player_detector != null:
			_player_detector.monitoring = true
	_update_visual_presentation()


func _run_ai(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	var has_target := player != null and _in_arena(player.global_position)
	var target := player.global_position if has_target else global_position
	match enemy_id:
		&"ceiling_diver":
			if has_target:
				_run_ceiling_diver(target)
			else:
				_suspend_ai()
		&"vent_flyer":
			_run_vent_flyer(delta)
		&"hopper":
			if has_target:
				_run_hopper(target, delta)
			else:
				_suspend_ai()
		&"spitter":
			if has_target:
				_run_spitter(target)
			else:
				_suspend_ai()
		&"armored_guard":
			_run_armored_guard()
		&"frost_floater":
			_run_frost_floater(delta)
		&"energy_parasite":
			_run_energy_parasite(target)
		&"shard_turret":
			_run_shard_turret(target, has_target)
		&"burrower":
			_run_burrower(delta)
		&"grasshopper":
			_run_grasshopper(target, has_target, delta)
		&"shooting_gargoyle":
			_run_shooting_gargoyle(target, has_target, delta)
		&"lava_monster":
			_run_lava_monster(target, has_target, delta)
		_:
			velocity = Vector2.ZERO


func _suspend_ai() -> void:
	var fall := velocity.y if enemy_id in GROUND_WALKERS and not is_on_floor() else 0.0
	velocity = Vector2.ZERO
	if enemy_id in GROUND_WALKERS:
		velocity.y = fall + GROUND_GRAVITY * get_physics_process_delta_time()
	_telegraph_remaining = 0.0
	_telegraph_action = &""


func _run_ceiling_diver(target: Vector2) -> void:
	EnemyAi.ceiling_diver(self, target)


func _run_vent_flyer(delta: float) -> void:
	EnemyAi.vent_flyer(self, delta)


func _run_hopper(target: Vector2, delta: float) -> void:
	if is_on_floor() and _jump_timer <= 0.0 and _telegraph_action.is_empty():
		_telegraph_remaining = minf(0.22, MAX_TELEGRAPH_SECONDS)
		_pending_attack_direction = Vector2(
			clampf(target.x - global_position.x, -HOPPER_TRACK_SPEED, HOPPER_TRACK_SPEED),
			HOPPER_JUMP_SPEED
		)
		_telegraph_action = &"hopper_jump"
		velocity = Vector2.ZERO
		_jump_timer = HOPPER_JUMP_INTERVAL
	else:
		velocity.y += 1200.0 * delta
		velocity.x = move_toward(
			velocity.x,
			signf(target.x - global_position.x) * HOPPER_TRACK_SPEED,
			HOPPER_TRACK_ACCEL * delta
		)


func _run_spitter(target: Vector2) -> void:
	velocity = Vector2.ZERO
	if _attack_timer > 0.0 or not _telegraph_action.is_empty():
		return
	_telegraph_remaining = minf(0.45, MAX_TELEGRAPH_SECONDS)
	_pending_attack_direction = (target - global_position).normalized()
	_telegraph_action = &"spitter_fire"
	_attack_timer = SPITTER_COOLDOWN


func _run_armored_guard() -> void:
	EnemyAi.armored_guard(self)


func _run_frost_floater(delta: float) -> void:
	velocity = Vector2.ZERO
	global_position = _home_position + Vector2(sin(_age * 1.7) * 70.0, sin(_age * 2.2) * 28.0)
	_age += delta * 0.0


func _run_energy_parasite(target: Vector2) -> void:
	EnemyAi.energy_parasite(self, target)


func _run_shard_turret(target: Vector2, has_target: bool) -> void:
	velocity = Vector2.ZERO
	if not has_target or _attack_timer > 0.0 or not _telegraph_action.is_empty():
		return
	_telegraph_remaining = minf(0.65, MAX_TELEGRAPH_SECONDS)
	_pending_attack_direction = (target - global_position).normalized()
	_telegraph_action = &"shard_burst"
	_attack_timer = SHARD_TURRET_COOLDOWN


func _run_burrower(delta: float) -> void:
	EnemyAi.burrower(self, delta)


func _run_grasshopper(target: Vector2, has_target: bool, delta: float) -> void:
	EnemyAi.grasshopper(self, target, has_target, delta)


func _run_shooting_gargoyle(target: Vector2, has_target: bool, delta: float) -> void:
	velocity = Vector2.ZERO
	_special_timer = maxf(_special_timer - delta, 0.0)
	if not has_target:
		return
	match _special_state:
		&"folded":
			if _special_timer <= 0.0 and _telegraph_action.is_empty():
				_special_state = &"waking"
				_telegraph_remaining = 0.5
				_telegraph_action = &"gargoyle_wake"
		&"open":
			if _special_timer <= 0.0 and _telegraph_action.is_empty():
				_special_state = &"charging"
				_pending_attack_direction = (target - global_position).normalized()
				_telegraph_remaining = 0.65
				_telegraph_action = &"gargoyle_fire"
		&"waking":
			if _telegraph_action.is_empty():
				_special_state = &"folded"
		&"charging":
			if _telegraph_action.is_empty():
				_special_state = &"open"
				_special_timer = 0.3
		&"recovering":
			if _special_timer <= 0.0:
				_special_state = &"folded"
				_special_timer = GARGOYLE_SHOT_COOLDOWN


func _run_lava_monster(target: Vector2, has_target: bool, delta: float) -> void:
	EnemyAi.lava_monster(self, target, has_target, delta)


func _fire_projectile(direction: Vector2) -> void:
	var projectile := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	if projectile == null:
		return
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(projectile)
	projectile.global_position = global_position + _muzzle_offset()
	projectile.style = PROJECTILE_STYLES.get(enemy_id, &"orb")
	projectile.launch(direction, contact_damage)
	if projectile.has_method("configure_arena"):
		projectile.call("configure_arena", arena_bounds)


func _perform_telegraph_action() -> void:
	var action := _telegraph_action
	_telegraph_action = &""
	_skip_ai_once = true
	match action:
		&"ceiling_dive":
			velocity = _pending_attack_direction
		&"hopper_jump":
			velocity = _pending_attack_direction
		&"spitter_fire":
			_fire_projectile(_pending_attack_direction)
		&"shard_burst":
			for offset in [-0.14, 0.0, 0.14]:
				_fire_projectile(_pending_attack_direction.rotated(offset))
		&"burrow_emerge":
			_burrow_phase = &"exposed"
			_burrow_timer = 1.15
			global_position = _home_position + Vector2.UP * 46.0
		&"grasshopper_leap":
			_special_state = &"airborne"
			velocity = _pending_attack_direction
		&"gargoyle_wake":
			_special_state = &"open"
			_special_timer = 0.2
		&"gargoyle_fire":
			_fire_projectile(_pending_attack_direction)
			_special_state = &"recovering"
			_special_timer = 0.35


func _freeze() -> void:
	if is_frozen:
		_freeze_remaining = Catalog.FREEZE_SECONDS
		return
	is_frozen = true
	_freeze_remaining = Catalog.FREEZE_SECONDS
	GameJuice.play_sfx(&"bubble_trap", &"freeze")
	velocity = Vector2.ZERO
	_bubble_rise = 0.0
	collision_layer = 40
	if _player_detector != null:
		_player_detector.set_deferred("monitoring", false)
	_hit_flash_remaining = HIT_FLASH_SECONDS
	_spawn_compact_hit(true)
	_ice_shape = Placement.ice_shape(self)
	_bubble_rect = Placement.bubble_rect(self)
	if not is_instance_valid(_bubble_visual):
		_bubble_visual = BubbleVisual.attach(self, _bubble_rect)
	_update_visual_presentation()
	queue_redraw()


## Bubble drift: rise slowly (capped so authored platform heights stay valid), never into a
## ceiling, and keep headroom for a player riding on top. Bubble floaters are the campaign's
## authored stepping stones (layout legend `floater`), so their bubble holds its altitude.
func _drift_bubble(delta: float) -> void:
	velocity = Vector2.ZERO
	if enemy_id in BUBBLE_ANCHORED_IDS:
		return
	var step := minf(Catalog.BUBBLE_RISE_SPEED * delta, Catalog.BUBBLE_MAX_RISE - _bubble_rise)
	if step <= 0.0:
		return
	var saved_mask := collision_mask
	collision_mask = 1
	var clearance := 8.0
	if _player_riding():
		clearance = 184.0
	var blocked := test_move(global_transform, Vector2(0.0, -(step + clearance)))
	collision_mask = saved_mask
	if blocked:
		return
	global_position.y -= step
	_bubble_rise += step


func _player_riding() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return false
	var offset := player.global_position - global_position
	return absf(offset.x) < 90.0 and offset.y < 0.0 and offset.y > -120.0


func _player_overlaps_body() -> bool:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = global_transform
	query.collision_mask = 2
	query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var body := hit.get("collider") as Node
		if body != null and body.is_in_group(&"player"):
			return true
	return false


func _thaw() -> void:
	if is_frozen and not _dying and is_inside_tree():
		var center := global_position + _bubble_rect.get_center()
		ArsenalFx.spawn_bubble_pop(_effect_parent(), center, maxf(_bubble_rect.size.x * 0.5, 30.0))
		GameJuice.play_sfx(&"bubble_pop", &"ice_shatter")
	is_frozen = false
	_freeze_remaining = 0.0
	if is_instance_valid(_bubble_visual):
		_bubble_visual.queue_free()
	_bubble_visual = null
	collision_layer = 8
	if _player_detector != null:
		_player_detector.set_deferred("monitoring", true)
	_update_visual_presentation()
	queue_redraw()


func _on_player_detector_body_entered(body: Node2D) -> void:
	if (
		is_frozen
		or _dying
		or (enemy_id == &"burrower" and _burrow_phase != &"exposed")
		or not body.has_method(&"take_damage")
		or not _in_arena(body.global_position)
	):
		return
	body.call(&"take_damage", contact_damage, global_position)


func _die() -> void:
	_dying = true
	health = 0
	collision_layer = 0
	collision_mask = 0
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(false)
	if _player_detector != null:
		_player_detector.set_deferred("monitoring", false)
	DefeatRewardsScript.spawn_for_defeat(self, false, is_frozen)
	if Audio.has_method(&"play_sfx"):
		Audio.play_sfx(&"enemy_death")
	hide()
	get_tree().create_timer(2.0).timeout.connect(queue_free, CONNECT_ONE_SHOT)


func _in_arena(point: Vector2) -> bool:
	return arena_bounds.size == Vector2.ZERO or arena_bounds.has_point(point)


func _clamp_to_arena(point: Vector2) -> Vector2:
	if arena_bounds.size == Vector2.ZERO:
		return point
	return Vector2(
		clampf(point.x, arena_bounds.position.x, arena_bounds.end.x),
		clampf(point.y, arena_bounds.position.y, arena_bounds.end.y)
	)


func _constrain_to_arena() -> void:
	if arena_bounds.size == Vector2.ZERO:
		return
	if enemy_id in GROUND_WALKERS or enemy_id == &"shooting_gargoyle":
		global_position.x = clampf(global_position.x, arena_bounds.position.x, arena_bounds.end.x)
		global_position.y = maxf(global_position.y, arena_bounds.position.y)
		return
	global_position = _clamp_to_arena(global_position)


func _configure_collision_profile() -> void:
	var sizes: Dictionary = {
		&"grasshopper": [Vector2(72.0, 44.0), Vector2(88.0, 60.0)],
		&"shooting_gargoyle": [Vector2(72.0, 80.0), Vector2(88.0, 96.0)],
		&"lava_monster": [Vector2(88.0, 72.0), Vector2(104.0, 88.0)],
	}
	if not sizes.has(enemy_id):
		return
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var detector_shape := get_node_or_null("PlayerDetector/CollisionShape2D") as CollisionShape2D
	var profile: Array = sizes[enemy_id]
	if body != null:
		var body_shape := RectangleShape2D.new()
		body_shape.size = profile[0]
		body.shape = body_shape
	if detector_shape != null:
		var contact_shape := RectangleShape2D.new()
		contact_shape.size = profile[1]
		detector_shape.shape = contact_shape


func _initialize_special_state() -> void:
	match enemy_id:
		&"grasshopper":
			_special_state = &"skitter"
		&"shooting_gargoyle":
			_special_state = &"folded"
			_special_timer = 0.8
		&"lava_monster":
			_special_state = &"submerged"
			_special_timer = 0.9
		&"armored_guard", &"energy_parasite", &"ceiling_diver":
			_special_state = &""
			_special_timer = 0.0


func _set_lava_surface_active(active: bool) -> void:
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null:
		body.set_deferred("disabled", not active)
	collision_layer = 8 if active else 0
	if _player_detector != null:
		_player_detector.set_deferred("monitoring", active)
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(active)


func _load_optional_sprite() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		return
	# Optional restyled art (combat lane) overrides the original dev-mode sprite.
	var path := "res://assets/sprites/devmode/%s.png" % String(enemy_id)
	var override_path := VisualProfiles.override_texture_path(enemy_id)
	if not override_path.is_empty():
		path = override_path
	if enemy_id == &"shooting_gargoyle":
		_closed_texture = _optional_texture(ART_OVERRIDE_DIR + "shooting_gargoyle_folded.png")
		_open_texture = _optional_texture(ART_OVERRIDE_DIR + "shooting_gargoyle_open.png")
	if not ResourceLoader.exists(path):
		return
	_sprite.texture = load(path) as Texture2D
	_has_art = _sprite.texture != null
	_sprite.visible = _has_art
	_fx = ShaderMaterial.new()
	_fx.shader = SPRITE_FX_SHADER
	_sprite.material = _fx
	_visual_base_position = VisualProfiles.visual_offset(enemy_id)
	var texture_scale := VisualProfiles.visual_scale(enemy_id)
	_visual_base_scale = Vector2.ONE * texture_scale
	_update_visual_presentation()


func _optional_texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _configure_projectile_hurtbox() -> void:
	# Projectiles must agree with the authored silhouette, including flying and
	# hanging enemies whose art extends far beyond the compact movement body.
	if _sprite == null or _sprite.texture == null:
		return
	var image := _sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	var images: Array[Image] = [image]
	if _open_texture != null and _open_texture.get_image() != null:
		images.append(_open_texture.get_image())
	_projectile_hurtbox = ProjectileHurtboxScript.new() as EnemyProjectileHurtbox
	_projectile_hurtbox.name = "ProjectileHurtbox"
	_sprite.add_child(_projectile_hurtbox)
	_projectile_hurtbox.configure(enemy_id, images)


func presentation_state() -> StringName:
	if _dying:
		return &"dying"
	if is_frozen:
		return &"frozen"
	if enemy_id == &"burrower":
		return _burrow_phase
	if enemy_id in [&"grasshopper", &"shooting_gargoyle", &"lava_monster"]:
		return _special_state
	if _telegraph_remaining > 0.0:
		return &"attack_telegraph"
	if _hit_flash_remaining > 0.0:
		return &"hit"
	if not velocity.is_zero_approx():
		return &"locomotion"
	return &"idle"


func _update_visual_presentation() -> void:
	if not _has_art or _sprite == null:
		return
	_sprite.position = _visual_base_position
	_sprite.scale = _visual_base_scale
	_sprite.rotation = 0.0
	_sprite.modulate = Color.WHITE
	var flash := 0.0
	var flash_color := Color.WHITE
	var glow := 0.0
	var glow_color := Color(1.0, 0.62, 0.22, 1.0)
	var frost := 0.0
	var darken := 0.0
	_update_facing()
	var flying := (
		enemy_id in [&"ceiling_diver", &"vent_flyer", &"frost_floater", &"energy_parasite"]
	)
	if flying and not is_frozen:
		_sprite.position.y += sin(_age * 4.1 + float(String(enemy_id).hash() % 7)) * 5.0
		_sprite.rotation = clampf(velocity.x / 1800.0, -0.09, 0.09)
	elif absf(velocity.x) > 1.0 and enemy_id not in [&"shard_turret", &"burrower"]:
		# Walk bob: lift off the ground only (never sink below the support line).
		_sprite.position.y -= absf(sin(_age * 11.0)) * 3.0
		_sprite.rotation = clampf(velocity.x / 4200.0, -0.055, 0.055)
	if enemy_id == &"hopper" and not is_on_floor():
		_sprite.rotation = clampf(velocity.x / 2600.0, -0.1, 0.1)
	if enemy_id == &"grasshopper":
		if _special_state == &"compress":
			_sprite.position.y += 22.0
			_sprite.scale *= Vector2(1.12, 0.68)
		elif _special_state == &"airborne":
			_sprite.rotation = clampf(velocity.x / 1800.0, -0.34, 0.34)
		elif _special_state == &"landing":
			_sprite.scale *= Vector2(1.08, 0.84)
	elif enemy_id == &"shooting_gargoyle":
		var open := _special_state not in [&"folded", &"waking"]
		if _open_texture != null and _closed_texture != null:
			_sprite.texture = _open_texture if open else _closed_texture
			if not open:
				darken = 0.25
		elif not open:
			_sprite.scale *= Vector2(0.72, 1.0)
			darken = 0.55
		if _special_state == &"waking":
			glow = 0.25 + 0.25 * sin(_age * 30.0)
			glow_color = Color(0.3, 0.9, 1.0, 1.0)
		elif _special_state == &"charging":
			glow = 0.5 + 0.3 * sin(_age * 34.0)
			glow_color = Color(0.3, 0.9, 1.0, 1.0)
			_sprite.scale *= 1.04
	elif enemy_id == &"lava_monster":
		if _special_state == &"submerged":
			_sprite.position.y += 70.0
			_sprite.scale *= Vector2(1.0, 0.16)
			_sprite.modulate.a = 0.52
		elif _special_state == &"bubbling":
			_sprite.position.y += 58.0
			_sprite.scale *= Vector2(1.0 + sin(_age * 18.0) * 0.06, 0.26)
			glow = 0.6
		elif not is_frozen:
			glow = 0.25 + 0.15 * sin(_age * 6.0)
	if enemy_id == &"burrower":
		if _burrow_phase == &"mound":
			_sprite.position.y += 54.0
			_sprite.scale = _visual_base_scale * Vector2(1.0, 0.36)
			_sprite.modulate = Color(0.52, 0.42, 0.34, 0.82)
		elif _burrow_phase == &"retreat":
			var retreat_ratio := clampf(_burrow_timer / 0.28, 0.0, 1.0)
			_sprite.scale = _visual_base_scale * Vector2(1.0, lerpf(0.4, 1.0, retreat_ratio))
	if _telegraph_remaining > 0.0:
		var pulse := 0.5 + 0.5 * sin(_age * 24.0)
		_sprite.scale *= 1.035 + pulse * 0.045
		glow = maxf(glow, 0.35 + pulse * 0.45)
		if enemy_id != &"shooting_gargoyle":
			glow_color = Color(1.0, 0.7, 0.28, 1.0)
	if is_frozen:
		# Trapped in a bubble: slight pale tint and a slow helpless rotation.
		frost = 0.28
		glow = 0.0
		_sprite.rotation = sin(_age * 1.6) * 0.08
		if _freeze_remaining < THAW_WARNING_SECONDS:
			# Pop notice: the enemy struggles inside the bubble before it bursts.
			var shiver := 1.0 - _freeze_remaining / THAW_WARNING_SECONDS
			_sprite.position.x += sin(_age * 70.0) * 2.5 * shiver
	if _squash > 0.0:
		_sprite.scale *= Vector2(1.0 + 0.1 * _squash, 1.0 - 0.08 * _squash)
	_sprite.position += _recoil
	var strength := GameJuice.flash_strength()
	if _hit_flash_remaining > 0.0:
		flash = clampf(_hit_flash_remaining / HIT_FLASH_SECONDS, 0.0, 1.0) * 0.9 * strength
		flash_color = Color(0.8, 0.95, 1.0) if is_frozen else Color(1.0, 0.97, 0.9)
	elif _block_flash_remaining > 0.0:
		flash = 0.5 * strength
		flash_color = Color(0.62, 0.68, 0.78)
		_sprite.position.x += sin(_age * 90.0) * 2.0
	if _fx != null:
		_fx.set_shader_parameter(&"flash_amount", flash)
		_fx.set_shader_parameter(&"flash_color", flash_color)
		_fx.set_shader_parameter(&"glow_amount", glow)
		_fx.set_shader_parameter(&"glow_color", glow_color)
		_fx.set_shader_parameter(&"frost_amount", frost)
		_fx.set_shader_parameter(&"darken_amount", darken)
	elif flash > 0.0:
		_sprite.modulate = Color(1.0, 0.94, 0.72, 1.0)


func _update_facing() -> void:
	if is_frozen or _dying:
		pass
	elif enemy_id in FACE_MOTION_IDS:
		if absf(velocity.x) > 8.0:
			_facing = signf(velocity.x)
	elif enemy_id in FACE_PLAYER_IDS:
		var player := get_tree().get_first_node_in_group(&"player") as Node2D
		if player != null and _in_arena(player.global_position):
			var dx := player.global_position.x - global_position.x
			if absf(dx) > 12.0:
				_facing = signf(dx)
	_sprite.flip_h = _facing < 0.0
	if _projectile_hurtbox != null:
		_projectile_hurtbox.scale = Vector2(-1.0 if _facing < 0.0 else 1.0, 1.0)


func _effect_parent() -> Node:
	var parent := get_parent()
	if parent == null and is_inside_tree():
		parent = get_tree().current_scene
	return parent


func _visual_center() -> Vector2:
	return global_position + _visual_base_position * 0.6


func _impact_position(hit_context: Dictionary) -> Vector2:
	var requested = hit_context.get("position")
	if requested is Vector2 and requested.is_finite():
		# Keep sparks on the silhouette even for area hits (bombs) centred elsewhere.
		var center := _visual_center()
		var offset: Vector2 = requested - center
		return center + offset.limit_length(70.0)
	return _visual_center()


func _hit_direction(hit_context: Dictionary, impact: Vector2) -> Vector2:
	var source = hit_context.get("source")
	if source is ProjectileBase and is_instance_valid(source):
		return Vector2.RIGHT.rotated((source as ProjectileBase).rotation)
	var away := _visual_center() - impact
	if away.length() < 4.0:
		var player := get_tree().get_first_node_in_group(&"player") as Node2D
		if player != null:
			away = global_position - player.global_position
	return away.normalized() if not away.is_zero_approx() else Vector2.RIGHT


func _muzzle_offset() -> Vector2:
	match enemy_id:
		&"spitter":
			return Vector2(18.0 * _facing, -118.0)
		&"shard_turret":
			return Vector2(96.0 * _facing, -74.0)
		&"shooting_gargoyle":
			return Vector2(8.0 * _facing, -104.0)
	return Vector2.ZERO


func _spawn_compact_hit(frozen: bool) -> void:
	var parent := _effect_parent()
	if parent != null:
		CombatFeedback.spawn_hit(parent, _visual_center(), frozen)


func _spawn_blocked_hit(impact := Vector2.INF, direction := Vector2.ZERO) -> void:
	var parent := _effect_parent()
	if parent != null:
		var position := impact if impact.is_finite() else _visual_center()
		CombatFeedback.spawn_blocked_hit(parent, position, direction)
	_block_flash_remaining = BLOCK_FLASH_SECONDS
	GameJuice.play_sfx(&"armor_clink", &"beam_ricochet")


func _draw() -> void:
	if not _has_art:
		return
	var center := _visual_base_position
	if enemy_id == &"burrower" and _burrow_phase == &"mound":
		draw_arc(
			center + Vector2(0.0, 66.0), 54.0, PI, TAU, 20, Color(0.68, 0.47, 0.28, 0.7), 4.0, true
		)
	elif enemy_id == &"burrower" and _burrow_phase == &"exposed":
		draw_arc(
			center + Vector2(0.0, 70.0), 48.0, PI, TAU, 20, Color(1.0, 0.65, 0.3, 0.72), 3.0, true
		)
	if _telegraph_remaining > 0.0 and enemy_id in PROJECTILE_STYLES:
		# Aim warning: a thin line along the locked shot direction.
		var origin := _muzzle_offset()
		var reach := 90.0 + (1.0 - _telegraph_remaining / 0.7) * 150.0
		var directions: Array[Vector2] = [_pending_attack_direction]
		if enemy_id == &"shard_turret":
			directions = [
				_pending_attack_direction.rotated(-0.14),
				_pending_attack_direction,
				_pending_attack_direction.rotated(0.14),
			]
		for direction in directions:
			draw_dashed_line(
				origin + direction * 26.0,
				origin + direction * reach,
				Color(1.0, 0.55, 0.3, 0.55),
				2.0,
				10.0
			)
