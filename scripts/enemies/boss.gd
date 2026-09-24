class_name CombatBoss extends CharacterBody2D

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")
const DefeatRewardsScript = preload("res://scripts/enemies/defeat_rewards.gd")
const VisualProfiles = preload("res://scripts/enemies/effects/runtime_visual_profiles.gd")
const ProjectileHurtboxScript = preload("res://scripts/enemies/projectile_hurtbox.gd")
const HitResult = preload("res://scripts/combat/hit_result.gd")
const BossVisuals = preload("res://scripts/enemies/effects/boss_visuals.gd")
const MAX_TELEGRAPH_SECONDS := 0.6
const HIT_FLASH_SECONDS := 0.14
const BLOCK_FLASH_SECONDS := 0.1
const CORE_BUBBLE_RADIUS := 84.0
const OPEN_WINDOW_SECONDS := 2.0
const CLOSING_WARNING_SECONDS := 0.45
const STAGGER_SECONDS := 0.75
const HEALTH_TRAIL_DELAY := 0.35
const PROJECTILE_STYLES := {
	&"stone_guardian": &"rock",
	&"furnace_mother": &"fire",
	&"tidal_heart": &"water",
}

signal defeated(id: StringName)

@export var runtime_id: StringName = &"stone_guardian"

var enemy_id: StringName = &""
var health := 1
var max_health := 1
var phase := 1
var is_frozen := false
var _dying := false
var _age := 0.0
var _branch_open := false
var _branch_timer := 0.0
var _attack_timer := 1.0
var _telegraph_remaining := 0.0
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
	max_health = int(
		Catalog.BOSS_DATA.get(enemy_id, Catalog.BOSS_DATA[&"stone_guardian"])["max_health"]
	)
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
	_advance_presentation_timers(delta)
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	_player_engaged = player != null and _in_arena(player.global_position)
	if player != null and not _player_engaged:
		velocity = Vector2.ZERO
		_telegraph_remaining = 0.0
		_attack_timer = 0.35
		_update_visual_presentation()
		queue_redraw()
		return
	if player != null:
		_move_boss(delta, player)
	_branch_timer -= delta
	_attack_timer -= delta
	var was_telegraphing := _telegraph_remaining > 0.0
	_telegraph_remaining = maxf(_telegraph_remaining - delta, 0.0)
	if _branch_timer <= 0.0:
		_advance_attack_window()
	if was_telegraphing and _telegraph_remaining == 0.0:
		_fire_boss_attack()
	elif not was_telegraphing and _attack_timer <= 0.0:
		_telegraph_remaining = minf(0.35, MAX_TELEGRAPH_SECONDS)
		_attack_timer = 1.8
		# Aim is locked when the telegraph starts so the warning lines tell the truth.
		_pending_directions = _attack_directions()
		GameJuice.play_sfx(&"boss_telegraph")
	_update_visual_presentation()
	queue_redraw()


func set_test_phase(requested_phase: int) -> void:
	if requested_phase not in [1, 2]:
		return
	var changed := phase != requested_phase
	phase = requested_phase
	_branch_open = false
	_branch_timer = 0.0
	_attack_timer = 0.2
	_telegraph_remaining = 0.0
	if changed:
		_spawn_phase_burst()
	_update_visual_presentation()
	queue_redraw()


func receive_hit(amount: int, kind: StringName, hit_context := {}) -> HitResult.Reaction:
	if _dying or amount < 0:
		return HitResult.Reaction.PASS
	var impact := _impact_position(hit_context)
	var direction := _hit_direction(hit_context, impact)
	if enemy_id == &"tidal_heart" and phase == 1 and kind == &"ice":
		_branch_open = true
		_branch_timer = 2.0
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
	if not is_vulnerable_to(kind):
		_spawn_blocked_hit(impact, direction)
		return HitResult.Reaction.BLOCKED
	health = maxi(health - amount, 0)
	_health_trail_delay = HEALTH_TRAIL_DELAY
	if health > 0 and phase == 1 and health <= maxi(max_health / 2, 1):
		phase = 2
		_branch_open = false
		_branch_timer = 0.0
		_spawn_phase_burst()
		queue_redraw()
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
		_spawn_compact_hit(impact, direction, heavy)
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
			if phase == 1:
				return kind == &"missile" and _branch_open
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
	_branch_timer = 2.0
	_update_visual_presentation()
	queue_redraw()


