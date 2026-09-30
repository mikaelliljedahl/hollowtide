extends Node

## Mini-bosses (docs/features/mini-bosses.md): the shared rules for every fightable mini-boss (two
## stages, M1 then M2, telegraph and punish floors, pacing, stage transition, engagement, pocket
## fairness, attack cycles), that the four-stage bosses are unchanged, the `mini:<id>` flag, flag
## gate and save round trip, and the layout. Per-boss cases live in tools/mini_cases/<id>.gd and
## run for every id that has a rotation; a boss added later only adds its case file.
## godot --headless --path . res://tools/check_mini_bosses.tscn -- --test-mode

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")
const Mini = preload("res://scripts/enemies/mini_boss_patterns.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const MiniSpawnScript = preload("res://scripts/campaign/mini_boss_spawn.gd")
const FlagGateScript = preload("res://scripts/campaign/flag_gate.gd")
const MAIN_BOSSES: Array[StringName] = [&"stone_guardian", &"furnace_mother", &"tidal_heart"]
const ARENA := Rect2(0.0, 300.0, 2000.0, 700.0)
const FLOOR_Y := 1000.0
const PHYSICS_HZ := 60.0
const MIN_TELEGRAPH := 0.45
const MIN_PUNISH_BY_STAGE := [1.2, 1.4]
const HARPOON_EVERY_FRAMES := 21
const STAGE_TIMEOUT_FRAMES := 60 * 40
## A player landing a Harpoon in every opening: spec target 25-45 s; the openings and windows in the
## spec add up to about 15 s, so the floor asserts that a fight is not a burst (see mini-bosses.md).
const MIN_FIGHT_SECONDS := 12.0
const MAX_FIGHT_SECONDS := 45.0

var failures: Array[String] = []
var probe: Probe
var events: Array[Dictionary] = []
var boss_under_test: CombatBoss


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
	_registry_rules()
	_main_bosses_unchanged()
	_layout()
	await _flags_and_save()
	_build_arena()
	get_tree().node_added.connect(_on_node_added)
	var ids := Mini.implemented_ids()
	check(ids.has(&"fernmaw"), "fernmaw is fightable")
	for boss_id in ids:
		await _stage_transition(boss_id)
		await _transition_shuts_window(boss_id)
		await _protection_rows(boss_id)
		await _fight_pacing(boss_id)
		await _engagement(boss_id)
		await _charge_pockets(boss_id)
		for stage in [1, 2]:
			await _attack_cycle(boss_id, stage)
		var path := "res://tools/mini_cases/%s.gd" % String(boss_id)
		if ResourceLoader.exists(path):
			await (load(path) as GDScript).new().run(self, boss_id)
		else:
			check(false, "%s has a case file" % boss_id)
	get_tree().node_added.disconnect(_on_node_added)
	for failure in failures:
		print("FAIL ", failure)
	print("mini-bosses: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		failures.append(label)


func frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func seconds_between(from_frame: int, to_frame: int) -> float:
	return float(to_frame - from_frame) / PHYSICS_HZ


# --- rules ---------------------------------------------------------------------------------


func _registry_rules() -> void:
	check(Mini.ids().size() == 5, "the registry knows five mini-bosses")
	check(
		Catalog.MINI_BOSS_IDS == Mini.ids(),
		"the catalog and the registry list the same ids in the same order"
	)
	check(Patterns.stage_count(&"fernmaw") == 2, "a mini-boss has two stages")
	check(Patterns.stage_count(&"stone_guardian") == 4, "a main boss keeps four stages")
	var cases := [[100, 1], [51, 1], [50, 2], [1, 2]]
	for boss_id in Mini.ids():
		check(Catalog.BOSS_DATA.has(boss_id), "%s has catalog stats" % boss_id)
		check(
			Catalog.DISPLAY_NAMES.get(boss_id, "") == String(boss_id).capitalize(),
			"%s has a player-visible name" % boss_id
		)
		var data: Dictionary = Catalog.BOSS_DATA[boss_id]
		var main_min_health := 300
		check(
			int(data["max_health"]) < main_min_health and int(data["contact_damage"]) < 24,
			"%s health and contact sit below the main bosses" % boss_id
		)
		for case in cases:
			var stage := Patterns.stage_for(int(case[0]), 100, boss_id)
			check(stage == int(case[1]), "%s: %d%% health is stage %d" % [boss_id, case[0], stage])
		check(Patterns.protection_phase(1, boss_id) == 1, "%s stage 1 uses M1" % boss_id)
		check(Patterns.protection_phase(2, boss_id) == 2, "%s stage 2 uses M2" % boss_id)
		check(
			(
				Patterns.stage_floor(1, 200, boss_id) == 100
				and Patterns.stage_floor(2, 200, boss_id) == 0
			),
			"%s stage 1 ends at half health" % boss_id
		)
		var share := Patterns.opening_damage(int(data["max_health"]), boss_id)
		check(
			share * 3 >= int(data["max_health"]) / 2 and share * 2 < int(data["max_health"]) / 2,
			"%s three openings clear a stage (opening %d)" % [boss_id, share]
		)
	for boss_id in Mini.implemented_ids():
		var stage_one := Patterns.attacks_in_stage(boss_id, 1)
		var stage_two := Patterns.attacks_in_stage(boss_id, 2)
		var added := stage_two.filter(func(a: StringName) -> bool: return not stage_one.has(a))
		check(added.size() == 1, "%s stage 2 adds exactly one attack (%s)" % [boss_id, added])
		check(
			stage_two.size() == stage_one.size() + 1,
			"%s stage 2 keeps every stage 1 attack" % boss_id
		)
		var chained := 0
		for index in 6:
			if Patterns.chain_at(boss_id, 2, index).size() > 1:
				chained += 1
		check(chained == 1, "%s stage 2 cycle has one chain" % boss_id)
		check(
			(
				is_equal_approx(Patterns.idle_seconds(1, boss_id), 1.1)
				and is_equal_approx(Patterns.idle_seconds(2, boss_id), 0.8)
			),
			"%s idles 1.1 s then 0.8 s between chains" % boss_id
		)
		for stage in [1, 2]:
			for attack in Patterns.attacks_in_stage(boss_id, stage):
				var telegraph := Patterns.telegraph_seconds(attack, stage)
				var punish := Patterns.punish_seconds(attack, stage, boss_id)
				check(
					telegraph >= MIN_TELEGRAPH and punish >= float(MIN_PUNISH_BY_STAGE[stage - 1]),
					(
						"%s %s stage %d telegraph %.2f s, punish %.2f s"
						% [boss_id, attack, stage, telegraph, punish]
					)
				)


func _main_bosses_unchanged() -> void:
	var cases := [[100, 1], [76, 1], [75, 2], [51, 2], [50, 3], [26, 3], [25, 4], [1, 4]]
	for case in cases:
		check(
			(
				Patterns.stage_for(int(case[0]), 100) == int(case[1])
				and Patterns.stage_for(int(case[0]), 100, &"stone_guardian") == int(case[1])
			),
			"main boss: %d%% health is stage %d" % [case[0], case[1]]
		)
	check(Patterns.opening_damage(300) == 19, "main boss opening share is unchanged")
	check(Patterns.stage_floor(3, 400) == 100 and Patterns.stage_floor(4, 400) == 0, "floors")
	check(
		Patterns.protection_phase(2) == 1 and Patterns.protection_phase(3) == 2,
		"main boss protection rows are unchanged"
	)
	check(
		Patterns.idle_seconds(3) == 0.8 and Patterns.idle_seconds(3, &"tidal_heart") == 0.8,
		"main boss idle time is unchanged"
	)
	for boss_id in MAIN_BOSSES:
		check(not Patterns.is_mini(boss_id), "%s is not a mini-boss" % boss_id)
		check(Patterns.stage_count(boss_id) == 4, "%s keeps four stages" % boss_id)
		check(
			Patterns.attacks_in_stage(boss_id, 4).size() >= 3,
			"%s keeps its stage 4 rotation" % boss_id
		)
	check(
		Catalog.BOSS_IDS == MAIN_BOSSES and not Catalog.BOSS_IDS.has(&"fernmaw"),
		"mini-bosses are not in the main boss list"
	)


# --- layout, flags, save -----------------------------------------------------------------------


func _layout() -> void:
	var room := FileAccess.get_file_as_string("res://scenes/campaign/rooms/fringe_08.tscn")
	check(room.contains("mini_boss_spawn.gd"), "fringe_08 builds a mini-boss spawn")
	check(room.contains('boss_id = &"fernmaw"'), "fringe_08 holds Fernmaw")
	check(not room.contains("ambush"), "fringe_08 has no ambush zone")
	check(room.contains('"mini:fernmaw"'), "fringe_08 seals its cache behind mini:fernmaw")
	var layout := FileAccess.get_file_as_string("res://scenes/campaign/layouts/fringe_08.txt")
	check(
		layout.contains("miniboss fernmaw arena=") and not layout.contains("ambush:"),
		"the fringe_08 layout has one miniboss entry and no ambush"
	)
	var index := FileAccess.get_file_as_string("res://scripts/campaign/campaign_rooms.gd")
	check(
		not index.contains('"kind": &"miniboss"'), "a mini-boss is not a boss gate for the solver"
	)


func _flags_and_save() -> void:
	GameState.reset_progress()
	var holder := Node2D.new()
	add_child(holder)
	var room := Node2D.new()
	var script := GDScript.new()
	script.source_code = 'extends Node2D\nvar room_id := "fringe_08"\n'
	script.reload()
	room.set_script(script)
	holder.add_child(room)
	var entities := Node2D.new()
	room.add_child(entities)
	var marker := _mini_marker(entities)
	await frames(3)
	var boss := marker.get("boss") as CombatBoss
	check(boss != null and boss.enemy_id == &"fernmaw", "an unbeaten room spawns Fernmaw")
	check(marker.call("flag_id") == "mini:fernmaw", "the flag is mini:fernmaw")
	check(boss.is_in_group(&"bosses"), "a mini-boss is a boss for music and combat locks")
	var gate := FlagGateScript.new()
	gate.set("required_flags", PackedStringArray(["mini:fernmaw"]))
	gate.set("gate_size", Vector2(64, 128))
	holder.add_child(gate)
	await frames(2)
	check(not bool(gate.get("is_open")), "a flaggate on mini:fernmaw is shut before the fight")
	boss.set_test_stage(2)
	boss.health = 1
	boss.call("_open_punish_window", 1.5)
	boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {})
	await frames(2)
	check(boss.health == 0, "the last Harpoon kills Fernmaw")
	check(GameState.has_world_flag("mini:fernmaw"), "defeat sets mini:fernmaw")
	gate.call("refresh", false)
	check(bool(gate.get("is_open")), "the flaggate opens once mini:fernmaw is set")
	var stray := false
	for key in GameState.world_flags:
		if String(key).begins_with("boss:") or String(key).begins_with("regional:"):
			stray = true
	check(not stray, "a mini-boss defeat sets no boss: or regional: flag")
	check(not GameState.has_world_flag("boss:fernmaw"), "no boss:fernmaw")
	# Save round trip: the flag rides in the free-form world flag set, no schema change.
	var saved := GameState.snapshot()
	check(saved["world_flags"].get("mini:fernmaw", false), "the snapshot carries mini:fernmaw")
	GameState.reset_progress()
	check(not GameState.has_world_flag("mini:fernmaw"), "a fresh game lacks the flag")
	check(GameState.restore_snapshot(saved), "a save with a mini: flag loads on this build")
	check(GameState.has_world_flag("mini:fernmaw"), "reload keeps mini:fernmaw")
	check(
		not saved.has("mini_bosses") and not saved.has("mini_flags"),
		"no new save keys were added for mini-bosses"
	)
	var old_save := saved.duplicate(true)
	(old_save["world_flags"] as Dictionary).erase("mini:fernmaw")
	check(GameState.restore_snapshot(old_save), "a save without mini: flags loads unchanged")
	GameState.restore_snapshot(saved)
	# Reload: the marker of a beaten room does not spawn again.
	var marker_two := _mini_marker(entities)
	await frames(3)
	check(marker_two.get("boss") == null, "a beaten mini-boss does not respawn")
	holder.queue_free()
	await frames(2)
	GameState.reset_progress()


func _mini_marker(parent: Node) -> Marker2D:
	var marker := Marker2D.new()
	marker.set_script(MiniSpawnScript)
	marker.set("boss_id", &"fernmaw")
	marker.set("arena", ARENA)
	marker.set("return_point", Vector2(200.0, FLOOR_Y))
	marker.position = Vector2(700.0, FLOOR_Y - 92.0)
	parent.add_child(marker)
	return marker


# --- fights ------------------------------------------------------------------------------------


## A hit across the half mark drops a wind-up unfired, gives a 1.0 s breather and carries no
## damage into stage 2.
func _stage_transition(boss_id: StringName) -> void:
	var boss := spawn_in_arena(boss_id)
	await frames(1)
	for _frame in 400:
		if boss.get("_attack_state") == &"telegraph":
			break
		await frames(1)
	check(boss.get("_attack_state") == &"telegraph", "%s starts a telegraph" % boss_id)
	var released := [false]
	boss.attack_released.connect(func(_attack: StringName) -> void: released[0] = true)
	var before := live_projectiles()
	var floor_health := Patterns.stage_floor(1, boss.max_health, boss_id)
	boss.health = floor_health + 1
	boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {})
	check(boss.stage == 2 and boss.phase == 2, "%s a hit across 50%% enters stage 2 (M2)" % boss_id)
	check(boss.health == floor_health, "%s no damage carries past the stage floor" % boss_id)
	check(
		boss.get("_attack_state") == &"idle" and float(boss.get("_telegraph_remaining")) == 0.0,
		"%s the transition drops the telegraph" % boss_id
	)
	await frames(int(Patterns.STAGE_BREATHER * PHYSICS_HZ) - 2)
	check(
		not released[0] and live_projectiles() == before,
		"%s the 1.0 s breather fires nothing" % boss_id
	)
	despawn(boss)
	await frames(2)


