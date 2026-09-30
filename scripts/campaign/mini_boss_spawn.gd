extends "res://scripts/campaign/boss_spawn.gd"
## Optional mini-boss spawn (docs/features/mini-bosses.md). Same arena, spawn and defeat flow as
## boss_spawn.gd, but the persistent flag is `mini:<id>`: no `boss:` or `regional:` flag, no wave
## grate and no `on_boss_defeated`, so the ending, boss shortcuts, fast travel and the Trials never
## see it. Victory moves the safe return point into the arena and autosaves.


func flag_id() -> String:
	return "mini:" + String(boss_id)


func _on_defeated(_id: StringName) -> void:
	var root := get_tree().get_first_node_in_group(&"campaign_root")
	var room := _room()
	var room_name: String = room.get("room_id") if room != null else ""
	GameState.set_world_flag(flag_id())
	if not room_name.is_empty():
		GameState.set_checkpoint(room_name, return_point)
	if root != null and root.has_method("_save"):
		root.call("_save")
