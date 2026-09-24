class_name EnemyAi
extends RefCounted
## Movement/AI routines split out of CombatEnemy (D20 aggression pass): the armored guard
## charge, the parasite swarm lunge and the vent flyer chase. Movement only; no status code.

const Placement = preload("res://scripts/enemies/effects/enemy_placement.gd")
const VENT_FLYER_CHASE := 110.0
const GUARD_PATROL_SPEED := 210.0
const GUARD_SIGHT := Vector2(520.0, 150.0)
const GUARD_WINDUP := 0.42
const GUARD_CHARGE_SPEED := 540.0
const GUARD_CHARGE_SECONDS := 0.7
const GUARD_RECOVER_SECONDS := 0.55
const GUARD_CHARGE_COOLDOWN := 1.6
const PARASITE_TRACK_SPEED := 250.0
const PARASITE_LUNGE_RANGE := 170.0
const PARASITE_LUNGE_SPEED := 560.0
const PARASITE_SEPARATION := 70.0


static func vent_flyer(enemy: CombatEnemy, delta: float) -> void:
	# Weaves around a home point that drifts after the player while she is in its arena.
	var player := enemy.get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null and enemy._in_arena(player.global_position):
		var goal := Vector2(player.global_position.x, enemy._home_position.y)
		enemy._home_position = enemy._clamp_to_arena(
			enemy._home_position.move_toward(goal, VENT_FLYER_CHASE * delta)
		)
	var previous := enemy.global_position
	enemy.global_position = (
		enemy._home_position + Vector2(sin(enemy._age * 1.9) * 180.0, sin(enemy._age * 3.1) * 64.0)
	)
	enemy.velocity = (enemy.global_position - previous) / maxf(delta, 0.0001)
	enemy.global_position = previous


static func armored_guard(enemy: CombatEnemy) -> void:
	var delta := enemy.get_physics_process_delta_time()
	enemy.velocity.y = (
		0.0 if enemy.is_on_floor() else enemy.velocity.y + CombatEnemy.GROUND_GRAVITY * delta
	)
	enemy._special_timer = maxf(enemy._special_timer - delta, 0.0)
	match enemy._special_state:
		&"windup":
			enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, 3000.0 * delta)
			if enemy._special_timer <= 0.0:
				enemy._special_state = &"charge"
				enemy._special_timer = GUARD_CHARGE_SECONDS
		&"charge":
			enemy.velocity.x = enemy._patrol_sign * GUARD_CHARGE_SPEED
			if enemy.is_on_wall() or enemy._special_timer <= 0.0:
				enemy._special_state = &"recover"
				enemy._special_timer = GUARD_RECOVER_SECONDS
				enemy._squash = 1.0
		&"recover":
			enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, 2400.0 * delta)
			if enemy._special_timer <= 0.0:
				enemy._special_state = &""
				enemy._attack_timer = GUARD_CHARGE_COOLDOWN
		_:
			enemy.velocity.x = enemy._patrol_sign * GUARD_PATROL_SPEED
			if enemy.is_on_wall() or Placement.at_leash_edge(enemy, enemy._patrol_sign):
				enemy._patrol_sign *= -1.0
			var player := enemy.get_tree().get_first_node_in_group(&"player") as Node2D
			if player != null and enemy._attack_timer <= 0.0 and enemy.is_on_floor():
				var offset := player.global_position - enemy.global_position
				if (
					enemy._in_arena(player.global_position)
					and absf(offset.x) < GUARD_SIGHT.x
					and absf(offset.y) < GUARD_SIGHT.y
				):
					# Lower the head, flash, then charge at the player.
					enemy._patrol_sign = signf(offset.x) if offset.x != 0.0 else enemy._patrol_sign
					enemy._special_state = &"windup"
					enemy._special_timer = GUARD_WINDUP
					enemy._telegraph_remaining = GUARD_WINDUP
					SurpriseSfx.play(enemy, &"guard_charge", -4.0)


