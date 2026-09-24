class_name HarpoonShot
extends ProjectileBase
## Harpoon (internal id `missiles`, D19): a heavy barbed bolt, slower than the beam. Hitting plain
## rock side-on embeds it as a short-lived standable peg (see HarpoonPeg).

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const HarpoonPegScript = preload("res://scripts/combat/harpoon_peg.gd")
const BOLT_ART_PATH := "res://assets/sprites/arsenal/harpoon_bolt.png"
const BOLT_FRAME := Vector2(96.0, 32.0)
const BOLT_TIP_X := 92.0
## Visual tip sits just ahead of the physics point so impacts never show the bolt inside rock.
const TIP_LEAD := 8.0
const TRAIL_INTERVAL := 0.03

var _trail_timer := 0.0
var _age_visual := 0.0
var _sprite: AnimatedSprite2D
var _last_hit_collider: Object


func _ready() -> void:
	speed = Catalog.HARPOON_SPEED
	lifetime = 1.8
	damage_amount = Catalog.MISSILE_DAMAGE
	damage_kind = &"missile"
	super._ready()
	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_configure_bolt_art()


func _configure_bolt_art() -> void:
	if _sprite == null:
		return
	var texture: Texture2D = null
	if ResourceLoader.exists(BOLT_ART_PATH):
		texture = load(BOLT_ART_PATH) as Texture2D
	if texture == null:
		_sprite.visible = false
		return
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 12.0)
	frames.set_animation_loop(&"default", true)
	var count := maxi(int(texture.get_width() / BOLT_FRAME.x), 1)
	for index in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(index * BOLT_FRAME.x, 0.0), BOLT_FRAME)
		frames.add_frame(&"default", atlas)
	_sprite.sprite_frames = frames
	# Tip of the art sits at the collision front.
	_sprite.position = Vector2(TIP_LEAD - (BOLT_TIP_X - BOLT_FRAME.x * 0.5), 0.0)
	_sprite.visible = true
	_sprite.play(&"default")


func has_bolt_art() -> bool:
	return _sprite != null and _sprite.visible


func _process(delta: float) -> void:
	_age_visual += delta
	_trail_timer -= delta
	queue_redraw()
	if _trail_timer > 0.0 or _consumed:
		return
	_trail_timer = TRAIL_INTERVAL
	var parent := get_parent()
	if parent == null:
		return
	# Wake of tiny air bubbles instead of rocket smoke.
	var puff := CombatFx.Puff.new()
	parent.add_child(puff)
	puff.global_position = (
		global_position - _direction * 80.0 + _direction.orthogonal() * randf_range(-5.0, 5.0)
	)
	puff.z_index = -1
	puff.configure(
		-_direction * 20.0 + Vector2(randf_range(-8.0, 8.0), randf_range(-26.0, -6.0)),
		0.42,
		2.0,
		5.0,
		Color(0.72, 0.95, 1.0, 0.55),
		1.0
	)


func _draw() -> void:
	# Procedural bolt is authored with its tip at x=46; shift it so the tip leads by TIP_LEAD.
	draw_set_transform(Vector2(TIP_LEAD - 46.0, 0.0))
	# Speed streak behind the bolt.
	draw_line(Vector2(-86.0, 0.0), Vector2(-40.0, 0.0), Color(0.6, 0.92, 1.0, 0.18), 6.0, true)
	draw_line(Vector2(-70.0, 0.0), Vector2(-40.0, 0.0), Color(0.85, 1.0, 1.0, 0.35), 2.0, true)
	if has_bolt_art():
		return
	_draw_procedural_bolt()


func _draw_procedural_bolt() -> void:
	var glint := 0.5 + 0.5 * sin(_age_visual * 30.0)
	var shaft := Color(0.36, 0.25, 0.17)
	var bone := Color(0.93, 0.9, 0.8)
	var brass := Color(0.72, 0.56, 0.26)
	draw_line(Vector2(-40.0, 0.0), Vector2(22.0, 0.0), shaft.darkened(0.3), 7.0, true)
	draw_line(Vector2(-40.0, -1.0), Vector2(22.0, -1.0), shaft, 4.0, true)
	for x in [-32.0, -22.0, -12.0]:
		draw_line(Vector2(x, -4.0), Vector2(x + 4.0, 4.0), Color(0.2, 0.6, 0.56, 0.9), 2.0, true)
	draw_rect(Rect2(14.0, -5.0, 9.0, 10.0), brass)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(22.0, -6.0),
				Vector2(46.0, 0.0),
				Vector2(22.0, 6.0),
				Vector2(28.0, 0.0),
			]
		),
		bone
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(24.0, -6.0), Vector2(16.0, -12.0), Vector2(30.0, -4.5)]), bone
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(24.0, 6.0), Vector2(16.0, 12.0), Vector2(30.0, 4.5)]), bone
	)
	draw_line(
		Vector2(28.0, -2.0), Vector2(44.0, 0.0), Color(0.6, 1.0, 0.95, 0.4 + 0.5 * glint), 1.5
	)


func _impact(position: Vector2, reaction: StringName, normal: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	GameJuice.shake(self, 2.0, 0.12)
	var embedded := false
	if reaction == &"wall":
		embedded = (
			HarpoonPegScript.try_embed(parent, position, normal, _last_hit_collider, self) != null
		)
	if embedded:
		GameJuice.play_sfx(&"harpoon_embed", &"missile_hit")
		ArsenalFx.spawn_sparks(parent, position, normal, 8, Color(0.85, 0.8, 0.7))
		return
	ArsenalFx.spawn_sparks(parent, position, normal, 10, Color(0.75, 0.95, 1.0))
	if reaction in [&"wall", &"immune", &"pass"]:
		GameJuice.play_sfx(&"harpoon_hit", &"missile_hit")


func _handle_collision(hit: Dictionary) -> bool:
	_last_hit_collider = hit.get("collider")
	return super._handle_collision(hit)
