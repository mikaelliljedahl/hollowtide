extends Node2D
## `bat_swarm`: a dark cluster of sleeping bats clinging to the ceiling. When the player passes
## below (or shoots it) the pods rustle for a moment and then burst into 4-7 bats.

const TRIGGER_HALF_WIDTH := 290.0
const TRIGGER_DEPTH := 580.0
const PROJECTILE_TRIGGER_RADIUS := 150.0
const RUSTLE_SECONDS := 0.4
const MIN_BATS := 4
const MAX_BATS := 7
const ROOST_SCALE := 0.62
const HitResult = preload("res://scripts/combat/hit_result.gd")

var enemy_id: StringName = &"bat_swarm"
var runtime_id: StringName = &"bat_swarm"
var arena_bounds := Rect2()
var state: StringName = &"roosting"
var bats: Array[Node2D] = []
var _timer := 0.0
var _age := 0.0
var _snap_frames := 3
var _sprite: Sprite2D
var _hurtbox: Area2D
var _rng := RandomNumberGenerator.new()
var _pods: Array[Vector2] = []


func _ready() -> void:
	add_to_group(&"surprise_roosts")
	_rng.seed = hash("bat_swarm") ^ int(global_position.x * 13.0 + global_position.y * 7.0)
	var count := _rng.randi_range(MIN_BATS, MAX_BATS)
	for index in count:
		var x := (float(index) - float(count - 1) * 0.5) * 22.0 + _rng.randf_range(-5, 5)
		_pods.append(Vector2(x, 26.0 + _rng.randf_range(0.0, 20.0)))
	var path := SurpriseCatalog.art_path("bat_roost")
	if ResourceLoader.exists(path):
		_sprite = Sprite2D.new()
		_sprite.texture = load(path) as Texture2D
		_sprite.scale = Vector2.ONE * ROOST_SCALE
		_sprite.z_index = -1
		# Claws at y≈14 of the 256 frame meet the ceiling line (local y = 0).
		_sprite.position = Vector2(0.0, (128.0 - 14.0) * ROOST_SCALE)
		add_child(_sprite)
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 8
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	_hurtbox.add_to_group(&"projectile_hurtbox")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(150, 80)
	shape.shape = rect
	shape.position = Vector2(0, 42)
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


func configure_arena(bounds: Rect2) -> void:
	arena_bounds = bounds


func _physics_process(delta: float) -> void:
	_age += delta
	if _snap_frames > 0:
		_snap_frames -= 1
		if _snap_frames == 0:
			_snap_to_ceiling()
	match state:
		&"roosting":
			if _should_wake():
				wake()
		&"rustling":
			_timer -= delta
			if _timer <= 0.0:
				_burst()
	queue_redraw()


## Starts the short rustle warning that precedes the burst.
func wake() -> void:
	if state != &"roosting":
		return
	state = &"rustling"
	_timer = RUSTLE_SECONDS
	SurpriseSfx.play(self, &"bat_rustle", -4.0)


func take_damage(amount: int, kind: StringName) -> void:
	receive_hit(amount, kind)


func receive_hit(_amount: int, _kind: StringName, _hit_context := {}) -> HitResult.Reaction:
	if state == &"roosting" or state == &"rustling":
		_burst()
		return HitResult.Reaction.TRIGGERED
	return HitResult.Reaction.PASS


func is_vulnerable_to(_kind: StringName) -> bool:
	return false


func presentation_state() -> StringName:
	return state


func _should_wake() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null:
		var offset := player.global_position - global_position
		if offset.y > -40.0 and offset.y < TRIGGER_DEPTH and absf(offset.x) < TRIGGER_HALF_WIDTH:
			return true
	for node in get_tree().get_nodes_in_group(&"transient"):
		if node is ProjectileBase or node.is_in_group(&"bombs"):
			if (node as Node2D).global_position.distance_to(global_position) < 150.0:
				return true
	return false


func _burst() -> void:
	if state == &"burst":
		return
	state = &"burst"
	_hurtbox.collision_layer = 0
	if _sprite != null:
		_sprite.hide()
	SurpriseSfx.play(self, &"bat_burst", 0.0)
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	for index in _pods.size():
		var bat := SurpriseCatalog.create(&"bat")
		if bat == null:
			continue
		add_child(bat)
		bat.global_position = global_position + _pods[index] + Vector2(0, 10)
		if bat.has_method("configure_arena"):
			bat.call("configure_arena", _bat_bounds())
		var spread := (float(index) / maxf(float(_pods.size() - 1), 1.0) - 0.5) * 2.0
		var toward := 0.0
		if player != null:
			toward = signf(player.global_position.x - global_position.x) * 120.0
		bat.call("launch", Vector2(spread * 380.0 + toward, _rng.randf_range(160.0, 320.0)))
		for group in get_groups():
			if not String(group).begins_with("_") and group != &"surprise_roosts":
				bat.add_to_group(group)
		bats.append(bat)


func _bat_bounds() -> Rect2:
	if arena_bounds.size != Vector2.ZERO:
		return arena_bounds.grow(120.0)
	return Rect2(global_position - Vector2(700, 100), Vector2(1400, 900))


func _snap_to_ceiling() -> void:
	var query := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0, 40), global_position + Vector2(0, -560), 1
	)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = Vector2(hit["position"]).y - 2.0


func _draw() -> void:
	if state == &"burst" or _sprite != null:
		if _sprite != null and state == &"rustling":
			_sprite.position.x = sin(_age * 60.0) * 2.5
		return
	# Placeholder: dark leathery pods hanging from the ceiling line.
	var shake := sin(_age * 60.0) * 2.5 if state == &"rustling" else 0.0
	for pod in _pods:
		var center := pod + Vector2(shake, 0)
		draw_line(Vector2(pod.x, 0), center + Vector2(0, -12), Color(0.1, 0.09, 0.1), 2.0)
		draw_colored_polygon(
			PackedVector2Array(
				[
					center + Vector2(-8, -12),
					center + Vector2(8, -12),
					center + Vector2(6, 10),
					center + Vector2(0, 16),
					center + Vector2(-6, 10),
				]
			),
			Color(0.11, 0.1, 0.12)
		)
		if state == &"rustling":
			draw_circle(center + Vector2(0, 6), 1.6, Color(0.5, 0.9, 0.85))
