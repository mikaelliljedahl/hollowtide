class_name RevisitRemix
extends RefCounted
## Revisit remix rules (docs/features/revisit-remix.md sections 3 and 6): after each boss falls,
## common enemies in rooms the player has already visited may return as elites. Pure apart from
## reading GameState, so the suite can test tiers, rolls and the kit filter directly.

const Catalog = preload("res://scripts/progression/content_catalog.gd")

## Elite chance per campaign enemy spawn, indexed by tier (bosses defeated).
const TIER_CHANCE: Array[float] = [0.0, 0.25, 0.4, 0.55]


static func tier() -> int:
	var count := 0
	for boss_id in Catalog.BOSS_IDS:
		if GameState.has_world_flag("boss:" + String(boss_id)):
			count += 1
	return count


static func chance(tier_value: int) -> float:
	return TIER_CHANCE[clampi(tier_value, 0, TIER_CHANCE.size() - 1)]


## Never in the dev track (it has no campaign root) or in scripted evidence runs.
static func enabled(tree: SceneTree, args: PackedStringArray) -> bool:
	for argument in args:
		if argument.begins_with("--evidence-run="):
			return false
	return tree != null and tree.get_first_node_in_group(&"campaign_root") != null


## Deterministic per room, spawn and tier. Each spawn has one fixed roll in [0, 1) and the tier sets
## the threshold, so every elite of a lower tier stays elite at a higher one.
static func rolls_elite(room_id: String, spawn_id: String, tier_value: int) -> bool:
	return spawn_roll(room_id, spawn_id) < chance(tier_value)


## An MD5 prefix, not String.hash(): near-identical keys (Enemy01, Enemy02) must not correlate.
static func spawn_roll(room_id: String, spawn_id: String) -> float:
	var key := "%s|%s" % [room_id, spawn_id]
	return float(key.md5_text().substr(0, 8).hex_to_int()) / 4294967296.0


## The ambush kill filter, plus: when harpoon bolts are the only owned way to hurt the enemy, a
## full quiver must cover the elite's health.
static func kit_can_beat(enemy_id: StringName) -> bool:
	if not AmbushRules.can_defeat_enemy(enemy_id):
		return false
	if not _ammo_only(enemy_id):
		return true
	return GameState.max_missiles * Catalog.MISSILE_DAMAGE >= EnemyElite.health_for(enemy_id)


static func is_elite_spawn(
	enemy_id: StringName, room_id: String, spawn_id: String, tier_value: int, revisit: bool
) -> bool:
	return (
		tier_value > 0
		and revisit
		and Catalog.ENEMY_IDS.has(enemy_id)
		and rolls_elite(room_id, spawn_id, tier_value)
		and kit_can_beat(enemy_id)
	)


static func _ammo_only(enemy_id: StringName) -> bool:
	for options in AmbushRules.requirements(enemy_id):
		var free := false
		for ability in options:
			if ability != &"missiles" and AmbushRules.owns(ability):
				free = true
				break
		if not free:
			return true
	return false
