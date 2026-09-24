class_name UndertowDash
extends RefCounted
## Undertow Dash (internal ability `undertow_dash`, D19; replaces the old spin attack).
## A short horizontal burst on the ground or in the air: one air dash per airtime, restored on
## landing or wall contact. It passes through enemies dealing Catalog.UNDERTOW_DAMAGE with damage
## kind `undertow`, breaks undertow barriers and ignores damage while active plus a
## short grace. Driven from Player._physics_process: update() before move, strike() just
## before move_and_slide(), after_move() right after it. The first moments of each dash turn
## enemy shots around (DashDeflect).

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const HitResult = preload("res://scripts/combat/hit_result.gd")
const ACTION := &"dash"
const AFTERIMAGE_INTERVAL := 0.03

var active := false
var press_queued := false
var direction := 1
var air_available := true
var deflect: DashDeflect
var _player: Player
var _timer := 0.0
var _cooldown := 0.0
var _grace := 0.0
var _hits: Array[Node] = []
var _afterimage_timer := 0.0


func _init(player: Player) -> void:
	_player = player
	deflect = DashDeflect.new(player)


func can_start() -> bool:
	var p := _player
	return (
		GameState.has_ability(&"undertow_dash")
		and not p.is_ball
		and not p._is_slipping
		and not p._dead
		and not active
		and _cooldown <= 0.0
		and p._hurt_input_lock_timer <= 0.0
		and (p.is_on_floor() or air_available)
	)


func protects() -> bool:
	return active or _grace > 0.0


func start(requested_direction: int = 0) -> bool:
	if not can_start():
		return false
	var p := _player
	if p.is_crouching and not p._try_stand_up():
		return false
	direction = requested_direction if requested_direction != 0 else p.facing
	p.facing = direction
	if not p.is_on_floor():
		air_available = false
	active = true
	deflect.open()
	_timer = Catalog.DASH_SECONDS
	_hits.clear()
	_afterimage_timer = 0.0
	p._stop_spin()
	p._jump_cutoff_applied = true
	p.velocity = Vector2(float(direction) * Catalog.DASH_SPEED, 0.0)
	p._play_optional_sfx(&"dash")
	DashFx.spawn_burst(p, direction)
	return true


func end(keep_speed := true) -> void:
	if not active:
		return
	active = false
	deflect.close()
	_timer = 0.0
	_cooldown = Catalog.DASH_COOLDOWN
	_grace = Catalog.DASH_INVULN_GRACE
	if keep_speed:
		_player.velocity.x = (
			float(direction) * minf(absf(_player.velocity.x), PlayerConfig.RUN_MAX)
		)
	_hits.clear()


func reset() -> void:
	end(false)
	_cooldown = 0.0
	_grace = 0.0
	air_available = true
	press_queued = false


func update(delta: float, move_input: float) -> void:
	var p := _player
	_cooldown = maxf(_cooldown - delta, 0.0)
	_grace = maxf(_grace - delta, 0.0)
	deflect.tick(delta)
	if p.is_on_floor() or p._wall_side != 0:
		air_available = true
	var pressed := press_queued
	if not pressed and InputMap.has_action(ACTION):
		pressed = Input.is_action_just_pressed(ACTION)
	press_queued = false
	if pressed and not active:
		var wanted := int(signf(move_input))
		if p._wall_side != 0 and not p.is_on_floor():
			wanted = -p._wall_side  # Dash away from the wall being clung to.
		start(wanted)
	if not active:
		return
	if p.is_ball or p._dead:
		end(false)
		return
	if p.velocity.y < 0.0 and not p._jump_cutoff_applied:
		# A jump during the dash ends it; the jump keeps only run speed.
		end()
		return
	_timer -= delta
	if _timer <= 0.0:
		end()
		return
	p.velocity.x = float(direction) * Catalog.DASH_SPEED
	if not p.is_on_floor():
		p.velocity.y = 0.0
	_afterimage_timer -= delta
	if _afterimage_timer <= 0.0:
		_afterimage_timer = AFTERIMAGE_INTERVAL
		DashFx.spawn_afterimage(p, p._sprite)


func after_move() -> void:
	if active and _player.is_on_wall():
		end(false)


## Hits everything the dash will sweep through this frame, before moving, so a barrier opens in
## time for the dash to pass instead of stopping against it.
func strike(delta: float) -> void:
	if not active:
		return
	var p := _player
	var reach := absf(p.velocity.x) * delta + 28.0
	var height := PlayerConfig.STANDING_HEIGHT
	var rect := RectangleShape2D.new()
	rect.size = Vector2(PlayerConfig.STANDING_WIDTH + reach, height)
	var center := p.global_position + Vector2(float(direction) * reach * 0.5, -height * 0.5)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = rect
	query.transform = Transform2D(0.0, center)
	query.collision_mask = 1 | 8
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [p.get_rid()]
	deflect.sweep(Rect2(center - rect.size * 0.5, rect.size), delta)
	for hit in p.get_world_2d().direct_space_state.intersect_shape(query, 32):
		var target := _target_for(hit.get("collider") as Node)
		if target == null or _hits.has(target):
			continue
		_hits.append(target)
		_hit(target, center)


func _target_for(node: Node) -> Node:
	var candidate := node
	if candidate != null and candidate.is_in_group(&"projectile_hurtbox"):
		candidate = candidate.get_parent()
		while candidate != null and not candidate.has_method(&"take_damage"):
			candidate = candidate.get_parent()
	if candidate == null or not candidate.is_in_group(&"damageable"):
		return null
	if candidate is AbilityGate and StringName(candidate.get("gate_kind")) != &"undertow":
		return null
	return candidate


func _hit(target: Node, center: Vector2) -> void:
	var context := {"position": center, "source": _player}
	if target.has_method(&"receive_hit"):
		var result = target.call(&"receive_hit", Catalog.UNDERTOW_DAMAGE, &"undertow", context)
		if result == HitResult.Reaction.DAMAGE:
			_player._play_optional_sfx(&"dash_hit")
		return
	if target.has_method(&"is_vulnerable_to") and not target.call(&"is_vulnerable_to", &"undertow"):
		return
	if target.has_method(&"take_damage"):
		target.call(&"take_damage", Catalog.UNDERTOW_DAMAGE, &"undertow")
		_player._play_optional_sfx(&"dash_hit")
