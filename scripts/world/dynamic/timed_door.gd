class_name TimedDoor
extends Node2D
## A heavy slab held shut until a linked switch is shot; it then stays open for `seconds` while a
## row of glowing segments on the frame counts down with ticking that speeds up at the end.
## It never closes on the player. Passing through latches it open for good (persistent flag), so
## the race is only needed once and the door can never strand anyone on the far side.
## Position is the centre of the door opening.

signal latched_open

const OPEN_SECONDS := 0.22
const CLOSE_SECONDS := 0.4
const WARN_SECONDS := 2.0

@export var door_size := Vector2(64, 192)
@export var seconds := 6.0
## Switch positions relative to the door centre.
@export var switch_offsets := PackedVector2Array([Vector2(-448, -64)])
@export var local_id := "door"
@export var flag_id := ""
@export var area_override: StringName = &""

var is_open := false
var is_latched := false
var remaining := 0.0
var switches: Array[TimedSwitch] = []
var _area: StringName = &"fringe"
var _body: StaticBody2D
var _shape: CollisionShape2D
var _slide := 0.0
var _slide_tween: Tween
var _trigger_side := 0.0
var _tick_timer := 0.0
var _flag := ""


func _ready() -> void:
	add_to_group(&"worldfx_timed_door")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_area = WorldFx.area_for(self, area_override)
	# Tiled fill needs repeat; the delivered (non power-of-two) art sheet must not repeat.
	WorldFx.warm("slabs", _area)
	texture_repeat = WorldFx.repeat_mode("slabs", _area)
	_flag = WorldFx.flag_for(self, "timed", local_id, flag_id)
	_body = StaticBody2D.new()
	_body.collision_layer = WorldFx.TERRAIN_LAYER
	_body.collision_mask = 0
	_shape = CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = door_size
	_shape.shape = rectangle
	_body.add_child(_shape)
	add_child(_body)
	for offset in switch_offsets:
		var switch := TimedSwitch.new()
		switch.area_id = _area
		switch.position = offset
		switch.triggered.connect(_on_switch)
		add_child(switch)
		switches.append(switch)
	if not _flag.is_empty() and GameState.has_world_flag(_flag):
		_latch(false)


func flag() -> String:
	return _flag


func _vertical() -> bool:
	return door_size.y >= door_size.x


func _on_switch() -> void:
	if is_latched:
		return
	var player := WorldFx.player_of(self)
	if player != null:
		_trigger_side = _side_of(player)
	remaining = seconds
	_tick_timer = 0.0
	if not is_open:
		_set_open(true)
	for switch in switches:
		switch.active = true


func _side_of(player: Node2D) -> float:
	var offset := player.global_position - global_position
	return signf(offset.x) if _vertical() else signf(offset.y - door_size.y * 0.5)


func _physics_process(delta: float) -> void:
	if is_latched or not is_open:
		return
	var player := WorldFx.player_of(self)
	if player != null and _trigger_side != 0.0:
		var side := _side_of(player)
		if side != 0.0 and side != _trigger_side and not _player_in_door(player):
			_latch(true)
			return
	remaining -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0 and remaining > 0.0:
		var warning := remaining <= WARN_SECONDS
		_tick_timer = 0.5 if warning else 1.0
		WorldFx.play(
			self,
			&"world_tick",
			global_position,
			-6.0 if not warning else -3.0,
			1.25 if warning else 1.0
		)
	queue_redraw()
	if remaining <= 0.0:
		if player != null and _player_in_door(player):
			remaining = 0.0
			return
		_set_open(false)
		for switch in switches:
			switch.active = false


func _player_in_door(player: Node2D) -> bool:
	var rect := Rect2(global_position - door_size * 0.5, door_size)
	return WorldFx.player_rect(player).grow(6.0).intersects(rect)


func _set_open(open: bool) -> void:
	is_open = open
	_shape.set_deferred("disabled", open)
	_body.collision_layer = 0 if open else WorldFx.TERRAIN_LAYER
	if _slide_tween != null:
		_slide_tween.kill()
	_slide_tween = create_tween()
	var target := 1.0 if open else 0.0
	_slide_tween.tween_method(_set_slide, _slide, target, OPEN_SECONDS if open else CLOSE_SECONDS)
	if open:
		WorldFx.play(self, &"world_door_open", global_position, -3.0)
	else:
		_slide_tween.tween_callback(_on_closed)


func _on_closed() -> void:
	WorldFx.play(self, &"world_slam", global_position + Vector2(0, door_size.y * 0.5), -4.0, 1.15)
	var colors := WorldFx.palette(_area)
	WorldFx.dust(
		get_parent(),
		global_position + Vector2(0, door_size.y * 0.5 - 6),
		Vector2(door_size.x * 0.5, 4),
		colors["dust"],
		12,
		140.0
	)
	WorldFx.shake(self, 2.5, 0.15)


func _set_slide(value: float) -> void:
	_slide = value
	queue_redraw()


func _latch(announce: bool) -> void:
	is_latched = true
	remaining = 0.0
	if not is_open:
		is_open = true
		_shape.set_deferred("disabled", true)
		_body.collision_layer = 0
	_slide = 1.0
	for switch in switches:
		switch.active = false
		switch.latched = true
	if not _flag.is_empty():
		GameState.set_world_flag(_flag)
	if announce:
		WorldFx.play(self, &"world_unlock", global_position, -4.0)
		latched_open.emit()
	queue_redraw()


func _draw() -> void:
	var half := door_size * 0.5
	var colors := WorldFx.palette(_area)
	var accent: Color = colors["accent"]
	var travel := door_size.y if _vertical() else door_size.x
	var shift := Vector2(0, -travel * _slide) if _vertical() else Vector2(travel * _slide, 0)
	var slab := Rect2(-half + shift, door_size)
	# Clip the slab to the opening so it disappears into the rock as it opens.
	var visible_rect := slab.intersection(Rect2(-half, door_size))
	WorldFx.draw_gate(self, slab, visible_rect, _area, 0.2)
	# Countdown segments along the frame edge facing the switch.
	var count := maxi(int(ceil(seconds)), 1)
	var lit := count if not is_open else int(ceil(remaining))
	if is_latched:
		lit = 0
	var warn := is_open and not is_latched and remaining <= WARN_SECONDS
	var blink := warn and fmod(remaining, 0.5) < 0.25
	# Dark gauge strip the countdown lights sit in.
	var gauge := (
		Rect2(Vector2(-half.x - 16, -half.y + 2), Vector2(14, door_size.y - 4))
		if _vertical()
		else Rect2(Vector2(-half.x + 2, -half.y - 16), Vector2(door_size.x - 4, 14))
	)
	draw_rect(gauge, Color(0.04, 0.04, 0.05, 0.9), true)
	for index in count:
		var t := (float(index) + 0.5) / float(count)
		var center := (
			Vector2(-half.x - 9, half.y - door_size.y * t)
			if _vertical()
			else Vector2(-half.x + door_size.x * t, -half.y - 9)
		)
		var on := is_open and index < lit
		var color := accent if not warn else Color(1.0, 0.3, 0.2)
		if not on:
			color = Color(0.16, 0.16, 0.18)
		elif blink:
			color = color.lightened(0.4)
		var seg := (
			Vector2(10, door_size.y / count - 8)
			if _vertical()
			else Vector2(door_size.x / count - 8, 10)
		)
		draw_rect(Rect2(center - seg * 0.5, seg), color, true)
		if on:
			var halo := color
			halo.a = 0.25
			draw_rect(Rect2(center - seg * 0.5 - Vector2(4, 4), seg + Vector2(8, 8)), halo, true)
