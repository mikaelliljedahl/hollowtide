extends RefCounted
## Ember Fan case of the boss rework check (tools/check_boss_rework.gd runs it in its arena). The
## first ember flies on the locked aim line and the rest fan out above it, so a curled ball clears
## the fan at any range. Jev round 7 probe in kiln_03 (docs/features/boss-rework.md, Cinder
## Warden): with the fan centred on the aim line, no response of 20 at any of 17 start times
## cleared the stage 3 and 4 fan 212 to 244 px from the Warden, where its lower embers crossed her
## column 7 to 16 px above the floor.

const Attacks = preload("res://scripts/enemies/boss_attacks.gd")
const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
## Feet 212 px from the Warden's centre on its floor, as at the r6-min-s1b stage 3 hits.
const DISTANCE := 212.0
## The player's hurtbox standing and curled into a ball.
const STANDING := Vector2(56, 176)
const CURLED := Vector2(56, 56)
const FAN_FRAMES := 150
## The arena floor of tools/check_boss_rework.gd.
const FLOOR_Y := 1000.0

var _host: Node


class Body:
	extends CharacterBody2D
	var hits := 0

	func _init(size: Vector2) -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = size
		shape.shape = box
		# The origin is the feet, as on the player.
		shape.position = Vector2(0, -size.y * 0.5)
		add_child(shape)

	func take_damage(_amount: int, _source := Vector2.ZERO) -> void:
		hits += 1


## `host` is the check scene: it owns `_check`, `_probe`, `_spawn_in_arena` and `_despawn`.
func _init(host: Node) -> void:
	_host = host


func run() -> void:
	var boss: CombatBoss = _host.call(&"_spawn_in_arena", &"furnace_mother")
	await _frames(1)
	for stage in [1, Patterns.ARMORED_STAGE, Patterns.DESPERATION_STAGE]:
		boss.set_test_stage(stage)
		var plan := Attacks.plan(boss, &"ember_fan")
		var aim: Vector2 = plan["aim"]
		var above := true
		for direction: Vector2 in plan["directions"]:
			above = above and aim.angle_to(direction) * signf(aim.x) <= 0.001
		_check(
			above and absf(aim.angle_to(plan["directions"][0])) < 0.001,
			"ember fan stage %d: first ember on the aim line, the rest above it" % stage
		)
	_host.call(&"_despawn", boss)
	await _frames(2)
	# The check's own probe stands in the player group; the fan aims at the first member.
	var probe: Node = _host.get("_probe")
	probe.remove_from_group(&"player")
	for stage in [Patterns.ARMORED_STAGE, Patterns.DESPERATION_STAGE]:
		var curled := await _fan_hits(stage, CURLED)
		_check(
			curled == 0,
			"a curled ball 212 px away clears the stage %d fan (%d hits)" % [stage, curled]
		)
		var standing := await _fan_hits(stage, STANDING)
		_check(standing > 0, "the stage %d fan still hits her standing there" % stage)
	probe.add_to_group(&"player")


## Hits a body of `size` takes, feet DISTANCE px from a real Warden forced into one Ember Fan.
func _fan_hits(stage: int, size: Vector2) -> int:
	var boss: CombatBoss = _host.call(&"_spawn_in_arena", &"furnace_mother")
	var body := Body.new(size)
	_host.add_child(body)
	body.add_to_group(&"player")
	body.global_position = Vector2(boss.global_position.x + DISTANCE, FLOOR_Y)
	await _frames(2)
	boss.set_test_stage(stage)
	var chain: Array[StringName] = [&"ember_fan"]
	boss.set("_attack_chain", chain)
	boss.call(&"_start_telegraph")
	for _frame in FAN_FRAMES:
		await _frames(1)
		if boss.get("_attack_state") == &"recover":
			boss.set_physics_process(false)
	var hits := body.hits
	body.queue_free()
	_host.call(&"_despawn", boss)
	await _frames(2)
	return hits


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)
