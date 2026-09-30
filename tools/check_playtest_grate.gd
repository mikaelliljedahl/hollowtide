extends RefCounted
## Echo grate case of the playtest agent check (tools/check_playtest_agent.gd runs it in its
## scene). A standing bolt starts at the muzzle, 71 px ahead of her feet, so a grate between her
## body and the muzzle is never crossed: r6-min-s1c fired about 1,000 forward Echo shots at the
## Tidal Heart's grate 46 px ahead and 96 px above her feet at depths_02 (27, 10), and its shell
## never opened. No opener is offered there, the state names a firing spot instead, and the same
## real shot from a grate ahead of the muzzle does open it.

const Actions = preload("res://tools/playtest_actions.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const State = preload("res://tools/playtest_state.gd")
## The r6-min-s1c grate, relative to the feet, and one a level shot crosses ahead of the muzzle.
const CLOSE_GRATE := Vector2(46, -96)
const AHEAD_GRATE := Vector2(320, -120)

var _host: Node
var _root: Node
var _player: Player


## `host` is the check scene: it owns `_check`, `_root` and `_player`.
func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	GameState.reset_progress()
	for id in [&"beam", &"wave_beam", &"missiles"]:
		GameState.unlock_ability(id)
	GameState.collect_pickup("round6.grate_quiver", &"missile_tank")
	GameState.reset_health()
	await _frames(30)
	var entities := WorldFxTestbed.entities(_root.current_room)
	var feet := _player.global_position
	var boss := EnemyFactory.create(&"tidal_heart") as Node2D
	entities.add_child(boss)
	boss.global_position = feet + Vector2(1100, -300)
	boss.call(&"configure_arena", Rect2(feet.x - 256, feet.y - 448, 1728, 448))
	boss.call(&"set_test_phase", 2)
	var grate := WaveGrate.new()
	entities.add_child(grate)
	grate.global_position = feet + CLOSE_GRATE
	grate.set_relay(boss)
	await _frames(2)
	var state := _snapshot()
	var found: Array = state["enemies"].filter(func(e: Dictionary) -> bool: return e["is_boss"])
	var opener: Dictionary = found[0]["opener"] if not found.is_empty() else {}
	var keys: Array = Actions.candidates(state, _player).map(
		func(e: Dictionary) -> String: return e["key"]
	)
	_check(
		not keys.any(func(k: String) -> bool: return k.begins_with("open_boss")),
		"no Echo at a grate behind the muzzle (%s)" % [keys]
	)
	_check(
		opener.get("visible") == false and (opener.get("spot_rel", []) as Array).size() == 2,
		"a grate behind the muzzle gets a firing spot (%s)" % opener
	)
	await _fire()
	_check(boss.get("_branch_open") != true, "a real Echo from here leaves the shell closed")
	grate.global_position = feet + AHEAD_GRATE
	await _frames(2)
	await _fire()
	_check(
		boss.get("_branch_open") == true, "the same Echo at a grate ahead of the muzzle opens it"
	)
	for node in [boss, grate]:
		node.queue_free()
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()
	await _frames(10)


func _snapshot() -> Dictionary:
	return State.new().snapshot(_root, _player, 1, 0.0)


## A standing forward Echo shot to the right through real inputs, then time for the bolt to fly.
func _fire() -> void:
	var driver := Programs.Driver.new()
	driver.start(Programs.shoot(1, "forward", &"fire_beam", _player.facing))
	while not driver.done():
		driver.step()
		await _host.get_tree().physics_frame
	driver.release_all()
	await _frames(40)


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame
