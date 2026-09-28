extends SceneTree

## Closing the window (or Cmd+Q) on the title while its music plays quits through
## Audio.shutdown, so the process exits without leaked objects or streams. The test runner fails
## a run whose log reports leaks, so a clean exit here is the check.

## Wall-clock budget for the graceful quit (shutdown waits on the real clock, not on frames).
const WAIT_MSEC := 5000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := (load("res://scenes/ui/start_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for frame in 30:
		await process_frame
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_MSEC:
		await process_frame
	push_error("check_close_request: closing the window did not quit the game")
	quit(1)
