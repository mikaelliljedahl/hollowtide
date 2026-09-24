class_name CombatLoot
extends Area2D

const Catalog = preload("res://scripts/progression/content_catalog.gd")

const PICKUP_DELAY := 0.16
const LIFETIME := 9.0
const FALL_ACCELERATION := 980.0
const MAX_FALL_SPEED := 480.0
const RADIUS := 16.0
const ICON_SCALE := Vector2(0.42, 0.42)

var kind: StringName = &"energy_refill"
var _sprite: Sprite2D
var _delay_remaining := PICKUP_DELAY
var _lifetime_remaining := LIFETIME
var _fall_velocity := 0.0
var _settled := false
var _claimed := false
var _shape: CollisionShape2D


func configure(drop_kind: StringName, spawn_position: Vector2) -> void:
	kind = drop_kind if Catalog.is_pickup_kind(drop_kind) else &""
	global_position = spawn_position


func _ready() -> void:
	if kind not in [&"energy_refill", &"missile_refill", &"flux_refill"]:
		queue_free()
		return
	collision_layer = 4
	collision_mask = 2
	monitoring = false
	monitorable = true
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	_shape.shape = circle
	add_child(_shape)
	_sprite = Sprite2D.new()
	_sprite.texture = Catalog.pickup_texture(kind)
	_sprite.scale = ICON_SCALE
	add_child(_sprite)
	body_entered.connect(_on_body_entered)
	add_to_group(&"transient")
	_safe_initial_position()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		queue_free()
		return
	if _delay_remaining > 0.0:
		_delay_remaining -= delta
		if _delay_remaining <= 0.0:
			monitoring = true
		return
	if _settled:
		return
	_fall_velocity = minf(_fall_velocity + FALL_ACCELERATION * delta, MAX_FALL_SPEED)
	var start := global_position
	var finish := start + Vector2.DOWN * _fall_velocity * delta
	var query := PhysicsRayQueryParameters2D.create(start, finish + Vector2.DOWN * RADIUS, 1)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = finish
		return
	var impact: Vector2 = hit.get("position", finish)
	global_position = impact - Vector2.DOWN * RADIUS
	_settled = true


func _on_body_entered(body: Node2D) -> void:
	if _claimed or not body.is_in_group(&"player"):
		return
	if kind not in [&"energy_refill", &"missile_refill", &"flux_refill"]:
		queue_free()
		return
	if GameState.collect_pickup("", kind):
		_claimed = true
		var audio := get_node_or_null("/root/Audio")
		var pickup_sound := Catalog.pickup_sound_for_kind(kind)
		if audio != null and pickup_sound != &"":
			audio.call("play_sfx", pickup_sound)
		set_deferred("monitoring", false)
		queue_free()


func _safe_initial_position() -> void:
	for step in 5:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = global_position
		query.collision_mask = 1
		if get_world_2d().direct_space_state.intersect_point(query, 1).is_empty():
			return
		global_position += Vector2.UP * RADIUS


func _draw() -> void:
	# Generated refill icon supplies soft alpha and distinct energy/missile identity.
	pass
