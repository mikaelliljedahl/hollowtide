class_name EnemyFactory extends RefCounted

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const CRAWLER_SCENE: PackedScene = preload("res://scenes/enemies/crawler.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/combat_enemy.tscn")
const SHARD_TURRET_SCENE: PackedScene = preload("res://scenes/enemies/shard_turret.tscn")
const BURROWER_SCENE: PackedScene = preload("res://scenes/enemies/burrower.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/enemies/boss.tscn")


static func create(runtime_id: StringName) -> Node2D:
	if runtime_id == &"crawler":
		return CRAWLER_SCENE.instantiate() as Node2D
	if runtime_id == &"shard_turret":
		return SHARD_TURRET_SCENE.instantiate() as Node2D
	if runtime_id == &"burrower":
		return BURROWER_SCENE.instantiate() as Node2D
	if SurpriseCatalog.has(runtime_id):
		return SurpriseCatalog.create(runtime_id)
	if Catalog.ENEMY_IDS.has(runtime_id):
		var enemy := ENEMY_SCENE.instantiate() as Node2D
		if enemy != null:
			enemy.set(&"runtime_id", runtime_id)
		return enemy
	if Catalog.BOSS_IDS.has(runtime_id):
		var boss := BOSS_SCENE.instantiate() as Node2D
		if boss != null:
			boss.set(&"runtime_id", runtime_id)
		return boss
	return null
