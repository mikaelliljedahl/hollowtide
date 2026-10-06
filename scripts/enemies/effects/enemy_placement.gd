extends RefCounted
## Placement, leash and frozen-shape helpers for CombatEnemy.

const VisualProfiles = preload("res://scripts/enemies/effects/runtime_visual_profiles.gd")
## Bubble Snare: margin around the body collider, and how much of the bubble the art may fill
## (a box at 0.7 of a circle's diameter keeps its corners inside the rim).
const BUBBLE_MARGIN := 10.0
const BUBBLE_ART_FILL := 0.7


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


## Bubble Snare (D19), local to the enemy: the bubble wraps the body collider with its rim on the
## collider's top, because that top is the platform she stands on (floater heights in the
## campaign graph are measured from it).
static func bubble_rect(enemy: CombatEnemy) -> Rect2:
	var body := Rect2(-25.0, -25.0, 50.0, 50.0)
	var shape := enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		var size := (shape.shape as RectangleShape2D).size
		body = Rect2(shape.position - size * 0.5, size)
	# Grow 10 px all round, then sink it so the drawn rim (2 px half-width) meets the top.
	var rect := body.grow(BUBBLE_MARGIN)
	rect.position.y += BUBBLE_MARGIN - 2.0
	return rect


## Sprite transform that squeezes the enemy's visible art into `bubble` (centred, aspect kept),
## so the drawn creature stays inside the smaller collider-sized bubble while it is trapped.
static func bubble_sprite_fit(enemy: CombatEnemy, bubble: Rect2) -> Transform2D:
	var fit := Transform2D(0.0, enemy._visual_base_scale, 0.0, enemy._visual_base_position)
	if enemy._sprite == null or enemy._sprite.texture == null:
		return fit
	var image := enemy._sprite.texture.get_image()
	if image == null or image.is_empty():
		return fit
	var used := Rect2(image.get_used_rect())
	used.position -= Vector2(image.get_size()) * 0.5
	var base := enemy._visual_base_scale.abs()
	var art := Vector2(used.size.x * base.x, used.size.y * base.y)
	if art.x <= 0.0 or art.y <= 0.0:
		return fit
	var shrink := minf(1.0, BUBBLE_ART_FILL * minf(bubble.size.x / art.x, bubble.size.y / art.y))
	var offset := used.get_center() * enemy._visual_base_scale * shrink
	if enemy._sprite.flip_h:
		offset.x = -offset.x
	return Transform2D(0.0, enemy._visual_base_scale * shrink, 0.0, bubble.get_center() - offset)
