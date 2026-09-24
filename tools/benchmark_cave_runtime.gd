extends Node

const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 360
const CAMERA_STEP := 8.0
const START_POSITION := Vector2(4200.0, 640.0)

var _level: Node2D
var _camera: Camera2D
var _phase := &"warmup"
var _phase_frames := 0
var _last_usec := 0
var _stationary_samples: Array[float] = []
var _moving_samples: Array[float] = []
var _stationary_process: Array[float] = []
var _moving_process: Array[float] = []
var _stationary_draws: Array[float] = []
var _moving_draws: Array[float] = []


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--benchmark-cave"):
		push_error("benchmark_cave_runtime requires --benchmark-cave")
		get_tree().quit(2)
		return
	var packed := load("res://scenes/levels/level_01.tscn") as PackedScene
	if packed == null:
		push_error("benchmark_cave_runtime cannot load level_01.tscn")
		get_tree().quit(2)
		return
	_level = packed.instantiate() as Node2D
	add_child(_level)
	var player_camera := _level.get_node_or_null("PlayerSpawn/Player/Camera2D") as Camera2D
	if player_camera != null:
		player_camera.enabled = false
	_camera = Camera2D.new()
	_camera.name = "BenchmarkCamera"
	_camera.position = START_POSITION
	_camera.position_smoothing_enabled = false
	_level.add_child(_camera)
	_camera.make_current()
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var now := Time.get_ticks_usec()
	var interval_ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_phase_frames += 1
	if _phase == &"warmup":
		_camera.position.x += CAMERA_STEP
		if _phase_frames >= WARMUP_FRAMES:
			_start_phase(&"stationary")
		return
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if _phase == &"stationary":
		_stationary_samples.append(interval_ms)
		_stationary_process.append(process_ms)
		_stationary_draws.append(draws)
		if _phase_frames >= SAMPLE_FRAMES:
			_start_phase(&"moving")
		return
	_camera.position.x += CAMERA_STEP
	_moving_samples.append(interval_ms)
	_moving_process.append(process_ms)
	_moving_draws.append(draws)
	if _phase_frames >= SAMPLE_FRAMES:
		_finish()


func _start_phase(next: StringName) -> void:
	_phase = next
	_phase_frames = 0
	if next == &"stationary":
		_camera.position = START_POSITION
	else:
		_camera.position = START_POSITION
	_last_usec = Time.get_ticks_usec()


func _finish() -> void:
	var result := {
		"stationary": _summary(_stationary_samples, _stationary_process, _stationary_draws),
		"moving": _summary(_moving_samples, _moving_process, _moving_draws),
		"camera_step_px_per_frame": CAMERA_STEP,
		"sample_frames": SAMPLE_FRAMES,
		"renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(),
		"viewport": [get_viewport().size.x, get_viewport().size.y],
	}
	print("CAVE_BENCHMARK=" + JSON.stringify(result))
	_level.free()
	await get_tree().process_frame
	await Audio.shutdown()
	await get_tree().process_frame
	get_tree().quit(0)


func _summary(
	frame_samples: Array[float], process_samples: Array[float], draw_samples: Array[float]
) -> Dictionary:
	var sorted := frame_samples.duplicate()
	sorted.sort()
	var mean_ms := _mean(frame_samples)
	return {
		"fps": 1000.0 / mean_ms if mean_ms > 0.0 else 0.0,
		"mean_ms": mean_ms,
		"p95_ms": _percentile(sorted, 0.95),
		"p99_ms": _percentile(sorted, 0.99),
		"process_mean_ms": _mean(process_samples),
		"draw_calls_mean": _mean(draw_samples),
	}


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	var index := clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)
	return sorted[index]
