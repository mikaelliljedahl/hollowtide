class_name CombatBoss extends CharacterBody2D
## Regional boss. Health drives four fight stages (docs/features/boss-rework.md); stages 1-2
## use damage-matrix phase B1 and stages 3-4 use B2. Every attack runs idle -> telegraph ->
## active -> recover, and the recover step is the punish window (B2 armor opens during it).

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const DefeatRewardsScript = preload("res://scripts/enemies/defeat_rewards.gd")
const VisualProfiles = preload("res://scripts/enemies/effects/runtime_visual_profiles.gd")
const ProjectileHurtboxScript = preload("res://scripts/enemies/projectile_hurtbox.gd")
const HitResult = preload("res://scripts/combat/hit_result.gd")
const BossVisuals = preload("res://scripts/enemies/effects/boss_visuals.gd")
const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")
const Motion = preload("res://scripts/enemies/boss_motion.gd")
const HIT_FLASH_SECONDS := 0.14
const BLOCK_FLASH_SECONDS := 0.1
const CORE_BUBBLE_RADIUS := 84.0
const OPEN_WINDOW_SECONDS := 2.0
const CLOSED_WINDOW_SECONDS := 999999.0
const CLOSING_WARNING_SECONDS := 0.45
const STAGGER_SECONDS := 0.75
const HEALTH_TRAIL_DELAY := 0.35
const DISENGAGED_ATTACK_DELAY := 0.35

signal defeated(id: StringName)
signal stage_changed(stage: int)
signal attack_telegraphed(attack: StringName)
signal attack_released(attack: StringName)

@export var runtime_id: StringName = &"stone_guardian"

var enemy_id: StringName = &""
var health := 1
var max_health := 1
## Damage-matrix protection phase (B1 = 1, B2 = 2), derived from `stage`.
var phase := 1
## Fight stage 1-4; 4 is the desperation stage.
var stage := 1
var is_frozen := false
var _dying := false
var _age := 0.0
var _branch_open := false
var _branch_timer := 0.0
var _window_length := OPEN_WINDOW_SECONDS
var _attack_timer := 1.0
var _attack_state: StringName = &"idle"
var _attack_id: StringName = &""
var _attack_chain: Array[StringName] = []
var _attack_plan := {}
var _rotation_index := 0
var _telegraph_remaining := 0.0
var _telegraph_length := 0.0
var _active_elapsed := 0.0
var _active_length := 0.0
var _recover_remaining := 0.0
var _emissions: Array[Dictionary] = []
var _charge_done := false
var _player_detector: Area2D
var _sprite: Sprite2D
var _projectile_hurtbox: EnemyProjectileHurtbox
var _has_art := false
var _visual_base_position := Vector2.ZERO
var _visual_base_scale := Vector2.ONE
var _hit_flash_remaining := 0.0
var _phase_burst_count := 0
var _movement_direction := 1.0
var _movement_timer := 1.4
var _home_position := Vector2.ZERO
var _player_engaged := false
var arena_bounds := Rect2()
# Presentation-only state (never read by gameplay rules).
var _fx: ShaderMaterial
var _overlay: Node2D
var _pending_directions: Array[Vector2] = []
var _telegraph_marks: Array[Dictionary] = []
var _was_open := false
var _open_elapsed := 0.0
var _block_flash_remaining := 0.0
var _stagger_remaining := 0.0
var _recoil := Vector2.ZERO
var _facing := 1.0
var _health_trail := 1.0
var _health_trail_delay := 0.0
var _tether_flash := 0.0
var _shield_ripples: Array[Dictionary] = []
var _core_cracked := false
var _steam_timer := 0.0
var _closed_texture: Texture2D
var _open_texture: Texture2D
var _core_bubble: BubbleVisual


func _ready() -> void:
	enemy_id = runtime_id
	max_health = int(_boss_data()["max_health"])
	health = max_health
	_health_trail = float(max_health)
	add_to_group(&"enemies")
	add_to_group(&"damageable")
	add_to_group(&"bosses")
	collision_layer = 8
	collision_mask = 3
	_player_detector = get_node_or_null("PlayerDetector") as Area2D
	if _player_detector != null:
		_player_detector.body_entered.connect(_on_player_detector_body_entered)
	_home_position = global_position
	_load_optional_sprite()
	_configure_projectile_hurtbox()
	_overlay = BossVisuals.create_overlay(self)
	queue_redraw()