static func energy_parasite(enemy: CombatEnemy, target: Vector2) -> void:
	var delta := enemy.get_physics_process_delta_time()
	var offset := target + Vector2(0.0, -50.0) - enemy.global_position
	enemy._special_timer = maxf(enemy._special_timer - delta, 0.0)
	if enemy._special_state == &"lunge":
		if enemy._special_timer <= 0.0:
			enemy._special_state = &""
			enemy._attack_timer = 1.1
		return
	if enemy._special_state == &"windup":
		enemy.velocity = enemy.velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
		if enemy._special_timer <= 0.0:
			enemy._special_state = &"lunge"
			enemy._special_timer = 0.28
			enemy.velocity = enemy._pending_attack_direction * PARASITE_LUNGE_SPEED
		return
	var desired := (
		offset.normalized() * PARASITE_TRACK_SPEED if offset.length() > 28.0 else Vector2.ZERO
	)
	# Swarm spacing: parasites fan out instead of stacking into one blob.
	for other in enemy.get_tree().get_nodes_in_group(&"enemies"):
		var parasite := other as CombatEnemy
		if parasite == null or parasite == enemy or parasite.enemy_id != &"energy_parasite":
			continue
		var away := enemy.global_position - parasite.global_position
		if away.length() < PARASITE_SEPARATION and away.length() > 0.1:
			desired += away.normalized() * (PARASITE_SEPARATION - away.length()) * 5.0
	desired += offset.orthogonal().normalized() * sin(enemy._age * 5.0) * 60.0
	enemy.velocity = enemy.velocity.move_toward(desired, 1200.0 * delta)
	if (
		enemy._attack_timer <= 0.0
		and offset.length() < PARASITE_LUNGE_RANGE
		and enemy._in_arena(target)
	):
		enemy._special_state = &"windup"
		enemy._special_timer = 0.26
		enemy._telegraph_remaining = 0.26
		SurpriseSfx.play(enemy, &"parasite_lunge", -8.0)
		enemy._pending_attack_direction = offset.normalized()


