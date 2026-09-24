class_name SurpriseEnemy
extends CombatEnemy
## Shared base for the D20 surprise enemies. Reuses CombatEnemy for damage, freeze/bubble
## status, hit feedback, death effects and drops; subclasses only add a state machine
## (`_special_state` / `_special_timer`), poses and placeholder drawing.
##
## Telegraphs use `_telegraph_remaining` purely as the visual wind-up glow; the state machine
## itself lives in `_surprise_ai`, so an interrupting hit can never strand an attack.

const NO_GATE := -1
const GROUND_ACCEL := 2600.0

## Pose -> Texture2D, from SurpriseCatalog.ART_DIR. Empty until the art batch lands.
var _poses: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _state_age := 0.0
## Ground creatures fall with gravity and are clamped only horizontally.
var grounded := false
## Arc/thread movers position themselves and skip the arena clamp.
var free_moving := false
var _tell: Node2D


func _ready() -> void:
	super._ready()
	var info := SurpriseCatalog.data(enemy_id)
	max_health = int(info["max_health"])
	health = max_health
	contact_damage = int(info["contact_damage"])
	freeze_capable = bool(info["freeze_capable"])
	_rng.seed = hash(String(enemy_id)) ^ int(global_position.x * 13.0 + global_position.y * 7.0)
	add_to_group(&"surprise_enemies")
	_tell = Node2D.new()
	_tell.name = "Tell"
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_tell.material = glow
	_tell.z_index = 1
	add_child(_tell)
	_tell.draw.connect(_on_tell_draw)
	_initialize_special_state()
	_surprise_ready()


# --- virtuals for subclasses -------------------------------------------------------------


func _surprise_ready() -> void:
	pass


## Pose name -> PNG base name inside SurpriseCatalog.ART_DIR. The first entry is the default.
func _pose_files() -> Dictionary:
	return {}


func _current_pose() -> StringName:
	return &""


func _reset_state() -> void:
	pass


func _surprise_ai(_player: Node2D, _has_target: bool, _delta: float) -> void:
	velocity = Vector2.ZERO


## Return a HitResult.Reaction to override the normal damage path, or NO_GATE.
func _hit_gate(_kind: StringName) -> int:
	return NO_GATE


func _on_gated_hit(_kind: StringName) -> void:
	pass


func _on_damaged(_kind: StringName) -> void:
	pass


func _contact_active() -> bool:
	return true


func _faces_player() -> bool:
	return false


func _on_defeated() -> void:
	pass


func _draw_placeholder() -> void:
	draw_circle(Vector2.ZERO, 26.0, Color(0.3, 0.32, 0.36))


func _on_tell_draw() -> void:
	if not _dying:
		_draw_extra(_tell)


## Telegraph overlays (aim lines, bubbles, threads). Drawn additively on an unshaded child
## layer so the dark cave grading never swallows a warning.
func _draw_extra(_canvas: CanvasItem) -> void:
	pass


## False when the poses differ so much that their union would be hittable empty air.
func _hurtbox_spans_poses() -> bool:
	return true


## Tweak the sprite after CombatEnemy applied flash/frost/squash (rotation, offsets, alpha).
func _decorate_sprite() -> void:
	pass


# --- CombatEnemy overrides -----------------------------------------------------------------


func _initialize_special_state() -> void:
	_telegraph_remaining = 0.0
	_telegraph_action = &""
	_special_timer = 0.0
	_state_age = 0.0
	_reset_state()


func _configure_collision_profile() -> void:
	pass  # SurpriseCatalog.create() already sized body and contact shapes.


func _run_ai(delta: float) -> void:
	_state_age += delta
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	# Surprise enemies judge range with their own geometry (under the roost, across the gap,
	# at the pool edge); the arena only limits where they may move.
	var has_target := player != null
	_surprise_ai(player, has_target, delta)
	if not _has_art:
		_update_facing_value(player)