func configure_arena(bounds: Rect2) -> void:
	arena_bounds = bounds
	global_position = _clamp_to_arena(global_position)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_age += delta
	BossVisuals.advance_timers(self, delta)
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	_player_engaged = player != null and _in_arena(player.global_position)
	if player != null and not _player_engaged:
		velocity = Vector2.ZERO
		_cancel_attack(DISENGAGED_ATTACK_DELAY)
		_update_visual_presentation()
		queue_redraw()
		return
	if player != null:
		Motion.move(self, delta, player)
	_branch_timer -= delta
	if _branch_timer <= 0.0:
		_advance_attack_window()
	_advance_attack(delta)
	_update_visual_presentation()
	queue_redraw()


func set_test_phase(requested_phase: int) -> void:
	if requested_phase not in [1, 2]:
		return
	set_test_stage(1 if requested_phase == 1 else Patterns.ARMORED_STAGE)


## Dev/test entry into a fight stage without changing health.
func set_test_stage(requested_stage: int) -> void:
	if requested_stage < 1 or requested_stage > Patterns.DESPERATION_STAGE:
		return
	var changed := stage != requested_stage
	stage = requested_stage
	phase = Patterns.protection_phase(stage)
	_branch_open = false
	_branch_timer = 0.0
	_cancel_attack(0.2)
	_rotation_index = 0
	if changed:
		_spawn_phase_burst()
		stage_changed.emit(stage)
	_update_visual_presentation()
	queue_redraw()


func receive_hit(amount: int, kind: StringName, hit_context := {}) -> HitResult.Reaction:
	if _dying or amount < 0:
		return HitResult.Reaction.PASS
	var impact := _impact_position(hit_context)
	var direction := _hit_direction(hit_context, impact)
	var outside := _player_outside_arena()
	if enemy_id == &"tidal_heart" and phase == 1 and kind == &"ice" and not outside:
		_branch_open = true
		_branch_timer = OPEN_WINDOW_SECONDS
		_window_length = OPEN_WINDOW_SECONDS
		_core_cracked = false
		ArsenalFx.spawn_rings(
			_effect_parent(), _core_world_position(), 110.0, Color(0.72, 0.95, 1.0, 0.9), 0.4, 2
		)
		GameJuice.play_sfx(&"bubble_trap", &"freeze")
		GameJuice.shake(self, 4.0, 0.2)
		_update_visual_presentation()
		queue_redraw()
		return HitResult.Reaction.TRIGGERED
	if amount <= 0:
		return HitResult.Reaction.PASS
	if outside or not is_vulnerable_to(kind):
		BossVisuals.spawn_blocked_hit(self, impact, direction)
		return HitResult.Reaction.BLOCKED
	health = maxi(health - amount, 0)
	_health_trail_delay = HEALTH_TRAIL_DELAY
	if health > 0:
		var reached := Patterns.stage_for(health, max_health)
		if reached > stage:
			_enter_stage(reached)
	if health == 0:
		_die()
	else:
		var heavy := kind in [&"missile", &"bomb"]
		_hit_flash_remaining = HIT_FLASH_SECONDS
		_recoil = direction * (14.0 if heavy else 7.0)
		if enemy_id == &"tidal_heart" and phase == 1 and not _core_cracked:
			_core_cracked = true
			ArsenalFx.spawn_bubble_pop(_effect_parent(), _core_world_position(), CORE_BUBBLE_RADIUS)
			GameJuice.play_sfx(&"bubble_pop", &"ice_shatter")
		BossVisuals.spawn_compact_hit(self, impact, direction, heavy)
		GameJuice.shake(self, 5.0 if heavy else 2.0, 0.18)
		GameJuice.play_sfx(&"enemy_hit", &"missile_hit" if heavy else &"")
		_update_visual_presentation()
	return HitResult.Reaction.DAMAGE


func take_damage(amount: int, kind: StringName) -> void:
	receive_hit(amount, kind)


func is_vulnerable_to(kind: StringName) -> bool:
	match enemy_id:
		&"stone_guardian":
			if phase == 1:
				return kind in [&"missile", &"undertow"]
			return kind == &"missile" and _branch_open
		&"furnace_mother":
			if phase == 1:
				return kind in [&"wave", &"missile"]
			return kind == &"missile" and _branch_open
		&"tidal_heart":
			return kind == &"missile" and _branch_open
	return false