func _transition_shuts_window(boss_id: StringName) -> void:
	var boss := spawn_in_arena(boss_id)
	await frames(1)
	boss.health = Patterns.stage_floor(1, boss.max_health, boss_id) + 1
	boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {})
	var reaction := boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {})
	check(reaction == HitResult.Reaction.BLOCKED, "%s stage 2 starts shut" % boss_id)
	boss.call("_open_punish_window", 1.5)
	check(
		boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {}) == HitResult.Reaction.DAMAGE,
		"%s the first punish window opens it" % boss_id
	)
	despawn(boss)
	await frames(2)


func _protection_rows(boss_id: StringName) -> void:
	var boss := spawn_in_arena(boss_id)
	await frames(1)
	boss.call("_open_punish_window", 1.5)
	boss.set("_opening_damage", 50)
	for kind in [&"beam", &"base", &"missile", &"wave"]:
		check(boss.is_vulnerable_to(kind), "%s M1 is hurt by %s in an opening" % [boss_id, kind])
	for kind in [&"ice", &"bomb", &"undertow"]:
		check(not boss.is_vulnerable_to(kind), "%s M1 glances %s" % [boss_id, kind])
	boss.set_test_stage(2)
	check(not boss.is_vulnerable_to(&"missile"), "%s M2 is shut outside a punish window" % boss_id)
	boss.call("_open_punish_window", 1.5)
	check(boss.is_vulnerable_to(&"missile"), "%s M2 takes a Harpoon in the window" % boss_id)
	for kind in [&"beam", &"base", &"wave", &"ice", &"bomb", &"undertow"]:
		check(
			not boss.is_vulnerable_to(kind), "%s M2 glances %s even in the window" % [boss_id, kind]
		)
	# Seed Bolts alone cannot finish stage 2: the health never moves.
	var health := boss.health
	for _hit in 30:
		boss.receive_hit(Catalog.BEAM_DAMAGE, &"beam", {})
	check(boss.health == health, "%s Seed Bolts alone cannot finish stage 2" % boss_id)
	despawn(boss)
	await frames(2)


## A Harpoon in every opening: attacks in both stages and a fight that is not a burst.
func _fight_pacing(boss_id: StringName) -> void:
	var boss := spawn_in_arena(boss_id)
	await frames(1)
	var released := {1: 0, 2: 0}
	boss.attack_released.connect(func(_attack: StringName) -> void: released[boss.stage] += 1)
	var count := 0
	var cooldown := 0
	while boss.health > 0 and count < 60 * 150:
		await frames(1)
		count += 1
		cooldown -= 1
		if cooldown <= 0 and boss.is_vulnerable_to(&"missile"):
			boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {})
			cooldown = HARPOON_EVERY_FRAMES
	var elapsed := count / PHYSICS_HZ
	check(boss.health == 0, "%s falls to perfect Harpoon play (%.1f s)" % [boss_id, elapsed])
	check(
		elapsed >= MIN_FIGHT_SECONDS and elapsed <= MAX_FIGHT_SECONDS,
		(
			"%s takes %.0f to %.0f s (%.1f s)"
			% [boss_id, MIN_FIGHT_SECONDS, MAX_FIGHT_SECONDS, elapsed]
		)
	)
	check(
		released[1] > 0 and released[2] > 0,
		"%s attacks in both stages before it falls (%s)" % [boss_id, released]
	)
	despawn(boss)
	await frames(2)


