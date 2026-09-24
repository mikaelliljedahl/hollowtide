extends Node
## Seed Crossbow (base weapon, internal id `beam`): player-visible names, the string-snap launch
## effect instead of a sci-fi muzzle flash, and the seed-bolt trail.

const Catalog = preload("res://scripts/progression/content_catalog.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	Weapons.reset_runtime()
	_test_names()
	await _test_fire_fx()
	GameState.reset_progress()
	Weapons.reset_runtime()
	if failures.is_empty():
		print("PASS: seed crossbow names, string snap and seed-bolt trail")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _test_names() -> void:
	_check(Catalog.display_name(&"beam") == "Seed Crossbow", "beam displays as Seed Crossbow")
	_check(Catalog.beam_display_name(&"base") == "Seed Bolt", "base shot displays as Seed Bolt")
	for id in Catalog.DISPLAY_NAMES:
		_check(not "Beam" in Catalog.DISPLAY_NAMES[id] or id == &"burst_beam", "%s name" % id)


func _test_fire_fx() -> void:
	GameState.unlock_ability(&"beam")
	Weapons.fire(&"beam", Vector2(200.0, 200.0), Vector2.RIGHT)
	await get_tree().process_frame
	var snaps := get_tree().get_nodes_in_group(&"crossbow_fx")
	_check(snaps.size() == 1, "base shot spawns one crossbow string snap")
	_check(get_tree().get_nodes_in_group(&"beam_fx").all(_is_trail), "no sci-fi muzzle flash")
	var shots := get_tree().get_nodes_in_group(&"projectiles")
	for node in get_tree().current_scene.get_children():
		if node is BeamShot:
			shots.append(node)
	var bolt: BeamShot = null
	for node in shots:
		if node is BeamShot:
			bolt = node
	_check(bolt != null, "base shot spawns a bolt")
	if bolt != null:
		var trail := bolt.get_node("Trail") as BeamFxTrail
		_check(trail.visible, "seed-bolt draws a trail")
		_check(trail.inner_color.g > trail.inner_color.r, "seed-bolt trail is green-turquoise")
	for frame in 20:
		await get_tree().process_frame
	_check(get_tree().get_nodes_in_group(&"crossbow_fx").is_empty(), "string snap frees itself")


func _is_trail(node: Node) -> bool:
	return node is BeamFxTrail


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
