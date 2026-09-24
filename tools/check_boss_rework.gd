extends Node

## Boss rework (docs/features/boss-rework.md): stage thresholds and the B1/B2 mapping, stage
## transitions under real hits, the desperation stage, and for every boss and stage that each
## attack telegraphs for at least 0.4 s before any projectile exists, that a punish window follows
## every chain, that B2 armor opens only in it, and that charges move the body along their lane.
## godot --headless --path . res://tools/check_boss_rework.tscn -- --test-mode

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const BOSS_IDS: Array[StringName] = [&"stone_guardian", &"furnace_mother", &"tidal_heart"]
const MIN_TELEGRAPH := 0.4
const MIN_PUNISH := 0.8
const ARENA := Rect2(0.0, 300.0, 2000.0, 700.0)
const FLOOR_Y := 1000.0
const PHYSICS_HZ := 60.0
const STAGE_TIMEOUT_FRAMES := 60 * 40

var _failures: Array[String] = []
var _events: Array[Dictionary] = []
var _boss: CombatBoss
var _probe: Probe


class Probe:
	extends CharacterBody2D
	var hits: Array[int] = []

	func _ready() -> void:
		add_to_group(&"player")
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(56.0, 176.0)
		shape.shape = box
		add_child(shape)

	func take_damage(_amount: int, _source := Vector2.ZERO) -> void:
		hits.append(Engine.get_physics_frames())


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_rules()
	_build_arena()
	get_tree().node_added.connect(_on_node_added)
	for boss_id in BOSS_IDS:
		await _stage_thresholds(boss_id)
	await _transition_cancels_telegraph()
	await _engages_on_floor_line()
	for boss_id in BOSS_IDS:
		for stage in range(1, Patterns.DESPERATION_STAGE + 1):
			await _attack_cycle(boss_id, stage)
	get_tree().node_added.disconnect(_on_node_added)
	for failure in _failures:
		print("FAIL ", failure)
	print("boss-rework: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _seconds(from_frame: int, to_frame: int) -> float:
	return float(to_frame - from_frame) / PHYSICS_HZ


# --- rules -----------------------------------------------------------------------------------


func _rules() -> void:
	var cases := [[100, 1], [76, 1], [75, 2], [51, 2], [50, 3], [26, 3], [25, 4], [1, 4]]
	for case in cases:
		_check(
			Patterns.stage_for(int(case[0]), 100) == int(case[1]),
			"%d%% health is stage %d" % [case[0], case[1]]
		)
	_check(Patterns.protection_phase(2) == 1, "stage 2 keeps B1 protection")
	_check(Patterns.protection_phase(3) == 2, "stage 3 uses B2 protection")
	for boss_id in BOSS_IDS:
		var seen: Array[StringName] = []
		for stage in range(1, Patterns.DESPERATION_STAGE + 1):
			var attacks := Patterns.attacks_in_stage(boss_id, stage)
			var added := attacks.filter(
				func(attack: StringName) -> bool: return not seen.has(attack)
			)
			if stage < Patterns.DESPERATION_STAGE:
				_check(not added.is_empty(), "%s stage %d adds a new pattern" % [boss_id, stage])
			seen.append_array(added)
			for attack in attacks:
				var telegraph := Patterns.telegraph_seconds(attack, stage)
				var punish := Patterns.punish_seconds(attack, stage)
				_check(
					telegraph >= MIN_TELEGRAPH and punish >= MIN_PUNISH,
					(
						"%s %s stage %d telegraph %.2f s, punish %.2f s"
						% [boss_id, attack, stage, telegraph, punish]
					)
				)
		_check(seen.size() >= 4, "%s uses at least four distinct attacks" % boss_id)
		var chains := 0
		for index in 3:
			if Patterns.chain_at(boss_id, Patterns.DESPERATION_STAGE, index).size() > 1:
				chains += 1
		_check(chains > 0, "%s desperation combines patterns into chains" % boss_id)


# --- stage transitions under real hits -------------------------------------------------------


func _stage_thresholds(boss_id: StringName) -> void:
	var boss := EnemyFactory.create(boss_id) as CombatBoss
	add_child(boss)
	boss.global_position = Vector2(1000.0, 600.0)
	await _frames(1)
	var stages: Array[int] = []
	boss.stage_changed.connect(func(stage: int) -> void: stages.append(stage))
	var bursts := int(boss.get("_phase_burst_count"))
	var mismatch := false
	for _hit in 40:
		if boss.health <= 0:
			break
		_open_for_harpoon(boss)
		boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {})
		if boss.health > 0 and boss.stage != Patterns.stage_for(boss.health, boss.max_health):
			mismatch = true
		if boss.health > 0 and boss.phase != Patterns.protection_phase(boss.stage):
			mismatch = true
		if boss.stage == Patterns.DESPERATION_STAGE and boss.health > 0:
			_check(
				float(boss.health) <= float(boss.max_health) * 0.25,
				"%s desperation starts at or below 25%% health" % boss_id
			)
		await _frames(1)
	_check(not mismatch, "%s stage and protection phase follow health after every hit" % boss_id)
	_check(stages == [2, 3, 4], "%s passes stages 2, 3, 4 once each (got %s)" % [boss_id, stages])
	_check(
		int(boss.get("_phase_burst_count")) == bursts + 3,
		"%s each stage transition emits one burst" % boss_id
	)
	_check(boss.health == 0, "%s dies through all four stages" % boss_id)
	boss.queue_free()
	await _frames(2)


