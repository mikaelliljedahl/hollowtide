extends RefCounted
## Placement, leash and frozen-shape helpers for CombatEnemy.

const VisualProfiles = preload("res://scripts/enemies/effects/runtime_visual_profiles.gd")


## True when a patrol heading `direction` has reached its arena leash edge. Arena clamping stops the
## body before any wall, so a patrol that only turns at walls would park at the edge forever.
static func at_leash_edge(enemy: CombatEnemy, direction: float) -> bool:
	var bounds := enemy.arena_bounds
	if not bounds.has_area():
		return false
	var edge := bounds.position.x if direction < 0.0 else bounds.end.x
	return (enemy.global_position.x - edge) * direction >= 0.0


static func snap_to_ceiling(enemy: CombatEnemy) -> void:
	# Hanging art must meet a real ceiling instead of dangling from empty air.
	if not enemy.is_inside_tree() or enemy._sprite == null:
		return
	var bounds: Array = VisualProfiles.profile(enemy.enemy_id).get("nominal_visible_bounds_px", [])
	if bounds.size() != 4:
		return
	var art_top := (
		enemy._visual_base_position.y + (float(bounds[1]) - 128.0) * enemy._visual_base_scale.y
	)
	# Start below the body so a spawn point inside a platform still finds its underside.
	var query := PhysicsRayQueryParameters2D.create(
		enemy.global_position + Vector2(0.0, 60.0),
		enemy.global_position + Vector2(0.0, -460.0),
		1,
		[enemy.get_rid()]
	)
	var hit := enemy.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var target_y: float = Vector2(hit["position"]).y - art_top - 4.0
	if (
		enemy.arena_bounds.size != Vector2.ZERO
		and not enemy.arena_bounds.has_point(Vector2(enemy.global_position.x, target_y))
	):
		return
	enemy.global_position.y = target_y
	enemy._home_position.y = target_y


static func snap_to_perch(enemy: CombatEnemy) -> void:
	# A perched gargoyle must sit on a ledge or floor, never in open air. The movement body rests
	# on the floor (physics would push it out otherwise) and the art is shifted so its visible
	# bottom meets the same floor line.
	if not enemy.is_inside_tree() or enemy._sprite == null or enemy._sprite.texture == null:
		return
	var query := PhysicsRayQueryParameters2D.create(
		enemy.global_position, enemy.global_position + Vector2(0.0, 900.0), 1, [enemy.get_rid()]
	)
	var hit := enemy.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var floor_y: float = Vector2(hit["position"]).y
	var half_height := 40.0
	var body := enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null and body.shape is RectangleShape2D:
		half_height = (body.shape as RectangleShape2D).size.y * 0.5 + body.position.y
	var target_y := floor_y - half_height - 0.5
	enemy.global_position.y = target_y
	enemy._home_position.y = target_y
	var image := enemy._sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	var texture_half := float(enemy._sprite.texture.get_height()) * 0.5
	var art_bottom := (
		enemy._visual_base_position.y
		+ (float(image.get_used_rect().end.y) - texture_half) * enemy._visual_base_scale.y
	)
	enemy._visual_base_position.y += floor_y + 2.0 - target_y - art_bottom
	enemy._update_visual_presentation()


static func ice_shape(enemy: CombatEnemy) -> PackedVector2Array:
	# A jagged translucent ice block around the visible silhouette.
	var bounds: Array = VisualProfiles.profile(enemy.enemy_id).get("nominal_visible_bounds_px", [])
	var rect := Rect2(-70.0, -70.0, 140.0, 140.0)
	if bounds.size() == 4:
		rect = Rect2(
			Vector2(float(bounds[0]) - 128.0, float(bounds[1]) - 128.0),
			Vector2(float(bounds[2]) - float(bounds[0]), float(bounds[3]) - float(bounds[1]))
		)
		rect.position *= enemy._visual_base_scale
		rect.size *= enemy._visual_base_scale
	rect = rect.grow(6.0)
	rect.position += enemy._visual_base_position
	var rng := RandomNumberGenerator.new()
	rng.seed = String(enemy.enemy_id).hash()
	var shape := PackedVector2Array()
	var center := rect.get_center()
	var steps := 18
	var radii := rect.size * 0.56
	for index in steps:
		var angle := TAU * float(index) / float(steps) + rng.randf_range(-0.08, 0.08)
		var direction := Vector2.RIGHT.rotated(angle)
		# Alternate crystal points and notches so the block reads as chipped ice.
		var jag := rng.randf_range(1.02, 1.14) if index % 2 == 0 else rng.randf_range(0.84, 0.94)
		shape.append(center + Vector2(direction.x * radii.x, direction.y * radii.y) * jag)
	return shape


## Bubble Snare (D19): ellipse around the visible silhouette, local to the enemy.
static func bubble_rect(enemy: CombatEnemy) -> Rect2:
	var shape := ice_shape(enemy)
	var rect := Rect2(shape[0], Vector2.ZERO)
	for point in shape:
		rect = rect.expand(point)
	return rect.grow(4.0)