func reset_runtime() -> void:
	_dying = false
	health = max_health
	phase = 1
	_branch_open = false
	_branch_timer = 0.0
	_attack_timer = 1.0
	_telegraph_remaining = 0.0
	_hit_flash_remaining = 0.0
	_phase_burst_count = 0
	_movement_direction = 1.0
	_movement_timer = 1.4
	_player_engaged = false
	_health_trail = float(max_health)
	_stagger_remaining = 0.0
	_block_flash_remaining = 0.0
	_was_open = false
	_pending_directions.clear()
	_shield_ripples.clear()
	velocity = Vector2.ZERO
	collision_layer = 8
	if _player_detector != null:
		_player_detector.monitoring = true
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(true)
	show()
	_update_visual_presentation()


func _move_boss(delta: float, player: Node2D) -> void:
	if arena_bounds.size == Vector2.ZERO:
		return
	var left := arena_bounds.position.x + 104.0
	var right := arena_bounds.end.x - 104.0
	match enemy_id:
		&"stone_guardian":
			var pursuit := signf(player.global_position.x - global_position.x)
			velocity.x = pursuit * (138.0 if phase == 2 else 92.0)
			velocity.y = minf(velocity.y + 1800.0 * delta, 900.0)
			move_and_slide()
		&"furnace_mother":
			_movement_timer -= delta
			if _movement_timer <= 0.0 or global_position.x <= left or global_position.x >= right:
				_movement_direction *= -1.0
				_movement_timer = 1.15 if phase == 2 else 1.55
			velocity.x = _movement_direction * (210.0 if phase == 2 else 145.0)
			velocity.y = minf(velocity.y + 1800.0 * delta, 900.0)
			move_and_slide()
		&"tidal_heart":
			var target := Vector2(
				clampf(player.global_position.x, left + 60.0, right - 60.0),
				_home_position.y - 100.0 + sin(_age * 1.15) * 110.0
			)
			velocity = (target - global_position).limit_length(150.0 if phase == 2 else 105.0)
			move_and_slide()
	global_position.x = clampf(global_position.x, left, right)
	global_position.y = clampf(
		global_position.y, arena_bounds.position.y + 104.0, arena_bounds.end.y - 92.0
	)
	if is_on_wall():
		_movement_direction *= -1.0


func _advance_attack_window() -> void:
	_branch_timer = 2.0
	match enemy_id:
		&"stone_guardian":
			_branch_open = phase == 1 or not _branch_open
		&"furnace_mother":
			_branch_open = phase == 1 or not _branch_open
		&"tidal_heart":
			if phase == 2:
				_branch_open = false
				_branch_timer = 999999.0
			else:
				_branch_open = false


func _attack_directions() -> Array[Vector2]:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	var target_direction := Vector2.DOWN
	if player != null and _in_arena(player.global_position):
		var aim_point := player.global_position + Vector2(0.0, -80.0)
		target_direction = (aim_point - _core_world_position()).normalized()
	var directions: Array[Vector2] = [target_direction]
	match enemy_id:
		&"stone_guardian":
			if phase == 2:
				directions = [
					target_direction.rotated(-0.22),
					target_direction,
					target_direction.rotated(0.22),
				]
		&"furnace_mother":
			directions = [
				target_direction.rotated(-0.3),
				target_direction,
				target_direction.rotated(0.3),
			]
			if phase == 2:
				directions.push_front(target_direction.rotated(-0.56))
				directions.append(target_direction.rotated(0.56))
		&"tidal_heart":
			directions.clear()
			for index in 8:
				directions.append(Vector2.RIGHT.rotated(TAU * float(index) / 8.0))
	return directions


func _fire_boss_attack() -> void:
	var directions := _pending_directions
	if directions.is_empty():
		directions = _attack_directions()
	_pending_directions = []
	var origin := _core_world_position()
	for direction in directions:
		var projectile := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
		if projectile == null:
			continue
		var parent := (
			get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		)
		parent.add_child(projectile)
		projectile.global_position = origin + direction * 60.0
		projectile.style = PROJECTILE_STYLES.get(enemy_id, &"orb")
		projectile.size_scale = 1.6
		projectile.launch(direction, int(Catalog.BOSS_DATA[enemy_id]["contact_damage"]))
		if projectile.has_method("configure_arena"):
			projectile.call("configure_arena", arena_bounds)
	CombatFx.spawn_muzzle_flash(_effect_parent(), origin, Vector2.UP, _boss_accent_color())


func _on_player_detector_body_entered(body: Node2D) -> void:
	if _dying or not body.has_method(&"take_damage") or not _in_arena(body.global_position):
		return
	var data: Dictionary = Catalog.BOSS_DATA[enemy_id]
	body.call(&"take_damage", int(data["contact_damage"]), global_position)


func _die() -> void:
	_dying = true
	health = 0
	collision_layer = 0
	collision_mask = 0
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