## With the player outside the arena the boss takes no damage and starts no attack.
func _engagement(boss_id: StringName) -> void:
	var boss := spawn_in_arena(boss_id)
	probe.global_position = Vector2(-600.0, FLOOR_Y - 88.0)
	await frames(2)
	var telegraphed := [false]
	boss.attack_telegraphed.connect(func(_attack: StringName) -> void: telegraphed[0] = true)
	var health := boss.health
	var reaction := boss.receive_hit(Catalog.MISSILE_DAMAGE, &"missile", {})
	check(
		reaction == HitResult.Reaction.BLOCKED and boss.health == health,
		"%s takes no damage with the player outside the arena" % boss_id
	)
	await frames(int(3.0 * PHYSICS_HZ))
	check(not telegraphed[0], "%s starts no attack with the player outside" % boss_id)
	despawn(boss)
	probe.global_position = Vector2(1500.0, FLOOR_Y - 88.0)
	await frames(2)


func _charge_pockets(boss_id: StringName) -> void:
	var obstacles := {
		"low roof": [Vector2(1850.0, 775.0), Vector2(300.0, 150.0)],
		"step": [Vector2(1850.0, FLOOR_Y - 64.0), Vector2(300.0, 128.0)],
	}
	var charges: Array[StringName] = []
	for stage in [1, 2]:
		for attack in Patterns.attacks_in_stage(boss_id, stage):
			if Patterns.is_charge(attack) and not charges.has(attack):
				charges.append(attack)
	for attack in charges:
		for obstacle: String in obstacles:
			var piece: Array = obstacles[obstacle]
			var wall := static_box(piece[0], piece[1])
			await _charge_stops_short(boss_id, attack, obstacle)
			wall.queue_free()
			await frames(2)
	# Pursuit stops at the same pocket, so a cornered player is never walked into.
	for obstacle: String in obstacles:
		var piece: Array = obstacles[obstacle]
		var wall := static_box(piece[0], piece[1])
		var boss := spawn_in_arena(boss_id)
		boss.global_position.x = 1100.0
		probe.global_position = Vector2(1700.0 - 30.0, FLOOR_Y - 88.0)
		await frames(2)
		boss.set_test_stage(2)
		probe.hits.clear()
		var reach := boss.global_position.x
		for _frame in int(4.0 * PHYSICS_HZ):
			boss.set("_attack_timer", 10.0)
			await frames(1)
			reach = maxf(reach, boss.global_position.x)
		var stop := 1700.0 - Attacks.BODY_RADIUS - Attacks.CHARGE_WALL_POCKET
		check(
			reach > 1300.0 and reach <= stop + 4.0,
			"%s walks to the pocket at a %s (x %.0f)" % [boss_id, obstacle, reach]
		)
		check(probe.hits.is_empty(), "%s walk leaves a player at a %s unhurt" % [boss_id, obstacle])
		despawn(boss)
		wall.queue_free()
		probe.global_position = Vector2(1500.0, FLOOR_Y - 88.0)
		await frames(2)


