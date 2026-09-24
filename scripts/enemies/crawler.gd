class_name Crawler extends CharacterBody2D

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const ProjectileHurtboxScript = preload("res://scripts/enemies/projectile_hurtbox.gd")
const HitResult = preload("res://scripts/combat/hit_result.gd")

signal player_contact_damage(amount: int)

const CONTACT_DAMAGE: int = Catalog.ENEMY_DATA[&"crawler"]["contact_damage"]
const MOVE_SPEED := 260.0
const MAX_HEALTH: int = Catalog.ENEMY_DATA[&"crawler"]["max_health"]
const TERRAIN_MASK := 1
const SUPPORT_DISTANCE := 16.0
const SUPPORT_LEAD := 22.0
const SUPPORT_DEPTH := 48.0
const FORWARD_DISTANCE := 42.0
const CORNER_FORWARD := 50.0
const CORNER_INWARD := 50.0
const ATTACH_SEARCH_DISTANCE := 256.0
const NORMAL_ALIGNMENT_DOT := 0.94
const VISUAL_ALPHA_SUPPORT := 31.0

@export var travel_direction := -1
@export var move_speed := MOVE_SPEED
@export var max_health := MAX_HEALTH

var enemy_id: StringName = &"crawler"
var health: int = MAX_HEALTH
var is_frozen := false

@onready var _body_collision: CollisionShape2D = $CollisionShape2D
@onready var _player_detector: Area2D = $PlayerDetector
@onready var _deflect_sparks: CPUParticles2D = $DeflectSparks
@onready var _visual: Node2D = $Visual

var _travel_sign := -1
var _surface_normal := Vector2.UP
var _health := 0
var _dying := false
var _has_surface := false
var _projectile_hurtbox: EnemyProjectileHurtbox


func _ready() -> void:
	add_to_group(&"enemies")
	add_to_group(&"damageable")
	_travel_sign = -1 if travel_direction < 0 else 1
	_health = maxi(max_health, 1)
	health = _health
	# Source alpha reaches local y=31 while physics support reaches y=16. Pull artwork
	# outward by exact difference so feet touch contour instead of sinking into stone.
	_visual.position = Vector2(0.0, -(VISUAL_ALPHA_SUPPORT - SUPPORT_DISTANCE))
	_configure_projectile_hurtbox()
	_player_detector.body_entered.connect(_on_player_detector_body_entered)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	if not _has_surface and not _acquire_nearest_surface():
		velocity = Vector2.ZERO
		return

	_follow_surface_before_motion()
	if not _has_surface:
		velocity = Vector2.ZERO
		return

	var tangent := _travel_tangent()
	velocity = tangent * move_speed
	global_position += velocity * delta
	_follow_surface_after_motion()


func receive_hit(amount: int, kind: StringName, hit_context := {}) -> HitResult.Reaction:
	if _dying or amount <= 0:
		return HitResult.Reaction.PASS
	var impact: Vector2 = hit_context.get("position", _visual.global_position)
	var direction := Vector2.ZERO
	var source = hit_context.get("source")
	if source is ProjectileBase and is_instance_valid(source):
		direction = Vector2.RIGHT.rotated((source as ProjectileBase).rotation)

	# Missile-only immunity is progression gating. Every other attack deflects.
	if kind != &"missile":
		CombatFeedback.spawn_blocked_hit(get_parent(), impact, direction)
		_play_beam_deflection()
		return HitResult.Reaction.BLOCKED

	_health = maxi(_health - amount, 0)
	health = _health
	CombatFeedback.spawn_hit(get_parent(), impact, false, direction, true)
	if _health == 0:
		GameJuice.hit_stop(self, 0.04)
	GameJuice.shake(self, 5.0 if _health == 0 else 3.0, 0.18)
	_play_missile_hit()
	if _health == 0:
		_die()
	return HitResult.Reaction.DAMAGE


func take_damage(amount: int, kind: StringName) -> void:
	receive_hit(amount, kind)


func is_vulnerable_to(kind: StringName) -> bool:
	return kind == &"missile"


func allows_projectile(_kind: StringName) -> bool:
	return false


func reset_runtime() -> void:
	_dying = false
	_health = maxi(max_health, 1)
	health = _health
	velocity = Vector2.ZERO
	_has_surface = false
	_surface_normal = Vector2.UP
	rotation = 0.0
	_body_collision.disabled = false
	_player_detector.monitoring = true
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(true)


func has_surface_contact() -> bool:
	return _has_surface


func surface_normal() -> Vector2:
	return _surface_normal


func _acquire_nearest_surface() -> bool:
	var closest_hit: Dictionary = {}
	var closest_distance := INF
	for direction in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		var hit := _ray_hit(global_position, global_position + direction * ATTACH_SEARCH_DISTANCE)
		if hit.is_empty():
			continue
		var distance := global_position.distance_to(hit["position"])
		if distance < closest_distance:
			closest_distance = distance
			closest_hit = hit
	if closest_hit.is_empty():
		return false
	_adopt_surface(closest_hit)
	return _has_surface


func _follow_surface_before_motion() -> void:
	var tangent := _travel_tangent()
	var forward_hit := _ray_hit(
		global_position + _surface_normal * 2.0,
		global_position + _surface_normal * 2.0 + tangent * FORWARD_DISTANCE,
	)
	if not forward_hit.is_empty():
		var forward_normal: Vector2 = forward_hit["normal"]
		if _surface_normal.dot(forward_normal) < NORMAL_ALIGNMENT_DOT:
			_adopt_surface(forward_hit)
			return
	_update_support_or_corner()


func _follow_surface_after_motion() -> void:
	if not _has_surface:
		return
	_update_support_or_corner()


