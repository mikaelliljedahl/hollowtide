extends RefCounted
## CombatBoss body movement inside its arena: idle pursuit/patrol/drift per boss, the still pose
## while telegraphing or punishable, and charge attacks along the lane locked by the plan.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")
const BossVisuals = preload("res://scripts/enemies/effects/boss_visuals.gd")
const GRAVITY := 1800.0
const MAX_FALL := 900.0
const EDGE_MARGIN := 104.0
const FLOOR_MARGIN := 92.0
const TIDAL_SINK_SPEED := 70.0


static func move(boss: CharacterBody2D, delta: float, player: Node2D) -> void:
	var bounds: Rect2 = boss.arena_bounds
	if bounds.size == Vector2.ZERO:
		return
	var left := bounds.position.x + EDGE_MARGIN
	var right := bounds.end.x - EDGE_MARGIN
	var id: StringName = boss.enemy_id
	var state: StringName = boss._attack_state
	var speed := Patterns.move_speed(id, boss.stage)
	if state == &"active" and Patterns.is_charge(boss._attack_id):
		_charge(boss, delta)
	elif state != &"idle":
		_hold(boss, delta)
	else:
		match id:
			&"stone_guardian":
				boss.velocity.x = signf(player.global_position.x - boss.global_position.x) * speed
				_fall_and_slide(boss, delta)
			&"furnace_mother":
				boss._movement_timer -= delta
				var x := boss.global_position.x
				if boss._movement_timer <= 0.0 or x <= left or x >= right:
					boss._movement_direction *= -1.0
					boss._movement_timer = 1.15 if boss.phase == 2 else 1.55
				boss.velocity.x = boss._movement_direction * speed
				_fall_and_slide(boss, delta)
			&"tidal_heart":
				var home: Vector2 = boss._home_position
				var target := Vector2(
					clampf(player.global_position.x, left + 60.0, right - 60.0),
					home.y - 100.0 + sin(boss._age * 1.15) * 110.0
				)
				boss.velocity = (target - boss.global_position).limit_length(speed)
				boss.move_and_slide()
	boss.global_position.x = clampf(boss.global_position.x, left, right)
	boss.global_position.y = clampf(
		boss.global_position.y, bounds.position.y + EDGE_MARGIN, bounds.end.y - FLOOR_MARGIN
	)
	if boss.is_on_wall():
		boss._movement_direction *= -1.0


static func _charge(boss: CharacterBody2D, delta: float) -> void:
	if boss._charge_done:
		_hold(boss, delta)
		return
	var plan: Dictionary = boss._attack_plan
	var direction := float(plan["charge_direction"])
	var end_x := float(plan["charge_end_x"])
	# The last step lands on the planned stop instead of overshooting it by up to a frame.
	var remaining := maxf((end_x - boss.global_position.x) * direction, 0.0)
	boss.velocity.x = direction * minf(Attacks.charge_speed(boss._attack_id), remaining / delta)
	_fall_and_slide(boss, delta)
	if boss.is_on_wall() or (boss.global_position.x - end_x) * direction >= -0.5:
		boss._charge_done = true
		boss.velocity.x = 0.0
		BossVisuals.charge_impact(boss)


## Telegraph and punish poses hold still; Tidal Heart sinks toward its home height instead.
static func _hold(boss: CharacterBody2D, delta: float) -> void:
	if boss.enemy_id == &"tidal_heart":
		var sink := TIDAL_SINK_SPEED if boss._attack_state == &"recover" else 0.0
		var home: Vector2 = boss._home_position
		boss.velocity = Vector2(0.0, clampf(home.y - boss.global_position.y, -sink, sink))
		boss.move_and_slide()
		return
	boss.velocity.x = 0.0
	_fall_and_slide(boss, delta)


static func _fall_and_slide(boss: CharacterBody2D, delta: float) -> void:
	boss.velocity.y = minf(boss.velocity.y + GRAVITY * delta, MAX_FALL)
	boss.move_and_slide()