func _charge_stops_short(boss_id: StringName, attack: StringName, obstacle: String) -> void:
	var label := "%s %s at a %s" % [boss_id, attack, obstacle]
	var boss := spawn_in_arena(boss_id)
	boss.global_position.x = 900.0
	probe.global_position = Vector2(1700.0 - 30.0, FLOOR_Y - 88.0)
	await frames(2)
	probe.hits.clear()
	boss.set_test_stage(2)
	var chain: Array[StringName] = [attack]
	boss.set("_attack_chain", chain)
	boss.call("_start_telegraph")
	var end_x := float((boss.get("_attack_plan") as Dictionary)["charge_end_x"])
	check(
		end_x <= 1700.0 - Attacks.BODY_RADIUS - Attacks.CHARGE_WALL_POCKET + 0.5,
		"%s plans its stop a pocket short of the face (end %.0f)" % [label, end_x]
	)
	for _frame in int(3.0 * PHYSICS_HZ):
		await frames(1)
		if boss.get("_attack_state") == &"recover":
			break
	check(
		boss.global_position.x <= end_x + 4.0 and boss.global_position.x > 1200.0,
		"%s runs to its planned stop (x %.0f)" % [label, boss.global_position.x]
	)
	check(probe.hits.is_empty(), "%s leaves a player backed against the face unhurt" % label)
	despawn(boss)
	probe.global_position = Vector2(1500.0, FLOOR_Y - 88.0)
	await frames(2)