func _update_support_or_corner() -> void:
	var tangent := _travel_tangent()
	var support_start := global_position + tangent * SUPPORT_LEAD + _surface_normal * 4.0
	var support_end := support_start - _surface_normal * SUPPORT_DEPTH
	var support_hit := _ray_hit(support_start, support_end)
	if not support_hit.is_empty():
		var support_normal: Vector2 = support_hit["normal"]
		if _surface_normal.dot(support_normal) >= NORMAL_ALIGNMENT_DOT:
			_snap_to_surface(support_hit)
			return
		_adopt_surface(support_hit)
		return

	# Missing support means actual contour turned around a convex corner. Probe from
	# around edge back toward old face; first hit is new wall/ceiling. Geometry chooses
	# contact point and normal, never authored route coordinates.
	var expected_normal := _surface_normal.rotated(float(_travel_sign) * PI / 2.0)
	var around_start := (
		global_position + tangent * CORNER_FORWARD - _surface_normal * (SUPPORT_DISTANCE + 2.0)
	)
	var corner_hit := _ray_hit(around_start, around_start - tangent * CORNER_INWARD * 2.0)
	if not corner_hit.is_empty():
		var corner_normal: Vector2 = corner_hit["normal"]
		if corner_normal.dot(expected_normal) >= NORMAL_ALIGNMENT_DOT:
			_adopt_surface(corner_hit)
			return

	# Terrain can be rebuilt after child _ready. Drop stale contact immediately, then
	# reacquire from live space next tick instead of continuing through air.
	_has_surface = false


func _travel_tangent() -> Vector2:
	return _surface_normal.rotated(PI / 2.0) * float(_travel_sign)


func _adopt_surface(hit: Dictionary) -> void:
	var normal: Vector2 = hit.get("normal", Vector2.ZERO).normalized()
	if normal.is_zero_approx():
		_has_surface = false
		return
	_surface_normal = normal
	rotation = Vector2.UP.angle_to(_surface_normal)
	global_position = Vector2(hit["position"]) + _surface_normal * SUPPORT_DISTANCE
	_has_surface = true


func _snap_to_surface(hit: Dictionary) -> void:
	var normal: Vector2 = hit.get("normal", Vector2.ZERO).normalized()
	if normal.is_zero_approx():
		_has_surface = false
		return
	var point := Vector2(hit["position"])
	var normal_error := (global_position - point).dot(normal) - SUPPORT_DISTANCE
	global_position -= normal * normal_error
	_surface_normal = normal
	rotation = Vector2.UP.angle_to(_surface_normal)
	_has_surface = true


func _ray_hit(from: Vector2, to: Vector2) -> Dictionary:
	if from.is_equal_approx(to) or not is_inside_tree():
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to, TERRAIN_MASK, [get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	return get_world_2d().direct_space_state.intersect_ray(query)


func _on_player_detector_body_entered(body: Node2D) -> void:
	if _dying:
		return
	if body.has_method(&"take_damage"):
		body.call(&"take_damage", CONTACT_DAMAGE, global_position)
		return
	player_contact_damage.emit(CONTACT_DAMAGE)
	push_warning("Crawler contacted player without take_damage; emitted player_contact_damage")


func _play_beam_deflection() -> void:
	GameJuice.play_sfx(&"armor_clink", &"beam_ricochet")
	_deflect_sparks.restart()
	_deflect_sparks.emitting = true
	var original_position := _visual.position
	var hop_offset := _surface_normal.rotated(-rotation) * 8.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "position", original_position + hop_offset, 0.045)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "position", original_position, 0.11)


func _play_missile_hit() -> void:
	Audio.play_sfx(&"missile_hit")
	_flash_sprite()
	var original_scale := _visual.scale
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "scale", original_scale * 1.12, 0.045)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", original_scale, 0.09)


func _die() -> void:
	_dying = true
	var frozen_at_death := is_frozen
	velocity = Vector2.ZERO
	_body_collision.disabled = true
	_player_detector.monitoring = false
	collision_layer = 0
	collision_mask = 0
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(false)
	_deflect_sparks.emitting = false
	CombatFeedback.spawn_death(self, false, frozen_at_death)
	_visual.visible = false
	Audio.play_sfx(&"enemy_death")
	var tween := create_tween()
	tween.tween_interval(0.05)
	tween.tween_callback(queue_free)


func _configure_projectile_hurtbox() -> void:
	var sprite := get_node_or_null("Visual/CrawlerSprite") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	var images: Array[Image] = []
	var frame_count := sprite.sprite_frames.get_frame_count(&"crawl")
	for frame_index in frame_count:
		var texture := sprite.sprite_frames.get_frame_texture(&"crawl", frame_index)
		if texture == null:
			continue
		var image := texture.get_image()
		if image != null and not image.is_empty():
			images.append(image)
	if images.is_empty():
		return
	_projectile_hurtbox = ProjectileHurtboxScript.new() as EnemyProjectileHurtbox
	_projectile_hurtbox.name = "ProjectileHurtbox"
	sprite.add_child(_projectile_hurtbox)
	# The source has soft antialiasing; two pixels retain that visible contour in physics.
	_projectile_hurtbox.configure(&"crawler", images, 2)


func _flash_sprite() -> void:
	var sprite := get_node_or_null("Visual/CrawlerSprite") as CanvasItem
	if sprite == null:
		return
	var fx := sprite.material as ShaderMaterial
	if fx == null:
		fx = ShaderMaterial.new()
		fx.shader = preload("res://resources/combat/sprite_fx.gdshader")
		sprite.material = fx
	fx.set_shader_parameter(&"flash_amount", 0.9 * GameJuice.flash_strength())
	var tween := create_tween()
	tween.tween_method(
		func(value: float): fx.set_shader_parameter(&"flash_amount", value), 0.9, 0.0, 0.14
	)
