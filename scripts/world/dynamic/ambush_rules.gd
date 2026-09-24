class_name AmbushRules
extends RefCounted
## Pure ambush rules (docs/features/ambush-arenas.md sections 3 and 5): which enemies the current
## kit can beat, which authored point a spawn uses, and which refill a clear drops. No scene access
## apart from reading GameState, so the suite can test every rule directly.

const Catalog = preload("res://scripts/progression/content_catalog.gd")

## A spawn closer than this to the player moves to another authored point.
const SAFE_DISTANCE := 256.0
const ANY_DAMAGE: Array[StringName] = [&"beam", &"missiles", &"bombs", &"undertow_dash"]
## Never spawned by an ambush: the Lava Monster needs an authored lava basin.
const NEVER_SPAWNED: Array[StringName] = [&"lava_monster"]
## Enemies authored on open-air points; every other enemy is authored on a floor (or platform)
## point. Mirrors FLYING_ENEMIES in tools/campaign_layout.py, which picks the points.
const AIR_ENEMIES: Array[StringName] = [
	&"vent_flyer", &"energy_parasite", &"frost_floater", &"ceiling_diver"
]


## Abilities an enemy needs to be beaten; each inner array is alternatives (any one suffices).
## An empty inner array means the enemy can never be beaten by an ambush (never spawned).
static func requirements(enemy_id: StringName) -> Array:
	if enemy_id in NEVER_SPAWNED or Catalog.BOSS_IDS.has(enemy_id):
		return [[]]
	if enemy_id == &"crawler":
		return [[&"missiles"]]
	if enemy_id == &"armored_guard":
		return [[&"missiles", &"bombs"]]
	return [ANY_DAMAGE]


static func owns(ability: StringName) -> bool:
	if ability == &"missiles":
		return GameState.has_missiles
	return GameState.has_ability(ability)


static func can_defeat_enemy(enemy_id: StringName) -> bool:
	for options in requirements(enemy_id):
		var ok := false
		for ability in options:
			if owns(ability):
				ok = true
				break
		if not ok:
			return false
	return true


## Keeps the spawns the current kit can beat, as [enemy_id, spawn_index] pairs. `first_index` is
## the flat index of the wave's first spawn across all waves of the ambush.
static func winnable_spawns(wave_ids: PackedStringArray, first_index: int) -> Array:
	var kept: Array = []
	for index in wave_ids.size():
		var enemy_id := StringName(wave_ids[index])
		if can_defeat_enemy(enemy_id):
			kept.append([enemy_id, first_index + index])
	return kept


static func is_air(enemy_id: StringName) -> bool:
	return enemy_id in AIR_ENEMIES


## Global spawn position for an authored point. A point within SAFE_DISTANCE of the player moves
## to the nearest other authored point of the same movement class (air or floor) that is far
## enough away, else to the same-class point farthest from the player. Point j's class is that of
## spawn j in `spawn_ids` (all waves in order); an empty list lets every point qualify. Positions
## are never invented, and a walker never lands on a flyer's point or the reverse.
static func resolve_spawn(
	authored: PackedVector2Array,
	index: int,
	player_at: Vector2,
	spawn_ids: PackedStringArray = PackedStringArray()
) -> Vector2:
	if authored.is_empty():
		return player_at
	var slot := index % authored.size()
	var wanted := authored[slot]
	if wanted.distance_to(player_at) >= SAFE_DISTANCE:
		return wanted
	var best := wanted
	var best_distance := INF
	var farthest := wanted
	for point_index in authored.size():
		if not _same_class(spawn_ids, index, point_index):
			continue
		var point := authored[point_index]
		if point.distance_to(player_at) > farthest.distance_to(player_at):
			farthest = point
		if point_index == slot or point.distance_to(player_at) < SAFE_DISTANCE:
			continue
		if point.distance_to(wanted) < best_distance:
			best = point
			best_distance = point.distance_to(wanted)
	return best if best_distance < INF else farthest


static func _same_class(spawn_ids: PackedStringArray, index: int, point_index: int) -> bool:
	if spawn_ids.is_empty() or index >= spawn_ids.size() or point_index >= spawn_ids.size():
		return spawn_ids.is_empty()
	return is_air(StringName(spawn_ids[index])) == is_air(StringName(spawn_ids[point_index]))


## Refill dropped on clear: missiles when owned and not full, otherwise energy.
static func reward_kind() -> StringName:
	if GameState.has_missiles and GameState.missile_count < GameState.max_missiles:
		return &"missile_refill"
	return &"energy_refill"
