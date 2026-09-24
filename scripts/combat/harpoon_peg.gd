class_name HarpoonPeg
extends StaticBody2D
## A harpoon bolt embedded in plain rock (D19). One tile long, standable from above only
## (one-way, frozen-platform layer 32 so only the player collides), lasts HARPOON_PEG_SECONDS,
## at most MAX_HARPOON_PEGS at once (the oldest crumbles). Group `transient`: room changes,
## deaths and resets remove it.

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const PEG_ART_PATH := "res://assets/sprites/arsenal/harpoon_peg.png"
const LENGTH := 64.0
const THICKNESS := 16.0
const SNAP := 16.0
const HEADROOM := 112.0
const WARN_SECONDS := 1.0
const PLATFORM_LAYER := 32
const TERRAIN_LAYER := 1
const DOOR_CLEARANCE := 160.0
const DOOR_GROUPS: Array[StringName] = [
	&"ability_gates", &"projectile_grate", &"campaign_flag_gate", &"dev_passage", &"doors"
]

var wall_side := 1  # +1: wall on the left, peg points right; -1: mirrored.
var remaining := Catalog.HARPOON_PEG_SECONDS
var _age := 0.0
var _art: Sprite2D
var _crumbling := false


func _ready() -> void:
	add_to_group(&"transient")
	add_to_group(&"harpoon_pegs")
	collision_layer = PLATFORM_LAYER
	collision_mask = 0
	z_index = 2
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(LENGTH, THICKNESS)
	shape.shape = rect
	shape.position = Vector2(float(wall_side) * LENGTH * 0.5, THICKNESS * 0.5)
	shape.one_way_collision = true
	shape.one_way_collision_margin = 8.0
	add_child(shape)
	var texture: Texture2D = null
	if ResourceLoader.exists(PEG_ART_PATH):
		texture = load(PEG_ART_PATH) as Texture2D
	if texture != null:
		_art = Sprite2D.new()
		_art.texture = texture
		_art.centered = false
		# Art: 128x48, wall surface at x=0, shaft top at y~14; drawn at half scale (64 px long).
		_art.scale = Vector2(float(wall_side), 1.0) * (LENGTH / float(texture.get_width()))
		_art.position = Vector2(0.0, -14.0 * _art.scale.y)
		add_child(_art)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	remaining -= delta
	if remaining <= 0.0:
		crumble()
		return
	if remaining < WARN_SECONDS:
		var blink := 0.55 + 0.45 * absf(cos(_age * 18.0))
		modulate.a = blink
	queue_redraw()


func crumble() -> void:
	if _crumbling:
		return
	_crumbling = true
	var parent := get_parent()
	if parent != null:
		var center := global_position + Vector2(float(wall_side) * LENGTH * 0.5, THICKNESS * 0.5)
		ArsenalFx.spawn_grit(parent, center, Vector2.UP, 4)
	queue_free()


func top_surface_y() -> float:
	return global_position.y


func _draw() -> void:
	if _art != null:
		return
	var s := float(wall_side)
	var shaft := Color(0.33, 0.23, 0.16)
	var bone := Color(0.9, 0.86, 0.76)
	var brass := Color(0.7, 0.55, 0.27)
	# Wooden shaft with a lighter top edge so it reads as a ledge.
	draw_rect(
		Rect2(Vector2(minf(0.0, s * LENGTH), 2.0), Vector2(LENGTH, 12.0)), shaft.darkened(0.25)
	)
	draw_rect(
		Rect2(Vector2(minf(0.0, s * LENGTH), 2.0), Vector2(LENGTH, 4.0)), shaft.lightened(0.2)
	)
	draw_rect(Rect2(Vector2(minf(s * 6.0, s * 16.0), 0.0), Vector2(10.0, 16.0)), brass)
	for x in [26.0, 38.0, 50.0]:
		draw_line(
			Vector2(s * x, 3.0), Vector2(s * (x + 5.0), 13.0), Color(0.2, 0.58, 0.54, 0.95), 2.5
		)
	# Frayed kelp tail at the free end.
	draw_line(
		Vector2(s * LENGTH, 8.0), Vector2(s * (LENGTH + 10.0), 18.0), Color(0.2, 0.5, 0.4), 2.0
	)
	draw_line(
		Vector2(s * LENGTH, 8.0), Vector2(s * (LENGTH + 13.0), 10.0), Color(0.2, 0.5, 0.4), 2.0
	)
	# Cracked rock where the bolt went in.
	for index in 4:
		var angle := -PI * 0.5 + float(index) * PI / 3.0
		var tip := Vector2(-s * 4.0, 8.0) + Vector2(-s * cos(angle), sin(angle)) * 14.0
		draw_line(Vector2(0.0, 8.0), tip, Color(0.12, 0.11, 0.1, 0.8), 2.0)
	draw_circle(Vector2(-s * 1.0, 8.0), 4.0, bone.darkened(0.5))


