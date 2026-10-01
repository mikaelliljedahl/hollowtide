extends RefCounted
## Tollwing case (docs/features/mini-bosses.md 3.2): Toll Ring is eight radial drops with a 60 degree
## gap centred on the player, Shard Drop locks three columns 224 px apart, Peal Lane is a low lane
## with a second stream 0.6 s after the first, Swoop is a charge, nothing is fired before release,
## and stage 2 adds only Peal Lane.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")


func run(suite: Node, boss_id: StringName) -> void:
	if boss_id != &"tollwing":
		return
	var boss: CombatBoss = suite.spawn_in_arena(boss_id)
	await suite.frames(1)
	boss.set_test_stage(2)
	_ring(suite, boss)
	_shards(suite, boss)
	_peal(suite, boss)
	suite.check(Patterns.is_charge(&"swoop"), "tollwing swoop is a charge")
	var stage_1 := Patterns.attacks_in_stage(boss_id, 1)
	var stage_2 := Patterns.attacks_in_stage(boss_id, 2)
	suite.check(
		stage_1.size() == 3
		and stage_1.has(&"toll_ring")
		and stage_1.has(&"shard_drop")
		and stage_1.has(&"swoop"),
		"tollwing stage 1 is Toll Ring, Shard Drop and Swoop"
	)
	suite.check(
		stage_2.size() == 4 and stage_2.has(&"peal_lane") and not stage_1.has(&"peal_lane"),
		"tollwing stage 2 adds only Peal Lane"
	)
	suite.check(int(boss.max_health) == 130 and boss.call("_contact_damage") == 16, "tollwing stats")
	suite.despawn(boss)
	await suite.frames(2)


func _ring(suite: Node, boss: CombatBoss) -> void:
	var plan := Attacks.plan(boss, &"toll_ring")
	var directions: Array = plan["directions"]
	var aim: Vector2 = plan["aim"]
	suite.check(directions.size() == 8, "tollwing toll ring has eight drops (%d)" % directions.size())
	var gap_clear := true
	var nearest := PI
	for direction: Vector2 in directions:
		nearest = minf(nearest, absf(aim.angle_to(direction)))
	gap_clear = nearest >= deg_to_rad(30.0) - 0.001
	suite.check(gap_clear, "tollwing toll ring leaves a 60 degree gap toward the player")
	suite.check(nearest <= deg_to_rad(31.0), "tollwing toll ring gap is no wider than 60 degrees")
	var shots := Attacks.emissions(boss, &"toll_ring", plan)
	suite.check(shots.size() == 8, "tollwing toll ring fires eight shots on release")
	suite.check(suite.live_projectiles() == 0, "tollwing toll ring fires nothing while planned")


func _shards(suite: Node, boss: CombatBoss) -> void:
	var player_x: float = suite.probe.global_position.x
	var plan := Attacks.plan(boss, &"shard_drop")
	var columns: Array = plan["columns"]
	suite.check(columns.size() == 3, "tollwing shard drop locks three columns (%s)" % [columns])
	suite.check(
		columns.has(player_x)
		and columns.has(clampf(player_x - 224.0, 40.0, 1960.0))
		and columns.has(clampf(player_x + 224.0, 40.0, 1960.0)),
		"tollwing shard columns are the player spot and 224 px either side"
	)
	suite.check(
		(plan["marks"] as Array).size() == columns.size(), "tollwing shows a floor mark per column"
	)
	var shots := Attacks.emissions(boss, &"shard_drop", plan)
	var on_columns := shots.size() == columns.size()
	for shot in shots:
		on_columns = on_columns and _near_column(columns, float(shot["origin"].x))
		on_columns = on_columns and float(shot["origin"].y) < float(plan["floor_y"]) - 100.0
	suite.check(on_columns, "tollwing shards fall from above onto the locked columns")
	suite.check(suite.live_projectiles() == 0, "tollwing shard drop fires nothing while planned")


func _peal(suite: Node, boss: CombatBoss) -> void:
	var plan := Attacks.plan(boss, &"peal_lane")
	var marks: Array = plan["marks"]
	suite.check(marks.size() == 1, "tollwing peal lane shows one lane")
	var lane_y: float = (marks[0] as Dictionary)["from"].y
	var floor_y: float = plan["floor_y"]
	suite.check(
		lane_y > floor_y - Attacks.HIGH_LANE_HEIGHT, "tollwing peal lane is low enough to jump"
	)
	var shots := Attacks.emissions(boss, &"peal_lane", plan)
	var first := 0.0
	var second := 0.0
	for shot in shots:
		suite.check(absf(float(shot["origin"].y) - lane_y) < 1.0, "tollwing peal chimes ride the lane")
		if float(shot["at"]) < 0.3:
			first += 1.0
		else:
			second += 1.0
	suite.check(first > 0.0 and first == second, "tollwing peal lane sends two equal streams")
	var last_at := 0.0
	for shot in shots:
		last_at = maxf(last_at, float(shot["at"]))
	suite.check(last_at >= 0.6, "tollwing second stream follows the first by 0.6 s (%.2f)" % last_at)
	suite.check(suite.live_projectiles() == 0, "tollwing peal lane fires nothing while planned")


func _near_column(columns: Array, x: float) -> bool:
	for column: float in columns:
		if absf(column - x) <= 30.0:
			return true
	return false
