extends SceneTree

## Probe for tools/check_godot_isolation.py. Prints the user:// directory and, only when it lies
## inside the run's scratch folder (the parent of --test-save-root), writes a marker into
## user://settings.cfg through the game's own settings code. Outside it, nothing is written.

const Settings = preload("res://scripts/ui/game_settings.gd")
const MARKER := 0.37


func _initialize() -> void:
	var user_dir := OS.get_user_data_dir()
	print("ISOLATION user_dir=%s" % user_dir)
	var scratch := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test-save-root="):
			scratch = argument.trim_prefix("--test-save-root=").get_base_dir()
	if scratch.is_empty() or not user_dir.begins_with(scratch + "/"):
		print("ISOLATION FAIL: user:// is outside the run's scratch folder; nothing written")
		quit(1)
		return
	Settings.set_setting("accessibility", "screen_shake", MARKER)
	print("ISOLATION PASS wrote %s" % ProjectSettings.globalize_path(Settings.PATH))
	quit(0)
