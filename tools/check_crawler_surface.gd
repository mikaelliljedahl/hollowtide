extends Node

const CRAWLER_SCENE: PackedScene = preload("res://scenes/enemies/crawler.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01.tscn")
const SUPPORT_FEET_OFFSET := 16.0

var failures: Array[String] = []
var _sandbox: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_outer_and_inner_corners()
	await _test_live_terrain_mutation()
	await _test_real_level_after_dev_build()
	if failures.is_empty():
		print("PASS: crawler follows live floor/wall/ceiling contours in real and mutation worlds")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _test_outer_and_inner_corners() -> void:
	_sandbox = Node2D.new()
	add_child(_sandbox)
	_add_static_rect(Vector2(500, 500), Vector2(320, 320))
	var crawler := _spawn_crawler(Vector2(500, 324), 1, 240.0)
	var observed: Array[Vector2] = []
	for _frame in 420:
		await get_tree().physics_frame
		if crawler.has_surface_contact():
			_append_unique_normal(observed, crawler.surface_normal())
	print("Crawler outer-corner normals: ", observed)
	_check(_has_normal(observed, Vector2.UP), "outer contour includes floor")
	_check(_has_normal(observed, Vector2.RIGHT), "outer contour turns onto right wall")
	_check(_has_normal(observed, Vector2.DOWN), "outer contour turns onto ceiling underside")
	_check(_has_normal(observed, Vector2.LEFT), "outer contour turns onto left wall")
	_check(crawler.has_surface_contact(), "outer contour never leaves terrain")
	await _clear_sandbox()

	_sandbox = Node2D.new()
	add_child(_sandbox)
	_add_static_rect(Vector2(500, 732), Vector2(500, 128))
	_add_static_rect(Vector2(782, 500), Vector2(64, 400))
	crawler = _spawn_crawler(Vector2(600, 652), 1, 180.0)
	var saw_inner_wall := false
	for _frame in 100:
		await get_tree().physics_frame
		if crawler.surface_normal().dot(Vector2.LEFT) > 0.94:
			saw_inner_wall = true
	print("Crawler inner-corner floor-to-wall: ", saw_inner_wall)
	_check(saw_inner_wall, "inner corner turns from floor onto wall")
	_check(crawler.has_surface_contact(), "inner corner retains contact")
	await _clear_sandbox()


func _test_live_terrain_mutation() -> void:
	_sandbox = Node2D.new()
	add_child(_sandbox)
	var crawler := _spawn_crawler(Vector2(400, 360), -1, 120.0)
	await _physics_frames(3)
	_check(not crawler.has_surface_contact(), "crawler waits instead of moving through empty air")
	var waiting_position := crawler.global_position
	var floor := _add_static_rect(Vector2(400, 500), Vector2(360, 64))
	await _physics_frames(3)
	_check(crawler.has_surface_contact(), "crawler acquires terrain added after child ready")
	_check(crawler.surface_normal().dot(Vector2.UP) > 0.94, "added floor provides live normal")
	floor.queue_free()
	await _physics_frames(3)
	_check(not crawler.has_surface_contact(), "crawler drops contact when terrain is removed")
	var detached_position := crawler.global_position
	await _physics_frames(3)
	_check(
		crawler.global_position.distance_to(detached_position) < 0.01,
		"crawler does not continue predetermined route after removal",
	)
	_check(
		waiting_position.distance_to(detached_position) > 1.0,
		"crawler moved only after floor existed"
	)
	_add_static_rect(detached_position + Vector2(-110, 0), Vector2(64, 300))
	await _physics_frames(3)
	_check(crawler.has_surface_contact(), "crawler reacquires nearest changed contour")
	_check(crawler.surface_normal().dot(Vector2.RIGHT) > 0.94, "reacquired wall normal is physical")
	await _clear_sandbox()


func _test_real_level_after_dev_build() -> void:
	GameState.reset_progress()
	var level := LEVEL_SCENE.instantiate()
	add_child(level)
	await _physics_frames(8)
	var crawlers := get_tree().get_nodes_in_group(&"enemies").filter(
		func(node: Node): return node is Crawler
	)
	_check(crawlers.size() >= 2, "actual dev level spawned original and annex crawlers")
	var attached := 0
	for crawler in crawlers:
		var support_error := _support_error(crawler) if crawler.has_surface_contact() else INF
		print(
			(
				"Crawler contact: pos=%s attached=%s normal=%s support_error=%.3f"
				% [
					crawler.global_position,
					crawler.has_surface_contact(),
					crawler.surface_normal(),
					support_error,
				]
			)
		)
		if crawler.has_surface_contact():
			attached += 1
			_check(support_error <= 1.5, "actual level crawler support offset <= 1.5 px")
	_check(attached == crawlers.size(), "all actual level crawlers attach to built TileMap terrain")
	print("Crawler real-level contact capture: %d/%d attached" % [attached, crawlers.size()])
	if DisplayServer.get_name() != "headless":
		var floor_crawler: Crawler
		for candidate in crawlers:
			if candidate.surface_normal().dot(Vector2.UP) > 0.94:
				floor_crawler = candidate
				break
		var player := get_tree().get_first_node_in_group(&"player") as Player
		if floor_crawler != null and player != null:
			player.reset_for_spawn(
				floor_crawler.global_position + Vector2(-260.0, SUPPORT_FEET_OFFSET)
			)
			player.facing = 1
			await _physics_frames(4)
		await get_tree().process_frame
		await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image != null:
			var save_error := image.save_png("/tmp/hollowtide-crawler-real-level.png")
			_check(save_error == OK, "actual level crawler screenshot saved")
			print("Crawler visual capture: /tmp/hollowtide-crawler-real-level.png")
	level.queue_free()
	await get_tree().physics_frame


func _support_error(crawler: Crawler) -> float:
	var normal := crawler.surface_normal()
	var query := (
		PhysicsRayQueryParameters2D
		. create(
			crawler.global_position + normal * 2.0,
			crawler.global_position - normal * 40.0,
			1,
			[crawler.get_rid()],
		)
	)
	var hit := crawler.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	return absf(crawler.global_position.distance_to(hit["position"]) - 16.0)


func _spawn_crawler(position: Vector2, direction: int, speed: float) -> Crawler:
	var crawler := CRAWLER_SCENE.instantiate() as Crawler
	crawler.travel_direction = direction
	crawler.move_speed = speed
	crawler.global_position = position
	_sandbox.add_child(crawler)
	return crawler


func _add_static_rect(position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = position
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)
	_sandbox.add_child(body)
	return body


func _append_unique_normal(normals: Array[Vector2], candidate: Vector2) -> void:
	for normal in normals:
		if normal.dot(candidate) > 0.94:
			return
	normals.append(candidate)


func _has_normal(normals: Array[Vector2], expected: Vector2) -> bool:
	for normal in normals:
		if normal.dot(expected) > 0.94:
			return true
	return false


func _physics_frames(count: int) -> void:
	for _frame in count:
		await get_tree().physics_frame


func _clear_sandbox() -> void:
	_sandbox.queue_free()
	await get_tree().physics_frame
	_sandbox = null


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
