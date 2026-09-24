class_name TestShutdown
extends RefCounted


static func finish(tree: SceneTree, exit_code: int = 0) -> void:
	# World props (rising shafts, enemy cues, loops) own their players; silence them so no stream is
	# still held by the mixer at exit.
	for type in ["AudioStreamPlayer2D", "AudioStreamPlayer"]:
		for node in tree.root.find_children("*", type, true, false):
			node.call("stop")
			node.set("stream", null)
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null and audio.has_method("shutdown"):
		await audio.call("shutdown")
	# The audio mixer releases streams in real time; with --fixed-fps frames run far faster than
	# that, so also wait a little wall-clock time before quitting.
	var started := Time.get_ticks_msec()
	await tree.process_frame
	while Time.get_ticks_msec() - started < 150:
		await tree.process_frame
	tree.quit(exit_code)
