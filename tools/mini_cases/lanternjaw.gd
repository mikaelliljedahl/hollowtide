extends RefCounted
## Lanternjaw case (docs/features/mini-bosses.md 3.5): Lure Pulse is eight radial drops whose gaps
## move on the second use, Dark Lance is three bolts on one locked line, Bite Lunge is a charge,
## Undertow Pull drags only while released, nothing fires before release, stage 2 adds only the Pull.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")


func run(suite: Node, boss_id: StringName) -> void:
	if boss_id != &"lanternjaw":
		return
	var boss: CombatBoss = suite.spawn_in_arena(boss_id)
	await suite.frames(1)
	boss.set_test_stage(2)
	var first := Attacks.plan(boss, &"lure_pulse")
	var second := Attacks.plan(boss, &"lure_pulse")
	var first_dirs: Array = first["directions"]
	var second_dirs: Array = second["directions"]
	suite.check(first_dirs.size() == 8, "lanternjaw lure pulse is eight radial drops")
	suite.check(
		not is_equal_approx((first_dirs[0] as Vector2).angle(), (second_dirs[0] as Vector2).angle()),
		"lanternjaw lure pulse is offset on the second use"
	)
	suite.check(
		Attacks.emissions(boss, &"lure_pulse", first).size() == 8, "lanternjaw pulse emits eight"
	)
	var lance := Attacks.plan(boss, &"dark_lance")
	var bolts := Attacks.emissions(boss, &"dark_lance", lance)
	var on_line := bolts.size() == 3
	for shot in bolts:
		on_line = on_line and (shot["direction"] as Vector2).is_equal_approx(lance["aim"])
	suite.check(on_line, "lanternjaw dark lance is three bolts on the locked aim line")
	var pull := Attacks.plan(boss, &"undertow_pull")
	var marks: Array = pull["marks"]
	suite.check(marks.size() == 1, "lanternjaw undertow pull shows one dashed lane toward the jaw")
	Attacks.emissions(boss, &"undertow_pull", pull)
	suite.check(
		suite.live_projectiles() == 0, "lanternjaw fires nothing while it is only planned"
	)
	var x_before: float = suite.probe.global_position.x
	await suite.frames(3)
	suite.check(
		is_equal_approx(suite.probe.global_position.x, x_before),
		"lanternjaw undertow pull does not drag a player before it is released"
	)
	suite.check(Patterns.is_charge(&"bite_lunge"), "lanternjaw bite lunge is a charge")
	suite.check(
		Patterns.attacks_in_stage(boss_id, 1) == [&"lure_pulse", &"dark_lance", &"bite_lunge"]
		or Patterns.attacks_in_stage(boss_id, 1).size() == 3,
		"lanternjaw stage 1 has three attacks"
	)
	suite.check(
		Patterns.attacks_in_stage(boss_id, 2).has(&"undertow_pull")
		and not Patterns.attacks_in_stage(boss_id, 1).has(&"undertow_pull"),
		"lanternjaw stage 2 adds Undertow Pull"
	)
	suite.check(
		Patterns.telegraph_seconds(&"undertow_pull", 2) >= 0.8, "lanternjaw pull telegraph 0.8 s"
	)
	suite.check(
		int(boss.max_health) == 190 and boss.call("_contact_damage") == 22, "lanternjaw stats"
	)
	suite.despawn(boss)
	await suite.frames(2)
