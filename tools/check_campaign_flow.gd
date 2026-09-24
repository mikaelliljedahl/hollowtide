extends Node

## Campaign flow check: new game, room transition + discovery, save shrine, death respawn in
## memory, boss victory autosave + persistence, continue from disk, and the ending to credits.
## godot --headless --path . res://tools/check_campaign_flow.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const TILE := 64.0

var _root: Node
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignEntry.prepare_new_game()
	_check(not SaveStore.has_save(), "fresh test save root has no campaign save")
	_check(SaveStore.domain == &"campaign", "save domain is campaign")
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(30)
	_check(_room() == Rooms.START_ROOM, "new game starts in %s" % Rooms.START_ROOM)
	_check(GameState.discovered_rooms.has(Rooms.START_ROOM), "start room discovered")

	# Walk out of fringe_01 through the breach into fringe_02.
	_root.call("teleport", "fringe_01", Vector2(49.5 * TILE, 12 * TILE))
	await _frames(120)
	_check(_room() == "fringe_02", "falling through the breach enters fringe_02")
	_check(GameState.discovered_rooms.has("fringe_02"), "fringe_02 discovered")

	# Slipstream pickup, then save at the shrine.
	_root.call("teleport", "fringe_02", Vector2(5.5 * TILE, 31 * TILE))
	await _frames(20)
	_check(GameState.has_slipstream, "slipstream collected")
	_root.call("teleport", "fringe_02", Vector2(17.5 * TILE, 32 * TILE))
	await _frames(60)
	_check(not SaveStore.has_save(), "spawning on a shrine does not save")
	_root.call("teleport", "fringe_02", Vector2(14.5 * TILE, 32 * TILE))
	await _frames(40)
	Input.action_press(&"move_right")
	await _wait_for(func(): return SaveStore.has_save(), 120)
	Input.action_release(&"move_right")
	_check(SaveStore.has_save(), "walking onto the save shrine wrote the campaign slot")
	_check(String(GameState.checkpoint["room"]) == "fringe_02", "checkpoint moved to fringe_02")

	# Collect the beam in fringe_03, then die: respawn at the shrine keeping the beam in memory.
	_root.call("teleport", "fringe_03", Vector2(7.5 * TILE, 15 * TILE))
	await _frames(20)
	_check(GameState.has_beam, "beam collected")
	GameState.apply_damage(9999)
	await _wait_for(
		func(): return _room() == "fringe_02" and GameState.health == GameState.max_health, 240
	)
	_check(_room() == "fringe_02", "death respawns in the checkpoint room")
	_check(GameState.health == GameState.max_health, "death restores full health")
	_check(GameState.has_beam, "death keeps progress collected after the save")
	var player := _root.get("player") as Node2D
	var local := player.global_position - (_root.get("current_room") as Node2D).global_position
	_check(local.distance_to(Vector2(17.5 * TILE, 32 * TILE)) < 96.0, "respawn at the shrine")
	await _frames(40)
	_check(_root.get("current_room") != null and GameState.health > 0, "player alive after respawn")

	# Boss victory in the Guardian's Vault: flags, checkpoint, autosave, shortcut opens.
	GameState.collect_pickup("flow.missile", &"missile_tank")
	_root.call("teleport", "vaults_03", Vector2(6.5 * TILE, 15 * TILE))
	await _frames(20)
	var boss := get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	_check(boss != null, "stone guardian spawned")
	if boss != null:
		for hit in 40:
			if not is_instance_valid(boss) or int(boss.get("health")) <= 0:
				break
			boss.call("receive_hit", 35, &"missile", {})
			boss.set("_branch_open", true)
			await _frames(2)
	await _frames(30)
	_check(GameState.has_world_flag("boss:stone_guardian"), "boss flag set")
	_check(GameState.has_world_flag("regional:stone_guardian"), "regional flag set")
	_check(String(GameState.checkpoint["room"]) == "vaults_03", "boss victory moves checkpoint")
	var gate := _first_flag_gate()
	_check(gate != null and bool(gate.get("is_open")), "guardian shortcut opened")
	_root.call("teleport", "vaults_03", Vector2(6.5 * TILE, 15 * TILE))
	await _frames(20)
	_check(get_tree().get_first_node_in_group(&"campaign_boss") == null, "defeated boss stays gone")

	# Continue from disk restores the autosaved boss flag.
	GameState.reset_progress()
	_check(CampaignEntry.prepare_continue(), "continue loads the campaign slot")
	_check(GameState.has_world_flag("boss:stone_guardian"), "boss flag persisted to disk")
	_check(String(GameState.checkpoint["room"]) == "vaults_03", "checkpoint persisted to disk")
	_check(GameState.has_beam and GameState.has_slipstream, "abilities persisted to disk")

	# Ending: after the Tidal Heart falls, the light leads to the credits.
	GameState.set_world_flag("boss:tidal_heart")
	var ending := Vector2(24.5 * TILE, 6 * TILE)
	_root.call("teleport", "depths_03", ending)
	await _wait_for(func(): return bool(_root.get("_ending")), 120)
	_check(bool(_root.get("_ending")), "ending light starts the ending fade")
	var credits := load("res://scenes/campaign/credits.tscn") as PackedScene
	_check(credits != null and credits.can_instantiate(), "credits scene loads")
	_check(SaveStore.has_save(), "save kept after the ending")

	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"campaign-flow: %s (%d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()]
		)
	)
	get_tree().paused = false
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _room() -> String:
	return String(_root.get("current_room_id")) if is_instance_valid(_root) else ""


func _first_flag_gate() -> Node:
	for node in get_tree().get_nodes_in_group(&"campaign_flag_gate"):
		return node
	return null


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
