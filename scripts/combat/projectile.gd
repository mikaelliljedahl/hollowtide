class_name ProjectileBase extends Area2D

const HitResult = preload("res://scripts/combat/hit_result.gd")

@export var speed := 0.0
@export var lifetime := 1.0
@export var damage_amount := 1
@export var damage_kind: StringName = &"beam":
	set(value):
		damage_kind = value
		_damage_kind_changed()

const MAX_PASSTHROUGH_GATES := 8
const MAX_HITS_PER_QUERY := 32
const TERRAIN_COLLISION_BIT := 1

var _direction := Vector2.RIGHT
var _age := 0.0
var _consumed := false
var _passed_gate_rids: Array[RID] = []


func _ready() -> void:
	add_to_group(&"transient")
	collision_layer = 16
	collision_mask = 9
	monitoring = true
	monitorable = true
	if not has_node("CollisionShape2D"):
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 6.0
		shape.shape = circle
		add_child(shape)
	_damage_kind_changed()


func launch(new_direction: Vector2) -> void:
	_direction = Vector2.RIGHT if new_direction.is_zero_approx() else new_direction.normalized()
	rotation = _direction.angle()


func set_long_beam_enabled(_enabled: bool) -> void:
	pass


func can_spawn_at(point: Vector2) -> bool:
	var hits := _shape_hits(get_world_2d().direct_space_state, point, [get_rid()])
	for hit in hits:
		var target := hit.get("collider") as Node
		if _is_damageable(target) or _is_passable_gate(target):
			return true
	for hit in hits:
		if _is_terrain(hit.get("collider") as Node):
			return false
	return true


func _physics_process(delta: float) -> void:
	if _consumed:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var segment_start := global_position
	for segment_end in _motion_points(delta):
		var hit := _find_hit(segment_start, segment_end)
		if not hit.is_empty() and _handle_collision(hit):
			return
		global_position = segment_end
		_physics_point_traversed(segment_end)
		segment_start = segment_end


func _motion_points(delta: float) -> PackedVector2Array:
	return PackedVector2Array([global_position + _direction * speed * delta])


func _find_hit(start: Vector2, finish: Vector2) -> Dictionary:
	var state := get_world_2d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(_passed_gate_rids)
	var passed_gate_count := _passed_gate_rids.size()

	# Every accepted grate adds only its own RID to exclusion, then same remaining
	# segment is queried again. Wall directly behind grate is therefore hit this tick.
	for _query_index in MAX_PASSTHROUGH_GATES + 1:
		var origin_hits := _shape_hits(state, start, exclude)
		var blocking_origin := _first_blocking_hit(origin_hits)
		if not blocking_origin.is_empty():
			blocking_origin["position"] = start
			return blocking_origin
		var origin_gate := _first_passable_gate(origin_hits)
		if not origin_gate.is_empty():
			if passed_gate_count >= MAX_PASSTHROUGH_GATES:
				origin_gate["gate_limit"] = true
				origin_gate["position"] = start
				return origin_gate
			_activate_gate(origin_gate)
			_append_collider_rid(exclude, origin_gate)
			_remember_passed_gate(origin_gate)
			passed_gate_count += 1
			continue

		var ray := PhysicsRayQueryParameters2D.create(start, finish, collision_mask, exclude)
		ray.hit_from_inside = true
		ray.collide_with_areas = true
		var ray_hit := state.intersect_ray(ray)
		if ray_hit.is_empty():
			return {}
		var ray_target := ray_hit.get("collider") as Node
		if not _is_passable_gate(ray_target):
			return ray_hit
		if passed_gate_count >= MAX_PASSTHROUGH_GATES:
			ray_hit["gate_limit"] = true
			return ray_hit
		_activate_gate(ray_hit)
		_append_collider_rid(exclude, ray_hit)
		_remember_passed_gate(ray_hit)
		passed_gate_count += 1
	return {}


func _shape_hits(
	state: PhysicsDirectSpaceState2D, point: Vector2, exclude: Array[RID]
) -> Array[Dictionary]:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return []
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = Transform2D(rotation, point)
	query.collision_mask = collision_mask
	query.exclude = exclude
	query.collide_with_areas = true
	return state.intersect_shape(query, MAX_HITS_PER_QUERY)


