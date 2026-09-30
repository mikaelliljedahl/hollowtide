extends RefCounted
## Rimeweaver case (docs/features/mini-bosses.md 3.3): Needle Line locks one aim line and fires three
## needles along it, Icicle Drop locks three columns 160 px apart, Frost Ring leaves a 77 degree gap
## toward the player and ten shards, Wall Skitter is a charge, stage 2 adds only Frost Ring.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")


func run(suite: Node, boss_id: StringName) -> void:
	if boss_id != &"rimeweaver":
		return
	var boss: CombatBoss = suite.spawn_in_arena(boss_id)
	await suite.frames(1)
	boss.set_test_stage(2)
	var player_x: float = suite.probe.global_position.x
	# Needle Line.
	var plan := Attacks.plan(boss, &"needle_line")
	var directions: Array = plan["directions"]
	suite.check(directions.size() == 1, "rimeweaver needle line shows one aim line")
	var shots := Attacks.emissions(boss, &"needle_line", plan)
	var along := shots.size() == 3
	for shot in shots:
		along = along and (shot["direction"] as Vector2).is_equal_approx(directions[0])
	suite.check(along, "rimeweaver needle line fires three needles along the locked line")
	# Icicle Drop.
	plan = Attacks.plan(boss, &"icicle_drop")
	var columns: Array = plan["columns"]
	suite.check(
		(
			columns.size() == 3
			and columns.has(player_x)
			and columns.has(player_x - 160.0)
			and columns.has(player_x + 160.0)
		),
		"rimeweaver icicle drop locks the player spot and 160 px either side (%s)" % [columns]
	)
	suite.check(
		(plan["marks"] as Array).size() == 3, "rimeweaver icicle drop shows a floor mark per column"
	)
	shots = Attacks.emissions(boss, &"icicle_drop", plan)
	var over_columns := shots.size() == 3
	for shot in shots:
		over_columns = over_columns and columns.has(float(shot["origin"].x))
		over_columns = over_columns and (shot["direction"] as Vector2) == Vector2.DOWN
	suite.check(over_columns, "rimeweaver icicles fall only in the locked columns")
	# Frost Ring.
	plan = Attacks.plan(boss, &"frost_ring")
	var mark: Dictionary = (plan["marks"] as Array)[0]
	suite.check(
		absf(rad_to_deg(float(mark["gap_width"])) - 77.0) < 0.1, "rimeweaver frost ring gap is 77 degrees"
	)
	shots = Attacks.emissions(boss, &"frost_ring", plan)
	suite.check(shots.size() == 10, "rimeweaver frost ring has ten shards (%d)" % shots.size())
	var gap := float(mark["gap"])
	var clear := true
	for shot in shots:
		var off := absf(wrapf((shot["direction"] as Vector2).angle() - gap, -PI, PI))
		clear = clear and off >= deg_to_rad(38.0)
	suite.check(clear, "rimeweaver frost ring leaves the gap toward the player clear")
	suite.check(
		suite.live_projectiles() == 0, "rimeweaver fires nothing while attacks are only planned"
	)
	# Shape of the fight.
	suite.check(Patterns.is_charge(&"wall_skitter"), "rimeweaver wall skitter is a charge")
	suite.check(
		Patterns.attacks_in_stage(boss_id, 1) == [&"needle_line", &"icicle_drop", &"wall_skitter"],
		"rimeweaver stage 1 is Needle Line, Icicle Drop and Wall Skitter"
	)
	suite.check(
		(
			Patterns.attacks_in_stage(boss_id, 2).has(&"frost_ring")
			and not Patterns.attacks_in_stage(boss_id, 1).has(&"frost_ring")
		),
		"rimeweaver stage 2 adds Frost Ring"
	)
	suite.check(
		int(boss.max_health) == 150 and boss.call("_contact_damage") == 18, "rimeweaver stats"
	)
	suite.despawn(boss)
	await suite.frames(2)