static func burrower(enemy: CombatEnemy, delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	if enemy._burrow_phase == &"mound":
		enemy._burrow_timer -= delta
		var player := enemy.get_tree().get_first_node_in_group(&"player") as Node2D
		if (
			player != null
			and enemy.arena_bounds.size != Vector2.ZERO
			and enemy._in_arena(player.global_position)
			and enemy._telegraph_action.is_empty()
		):
			# The mound tunnels after the player before it bursts out.
			enemy._home_position.x = clampf(
				move_toward(
					enemy._home_position.x,
					player.global_position.x,
					CombatEnemy.BURROWER_TRACK_SPEED * delta
				),
				enemy.arena_bounds.position.x,
				enemy.arena_bounds.end.x
			)
			enemy.global_position.x = enemy._home_position.x
		if enemy._burrow_timer <= 0.0 and enemy._telegraph_action.is_empty():
			enemy._telegraph_remaining = minf(0.65, CombatEnemy.MAX_TELEGRAPH_SECONDS)
			enemy._telegraph_action = &"burrow_emerge"
			enemy._burrow_timer = 2.2
	elif enemy._burrow_phase == &"exposed":
		enemy._burrow_timer -= delta
		if enemy._burrow_timer <= 0.0:
			enemy._burrow_phase = &"retreat"
			enemy._burrow_timer = 0.28
	elif enemy._burrow_phase == &"retreat":
		enemy._burrow_timer -= delta
		enemy.global_position = (
			enemy._home_position + Vector2.UP * maxf(enemy._burrow_timer / 0.28, 0.0) * 46.0
		)
		if enemy._burrow_timer <= 0.0:
			enemy.global_position = enemy._home_position
			enemy._burrow_phase = &"mound"
			enemy._burrow_timer = 0.9


static func grasshopper(
	enemy: CombatEnemy, target: Vector2, has_target: bool, delta: float
) -> void:
	if not has_target:
		enemy._suspend_ai()
		return
	if enemy._special_state == &"landing":
		enemy._special_timer -= delta
		enemy.velocity.x = move_toward(
			enemy.velocity.x, 0.0, CombatEnemy.GRASSHOPPER_GRAVITY * delta
		)
		if enemy._special_timer <= 0.0:
			enemy._special_state = &"skitter"
		return
	if not enemy.is_on_floor():
		enemy._special_state = &"airborne"
		enemy.velocity.y += CombatEnemy.GRASSHOPPER_GRAVITY * delta
		return
	if enemy._special_state == &"airborne":
		enemy._special_state = &"landing"
		enemy._special_timer = 0.2
		enemy.velocity = Vector2.ZERO
		return
	if enemy._special_state == &"compress" and enemy._telegraph_action.is_empty():
		enemy._special_state = &"skitter"  # A hit cancelled the leap.
	enemy.velocity.x = (
		signf(target.x - enemy.global_position.x) * CombatEnemy.GRASSHOPPER_SKITTER_SPEED
	)
	if enemy._jump_timer <= 0.0 and enemy._telegraph_action.is_empty():
		enemy._special_state = &"compress"
		enemy._telegraph_remaining = 0.34
		enemy._pending_attack_direction = Vector2(
			signf(target.x - enemy.global_position.x) * CombatEnemy.GRASSHOPPER_LEAP.x,
			CombatEnemy.GRASSHOPPER_LEAP.y,
		)
		enemy._telegraph_action = &"grasshopper_leap"
		enemy._jump_timer = CombatEnemy.GRASSHOPPER_LEAP_INTERVAL
		enemy.velocity = Vector2.ZERO


static func lava_monster(
	enemy: CombatEnemy, target: Vector2, has_target: bool, delta: float
) -> void:
	enemy._special_timer = maxf(enemy._special_timer - delta, 0.0)
	match enemy._special_state:
		&"submerged":
			# The bubble line creeps toward the player under the crust before surfacing.
			var dx := target.x - enemy.global_position.x
			enemy.velocity = Vector2(
				signf(dx) * CombatEnemy.LAVA_STALK_SPEED if has_target and absf(dx) > 24.0 else 0.0,
				0.0
			)
			if has_target and enemy._special_timer <= 0.0:
				enemy._special_state = &"bubbling"
				enemy._special_timer = 0.7
		&"bubbling":
			enemy.velocity = Vector2.ZERO
			if enemy._special_timer <= 0.0:
				enemy._set_lava_surface_active(true)
				enemy._special_state = &"surface"
				enemy._special_timer = CombatEnemy.LAVA_ACTIVE_SECONDS
		&"surface":
			enemy.velocity.x = (
				signf(target.x - enemy.global_position.x) * 300.0 if has_target else 0.0
			)
			if enemy._special_timer <= 0.0 and not enemy._player_overlaps_body():
				enemy._set_lava_surface_active(false)
				enemy._special_state = &"submerged"
				enemy._special_timer = 0.9


## Ceiling Diver: winds up, dives at the player's last position until it reaches her height, the
## floor or the arena edge, then climbs back to its perch. The dive is tracked as state rather than
## as distance from the perch, because the first dive frame only covers a few pixels.
static func ceiling_diver(enemy: CombatEnemy, target: Vector2) -> void:
	var delta := enemy.get_physics_process_delta_time()
	match enemy._special_state:
		&"diving":
			if not enemy._telegraph_action.is_empty():
				enemy.velocity = Vector2.ZERO
			elif (
				enemy.global_position.y >= enemy._dive_target_y
				or enemy.is_on_floor()
				or enemy.get_real_velocity().y <= 0.0
			):
				enemy._special_state = &"returning"
		&"returning":
			var to_home := enemy._home_position - enemy.global_position
			if to_home.length() <= CombatEnemy.DIVER_RETURN_SPEED * delta or enemy.is_on_ceiling():
				enemy.global_position = enemy._home_position
				enemy.velocity = Vector2.ZERO
				enemy._special_state = &""
			else:
				enemy.velocity = to_home.normalized() * CombatEnemy.DIVER_RETURN_SPEED
		_:
			enemy.velocity = Vector2.ZERO
			if enemy._attack_timer > 0.0 or not enemy._telegraph_action.is_empty():
				return
			enemy._dive_target_y = enemy._clamp_to_arena(target).y
			var fall_time := maxf(enemy._dive_target_y - enemy.global_position.y, 1.0)
			fall_time /= CombatEnemy.DIVER_DIVE.y
			enemy._pending_attack_direction = Vector2(
				clampf(
					(target.x - enemy.global_position.x) / fall_time,
					-CombatEnemy.DIVER_DIVE.x,
					CombatEnemy.DIVER_DIVE.x
				),
				CombatEnemy.DIVER_DIVE.y
			)
			enemy._telegraph_remaining = minf(0.3, CombatEnemy.MAX_TELEGRAPH_SECONDS)
			enemy._telegraph_action = &"ceiling_dive"
			enemy._special_state = &"diving"
			enemy._attack_timer = CombatEnemy.DIVER_COOLDOWN
			SurpriseSfx.play(enemy, &"diver_screech", -8.0)
