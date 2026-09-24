class_name DashDeflect
extends RefCounted
## Timed dash deflect (internal id; design in docs/features/dash-deflect.md). For WINDOW_SECONDS
## after an Undertow Dash starts, an enemy projectile the body touches is turned around along its
## incoming line as a player-owned ReflectedShot. Later in the dash, projectiles are only passed
## through as before. One input, one outcome: while the window is open every other action press is
## dropped (Player._physics_process), so no second action can come out of it.

## Same leniency as COYOTE_TIME: the first six physics frames (~150 px) of the 0.18 s burst.
const WINDOW_SECONDS := 0.10
const SHOT_GROUP := &"enemy_shot"
const HIT_STOP_SECONDS := 0.05
## Float residue of 0.10 - 6 * (1 / 60) must not keep the window open for a seventh frame.
const EPSILON := 0.0001

var reflected_count := 0
var _player: Player
var _remaining := 0.0


func _init(player: Player) -> void:
	_player = player


func is_open() -> bool:
	return _remaining > EPSILON


func open() -> void:
	_remaining = WINDOW_SECONDS


func close() -> void:
	_remaining = 0.0


func tick(delta: float) -> void:
	_remaining = maxf(_remaining - delta, 0.0)


## Drops every action press made while the window is open, so none acts later either.
func discard_inputs() -> void:
	_player._jump_buffer_timer = 0.0
	_player._slip_press_queued = false
	_player._beam_press_queued = false
	_player._missile_press_queued = false
	_player._cycle_press_queued = false


## Turns every enemy shot that reaches `area` (the dash's swept body rectangle) this frame. The
## shot's next step is included so a shot is caught before its own ray reaches the body.
func sweep(area: Rect2, delta: float) -> void:
	if not is_open():
		return
	for node in _player.get_tree().get_nodes_in_group(SHOT_GROUP):
		var shot := node as EnemyProjectile
		if shot == null or shot.is_queued_for_deletion():
			continue
		var reach := area.grow(7.0 * shot.size_scale)
		var next := shot.global_position + shot.direction * shot.speed * delta
		if reach.has_point(shot.global_position) or reach.has_point(next):
			reflect(shot)


## Called by a shot whose ray reached the player; true when the shot was turned instead.
func try_reflect(shot: EnemyProjectile) -> bool:
	if not is_open() or shot == null or shot.is_queued_for_deletion():
		return false
	reflect(shot)
	return true


func reflect(shot: EnemyProjectile) -> void:
	var parent := shot.get_parent()
	var origin := shot.global_position
	var heading := -shot.direction
	shot.set_physics_process(false)
	shot.hide()
	shot.queue_free()
	if parent == null:
		return
	reflected_count += 1
	var returned := ReflectedShot.new()
	returned.style = shot.style
	returned.size_scale = shot.size_scale
	parent.add_child(returned)
	returned.global_position = origin
	returned.launch(heading)
	DashFx.spawn_turn(parent, origin, heading, shot.size_scale)
	GameJuice.play_sfx(&"dash_deflect", &"dash_hit")
	GameJuice.hit_stop(_player, HIT_STOP_SECONDS)