func _in_arena(point: Vector2) -> bool:
	return arena_bounds.size == Vector2.ZERO or arena_bounds.has_point(point)


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
	if not _branch_open or _branch_timer > OPEN_WINDOW_SECONDS + 0.01:
		return -1.0
	if phase == 1 and enemy_id != &"tidal_heart":
		return -1.0
	return clampf(_branch_timer / OPEN_WINDOW_SECONDS, 0.0, 1.0)


func _advance_presentation_timers(delta: float) -> void:
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	_block_flash_remaining = maxf(_block_flash_remaining - delta, 0.0)
	_stagger_remaining = maxf(_stagger_remaining - delta, 0.0)
	_tether_flash = maxf(_tether_flash - delta, 0.0)
	_recoil *= exp(-14.0 * delta)
	_health_trail_delay = maxf(_health_trail_delay - delta, 0.0)
	if _health_trail_delay == 0.0:
		_health_trail = move_toward(_health_trail, float(health), float(max_health) * delta * 0.6)
	_health_trail = maxf(_health_trail, float(health))
	for ripple in _shield_ripples:
		ripple["age"] = float(ripple["age"]) + delta
	_shield_ripples = _shield_ripples.filter(func(r): return float(r["age"]) < 0.45)
	var exposed := weak_point_exposed()
	var window := phase == 2 or enemy_id == &"tidal_heart"
	if exposed != _was_open and window:
		if exposed:
			GameJuice.play_sfx(&"boss_open")
			CombatFeedback.spawn_phase_burst(self, _boss_accent_color(), _core_local())
		else:
			GameJuice.play_sfx(&"boss_close")
			_spawn_close_puff()
	_was_open = exposed
	_open_elapsed = _open_elapsed + delta if exposed else 0.0
	if enemy_id == &"furnace_mother" and phase == 2:
		_steam_timer -= delta
		if _steam_timer <= 0.0:
			_steam_timer = 0.12 if _branch_open else 0.3
			_spawn_heat_particle()


func _update_visual_presentation() -> void:
	if not _has_art or _sprite == null:
		return
	var accent := _boss_accent_color()
	_update_facing()
	_apply_state_art()
	_sprite.position = _visual_base_position + _recoil
	_sprite.position.y += sin(_age * 1.8) * (4.0 if enemy_id == &"tidal_heart" else 1.5)
	_sprite.scale = _visual_base_scale
	_sprite.rotation = sin(_age * 1.25) * (0.018 if enemy_id == &"tidal_heart" else 0.008)
	_sprite.modulate = Color.WHITE
	var look := BossVisuals.state_look(self)
	var glow: float = look["glow"]
	var darken: float = look["darken"]
	var frost: float = look["frost"]
	var glow_color: Color = look["glow_color"]
	var flash := 0.0
	var flash_color := Color.WHITE
	if _telegraph_remaining > 0.0:
		var attack_pulse := 0.5 + 0.5 * sin(_age * 26.0)
		_sprite.scale *= Vector2(1.035 + attack_pulse * 0.035, 0.98 - attack_pulse * 0.015)
		glow = maxf(glow, 0.45 + attack_pulse * 0.35)
		glow_color = accent
	if _stagger_remaining > 0.0:
		var shake := _stagger_remaining / STAGGER_SECONDS
		_sprite.position += Vector2(sin(_age * 80.0), cos(_age * 67.0)) * 6.0 * shake
		flash = maxf(flash, 0.35 * shake)
		flash_color = accent
	var strength := GameJuice.flash_strength()
	if _hit_flash_remaining > 0.0:
		flash = clampf(_hit_flash_remaining / HIT_FLASH_SECONDS, 0.0, 1.0) * 0.85 * strength
		flash_color = Color(1.0, 0.97, 0.9)
		_sprite.scale *= 1.02
	elif _block_flash_remaining > 0.0:
		flash = 0.45 * strength
		flash_color = Color(0.6, 0.66, 0.76)
		_sprite.position.x += sin(_age * 95.0) * 2.5
	if _fx != null:
		_fx.set_shader_parameter(&"flash_amount", flash)
		_fx.set_shader_parameter(&"flash_color", flash_color)
		_fx.set_shader_parameter(&"glow_amount", glow)
		_fx.set_shader_parameter(&"glow_color", glow_color)
		_fx.set_shader_parameter(&"frost_amount", frost)
		_fx.set_shader_parameter(&"darken_amount", darken)
	if _overlay != null:
		_overlay.queue_redraw()


func _update_facing() -> void:
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


