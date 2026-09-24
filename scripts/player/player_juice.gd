extends RefCounted
## Player presentation juice: dust, hurt flash, impact shake. Purely visual; it only
## reads player state after movement has been resolved and never touches velocity,
## timers or tuned movement values.

const SPRITE_FX_SHADER = preload("res://resources/combat/sprite_fx.gdshader")
const HURT_FLASH_SECONDS := 0.12
const LAND_DUST_MIN_SPEED := 320.0
const HARD_LANDING_SPEED := 1150.0
const SLIDE_DUST_INTERVAL := 0.09
const SKID_DUST_INTERVAL := 0.08
const SKID_MIN_SPEED := 260.0

var _player: CharacterBody2D
var _fx: ShaderMaterial
var _last_velocity := Vector2.ZERO
var _was_on_floor := true
var _last_wall_pose := 0.0
var _last_invulnerability := 0.0
var _hurt_flash := 0.0
var _slide_timer := 0.0
var _skid_timer := 0.0
var _last_step_timer := 0.0


func _init(player: CharacterBody2D) -> void:
	_player = player


func tick(delta: float) -> void:
	GameJuice.ensure_time_restored()
	if _player == null or not _player.is_inside_tree():
		return
	var sprite := _player.get("_sprite") as AnimatedSprite2D
	if sprite != null and _fx == null:
		_fx = ShaderMaterial.new()
		_fx.shader = SPRITE_FX_SHADER
		sprite.material = _fx
	var on_floor := _player.is_on_floor()
	var is_ball := bool(_player.get("is_ball"))
	var feet := _player.global_position
	var parent := _player.get_parent()
	# Landing: dust scales with how hard we came down.
	if on_floor and not _was_on_floor and _last_velocity.y > LAND_DUST_MIN_SPEED:
		var strength := clampf(_last_velocity.y / 900.0, 0.45, 1.35) * (0.7 if is_ball else 1.0)
		CombatFx.spawn_dust(parent, feet, &"land", 1.0, strength)
		if _last_velocity.y > HARD_LANDING_SPEED:
			GameJuice.shake(_player, 3.0, 0.14)
	# Take-off from the ground.
	if _was_on_floor and not on_floor and _player.velocity.y < -300.0:
		CombatFx.spawn_dust(parent, feet, &"jump", 1.0, 0.9)
	# Wall jump: the pose timer is re-armed exactly when a wall jump fires.
	var wall_pose := float(_player.get("_wall_jump_pose_timer"))
	if wall_pose > _last_wall_pose + 0.05:
		var away := signf(_player.velocity.x) if absf(_player.velocity.x) > 1.0 else 1.0
		CombatFx.spawn_dust(parent, feet + Vector2(-away * 22.0, -70.0), &"wall", away, 1.0)
	_last_wall_pose = wall_pose
	# Wall slide: a thin trickle of grit at the hand/foot contact.
	_slide_timer = maxf(_slide_timer - delta, 0.0)
	if bool(_player.get("_wall_sliding")) and _slide_timer == 0.0:
		_slide_timer = SLIDE_DUST_INTERVAL
		var side := float(_player.get("_wall_side"))
		CombatFx.spawn_dust(parent, feet + Vector2(side * 22.0, -30.0), &"slide", -side, 0.8)
	# Running dust on each footstep while sprinting, and skid dust on hard turns.
	var step_timer := float(_player.get("_step_timer"))
	if on_floor and not is_ball and step_timer > _last_step_timer + 0.01:
		if bool(_player.get("_is_running")):
			CombatFx.spawn_dust(parent, feet, &"run", float(_player.get("facing")), 0.8)
	_last_step_timer = step_timer
	_skid_timer = maxf(_skid_timer - delta, 0.0)
	var input := Input.get_axis("move_left", "move_right")
	if (
		on_floor
		and not is_ball
		and _skid_timer == 0.0
		and absf(_player.velocity.x) > SKID_MIN_SPEED
		and input != 0.0
		and signf(input) != signf(_player.velocity.x)
	):
		_skid_timer = SKID_DUST_INTERVAL
		CombatFx.spawn_dust(parent, feet, &"skid", signf(_player.velocity.x) * -1.0, 1.0)
	# Hurt: a sharp red-white flash, a small shake and a few frames of hit-stop.
	var invulnerability := float(_player.get("_invulnerability_timer"))
	if invulnerability > _last_invulnerability + 0.05:
		_hurt_flash = HURT_FLASH_SECONDS
		GameJuice.shake(_player, 6.0, 0.22)
		GameJuice.hit_stop(_player, 0.05)
	_last_invulnerability = invulnerability
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	if _fx != null:
		var amount := _hurt_flash / HURT_FLASH_SECONDS * 0.85 * GameJuice.flash_strength()
		_fx.set_shader_parameter(&"flash_amount", amount)
		_fx.set_shader_parameter(&"flash_color", Color(1.0, 0.42, 0.36))
	_was_on_floor = on_floor
	_last_velocity = _player.velocity
