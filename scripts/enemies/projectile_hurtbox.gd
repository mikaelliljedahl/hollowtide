class_name EnemyProjectileHurtbox extends Area2D

const ENEMY_COLLISION_LAYER := 8
const ALPHA_THRESHOLD := 0.05
const POLYGON_SIMPLIFICATION := 2.0
const MIN_POLYGON_AREA := 24.0

static var _polygon_cache: Dictionary = {}


func _init() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(&"projectile_hurtbox")


func configure(
	cache_key: StringName,
	images: Array[Image],
	soft_edge_margin: int = 0,
) -> void:
	_clear_shapes()
	var polygons: Array = _polygon_cache.get(cache_key, [])
	if polygons.is_empty():
		polygons = _build_polygons(images, soft_edge_margin)
		_polygon_cache[cache_key] = polygons
	for source_polygon: PackedVector2Array in polygons:
		var collision := CollisionPolygon2D.new()
		var transformed := PackedVector2Array()
		var frame_size := images[0].get_size()
		var frame_center := Vector2(frame_size) * 0.5
		for point in source_polygon:
			transformed.append(point - frame_center)
		collision.polygon = transformed
		add_child(collision)


func set_enabled(enabled: bool) -> void:
	collision_layer = ENEMY_COLLISION_LAYER if enabled else 0


func _build_polygons(images: Array[Image], soft_edge_margin: int) -> Array:
	if images.is_empty() or images[0] == null or images[0].is_empty():
		return []
	var frame_size := images[0].get_size()
	var mask := BitMap.new()
	mask.create(frame_size)
	for image in images:
		if image == null or image.is_empty() or image.get_size() != frame_size:
			continue
		for y in frame_size.y:
			for x in frame_size.x:
				if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
					mask.set_bit(x, y, true)
	if soft_edge_margin > 0:
		mask.grow_mask(soft_edge_margin, Rect2i(Vector2i.ZERO, frame_size))
	var result: Array = []
	for polygon in mask.opaque_to_polygons(
		Rect2i(Vector2i.ZERO, frame_size), POLYGON_SIMPLIFICATION
	):
		if absf(_signed_area(polygon)) >= MIN_POLYGON_AREA:
			result.append(polygon)
	return result


func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in polygon.size():
		var next_index := (index + 1) % polygon.size()
		area += polygon[index].cross(polygon[next_index])
	return area * 0.5


func _clear_shapes() -> void:
	for child in get_children():
		child.queue_free()