func allows_projectile(_kind: StringName) -> bool:
	return false


func open_wave_window() -> void:
	if _dying or enemy_id != &"tidal_heart" or phase != 2:
		return
	if not _branch_open:
		_tether_flash = 0.5
		GameJuice.shake(self, 4.0, 0.2)
	_branch_open = true
	_branch_timer = OPEN_WINDOW_SECONDS
	_window_length = OPEN_WINDOW_SECONDS
	_update_visual_presentation()
	queue_redraw()


func reset_runtime() -> void:
	_dying = false
	health = max_health
	stage = 1
	phase = 1
	_branch_open = false
	_branch_timer = 0.0
	_window_length = OPEN_WINDOW_SECONDS
	_cancel_attack(1.0)
	_rotation_index = 0
	_hit_flash_remaining = 0.0
	_phase_burst_count = 0
	_movement_direction = 1.0
	_movement_timer = 1.4
	_player_engaged = false
	_health_trail = float(max_health)
	_stagger_remaining = 0.0
	_block_flash_remaining = 0.0
	_was_open = false
	_shield_ripples.clear()
	velocity = Vector2.ZERO
	collision_layer = 8
	if _player_detector != null:
		_player_detector.monitoring = true
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(true)
	show()
	_update_visual_presentation()


func _enter_stage(new_stage: int) -> void:
	stage = new_stage
	var new_phase := Patterns.protection_phase(stage)
	if new_phase != phase:
		phase = new_phase
		_branch_open = false
		_branch_timer = 0.0
	# The stagger is a free breather: whatever was winding up is dropped unfired.
	_cancel_attack(Patterns.STAGE_BREATHER)
	_rotation_index = 0
	_spawn_phase_burst()
	stage_changed.emit(stage)
	queue_redraw()


func _advance_attack(delta: float) -> void:
	match _attack_state:
		&"idle":
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_chain = Patterns.chain_at(enemy_id, stage, _rotation_index)
				_rotation_index += 1
				_start_telegraph()
		&"telegraph":
			_telegraph_remaining = maxf(_telegraph_remaining - delta, 0.0)
			if _telegraph_remaining == 0.0:
				_release_attack()
		&"active":
			_active_elapsed += delta
			_fire_due_emissions()
			var done := _active_elapsed >= _active_length
			if Patterns.is_charge(_attack_id):
				done = _charge_done or done
			if done and _emissions.is_empty():
				_finish_attack()
		&"recover":
			_recover_remaining -= delta
			if _recover_remaining <= 0.0:
				_attack_state = &"idle"
				_attack_timer = Patterns.idle_seconds(stage)


func _start_telegraph() -> void:
	_attack_id = _attack_chain.pop_front()
	_attack_state = &"telegraph"
	_telegraph_length = Patterns.telegraph_seconds(_attack_id, stage)
	_telegraph_remaining = _telegraph_length
	# Aim, lanes and floor targets lock now so the telegraph tells the truth.
	_attack_plan = Attacks.plan(self, _attack_id)
	_pending_directions = _attack_plan["directions"]
	_telegraph_marks = _attack_plan["marks"]
	if Patterns.is_charge(_attack_id):
		_facing = float(_attack_plan["charge_direction"])
	GameJuice.play_sfx(&"boss_telegraph")
	attack_telegraphed.emit(_attack_id)


func _release_attack() -> void:
	_attack_state = &"active"
	_active_elapsed = 0.0
	_active_length = Patterns.active_seconds(_attack_id, stage)
	_emissions = Attacks.emissions(self, _attack_id, _attack_plan)
	_charge_done = false
	if Patterns.is_charge(_attack_id):
		_charge_done = absf(float(_attack_plan["charge_end_x"]) - global_position.x) < 4.0
	_pending_directions = []
	attack_released.emit(_attack_id)
	BossVisuals.release_feedback(self, _attack_id)
	_fire_due_emissions()


func _fire_due_emissions() -> void:
	while not _emissions.is_empty() and float(_emissions[0]["at"]) <= _active_elapsed:
		Attacks.fire(self, _emissions.pop_front())