func _perform_telegraph_action() -> void:
	# Wind-up glow finished; the state machine owns what happens next.
	_telegraph_action = &""


func receive_hit(amount: int, kind: StringName, hit_context := {}) -> HitResult.Reaction:
	if _dying or amount < 0:
		return HitResult.Reaction.PASS
	var gate := _hit_gate(kind)
	if gate != NO_GATE:
		if gate == HitResult.Reaction.BLOCKED:
			var impact := _impact_position(hit_context)
			_spawn_blocked_hit(impact, _hit_direction(hit_context, impact))
		_on_gated_hit(kind)
		return gate as HitResult.Reaction
	var result := super.receive_hit(amount, kind, hit_context)
	if result == HitResult.Reaction.DAMAGE and not _dying:
		_on_damaged(kind)
	return result


func is_vulnerable_to(kind: StringName) -> bool:
	if _hit_gate(kind) != NO_GATE:
		return false
	return super.is_vulnerable_to(kind)


func _on_player_detector_body_entered(body: Node2D) -> void:
	if not _contact_active() or is_frozen or _dying or not body.has_method(&"take_damage"):
		return
	body.call(&"take_damage", contact_damage, global_position)


func _die() -> void:
	_on_defeated()
	super._die()


## Size the Bubble Snare to this creature (the shared default is a 140 px block, too big for
## a bat and too small for the stalker).
func _freeze() -> void:
	super._freeze()
	_bubble_rect = _bubble_local_rect()
	if is_instance_valid(_bubble_visual):
		_bubble_visual.rect = _bubble_rect


func _bubble_local_rect() -> Rect2:
	if _has_art and _sprite != null and _sprite.texture != null:
		var image := _sprite.texture.get_image()
		if image != null and not image.is_empty():
			var used := Rect2(image.get_used_rect())
			used.position -= Vector2(image.get_size()) * 0.5
			used.position *= _visual_base_scale
			used.size *= _visual_base_scale
			if _sprite.flip_h:
				used.position.x = -used.end.x
			used.position += _sprite.position
			return used.grow(8.0)
	var detector := get_node_or_null("PlayerDetector/CollisionShape2D") as CollisionShape2D
	var size := Vector2(60, 60)
	if detector != null and detector.shape is RectangleShape2D:
		size = (detector.shape as RectangleShape2D).size
	return Rect2(-size * 0.5, size).grow(10.0)


func presentation_state() -> StringName:
	if _dying:
		return &"dying"
	if is_frozen:
		return &"frozen"
	return _special_state if not _special_state.is_empty() else &"idle"


func _constrain_to_arena() -> void:
	if free_moving or arena_bounds.size == Vector2.ZERO:
		return
	if grounded:
		global_position.x = clampf(global_position.x, arena_bounds.position.x, arena_bounds.end.x)
		return
	global_position = _clamp_to_arena(global_position)


func _load_optional_sprite() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		return
	var files := _pose_files()
	for pose in files:
		var path := SurpriseCatalog.art_path(String(files[pose]))
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			if texture != null:
				_poses[pose] = texture
	if _poses.is_empty():
		_has_art = false
		_sprite.visible = false
		return
	var first: Texture2D = _poses.get(files.keys()[0], _poses.values()[0])
	_sprite.texture = first
	# CombatEnemy builds the projectile hurtbox from the union of texture and _open_texture.
	for texture in _poses.values():
		if not _hurtbox_spans_poses():
			break
		if texture != first and texture.get_size() == first.get_size():
			_open_texture = texture
			break
	_has_art = true
	_sprite.visible = true
	_fx = ShaderMaterial.new()
	_fx.shader = SPRITE_FX_SHADER
	_sprite.material = _fx
	_visual_base_position = _art_offset(first)
	_visual_base_scale = Vector2.ONE * _art_scale()