func _attack_cycle(boss_id: StringName, stage: int) -> void:
	var boss := spawn_in_arena(boss_id)
	await frames(1)
	boss.set_test_stage(stage)
	events.clear()
	var label := "%s stage %d" % [boss_id, stage]
	var expected := Patterns.attacks_in_stage(boss_id, stage)
	var released: Array[StringName] = []
	boss.attack_telegraphed.connect(func(a: StringName) -> void: log_event(&"telegraph", a))
	boss.attack_released.connect(func(a: StringName) -> void: log_event(&"release", a))
	var state: StringName = boss.get("_attack_state")
	var recover_frame := -1
	var recover_attack := &""
	var armored_ok := true
	for _frame in STAGE_TIMEOUT_FRAMES:
		await frames(1)
		var now: StringName = boss.get("_attack_state")
		if now == &"recover" and state != &"recover":
			recover_frame = Engine.get_physics_frames()
			recover_attack = boss.get("_attack_id")
		if now == &"idle" and state == &"recover":
			var punished := seconds_between(recover_frame, Engine.get_physics_frames())
			var wanted := Patterns.punish_seconds(recover_attack, stage, boss_id)
			check(
				punished >= wanted - 0.02 and punished >= float(MIN_PUNISH_BY_STAGE[stage - 1]),
				"%s %s punish window %.2f s" % [label, recover_attack, punished]
			)
		if stage == 2:
			var open := boss.is_vulnerable_to(&"missile")
			if now == &"telegraph" and open:
				armored_ok = false
			if now == &"recover" and not open:
				armored_ok = false
		state = now
		for event in events:
			if event["kind"] == &"release" and not released.has(event["attack"]):
				released.append(event["attack"])
		if released.size() == expected.size() and now == &"idle":
			break
	check(
		released.size() == expected.size(),
		"%s releases every attack %s (got %s)" % [label, expected, released]
	)
	_check_telegraph_order(label)
	if stage == 2:
		check(
			armored_ok, "%s armor is open in every punish window and shut while winding up" % label
		)
	despawn(boss)
	await frames(2)


func _check_telegraph_order(label: String) -> void:
	var telegraph_frame := -1
	var telegraph_attack := &""
	var active := false
	var ok := true
	var shortest := INF
	var projectiles := 0
	for event in events:
		match event["kind"]:
			&"telegraph":
				telegraph_frame = event["frame"]
				telegraph_attack = event["attack"]
				active = false
			&"release":
				var waited := seconds_between(telegraph_frame, int(event["frame"]))
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
	check(ok, "%s every release follows its own telegraph (shortest %.2f s)" % [label, shortest])
	check(
		projectiles > 0, "%s projectiles appear only after release (%d seen)" % [label, projectiles]
	)


# --- helpers (public: per-boss case files use them) ---------------------------------------------


func _build_arena() -> void:
	var pieces := [
		[Vector2(1000.0, FLOOR_Y + 32.0), Vector2(2400.0, 64.0)],
		[Vector2(-32.0, 650.0), Vector2(64.0, 800.0)],
		[Vector2(2032.0, 650.0), Vector2(64.0, 800.0)],
	]
	for piece in pieces:
		static_box(piece[0], piece[1])
	probe = Probe.new()
	add_child(probe)
	probe.global_position = Vector2(1500.0, FLOOR_Y - 88.0)


func spawn_in_arena(boss_id: StringName) -> CombatBoss:
	var boss := EnemyFactory.create(boss_id) as CombatBoss
	add_child(boss)
	boss.global_position = Vector2(700.0, FLOOR_Y - 92.0)
	boss.configure_arena(ARENA)
	boss_under_test = boss
	return boss


func despawn(boss: CombatBoss) -> void:
	boss.queue_free()
	boss_under_test = null
	for node in get_tree().get_nodes_in_group(&"transient"):
		node.queue_free()


func static_box(center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = center
	return body


func live_projectiles() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"transient"):
		if node is EnemyProjectile and not node.is_queued_for_deletion():
			count += 1
	return count


func log_event(kind: StringName, attack: StringName) -> void:
	events.append({"kind": kind, "attack": attack, "frame": Engine.get_physics_frames()})


func _on_node_added(node: Node) -> void:
	if node is EnemyProjectile and is_instance_valid(boss_under_test):
		(
			events
			. append(
				{
					"kind": &"projectile",
					"state": boss_under_test.get("_attack_state"),
					"frame": Engine.get_physics_frames(),
				}
			)
		)
