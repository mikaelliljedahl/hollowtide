class_name EnvironmentAmbience
extends Node2D

var ambient_id: StringName = &""
var _player: AudioStreamPlayer2D


func configure(id: StringName, location: Vector2) -> void:
	ambient_id = id
	position = location
	if _player == null:
		_player = AudioStreamPlayer2D.new()
		_player.name = "PositionalAmbient"
		add_child(_player)
	var audio := get_node_or_null("/root/Audio")
	if audio == null or not audio.has_method("configure_positional_loop"):
		return
	if audio.call("configure_positional_loop", _player, ambient_id):
		_player.play()


func _exit_tree() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and _player != null and audio.has_method("clear_positional_player"):
		audio.call("clear_positional_player", _player)