func _spawn_compact_hit(
	impact_position: Vector2, direction := Vector2.ZERO, heavy := false
) -> void:
	var parent := _effect_parent()
	if parent != null:
		var tint := _boss_accent_color().lightened(0.25)
		CombatFeedback.spawn_hit(parent, impact_position, false, direction, heavy, tint)


func _spawn_blocked_hit(impact_position: Vector2, direction := Vector2.ZERO) -> void:
	var parent := _effect_parent()
	if parent != null:
		CombatFeedback.spawn_blocked_hit(parent, impact_position, direction)
	_block_flash_remaining = BLOCK_FLASH_SECONDS
	if enemy_id == &"tidal_heart" and phase == 2:
		_shield_ripples.append({"position": to_local(impact_position), "age": 0.0})
	if Audio.has_method(&"play_sfx"):
		GameJuice.play_sfx(&"armor_clink", &"beam_ricochet")


func _spawn_phase_burst() -> void:
	_phase_burst_count += 1
	_stagger_remaining = STAGGER_SECONDS
	CombatFeedback.spawn_phase_burst(self, _boss_accent_color(), _visual_base_position)
	GameJuice.shake(self, 9.0, 0.45)
	GameJuice.hit_stop(self, 0.1)
	GameJuice.play_sfx(&"boss_phase")


func _spawn_close_puff() -> void:
	var parent := _effect_parent()
	if parent == null:
		return
	var tint := Color(0.5, 0.5, 0.52, 0.5)
	for index in 3:
		var puff := CombatFx.Puff.new()
		parent.add_child(puff)
		puff.global_position = _core_world_position()
		puff.z_index = 6
		puff.configure(
			Vector2.RIGHT.rotated(TAU * float(index) / 3.0 + _age) * 70.0, 0.35, 10.0, 34.0, tint
		)


func _spawn_heat_particle() -> void:
	var parent := _effect_parent()
	if parent == null or not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var puff := CombatFx.Puff.new()
	parent.add_child(puff)
	var spread := Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-170.0, -40.0))
	puff.global_position = global_position + _visual_base_position + spread
	puff.z_index = 6
	if _branch_open:
		# Cooling window: pale steam vents off the cracked shell.
		puff.configure(
			Vector2(0.0, -rng.randf_range(80.0, 150.0)),
			0.7,
			8.0,
			36.0,
			Color(0.85, 0.87, 0.9, 0.4),
			1.5
		)
	else:
		# Overheated: embers rise off the white-hot carapace.
		puff.configure(
			Vector2(rng.randf_range(-20.0, 20.0), -rng.randf_range(120.0, 220.0)),
			0.45,
			3.0,
			5.0,
			Color(1.0, 0.72, 0.3, 0.9),
			0.5
		)


func _draw() -> void:
	if not _has_art or not _player_engaged:
		return
	BossVisuals.draw_health_bar(self)


func _draw_overlay_on(canvas: CanvasItem) -> void:
	BossVisuals.draw_overlay(self, canvas)


## Tidal Heart has authored closed/open shell art; other bosses use shader states only.
func has_state_art() -> bool:
	return _closed_texture != null and _open_texture != null


func _apply_state_art() -> void:
	if not has_state_art():
		return
	var exposed := weak_point_exposed()
	_sprite.texture = _open_texture if exposed else _closed_texture
	# D19 "Bubble -> Harpoon": Bubble Snare encases the exposed core; a harpoon pops it.
	var bubbled := phase == 1 and _branch_open and not _core_cracked
	if bubbled and not is_instance_valid(_core_bubble):
		_core_bubble = BubbleVisual.attach(
			self,
			Rect2(
				-CORE_BUBBLE_RADIUS,
				-CORE_BUBBLE_RADIUS,
				CORE_BUBBLE_RADIUS * 2.0,
				CORE_BUBBLE_RADIUS * 2.0
			),
			4
		)
	if is_instance_valid(_core_bubble):
		_core_bubble.visible = bubbled
		_core_bubble.position = _core_local()
		_core_bubble.warning = (
			clampf(1.0 - _branch_timer / CLOSING_WARNING_SECONDS, 0.0, 1.0) if bubbled else 0.0
		)


func _boss_color() -> Color:
	match enemy_id:
		&"furnace_mother":
			return Color(0.78, 0.18, 0.08, 1.0)
		&"tidal_heart":
			return Color(0.08, 0.38, 0.75, 1.0)
	return Color(0.35, 0.38, 0.45, 1.0)


func _boss_accent_color() -> Color:
	match enemy_id:
		&"furnace_mother":
			return Color(1.0, 0.52, 0.12, 1.0)
		&"tidal_heart":
			return Color(0.28, 0.9, 1.0, 1.0)
	return Color(1.0, 0.76, 0.24, 1.0)
