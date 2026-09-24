class_name BeamFxTrail extends Node2D

const MAX_POINTS := 16
const BASE_HISTORY_SECONDS := 0.065
const LONG_HISTORY_SECONDS := 0.085
const OUTER_COLOR := Color(0.24, 0.92, 0.72, 0.15)
const INNER_COLOR := Color(0.64, 1.0, 0.88, 0.82)

var history_seconds := BASE_HISTORY_SECONDS
var outer_color := OUTER_COLOR
var inner_color := INNER_COLOR
var history_scale := 1.0
var physics_points: PackedVector2Array
var _point_times: PackedFloat32Array
var _physics_clock := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	add_to_group(&"beam_fx")


func _physics_process(delta: float) -> void:
	_physics_clock += delta
	_trim_history()
	queue_redraw()


func set_long_history(enabled: bool) -> void:
	history_seconds = (LONG_HISTORY_SECONDS if enabled else BASE_HISTORY_SECONDS) * history_scale
	_trim_history()


func set_active(enabled: bool) -> void:
	visible = enabled
	if not enabled:
		clear_points()


func clear_points() -> void:
	physics_points.clear()
	_point_times.clear()
	queue_redraw()


func record_physics_point(point: Vector2) -> void:
	if not visible:
		return
	if not physics_points.is_empty() and physics_points[-1].is_equal_approx(point):
		return
	physics_points.append(point)
	_point_times.append(_physics_clock)
	while physics_points.size() > MAX_POINTS:
		physics_points.remove_at(0)
		_point_times.remove_at(0)
	_trim_history()
	queue_redraw()


func get_physics_points() -> PackedVector2Array:
	return physics_points.duplicate()


func _trim_history() -> void:
	while not _point_times.is_empty() and _physics_clock - _point_times[0] > history_seconds:
		physics_points.remove_at(0)
		_point_times.remove_at(0)


func _draw() -> void:
	if physics_points.size() < 2:
		return
	var segment_count := physics_points.size() - 1
	for index in segment_count:
		var amount := float(index + 1) / float(segment_count)
		var start := physics_points[index]
		var finish := physics_points[index + 1]
		draw_line(start, finish, outer_color, lerpf(2.0, 10.0, amount), true)
		draw_line(start, finish, inner_color, lerpf(1.0, 4.2, amount), true)
