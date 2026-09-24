extends SurpriseEnemy
## Sits across a gap behind its own shell. It rises, draws a visible aim line that tracks the
## player and then locks (brighter, blinking) for a beat, fires one fast lance, and ducks back.
## Hidden it is armored against everything but a Resonance Pulse (bomb); exposed it is soft.

const TRIGGER_DISTANCE := 1250.0
const RISE_SECONDS := 0.3
const TRACK_SECONDS := 0.8
const LOCK_SECONDS := 0.34
const RECOVER_SECONDS := 0.45
const HIDE_SECONDS := 1.6
const SHOT_SPEED := 1000.0
const AIM_REACH := 1500.0
const ART_SCALE := 0.6
const LANCE_TIP_IN_ART := Vector2(107.0, 52.0)

var _aim := Vector2.RIGHT
var _aim_end := Vector2.ZERO
var _shot_damage := 14


func _surprise_ready() -> void:
	grounded = true
	_shot_damage = int(SurpriseCatalog.data(enemy_id).get("projectile_damage", contact_damage))


func _pose_files() -> Dictionary:
	return {&"hidden": "chasm_sniper_hidden", &"exposed": "chasm_sniper"}


func _current_pose() -> StringName:
	return &"hidden" if _special_state in [&"hidden", &"rise"] else &"exposed"


func _art_scale() -> float:
	return ART_SCALE


func _faces_player() -> bool:
	return _special_state in [&"hidden", &"rise", &"track"]


func _reset_state() -> void:
	_set_state(&"hidden", 1.0)


func _hit_gate(kind: StringName) -> int:
	if _special_state == &"hidden" and kind != &"bomb":
		return HitResult.Reaction.BLOCKED
	return NO_GATE


func _on_damaged(_kind: StringName) -> void:
	if _special_state in [&"track", &"lock"]:
		# A hit spoils the shot: it flinches and ducks.
		_set_state(&"recover", 0.3)
		_telegraph_remaining = 0.0


func _surprise_ai(player: Node2D, has_target: bool, delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = 0.0
	_special_timer -= delta
	var sees := (
		player != null
		and has_target
		and player.global_position.distance_to(global_position) < TRIGGER_DISTANCE
		and _ray(_muzzle_world(), _chest(player)).is_empty()
	)
	match _special_state:
		&"hidden":
			if _special_timer <= 0.0 and sees:
				_set_state(&"rise", RISE_SECONDS)
				_sfx(&"sniper_rise", -6.0)
		&"rise":
			if _special_timer <= 0.0:
				_set_state(&"track", TRACK_SECONDS)
				_sfx(&"sniper_charge")
		&"track":
			if not sees:
				_set_state(&"recover", 0.2)
			else:
				_aim = (_chest(player) - _muzzle_world()).normalized()
				if _special_timer <= 0.0:
					_set_state(&"lock", LOCK_SECONDS)
					_wind_up(LOCK_SECONDS)
					_sfx(&"sniper_lock")
		&"lock":
			if _special_timer <= 0.0:
				_fire()
				_set_state(&"recover", RECOVER_SECONDS)
		&"recover":
			if _special_timer <= 0.0:
				_set_state(&"hidden", HIDE_SECONDS)
	if _special_state in [&"track", &"lock"]:
		var hit := _ray(_muzzle_world(), _muzzle_world() + _aim * AIM_REACH)
		_aim_end = (
			Vector2(hit["position"]) if not hit.is_empty() else _muzzle_world() + _aim * AIM_REACH
		)


func _chest(player: Node2D) -> Vector2:
	return player.global_position + Vector2(0, -80)


func _muzzle_local() -> Vector2:
	if _has_art:
		return _visual_base_position + LANCE_TIP_IN_ART * ART_SCALE * Vector2(_facing, 1.0)
	return Vector2(50.0 * _facing, -22.0)


func _muzzle_world() -> Vector2:
	return global_position + _muzzle_local()


func _fire() -> void:
	var projectile := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	if projectile == null:
		return
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(projectile)
	projectile.global_position = _muzzle_world()
	projectile.style = &"shard"
	projectile.speed = SHOT_SPEED
	projectile.lifetime = 2.0
	projectile.launch(_aim, _shot_damage)
	_recoil = -_aim * 14.0
	CombatFx.spawn_muzzle_flash(parent, projectile.global_position, _aim, Color(0.4, 0.9, 1.0))
	_sfx(&"sniper_fire")


func _decorate_sprite() -> void:
	if _special_state == &"rise":
		var t := clampf(_state_age / RISE_SECONDS, 0.0, 1.0)
		_sprite.position.y += (1.0 - t) * 10.0
	elif _special_state == &"lock":
		_fx.set_shader_parameter(&"glow_color", Color(0.4, 0.9, 1.0))


func _draw_extra(canvas: CanvasItem) -> void:
	if _special_state not in [&"track", &"lock"]:
		return
	var from := _muzzle_local()
	var to := to_local(_aim_end)
	if _special_state == &"track":
		var fade := clampf(_state_age / TRACK_SECONDS, 0.0, 1.0)
		canvas.draw_line(from, to, Color(1.0, 0.35, 0.25, 0.18 + 0.3 * fade), 1.5, true)
	else:
		var blink := 0.55 + 0.45 * absf(sin(_age * 38.0))
		canvas.draw_line(from, to, Color(1.0, 0.3, 0.2, 0.45 * blink), 6.0, true)
		canvas.draw_line(from, to, Color(1.0, 0.85, 0.7, 0.9 * blink), 2.0, true)
		canvas.draw_circle(to, 6.0 * blink, Color(1.0, 0.5, 0.3, 0.8))


func _draw_placeholder() -> void:
	var color := _placeholder_color(Color(0.22, 0.24, 0.27))
	var hidden := _current_pose() == &"hidden"
	var dome := PackedVector2Array(
		[
			Vector2(-40, 30),
			Vector2(-44, 4),
			Vector2(-20, -18 if hidden else -34),
			Vector2(18, -22 if hidden else -38),
			Vector2(42, 4),
			Vector2(40, 30),
		]
	)
	draw_colored_polygon(dome, color)
	if not hidden:
		draw_line(Vector2(10 * _facing, -22), _muzzle_local(), Color(0.4, 0.85, 0.95), 5.0)
		draw_circle(Vector2(12 * _facing, -30), 5.0, Color(0.4, 0.9, 1.0))