## Like CombatEnemy's alpha hurtbox, but with a small grown margin so thin legs, wings and
## tails decompose into clean convex pieces.
func _configure_projectile_hurtbox() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var image := _sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	var images: Array[Image] = [image]
	if _open_texture != null and _open_texture.get_image() != null:
		images.append(_open_texture.get_image())
	_projectile_hurtbox = ProjectileHurtboxScript.new() as EnemyProjectileHurtbox
	_projectile_hurtbox.name = "ProjectileHurtbox"
	_sprite.add_child(_projectile_hurtbox)
	_projectile_hurtbox.configure(StringName("surprise_" + String(enemy_id)), images, 3)


## Scale applied to the 256 px art. Subclasses size their creature here.
func _art_scale() -> float:
	return 0.5


## Default: art bottom (frame bottom minus 26 px margin) sits on the body's bottom edge.
func _art_offset(texture: Texture2D) -> Vector2:
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var half := 0.0
	if body != null and body.shape is RectangleShape2D:
		half = (body.shape as RectangleShape2D).size.y * 0.5
	var frame_half := texture.get_size().y * 0.5
	return Vector2(0.0, half - (frame_half - 26.0) * _art_scale())


func _update_visual_presentation() -> void:
	if _has_art and _sprite != null:
		var pose := _current_pose()
		if _poses.has(pose):
			_sprite.texture = _poses[pose]
	super._update_visual_presentation()
	if _has_art and _sprite != null:
		_decorate_sprite()


func _update_facing() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	_update_facing_value(player)
	if _sprite != null:
		_sprite.flip_h = _facing < 0.0
	if _projectile_hurtbox != null:
		_projectile_hurtbox.scale = Vector2(-1.0 if _facing < 0.0 else 1.0, 1.0)


func _update_facing_value(player: Node2D) -> void:
	if is_frozen or _dying:
		return
	if _faces_player() and player != null:
		var dx := player.global_position.x - global_position.x
		if absf(dx) > 12.0:
			_facing = signf(dx)
	elif absf(velocity.x) > 8.0:
		_facing = signf(velocity.x)


func _draw() -> void:
	super._draw()
	if not _has_art and not _dying:
		_draw_placeholder()
	if _tell != null:
		_tell.queue_redraw()


# --- helpers -------------------------------------------------------------------------------


func _set_state(state: StringName, timer := 0.0) -> void:
	_special_state = state
	_special_timer = timer
	_state_age = 0.0


func _wind_up(seconds: float) -> void:
	_telegraph_remaining = minf(seconds, MAX_TELEGRAPH_SECONDS)
	_telegraph_action = &""


func _apply_gravity(delta: float, gravity := GROUND_GRAVITY) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + gravity * delta, 1600.0)


func _ground_toward(target_speed: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, target_speed, GROUND_ACCEL * delta)


func _sfx(id: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	SurpriseSfx.play(self, id, volume_db, pitch)


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(query)


func _line_of_sight(to: Vector2) -> bool:
	return _ray(global_position + Vector2(0, -20), to).is_empty()


## Placeholder tint including hit flash, telegraph glow and frost.
func _placeholder_color(base: Color) -> Color:
	var color := base
	if _telegraph_remaining > 0.0:
		color = color.lerp(Color(1.0, 0.7, 0.3), 0.35 + 0.25 * sin(_age * 24.0))
	if _hit_flash_remaining > 0.0:
		color = color.lerp(Color.WHITE, 0.8)
	elif _block_flash_remaining > 0.0:
		color = color.lerp(Color(0.62, 0.68, 0.78), 0.6)
	if is_frozen:
		color = color.lerp(Color(0.7, 0.9, 1.0), 0.6)
	return color


func _mirror(points: PackedVector2Array) -> PackedVector2Array:
	if _facing >= 0.0:
		return points
	var out := PackedVector2Array()
	for point in points:
		out.append(Vector2(-point.x, point.y))
	return out