## Embeds a peg where a harpoon hit plain rock side-on. Returns null when the spot is not a side
## wall, is not plain terrain, is too cramped (tunnels) or would touch doors/gates.
static func try_embed(
	parent: Node, impact: Vector2, normal: Vector2, collider: Object, canvas: CanvasItem
) -> HarpoonPeg:
	if not is_instance_valid(parent) or not (collider is TileMapLayer):
		return null
	if absf(normal.x) < 0.7:
		return null
	var side := 1 if normal.x > 0.0 else -1
	if canvas == null or not canvas.is_inside_tree():
		return null
	var space := canvas.get_world_2d().direct_space_state
	# Shape hits report the projectile origin; find the exact wall surface on this row.
	var probe := PhysicsRayQueryParameters2D.create(
		impact + Vector2(float(side) * 48.0, 0.0),
		impact - Vector2(float(side) * 48.0, 0.0),
		TERRAIN_LAYER
	)
	var surface := space.intersect_ray(probe)
	if surface.is_empty():
		return null
	impact = Vector2(surface["position"])
	var top := snappedf(impact.y - THICKNESS * 0.5, SNAP)
	var anchor := Vector2(impact.x, top)
	var near_x := anchor.x + float(side) * 2.0
	var far_x := anchor.x + float(side) * LENGTH
	var body_rect := Rect2(
		Vector2(minf(near_x, far_x), top + 1.0), Vector2(absf(far_x - near_x), THICKNESS - 2.0)
	)
	var headroom_rect := Rect2(
		Vector2(body_rect.position.x, top - HEADROOM), Vector2(body_rect.size.x, HEADROOM)
	)
	if _rect_blocked(space, body_rect, true) or _rect_blocked(space, headroom_rect, true):
		return null
	if _near_door(canvas.get_tree(), body_rect.get_center()):
		return null
	# The wall must actually back the whole peg thickness.
	for y in [top + 2.0, top + THICKNESS - 2.0]:
		var ray := PhysicsRayQueryParameters2D.create(
			Vector2(anchor.x + float(side) * 6.0, y),
			Vector2(anchor.x - float(side) * 10.0, y),
			TERRAIN_LAYER
		)
		if space.intersect_ray(ray).is_empty():
			return null
	var existing := canvas.get_tree().get_nodes_in_group(&"harpoon_pegs")
	var live: Array[HarpoonPeg] = []
	for node in existing:
		var peg := node as HarpoonPeg
		if peg != null and not peg._crumbling and not peg.is_queued_for_deletion():
			live.append(peg)
	live.sort_custom(func(a: HarpoonPeg, b: HarpoonPeg): return a.remaining < b.remaining)
	while live.size() >= Catalog.MAX_HARPOON_PEGS:
		live.pop_front().crumble()
	var peg := HarpoonPeg.new()
	peg.wall_side = side
	parent.add_child(peg)
	peg.global_position = anchor
	return peg


static func _near_door(tree: SceneTree, point: Vector2) -> bool:
	for group in DOOR_GROUPS:
		for node in tree.get_nodes_in_group(group):
			var door := node as Node2D
			if door != null and door.global_position.distance_to(point) < DOOR_CLEARANCE:
				return true
	return false


static func _rect_blocked(
	space: PhysicsDirectSpaceState2D, rect: Rect2, include_platforms: bool
) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = TERRAIN_LAYER | (PLATFORM_LAYER if include_platforms else 0)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	for hit in space.intersect_shape(query, 8):
		var target := hit.get("collider") as Node
		if target is HarpoonPeg:
			continue
		return true
	return false
