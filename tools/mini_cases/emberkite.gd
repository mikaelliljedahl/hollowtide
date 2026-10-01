extends RefCounted
## Emberkite case (docs/features/mini-bosses.md 3.4): Cinder Rain locks four columns around a bright
## gap at the player's spot, fires only onto them and nothing before release; Flare Dive is a charge;
## Ember Fan and Vent Column are the reused main attacks; stage 2 adds only Cinder Rain; kiln_08 holds
## the miniboss entry and gates its Bolt Quiver behind mini:emberkite.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")
const LAYOUT := "res://scenes/campaign/layouts/kiln_08.txt"


func run(suite: Node, boss_id: StringName) -> void:
	if boss_id != &"emberkite":
		return
	var boss: CombatBoss = suite.spawn_in_arena(boss_id)
	await suite.frames(1)
	var player_x: float = suite.probe.global_position.x
	boss.set_test_stage(2)
	var plan := Attacks.plan(boss, &"cinder_rain")
	var columns: Array = plan["columns"]
	suite.check(columns.size() == 4, "emberkite cinder rain locks four columns (%s)" % [columns])
	var gap_clear := true
	for column: float in columns:
		gap_clear = gap_clear and absf(column - player_x) >= 160.0
	suite.check(gap_clear, "emberkite cinder rain leaves the player's spot as the gap")
	var marks: Array = plan["marks"]
	suite.check(marks.size() == columns.size(), "emberkite cinder rain shows a floor mark per column")
	var shots := Attacks.emissions(boss, &"cinder_rain", plan)
	var on_columns := not shots.is_empty()
	for shot in shots:
		on_columns = on_columns and _near_column(columns, float(shot["origin"].x))
	suite.check(on_columns, "emberkite cinder rain fires only onto its locked columns")
	suite.check(
		suite.live_projectiles() == 0, "emberkite cinder rain fires nothing while it is only planned"
	)
	suite.check(Patterns.is_charge(&"flare_dive"), "emberkite flare dive is a charge")
	suite.check(
		_same_set(
			Patterns.attacks_in_stage(boss_id, 1), [&"ember_fan", &"vent_burst", &"flare_dive"]
		),
		"emberkite stage 1 is Ember Fan, Vent Column and Flare Dive"
	)
	suite.check(
		Patterns.attacks_in_stage(boss_id, 2).has(&"cinder_rain")
		and not Patterns.attacks_in_stage(boss_id, 1).has(&"cinder_rain"),
		"emberkite stage 2 adds Cinder Rain"
	)
	suite.check(
		is_equal_approx(Patterns.telegraph_seconds(&"cinder_rain", 2), 1.1), "cinder rain telegraph"
	)
	suite.check(int(boss.max_health) == 170 and boss.call("_contact_damage") == 20, "emberkite stats")
	suite.despawn(boss)
	await suite.frames(2)
	_layout(suite)


func _layout(suite: Node) -> void:
	var text := FileAccess.get_file_as_string(LAYOUT)
	suite.check(text.contains("miniboss emberkite arena="), "kiln_08 holds the emberkite miniboss")
	suite.check(not text.contains("\nambush:"), "kiln_08 has no ambush zone")
	suite.check(
		text.contains("missile_tank missile_02") and text.contains("flaggate mini:emberkite"),
		"kiln_08 keeps missile_02 behind flaggate mini:emberkite"
	)


func _same_set(found: Array, expected: Array) -> bool:
	if found.size() != expected.size():
		return false
	for attack in expected:
		if not found.has(attack):
			return false
	return true


func _near_column(columns: Array, x: float) -> bool:
	for column: float in columns:
		if absf(column - x) <= 30.0:
			return true
	return false
