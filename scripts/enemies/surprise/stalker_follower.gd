class_name StalkerFollower
extends Node
## Campaign hook for the `stalker`: at most one per area, it follows the player between rooms
## of that area. Lives as a child of the campaign root (any ancestor with a `room_changed`
## signal and a `current_room` property), so no campaign script has to change:
## - a stalker that has seen the player is "hunting"; when its room unloads it stores its HP;
## - on the next room_changed inside the same area it re-enters from the door the player used
##   after FOLLOW_DELAY seconds;
## - killing it sets the saved world flag `stalker_defeated:<area>` for good.
## HP/position live only for this campaign session (a new campaign root starts fresh).

const NODE_NAME := "StalkerFollower"
const FOLLOW_DELAY := 3.5
const ENTRY_INSET := 110.0

## area -> {"hp": int, "hunting": bool, "present": bool}
var states: Dictionary = {}
var _root: Node
const PROTECTED_SCRIPTS := ["boss_spawn.gd", "ending_trigger.gd"]

var _pending_area: StringName = &""
var _pending_timer := -1.0
var _entry_frames := 0
var _entry_local := Vector2.ZERO


static func defeat_flag(area: StringName) -> String:
	return "stalker_defeated:" + String(area)


static func find_root(node: Node) -> Node:
	var cursor := node
	while cursor != null:
		if cursor.has_signal(&"room_changed") and cursor.get(&"current_room") != null:
			return cursor
		cursor = cursor.get_parent()
	return null


## Returns the session follower for the campaign root above `node`, or null outside a campaign.
static func attach(node: Node) -> StalkerFollower:
	var root := find_root(node)
	if root == null:
		return null
	var existing := root.get_node_or_null(NODE_NAME) as StalkerFollower
	if existing != null:
		return existing
	var follower := StalkerFollower.new()
	follower.name = NODE_NAME
	follower._root = root
	root.add_child.call_deferred(follower)
	root.connect(&"room_changed", follower._on_room_changed)
	return follower


static func area_of(node: Node) -> StringName:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor.get(&"area_id") != null:
			return StringName(cursor.get(&"area_id"))
		cursor = cursor.get_parent()
	return &""


func is_defeated(area: StringName) -> bool:
	return GameState.has_world_flag(defeat_flag(area))


func is_hunting(area: StringName) -> bool:
	return bool(_state(area).get("hunting", false))


func stored_hp(area: StringName, fallback: int) -> int:
	var hp := int(_state(area).get("hp", -1))
	return hp if hp > 0 else fallback


func register(area: StringName, hp: int) -> void:
	var state := _state(area)
	state["present"] = true
	state["hp"] = hp


func mark_hunting(area: StringName) -> void:
	_state(area)["hunting"] = true


func store(area: StringName, hp: int) -> void:
	var state := _state(area)
	state["present"] = false
	state["hp"] = hp


func defeat(area: StringName) -> void:
	states.erase(area)
	GameState.set_world_flag(defeat_flag(area))
	if _pending_area == area:
		_pending_timer = -1.0


func _state(area: StringName) -> Dictionary:
	if not states.has(area):
		states[area] = {"hp": -1, "hunting": false, "present": false}
	return states[area]


func _on_room_changed(_room_id: String) -> void:
	var room := _root.get(&"current_room") as Node2D if _root != null else null
	_pending_timer = -1.0
	if room == null:
		return
	var area := StringName(room.get(&"area_id"))
	var state: Dictionary = states.get(area, {})
	if state.is_empty() or not bool(state["hunting"]) or bool(state["present"]):
		return
	if is_defeated(area):
		return
	_pending_area = area
	_pending_timer = FOLLOW_DELAY
	_entry_frames = 2


func _physics_process(delta: float) -> void:
	if _pending_timer < 0.0:
		return
	var room := _root.get(&"current_room") as Node2D if _root != null else null
	if room == null:
		_pending_timer = -1.0
		return
	if _entry_frames > 0:
		# The player is placed at the door right after room_changed; remember where.
		_entry_frames -= 1
		var player := get_tree().get_first_node_in_group(&"player") as Node2D
		if player != null:
			_entry_local = player.global_position - room.global_position
		return
	_pending_timer -= delta
	if _pending_timer > 0.0:
		return
	_pending_timer = -1.0
	var state: Dictionary = states.get(_pending_area, {})
	if (
		state.is_empty()
		or bool(state["present"])
		or StringName(room.get(&"area_id")) != _pending_area
		or is_protected_room(room)
	):
		return
	spawn_at_entry(room)


## Boss arenas and the ending room never get a follower: a stalker on top of a boss is unfair.
static func is_protected_room(room: Node) -> bool:
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_in_group(&"bosses"):
			return true
		var script := node.get_script() as Script
		if script != null and script.resource_path.get_file() in PROTECTED_SCRIPTS:
			return true
		stack.append_array(node.get_children())
	return false


func spawn_at_entry(room: Node2D) -> Node2D:
	var stalker := SurpriseCatalog.create(&"stalker")
	if stalker == null:
		return null
	stalker.set(&"is_follower", true)
	var size: Vector2 = (
		room.call(&"size_px") if room.has_method(&"size_px") else Vector2(1920, 1088)
	)
	var local := Vector2(
		clampf(_entry_local.x, ENTRY_INSET, size.x - ENTRY_INSET),
		clampf(_entry_local.y - 30.0, 96.0, size.y - 96.0)
	)
	var parent := room.get_node_or_null("Entities")
	if parent == null:
		parent = room
	parent.add_child(stalker)
	stalker.global_position = room.global_position + local
	stalker.call(
		&"configure_arena", Rect2(room.global_position + Vector2(64, 64), size - Vector2(128, 96))
	)
	stalker.add_to_group(&"campaign_enemy")
	return stalker