func _finish_attack() -> void:
	_telegraph_marks = []
	if not _attack_chain.is_empty():
		_start_telegraph()
		return
	_attack_state = &"recover"
	_recover_remaining = Patterns.punish_seconds(_attack_id, stage)
	_open_punish_window(_recover_remaining)


func _cancel_attack(idle_delay: float) -> void:
	_attack_state = &"idle"
	_attack_timer = idle_delay
	_attack_chain.clear()
	_emissions.clear()
	_telegraph_remaining = 0.0
	_recover_remaining = 0.0
	_pending_directions = []
	_telegraph_marks = []


## B2 armor/overheat opens for the whole punish window; B1 bodies are already open.
func _open_punish_window(seconds: float) -> void:
	if phase != 2 or enemy_id == &"tidal_heart":
		return
	_branch_open = true
	_branch_timer = seconds
	_window_length = seconds


func _advance_attack_window() -> void:
	_branch_timer = OPEN_WINDOW_SECONDS
	_window_length = OPEN_WINDOW_SECONDS
	match enemy_id:
		&"stone_guardian", &"furnace_mother":
			# B1 stays open; B2 opens only through a punish window after an attack.
			_branch_open = phase == 1
			if phase == 2:
				_branch_timer = CLOSED_WINDOW_SECONDS
		&"tidal_heart":
			_branch_open = false
			if phase == 2:
				_branch_timer = CLOSED_WINDOW_SECONDS


func _on_player_detector_body_entered(body: Node2D) -> void:
	if _dying or not body.has_method(&"take_damage") or not _in_arena(body.global_position):
		return
	body.call(&"take_damage", _contact_damage(), global_position)


func _boss_data() -> Dictionary:
	return Catalog.BOSS_DATA.get(enemy_id, Catalog.BOSS_DATA[&"stone_guardian"])


func _contact_damage() -> int:
	return int(_boss_data()["contact_damage"])


func _die() -> void:
	_dying = true
	health = 0
	collision_layer = 0
	collision_mask = 0
	_cancel_attack(0.0)
	if _player_detector != null:
		_player_detector.set_deferred("monitoring", false)
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(false)
	defeated.emit(enemy_id)
	# Staged death: the sequence plays &"boss_defeated" at its final burst.
	CombatFx.spawn_boss_death_sequence(self, _boss_accent_color(), &"boss_defeated")
	GameJuice.hit_stop(self, 0.12)
	GameJuice.shake(self, 10.0, 0.4)
	DefeatRewardsScript.spawn_for_defeat(self, true, false, false)
	hide()
	get_tree().create_timer(2.0).timeout.connect(queue_free, CONNECT_ONE_SHOT)


## The same test that freezes the boss in `_physics_process`: a boss that cannot answer cannot be
## hurt, so hits from outside its arena glance off (docs/features/boss-rework.md, section 4).
func _player_outside_arena() -> bool:
	if not is_inside_tree():
		return false
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	return player != null and not _in_arena(player.global_position)


func _in_arena(point: Vector2) -> bool:
	if arena_bounds.size == Vector2.ZERO:
		return true
	var margin := CombatEnemy.ARENA_FLOOR_MARGIN
	return arena_bounds.grow_individual(0.0, 0.0, 0.0, margin).has_point(point)


func _clamp_to_arena(point: Vector2) -> Vector2:
	if arena_bounds.size == Vector2.ZERO:
		return point
	return Vector2(
		clampf(point.x, arena_bounds.position.x, arena_bounds.end.x),
		clampf(point.y, arena_bounds.position.y, arena_bounds.end.y)
	)


func _load_optional_sprite() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	var path := "res://assets/sprites/devmode/%s.png" % String(enemy_id)
	if _sprite == null or not ResourceLoader.exists(path):
		return
	_sprite.texture = load(path) as Texture2D
	_has_art = _sprite.texture != null
	_sprite.visible = _has_art
	_fx = ShaderMaterial.new()
	_fx.shader = preload("res://resources/combat/sprite_fx.gdshader")
	_sprite.material = _fx
	if enemy_id == &"tidal_heart":
		_closed_texture = BossVisuals.optional_texture("tidal_heart_closed.png")
		_open_texture = BossVisuals.optional_texture("tidal_heart_open.png")
	_visual_base_position = VisualProfiles.visual_offset(enemy_id)
	var texture_scale := VisualProfiles.visual_scale(enemy_id)
	_visual_base_scale = Vector2.ONE * texture_scale
	_update_visual_presentation()


