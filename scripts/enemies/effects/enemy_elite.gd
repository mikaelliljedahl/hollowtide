class_name EnemyElite
extends RefCounted
## Elite variant of a common enemy (docs/features/revisit-remix.md section 4): more health, a
## faster step and attack cooldown behind the same telegraphs, a rose tint with a pulsing rim, and
## a guaranteed refill pair on defeat. Contact/projectile damage and the reaction matrix are
## unchanged. Which spawns become elite is decided by `scripts/campaign/revisit_remix.gd`.

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const CombatLootScript = preload("res://scripts/pickups/combat_loot.gd")
const OUTLINE_SHADER = preload("res://resources/combat/elite_outline.gdshader")

const META := &"elite"
const HEALTH_SCALE := 1.6
const SPEED_SCALE := 1.15
## Attack and jump cooldowns tick this much faster; telegraph durations never change.
const CADENCE_SCALE := 1.25
## Movers whose velocity is integrated by move_and_slide. Position-driven movers (vent flyer,
## frost floater, burrower) and the aimed ceiling dive keep their paths.
const SPEED_IDS: Array[StringName] = [
	&"hopper", &"grasshopper", &"armored_guard", &"energy_parasite", &"lava_monster"
]
const TINT := Color(1.0, 0.8, 0.88)
const RIM_COLOR := Color(0.95, 0.3, 0.62, 0.9)
## Rim width in screen pixels, independent of each sprite's texture scale.
const RIM_PIXELS := 4.0
const REWARD_SPREAD := 22.0


static func health_for(enemy_id: StringName) -> int:
	var data: Dictionary = Catalog.ENEMY_DATA.get(enemy_id, {})
	return ceili(float(data.get("max_health", 1)) * HEALTH_SCALE)


static func is_elite(enemy: Node) -> bool:
	return is_instance_valid(enemy) and enemy.has_meta(META)


## Turns a spawned (already in-tree) common enemy into its elite variant. Idempotent.
static func apply(enemy: Node2D) -> void:
	if not is_instance_valid(enemy) or is_elite(enemy):
		return
	var enemy_id := StringName(enemy.get("enemy_id"))
	if not Catalog.ENEMY_DATA.has(enemy_id):
		return
	enemy.set_meta(META, true)
	var health := health_for(enemy_id)
	enemy.set("max_health", health)
	enemy.set("health", health)
	if enemy is Crawler:
		# The crawler tracks live health in a private field next to its public mirror.
		enemy.set("_health", health)
		enemy.set("move_speed", float(enemy.get("move_speed")) * SPEED_SCALE)
		_decorate(enemy.get_node_or_null("Visual/CrawlerSprite") as Node2D)
		return
	if enemy_id in SPEED_IDS:
		enemy.set("speed_scale", SPEED_SCALE)
	enemy.set("cadence_scale", CADENCE_SCALE)
	_decorate(enemy.get_node_or_null("Sprite2D") as Node2D)


## Elite defeat reward: the refill the player needs most (as an ambush clear) plus an energy refill.
static func spawn_reward(source: Node2D) -> void:
	if not is_elite(source):
		return
	var parent := source.get_parent()
	if parent == null:
		return
	var kinds: Array[StringName] = [AmbushRules.reward_kind(), &"energy_refill"]
	for index in kinds.size():
		var loot := CombatLootScript.new() as Area2D
		var offset := Vector2(REWARD_SPREAD * (index * 2 - 1), 0.0)
		loot.configure(kinds[index], source.global_position + offset)
		parent.add_child(loot)


static func _decorate(sprite: Node2D) -> void:
	if sprite == null:
		return
	sprite.self_modulate = TINT
	var rim := Rim.new()
	rim.name = "EliteRim"
	rim.source = sprite
	sprite.add_child(rim)


## Draws the source sprite's current frame behind it through the rim shader.
class Rim:
	extends Sprite2D
	var source: Node2D

	func _ready() -> void:
		show_behind_parent = true
		var fx := ShaderMaterial.new()
		fx.shader = OUTLINE_SHADER
		fx.set_shader_parameter(&"rim_color", RIM_COLOR)
		material = fx
		_sync()

	func _process(_delta: float) -> void:
		_sync()

	func _sync() -> void:
		if not is_instance_valid(source):
			return
		if source is Sprite2D:
			var sprite := source as Sprite2D
			texture = sprite.texture
			flip_h = sprite.flip_h
			offset = sprite.offset
			centered = sprite.centered
		elif source is AnimatedSprite2D:
			var animated := source as AnimatedSprite2D
			if animated.sprite_frames != null:
				texture = animated.sprite_frames.get_frame_texture(
					animated.animation, animated.frame
				)
			flip_h = animated.flip_h
			offset = animated.offset
			centered = animated.centered
		var fx := material as ShaderMaterial
		var screen_scale := absf(global_transform.get_scale().x)
		if fx != null and screen_scale > 0.001:
			fx.set_shader_parameter(&"width", RIM_PIXELS / screen_scale)
