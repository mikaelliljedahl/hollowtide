extends CanvasLayer
class_name DevOverlay

const Catalog = preload("res://scripts/progression/content_catalog.gd")

var room_id := "?"
var _label: Label
var _player: Node2D
var _enabled := false
var _refresh_elapsed := 0.0


func configure(player: Node2D) -> void:
	_player = player
	layer = 23
	_label = Label.new()
	_label.position = Vector2(28, 1040)
	_label.add_theme_font_size_override("font_size", 17)
	_label.modulate = Color("9ed0c4")
	add_child(_label)
	set_enabled(false)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _label != null:
		_label.visible = enabled
	_refresh()


func _process(delta: float) -> void:
	if not _enabled:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	if _label == null or not _enabled:
		return
	var ability_names: Array[String] = []
	for id in Catalog.ABILITY_IDS:
		if GameState.has_ability(id):
			ability_names.append(String(id))
	var position := _player.global_position if _player != null else Vector2.ZERO
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_label.text = (
		(
			"PERF  FPS=%d  process=%.2f ms  physics=%.2f ms  draws=%d\n"
			+ "DEV STATUS  room=%s  pos=(%.0f, %.0f)  HP=%d/%d  missiles=%d/%d\nabilities: %s"
		)
		% [
			Engine.get_frames_per_second(),
			process_ms,
			physics_ms,
			draw_calls,
			room_id,
			position.x,
			position.y,
			GameState.health,
			GameState.max_health,
			GameState.missile_count,
			GameState.max_missiles,
			", ".join(ability_names),
		]
	)