func _configure_projectile_hurtbox() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var image := _sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	_projectile_hurtbox = ProjectileHurtboxScript.new() as EnemyProjectileHurtbox
	_projectile_hurtbox.name = "ProjectileHurtbox"
	_sprite.add_child(_projectile_hurtbox)
	_projectile_hurtbox.configure(StringName("boss_" + String(enemy_id)), [image], 2)


func presentation_state() -> StringName:
	if _dying:
		return &"dying"
	if _telegraph_remaining > 0.0:
		return &"attack"
	if _branch_open:
		return &"open"
	return &"protected"


## True when the weak point is currently showing (drives glow/ring visuals).
func weak_point_exposed() -> bool:
	match enemy_id:
		&"stone_guardian", &"furnace_mother":
			return phase == 1 or _branch_open
	return _branch_open


func window_fraction_left() -> float:
	if not _branch_open or _branch_timer > _window_length + 0.01:
		return -1.0
	if phase == 1 and enemy_id != &"tidal_heart":
		return -1.0
	return clampf(_branch_timer / _window_length, 0.0, 1.0)


func _update_visual_presentation() -> void:
	if not _has_art or _sprite == null:
		return
	_update_facing()
	BossVisuals.apply_state_art(self)
	BossVisuals.apply_presentation(self)


func _update_facing() -> void:
	if _attack_state == &"idle":
		match enemy_id:
			&"stone_guardian":
				var player := get_tree().get_first_node_in_group(&"player") as Node2D
				if player != null and _player_engaged:
					var dx := player.global_position.x - global_position.x
					if absf(dx) > 24.0:
						_facing = signf(dx)
			&"furnace_mother":
				if absf(velocity.x) > 8.0:
					_facing = signf(velocity.x)
	_sprite.flip_h = _facing < 0.0
	if _projectile_hurtbox != null:
		_projectile_hurtbox.scale = Vector2(-1.0 if _facing < 0.0 else 1.0, 1.0)


## Weak-point position relative to the boss origin (follows facing and sprite bob).
func _core_local() -> Vector2:
	var core := BossVisuals.core_offset(enemy_id)
	var sprite_position := _sprite.position if _sprite != null else _visual_base_position
	return sprite_position + Vector2(core.x * _facing, core.y)


func _core_world_position() -> Vector2:
	return global_position + _core_local()


func _effect_parent() -> Node:
	var parent := get_parent()
	if parent == null and is_inside_tree():
		parent = get_tree().current_scene
	return parent


func _impact_position(hit_context: Dictionary) -> Vector2:
	var fallback := global_position + _visual_base_position * 0.35
	var requested = hit_context.get("position")
	return requested if requested is Vector2 and requested.is_finite() else fallback


func _hit_direction(hit_context: Dictionary, impact: Vector2) -> Vector2:
	var source = hit_context.get("source")
	if source is ProjectileBase and is_instance_valid(source):
		return Vector2.RIGHT.rotated((source as ProjectileBase).rotation)
	var away := _core_world_position() - impact
	return away.normalized() if away.length() > 4.0 else Vector2.RIGHT


func _spawn_phase_burst() -> void:
	_phase_burst_count += 1
	_stagger_remaining = STAGGER_SECONDS
	CombatFeedback.spawn_phase_burst(self, _boss_accent_color(), _visual_base_position)
	GameJuice.shake(self, 9.0, 0.45)
	GameJuice.hit_stop(self, 0.1)
	GameJuice.play_sfx(&"boss_phase")


func _draw() -> void:
	if not _has_art or not _player_engaged:
		return
	BossVisuals.draw_health_bar(self)


func _draw_overlay_on(canvas: CanvasItem) -> void:
	BossVisuals.draw_overlay(self, canvas)


## Tidal Heart has authored closed/open shell art; other bosses use shader states only.
func has_state_art() -> bool:
	return _closed_texture != null and _open_texture != null


func _boss_accent_color() -> Color:
	match enemy_id:
		&"furnace_mother":
			return Color(1.0, 0.52, 0.12, 1.0)
		&"tidal_heart":
			return Color(0.28, 0.9, 1.0, 1.0)
	return Color(1.0, 0.76, 0.24, 1.0)