func _first_blocking_hit(hits: Array[Dictionary]) -> Dictionary:
	for hit in hits:
		var target := hit.get("collider") as Node
		if _is_damageable(target) or not _is_passable_gate(target):
			return hit
	return {}


func _first_passable_gate(hits: Array[Dictionary]) -> Dictionary:
	for hit in hits:
		if _is_passable_gate(hit.get("collider") as Node):
			return hit
	return {}


func _handle_collision(hit: Dictionary) -> bool:
	var impact_position := Vector2(hit.get("position", global_position))
	var impact_normal := Vector2(hit.get("normal", -_direction))
	_physics_point_traversed(impact_position)
	if hit.get("gate_limit", false):
		_impact(impact_position, &"immune", impact_normal)
		_consume()
		return true
	var target := hit.get("collider") as Node
	var damage_target := _damage_target(target)
	var result := HitResult.Reaction.PASS
	if damage_target != null:
		if damage_target.has_method(&"receive_hit"):
			result = (
				damage_target
				. call(
					&"receive_hit",
					damage_amount,
					damage_kind,
					{"position": impact_position, "normal": impact_normal, "source": self},
				)
			)
		else:
			var vulnerable: bool = (
				not damage_target.has_method(&"is_vulnerable_to")
				or damage_target.call(&"is_vulnerable_to", damage_kind) == true
			)
			damage_target.call(&"take_damage", damage_amount, damage_kind)
			result = HitResult.Reaction.DAMAGE if vulnerable else HitResult.Reaction.BLOCKED
	var reaction := HitResult.projectile_reaction(result) if damage_target != null else &"wall"
	_impact(impact_position, reaction, impact_normal)
	_consume()
	return true


func _activate_gate(hit: Dictionary) -> void:
	var target := hit.get("collider") as Node
	if target == null or not target.has_method(&"allows_projectile"):
		return
	if target.call(&"allows_projectile", damage_kind) == false:
		return
	var intersection := Vector2(hit.get("position", global_position))
	var normal := Vector2(hit.get("normal", -_direction))
	_physics_point_traversed(intersection)
	_gate_impact(intersection, normal)


func _append_collider_rid(exclude: Array[RID], hit: Dictionary) -> void:
	var target := hit.get("collider") as CollisionObject2D
	if target == null:
		return
	var rid := target.get_rid()
	if rid.is_valid() and not exclude.has(rid):
		exclude.append(rid)


func _remember_passed_gate(hit: Dictionary) -> void:
	var target := hit.get("collider") as CollisionObject2D
	if target == null:
		return
	var rid := target.get_rid()
	if rid.is_valid() and not _passed_gate_rids.has(rid):
		_passed_gate_rids.append(rid)


func _is_damageable(target: Node) -> bool:
	return _damage_target(target) != null


func _damage_target(target: Node) -> Node:
	if target == null:
		return null
	if target.has_method(&"take_damage"):
		return target
	if target.is_in_group(&"projectile_hurtbox"):
		var owner := target.get_parent()
		while owner != null:
			if owner.has_method(&"take_damage"):
				return owner
			owner = owner.get_parent()
	return null


func _is_passable_gate(target: Node) -> bool:
	return (
		target != null
		and target.has_method(&"can_pass_projectile")
		and target.call(&"can_pass_projectile", damage_kind) == true
	)


func _is_terrain(target: Node) -> bool:
	return (
		target is CollisionObject2D
		and ((target as CollisionObject2D).collision_layer & TERRAIN_COLLISION_BIT) != 0
	)


func _damage_kind_changed() -> void:
	queue_redraw()


func _physics_point_traversed(_point: Vector2) -> void:
	pass


func _gate_impact(_position: Vector2, _normal: Vector2) -> void:
	pass


func _impact(_position: Vector2, _reaction: StringName, _normal: Vector2) -> void:
	pass


func _consume() -> void:
	if _consumed:
		return
	_consumed = true
	queue_free()