## Opens the weak point the way the fight does: Snare or Echo for Tidal Heart, a punish
## window for armored stages.
func _open_for_harpoon(boss: CombatBoss) -> void:
	if boss.enemy_id == &"tidal_heart":
		if boss.phase == 1:
			boss.receive_hit(0, &"ice", {})
		else:
			boss.open_wave_window()
	elif boss.phase == 2:
		boss.call("_open_punish_window", 1.5)


func _transition_cancels_telegraph() -> void:
	var boss := _spawn_in_arena(&"stone_guardian")
	await _frames(1)
	for _frame in 240:
		if boss.get("_attack_state") == &"telegraph":
			break
		await _frames(1)
	_check(boss.get("_attack_state") == &"telegraph", "stone guardian starts a telegraph")
	var released := [false]
	boss.attack_released.connect(func(_attack: StringName) -> void: released[0] = true)
	var projectiles_before := _live_projectiles()
	boss.receive_hit(boss.health - int(boss.max_health * 0.75), &"missile", {})
	_check(boss.stage == 2, "a hit across 75% enters stage 2")
	_check(
		boss.get("_attack_state") == &"idle" and float(boss.get("_telegraph_remaining")) == 0.0,
		"a stage transition drops the telegraph"
	)
	await _frames(int(Patterns.STAGE_BREATHER * PHYSICS_HZ) - 2)
	_check(not released[0], "the dropped attack never fires")
	_check(_live_projectiles() == projectiles_before, "the stage breather fires nothing")
	_despawn(boss)
	await _frames(2)


## Arenas end on the floor line, so a player whose feet stand exactly on it must count as inside:
## the boss engages and attacks, and common enemies treat the same point as inside their leash.
func _engages_on_floor_line() -> void:
	var boss := _spawn_in_arena(&"stone_guardian")
	_probe.global_position = Vector2(1500.0, ARENA.end.y)
	var telegraphed := [false]
	boss.attack_telegraphed.connect(func(_attack: StringName) -> void: telegraphed[0] = true)
	await _frames(int(3.0 * PHYSICS_HZ))
	_check(bool(boss.get("_player_engaged")), "boss engages a player on the arena floor line")
	_check(telegraphed[0], "boss attacks a player on the arena floor line")
	_check(
		not boss.call("_in_arena", Vector2(1500.0, ARENA.end.y + 40.0)),
		"a point well below the arena floor is outside"
	)
	var enemy := EnemyFactory.create(&"hopper") as CombatEnemy
	add_child(enemy)
	enemy.configure_arena(ARENA)
	_check(enemy._in_arena(Vector2(1500.0, ARENA.end.y)), "enemy leash holds the arena floor line")
	enemy.queue_free()
	_despawn(boss)
	_probe.global_position = Vector2(1500.0, FLOOR_Y - 88.0)
	await _frames(2)


# --- attack cycles ---------------------------------------------------------------------------


