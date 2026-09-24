extends "res://scripts/campaign/boss_spawn.gd"
## Campaign boss spawn for the Boss Rush: always spawns (the finished save has every boss flag)
## and reports the victory without touching world flags, checkpoint or the save.

signal boss_defeated(id: StringName)


func _ready() -> void:
	call_deferred("_spawn")


func _on_defeated(id: StringName) -> void:
	if is_instance_valid(_grate):
		_grate.queue_free()
	boss_defeated.emit(id)
