extends Node

## Dying inside a hazard respawns cleanly: after the room reloads, the player stands on the
## checkpoint at full health and is not hit or knocked off it by a hazard that overlapped the
## spot where she died (lava, heat, crusher, falling spikes, rising flood).
## godot --headless --path . --fixed-fps 60 res://tools/check_hazard_respawn.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const WATCH_FRAMES := 120
## [label, room, checkpoint (feet), death room, death position, frames inside before the death]
const CASES := [
	["lava", "kiln_01", Vector2(288, 576), "kiln_01", Vector2(1056, 860), 6],
	["heat", "kiln_02", Vector2(800, 2048), "kiln_02", Vector2(1280, 1000), 40],
	["crusher", "kiln_02", Vector2(800, 2048), "kiln_02", Vector2(608, 1900), 150],
	["spikes", "fringe_02", Vector2(1120, 2048), "fringe_02", Vector2(800, 1760), 120],
	["flood", "depths_01", Vector2(800, 2048), "depths_03", Vector2(960, 1950), 200],
]

var _root: Node
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignEntry.prepare_new_game()
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(30)
	for entry in CASES:
		await _case(entry[0], entry[1], entry[2], entry[3], entry[4], entry[5])
	# The settle frames only hide the stale contact: stepping into lava still hurts at once.
	GameState.reset_health()
	_root.call("teleport", "kiln_01", Vector2(1056, 860))
	await _frames(10)
	_check(GameState.health < GameState.max_health, "lava still hurts right after a teleport")
	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"hazard-respawn: %s (%d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()]
		)
	)
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _case(
	label: String, room: String, spawn: Vector2, death_room: String, at: Vector2, inside: int
) -> void:
	GameState.reset_health()
	_check(GameState.set_checkpoint(room, spawn), "%s: checkpoint accepted" % label)
	_root.call("teleport", death_room, at)
	await _frames(inside)
	GameState.apply_damage(9999)
	var player := _root.get("player") as Node2D
	await _wait_for(func() -> bool: return not bool(player.get("_dead")), 240)
	var worst_health := GameState.health
	var worst_shift := 0.0
	var watched := 0
	while watched < WATCH_FRAMES or bool(_root.get("_respawning")):
		var local := player.global_position - (_root.get("current_room") as Node2D).global_position
		worst_health = mini(worst_health, GameState.health)
		worst_shift = maxf(worst_shift, absf(local.x - spawn.x))
		watched += 1
		if watched > WATCH_FRAMES + 240:
			break
		await get_tree().physics_frame
	_check(String(_root.get("current_room_id")) == room, "%s: respawns in %s" % [label, room])
	_check(
		worst_health == GameState.max_health,
		"%s: no hit after respawn (lowest health %d)" % [label, worst_health]
	)
	_check(worst_shift < 16.0, "%s: stays on the checkpoint (moved %.0f px)" % [label, worst_shift])


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame


func _wait_for(condition: Callable, max_frames: int) -> void:
	for frame in max_frames:
		if condition.call():
			return
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok  ", label)
	else:
		_failures.append(label)