func _attack_cycle(boss_id: StringName, stage: int) -> void:
	var boss := _spawn_in_arena(boss_id)
	await _frames(1)
	boss.set_test_stage(stage)
	_events.clear()
	var label := "%s stage %d" % [boss_id, stage]
	var expected := Patterns.attacks_in_stage(boss_id, stage)
	var released: Array[StringName] = []
	boss.attack_telegraphed.connect(func(a: StringName) -> void: _log(&"telegraph", a))
	boss.attack_released.connect(func(a: StringName) -> void: _log(&"release", a))
	var state: StringName = boss.get("_attack_state")
	var recover_frame := -1
	var recover_attack := &""
	var release_x := 0.0
	var chained := false
	var armored_ok := true
	var charge_moved := {}
	for _frame in STAGE_TIMEOUT_FRAMES:
		await _frames(1)
		var now: StringName = boss.get("_attack_state")
		var attack: StringName = boss.get("_attack_id")
		if now == &"active" and state == &"telegraph":
			release_x = boss.global_position.x
		if now == &"telegraph" and state == &"active":
			chained = true
		if now == &"recover" and state != &"recover":
			recover_frame = Engine.get_physics_frames()
			recover_attack = attack
			if Patterns.is_charge(attack):
				charge_moved[attack] = absf(boss.global_position.x - release_x) > 150.0
		if now == &"idle" and state == &"recover":
			var punished := _seconds(recover_frame, Engine.get_physics_frames())
			var wanted := Patterns.punish_seconds(recover_attack, stage)
			_check(
				punished >= wanted - 0.02 and punished >= MIN_PUNISH,
				"%s %s punish window %.2f s" % [label, recover_attack, punished]
			)
		if boss.phase == 2 and boss_id != &"tidal_heart":
			var open := boss.is_vulnerable_to(&"missile")
			if now == &"telegraph" and open:
				armored_ok = false
			if now == &"recover" and not open:
				armored_ok = false
		state = now
		for event in _events:
			if event["kind"] == &"release" and not released.has(event["attack"]):
				released.append(event["attack"])
		if released.size() == expected.size() and now == &"idle":
			break
	_check(
		released.size() == expected.size(),
		"%s releases every attack %s (got %s)" % [label, expected, released]
	)
	_check_telegraph_order(label)
	if boss.phase == 2 and boss_id != &"tidal_heart":
		_check(
			armored_ok, "%s armor is open in every punish window and shut while winding up" % label
		)
	if stage == Patterns.DESPERATION_STAGE:
		_check(chained, "%s chains a second telegraph straight after an attack" % label)
	for attack in charge_moved:
		_check(charge_moved[attack], "%s %s carries the body along its lane" % [label, attack])
	_despawn(boss)
	await _frames(2)


func _check_telegraph_order(label: String) -> void:
	var telegraph_frame := -1
	var telegraph_attack := &""
	var active := false
	var ok := true
	var shortest := INF
	var projectiles := 0
	for event in _events:
		match event["kind"]:
			&"telegraph":
				telegraph_frame = event["frame"]
				telegraph_attack = event["attack"]
				active = false
			&"release":
				var waited := _seconds(telegraph_frame, int(event["frame"]))
				shortest = minf(shortest, waited)
				if (
					telegraph_frame < 0
					or event["attack"] != telegraph_attack
					or waited < MIN_TELEGRAPH
				):
					ok = false
				active = true
			&"projectile":
				projectiles += 1
				if not active or event["state"] != &"active":
					ok = false
	_check(ok, "%s every release follows its own telegraph (shortest %.2f s)" % [label, shortest])
	_check(
		projectiles > 0, "%s projectiles appear only after release (%d seen)" % [label, projectiles]
	)


# --- helpers ---------------------------------------------------------------------------------


func _build_arena() -> void:
	var pieces := [
		[Vector2(1000.0, FLOOR_Y + 32.0), Vector2(2400.0, 64.0)],
		[Vector2(-32.0, 650.0), Vector2(64.0, 800.0)],
		[Vector2(2032.0, 650.0), Vector2(64.0, 800.0)],
	]
	for piece in pieces:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = piece[1]
		shape.shape = box
		body.add_child(shape)
		add_child(body)
		body.global_position = piece[0]
	_probe = Probe.new()
	add_child(_probe)
	_probe.global_position = Vector2(1500.0, FLOOR_Y - 88.0)


func _spawn_in_arena(boss_id: StringName) -> CombatBoss:
	var boss := EnemyFactory.create(boss_id) as CombatBoss
	add_child(boss)
	boss.global_position = Vector2(700.0, 600.0 if boss_id == &"tidal_heart" else FLOOR_Y - 92.0)
	boss.configure_arena(ARENA)
	_boss = boss
	return boss


func _despawn(boss: CombatBoss) -> void:
	boss.queue_free()
	_boss = null
	for node in get_tree().get_nodes_in_group(&"transient"):
		node.queue_free()


func _live_projectiles() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"transient"):
		if node is EnemyProjectile and not node.is_queued_for_deletion():
			count += 1
	return count


func _log(kind: StringName, attack: StringName) -> void:
	_events.append({"kind": kind, "attack": attack, "frame": Engine.get_physics_frames()})


func _on_node_added(node: Node) -> void:
	if node is EnemyProjectile and is_instance_valid(_boss):
		(
			_events
			. append(
				{
					"kind": &"projectile",
					"state": _boss.get("_attack_state"),
					"frame": Engine.get_physics_frames(),
				}
			)
		)
