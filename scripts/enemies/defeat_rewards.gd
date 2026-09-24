class_name DefeatRewards
extends RefCounted

const CombatLootScript = preload("res://scripts/pickups/combat_loot.gd")

const DROP_CHANCE := 0.34
const BOSS_DROP_CHANCE := 0.7
const MISSILE_WEIGHT := 0.28
const FLUX_WEIGHT := 0.18

static var _test_seed := 0x484F4C4C
static var _roll_index := 0


static func set_test_seed(seed: int) -> void:
	_test_seed = seed
	_roll_index = 0


static func spawn_for_defeat(
	source: Node2D, boss: bool, frozen: bool = false, with_effect: bool = true
) -> void:
	if not is_instance_valid(source):
		return
	if with_effect:
		CombatFeedback.spawn_death(source, boss, frozen)
	var enemy_id := StringName(source.get("enemy_id"))
	if not _should_drop(enemy_id, source.global_position, boss):
		return
	var parent := source.get_parent()
	if parent == null:
		return
	var loot := CombatLootScript.new() as Area2D
	if loot == null:
		return
	loot.configure(_drop_kind(enemy_id, source.global_position), source.global_position)
	parent.add_child(loot)


static func _should_drop(enemy_id: StringName, position: Vector2, boss: bool) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(enemy_id, position)
	_roll_index += 1
	return rng.randf() < (BOSS_DROP_CHANCE if boss else DROP_CHANCE)


static func _drop_kind(enemy_id: StringName, position: Vector2) -> StringName:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(enemy_id, position) ^ 0xD09
	var roll := rng.randf()
	if (
		GameState.has_ability(&"flux_shield")
		or GameState.has_ability(&"burst_beam")
		or GameState.has_ability(&"echo_scan")
	):
		if GameState.flux_current < GameState.flux_max:
			if roll < FLUX_WEIGHT:
				return &"flux_refill"
			roll = (roll - FLUX_WEIGHT) / (1.0 - FLUX_WEIGHT)
	return &"missile_refill" if roll < MISSILE_WEIGHT else &"energy_refill"


static func _seed(enemy_id: StringName, position: Vector2) -> int:
	var value := _test_seed
	value ^= String(enemy_id).hash()
	value ^= int(round(position.x * 17.0))
	value ^= int(round(position.y * 31.0))
	value ^= _roll_index * 7919
	return value
