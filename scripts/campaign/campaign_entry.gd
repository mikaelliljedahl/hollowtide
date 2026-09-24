class_name CampaignEntry
extends RefCounted

## Campaign entry points used by the start menu. Both entry calls change scene themselves.
## Direct launch without the menu: godot --path . res://scenes/campaign/campaign.tscn
## (continues the campaign save when one exists, otherwise starts a new game).

const CAMPAIGN_SCENE := "res://scenes/campaign/campaign.tscn"
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")

static var last_error: Error = OK


static func has_save() -> bool:
	var store := _node("SaveStore")
	return store != null and bool(store.call("has_save"))


static func new_game() -> void:
	prepare_new_game()
	_change_scene()


static func continue_game() -> void:
	if not prepare_continue():
		push_warning("Campaign: continue failed: %s" % error_string(last_error))
		return
	_change_scene()


## Resets GameState to a fresh campaign without touching the save file on disk. The slot is
## first written at the first save shrine.
static func prepare_new_game() -> void:
	last_error = OK
	var state := _node("GameState")
	if state == null:
		last_error = ERR_UNAVAILABLE
		return
	state.call("reset_progress")
	state.call("set_checkpoint", Rooms.START_ROOM, Rooms.START_POSITION)


static func prepare_continue() -> bool:
	var store := _node("SaveStore")
	if store == null:
		last_error = ERR_UNAVAILABLE
		return false
	last_error = store.call("load_game")
	return last_error == OK


static func _change_scene() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file(CAMPAIGN_SCENE)


static func _node(autoload: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload)
