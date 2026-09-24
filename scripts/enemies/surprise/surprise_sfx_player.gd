extends AudioStreamPlayer2D
## One-shot positional player for SurpriseSfx. Releases its stream as soon as the Audio
## autoload starts shutting down so no stream is still referenced by the mixer at exit.

var _audio: Node


func _ready() -> void:
	_audio = get_tree().root.get_node_or_null("Audio")
	finished.connect(_release)


func _process(_delta: float) -> void:
	if _audio != null and bool(_audio.get(&"_shutting_down")):
		_release()


func _release() -> void:
	stop()
	stream = null
	queue_free()
