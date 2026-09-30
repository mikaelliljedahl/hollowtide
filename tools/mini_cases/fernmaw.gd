extends RefCounted
## Fernmaw case (docs/features/mini-bosses.md 3.1): Spore Lob and Root Burst lock three columns
## (player spot and one either side) that the telegraph shows and the emissions hit, nothing is
## fired before release, Pounce is a charge, and stage 2 adds only Root Burst.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")


func run(suite: Node, boss_id: StringName) -> void:
	if boss_id != &"fernmaw":
		return
	var boss: CombatBoss = suite.spawn_in_arena(boss_id)
	await suite.frames(1)
	var player_x: float = suite.probe.global_position.x
	var cases := {&"spore_lob": 192.0, &"root_burst": 256.0}
	for attack: StringName in cases:
		var spacing: float = cases[attack]
		boss.set_test_stage(2)
		var plan := Attacks.plan(boss, attack)
		var columns: Array = plan["columns"]
		suite.check(columns.size() == 3, "fernmaw %s locks three columns (%s)" % [attack, columns])
		suite.check(
			columns.has(player_x)
			and columns.has(clampf(player_x - spacing, 40.0, 1960.0))
			and columns.has(clampf(player_x + spacing, 40.0, 1960.0)),
			"fernmaw %s columns are the player spot and %d px either side" % [attack, int(spacing)]
		)
		var marks: Array = plan["marks"]
		suite.check(marks.size() == columns.size(), "fernmaw %s shows a floor mark per column" % attack)
		var shots := Attacks.emissions(boss, attack, plan)
		var hits_columns := not shots.is_empty()
		for shot in shots:
			hits_columns = hits_columns and _near_column(columns, float(shot["origin"].x))
		suite.check(hits_columns, "fernmaw %s fires only onto its locked columns" % attack)
		suite.check(
			suite.live_projectiles() == 0, "fernmaw %s fires nothing while it is only planned" % attack
		)
	suite.check(Patterns.is_charge(&"pounce"), "fernmaw pounce is a charge")
	suite.check(
		Patterns.attacks_in_stage(boss_id, 1) == [&"spore_lob", &"pounce"],
		"fernmaw stage 1 is Spore Lob and Pounce"
	)
	suite.check(
		Patterns.attacks_in_stage(boss_id, 2).has(&"root_burst")
		and not Patterns.attacks_in_stage(boss_id, 1).has(&"root_burst"),
		"fernmaw stage 2 adds Root Burst"
	)
	suite.check(int(boss.max_health) == 100 and boss.call("_contact_damage") == 14, "fernmaw stats")
	suite.despawn(boss)
	await suite.frames(2)


func _near_column(columns: Array, x: float) -> bool:
	for column: float in columns:
		if absf(column - x) <= 30.0:
			return true
	return false
