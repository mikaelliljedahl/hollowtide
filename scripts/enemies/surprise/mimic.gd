extends SurpriseEnemy
## `mimic` sits as an ordinary boulder; `mimic_lure` as a glowing pickup on a rock. When the
## player steps next to it (or shoots it) it rattles for a beat, lunges, scuttles around the
## player for a few seconds and then burrows back into its disguise somewhere else.
## Disguised: beam/wave/undertow glance off (armored rock) but still wake it; heavy hits land.

const TRIGGER_DISTANCE := Vector2(150.0, 110.0)
const LURE_TRIGGER_DISTANCE := Vector2(110.0, 120.0)
const REVEAL_SECONDS := 0.34
const LUNGE := Vector2(640.0, -430.0)
const SCUTTLE_SPEED := 330.0
const SCUTTLE_SECONDS := 2.6
const SETTLE_SECONDS := 0.5
const REARM_SECONDS := 1.4

var _scuttle_sign := 1.0
var _hop_timer := 0.0


func _surprise_ready() -> void:
	grounded = true


func _is_lure() -> bool:
	return enemy_id == &"mimic_lure"


func _pose_files() -> Dictionary:
	if _is_lure():
		return {&"closed": "mimic_lure", &"open": "mimic_lure_open"}
	return {&"closed": "mimic_rock", &"open": "mimic_open"}


func _current_pose() -> StringName:
	return &"closed" if _special_state in [&"disguised", &"settle"] else &"open"


func _art_scale() -> float:
	return 0.8


func _faces_player() -> bool:
	return _special_state in [&"reveal", &"lunge"]


func _reset_state() -> void:
	_set_state(&"disguised", 0.0)


func _contact_active() -> bool:
	return _special_state not in [&"disguised", &"settle"]


func _hit_gate(kind: StringName) -> int:
	if _special_state == &"disguised" and kind in [&"beam", &"wave", &"undertow"]:
		return HitResult.Reaction.BLOCKED
	return NO_GATE


func _on_gated_hit(_kind: StringName) -> void:
	_reveal()


func _on_damaged(_kind: StringName) -> void:
	if _special_state in [&"disguised", &"settle"]:
		_reveal()


func _surprise_ai(player: Node2D, has_target: bool, delta: float) -> void:
	_special_timer -= delta
	_apply_gravity(delta)
	match _special_state:
		&"disguised":
			velocity.x = 0.0
			if _special_timer <= 0.0 and player != null and has_target and _player_adjacent(player):
				_reveal()
		&"reveal":
			velocity.x = 0.0
			if _special_timer <= 0.0:
				var dir := (
					signf(player.global_position.x - global_position.x) if player else _facing
				)
				dir = dir if dir != 0.0 else 1.0
				velocity = Vector2(LUNGE.x * dir, LUNGE.y)
				_facing = dir
				_set_state(&"lunge", 0.25)
				_sfx(&"mimic_lunge")
		&"lunge":
			if _special_timer <= 0.0 and is_on_floor():
				_scuttle_sign = -_facing if _rng.randf() < 0.6 else _facing
				_set_state(&"scuttle", SCUTTLE_SECONDS)
				_hop_timer = _rng.randf_range(0.5, 0.9)
		&"scuttle":
			if is_on_wall():
				_scuttle_sign *= -1.0
			_ground_toward(_scuttle_sign * SCUTTLE_SPEED, delta)
			_hop_timer -= delta
			if _hop_timer <= 0.0 and is_on_floor():
				_hop_timer = _rng.randf_range(0.55, 1.0)
				velocity.y = -260.0
				if player != null and _rng.randf() < 0.5:
					_scuttle_sign = signf(player.global_position.x - global_position.x)
				_sfx(&"mimic_skitter", -8.0, _rng.randf_range(0.9, 1.2))
			if _special_timer <= 0.0 and is_on_floor():
				_set_state(&"settle", SETTLE_SECONDS)
		&"settle":
			_ground_toward(0.0, delta)
			if _special_timer <= 0.0:
				_set_state(&"disguised", REARM_SECONDS)


func _player_adjacent(player: Node2D) -> bool:
	var reach := LURE_TRIGGER_DISTANCE if _is_lure() else TRIGGER_DISTANCE
	var offset := player.global_position - global_position
	return absf(offset.x) < reach.x and absf(offset.y) < reach.y


func _reveal() -> void:
	if _special_state not in [&"disguised", &"settle"]:
		return
	_set_state(&"reveal", REVEAL_SECONDS)
	_wind_up(REVEAL_SECONDS)
	_sfx(&"mimic_rattle")


func _decorate_sprite() -> void:
	match _special_state:
		&"reveal":
			_sprite.position.x += sin(_age * 70.0) * 3.0
		&"disguised":
			if _is_lure():
				# The bait glints like a real pickup; the rock itself never moves.
				_fx.set_shader_parameter(&"glow_amount", 0.18 + 0.1 * sin(_age * 3.0))
				_fx.set_shader_parameter(&"glow_color", Color(1.0, 0.86, 0.5))
		&"scuttle":
			_sprite.rotation = sin(_age * 30.0) * 0.05


func _draw_placeholder() -> void:
	var rock := _placeholder_color(Color(0.27, 0.28, 0.31))
	var open := _current_pose() == &"open"
	var base_y := 32.0
	var shell := PackedVector2Array(
		[
			Vector2(-50, base_y),
			Vector2(-54, base_y - 30),
			Vector2(-30, base_y - 62),
			Vector2(10, base_y - 68),
			Vector2(44, base_y - 44),
			Vector2(52, base_y),
		]
	)
	if open:
		for i in shell.size():
			shell[i].y -= 14.0
		for leg in [-36.0, -14.0, 14.0, 36.0]:
			draw_line(
				Vector2(leg, base_y - 16), Vector2(leg * 1.2, base_y), Color(0.2, 0.2, 0.22), 5.0
			)
	draw_colored_polygon(_mirror(shell), rock)
	if open:
		var jaw := _mirror(
			PackedVector2Array(
				[Vector2(10, base_y - 44), Vector2(56, base_y - 50), Vector2(48, base_y - 26)]
			)
		)
		draw_colored_polygon(jaw, Color(0.08, 0.05, 0.06))
		draw_circle(Vector2(20 * _facing, base_y - 56), 4.0, Color(1.0, 0.65, 0.2))
	elif _is_lure():
		var glow := 0.5 + 0.5 * sin(_age * 3.0)
		draw_circle(Vector2(0, base_y - 80), 22.0 + glow * 4.0, Color(1.0, 0.9, 0.55, 0.18))
		draw_circle(Vector2(0, base_y - 80), 14.0, Color(1.0, 0.92, 0.7))
	else:
		draw_line(Vector2(-30, base_y - 30), Vector2(34, base_y - 34), Color(0.18, 0.18, 0.2), 1.5)
