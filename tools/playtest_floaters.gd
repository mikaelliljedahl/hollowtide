extends RefCounted
## Frozen floaters for the playtest agent's campaign mode (harness:
## docs/features/playtest-agent.md). The route solver stands on a frost floater's cell once the Bubble Snare is
## owned (tools/check_campaign_graph.py, `platform`); in the game a floater only carries the player
## while frozen (scripts/enemies/combat_enemy.gd, `_freeze`, 4 s). This offers `freeze:<enemy>` for
## each floater the next hops land on, farthest first (a frozen near one would stop the bolt), as
## the real inputs a player uses: switch to the Snare, face it, fire, crouched when it floats low.

const Programs = preload("res://tools/playtest_programs.gd")
const Boss = preload("res://tools/playtest_boss.gd")
const TILE := 64.0
const FLOATER := &"frost_floater"
## A floater frozen with more than this left needs no new shot yet.
const FROZEN_ENOUGH := 1.5
## Crossbow heights above the feet, standing and crouched (PlayerConfig muzzle offsets).
const STAND_MUZZLE := 161.0
const CROUCH_MUZZLE := 72.0
const CROUCH_FRAMES := 5
const AFTER_SHOT_FRAMES := 10
## The shot goes when the floater is this close (px) to home, or after WAIT_FRAMES regardless (it
## bobs 70 px sideways and 28 px up and down around home).
const HOME_PX := 28.0
const WAIT_FRAMES := 240
## Beyond this a Snare bolt falls short (Catalog.BEAM_RANGE, without the Focus Lens).
const RANGE := 600.0
## A level shot passes within this of the floater's centre (its body is about a tile wide).
const LEVEL := 40.0


## Floaters the upcoming landing cells rest on, not frozen for long enough, farthest first.
## `landings` holds [room, x, y] resting cells in route order.
static func needed(tree: SceneTree, room_node: Node2D, landings: Array, feet: Vector2) -> Array:
	var found: Array = []
	for node in tree.get_nodes_in_group(&"enemies"):
		var enemy := node as Node2D
		if enemy == null or StringName(enemy.get("enemy_id")) != FLOATER:
			continue
		if not room_node.is_ancestor_of(enemy) or int(enemy.get("health")) <= 0:
			continue
		if bool(enemy.get("is_frozen")) and float(enemy.get("_freeze_remaining")) > FROZEN_ENOUGH:
			continue
		var home: Vector2 = Vector2(enemy.get("_home_position")) - room_node.global_position
		var cell := Vector2i(floori(home.x / TILE), floori(home.y / TILE))
		for landing in landings:
			if int(landing[1]) == cell.x and int(landing[2]) + 1 == cell.y:
				found.append(enemy)
				break
	found.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				feet.distance_squared_to(a.global_position)
				> feet.distance_squared_to(b.global_position)
			)
	)
	return found


## The `freeze` candidate for `floater`, or {} unless the player stands where a level bolt,
## standing or crouched, reaches its home spot. Floaters bob around home
## (scripts/enemies/combat_enemy.gd, `_run_frost_floater`) and the route stands on the home cell,
## so the shot waits until it passes there.
static func candidate(floater: Node2D, player: Player, label: String) -> Dictionary:
	var home: Vector2 = floater.get("_home_position")
	var rel := home - player.global_position
	var miss := minf(absf(rel.y + CROUCH_MUZZLE), absf(rel.y + STAND_MUZZLE))
	if absf(rel.x) > RANGE or absf(rel.x) < TILE or miss > LEVEL or not player.is_on_floor():
		return {}
	var toward := -1 if rel.x < 0.0 else 1
	var setup: Array = []
	var owned := Boss.owned_beams()
	if String(GameState.active_beam) != "ice":
		var taps := owned.find("ice") - owned.find(String(GameState.active_beam))
		setup.append_array(Programs.cycle_beam(taps, owned.size()))
	if toward != player.facing:
		setup.append_array(Programs.hold([Programs.move_action(toward)], 2))
	var crouch := absf(rel.y + CROUCH_MUZZLE) < absf(rel.y + STAND_MUZZLE)
	var held: Array = [&"move_down"] if crouch else []
	var shot: Array = Programs.hold(held, CROUCH_FRAMES if crouch else 1)
	shot.append_array(Programs.hold(held + [&"fire_beam"], 3))
	shot.append_array(Programs.hold(held, AFTER_SHOT_FRAMES))
	return {
		"key": "freeze:%s" % label,
		"kind": "freeze",
		"label":
		(
			"freeze the frost floater %s with the Snare as it passes its spot on the route"
			% ("below the crossbow (crouched)" if crouch else "ahead")
		),
		"program": Freeze.new(floater, setup, shot),
	}


## Live program: switch and face (`setup`), wait until the floater is back near home, then fire
## (`shot`, crouched when it floats low).
class Freeze:
	extends RefCounted

	var finished := false
	var _floater: Node2D
	var _frames: Array = []
	var _shot: Array = []
	var _waited := 0

	func _init(floater: Node2D, setup: Array, shot: Array) -> void:
		_floater = floater
		_frames = setup.duplicate()
		_shot = shot

	func next() -> Array:
		if not _frames.is_empty():
			return _frames.pop_front()
		if not _shot.is_empty() and not _near_home() and _waited < WAIT_FRAMES:
			_waited += 1
			return []
		if _shot.is_empty():
			finished = true
			return []
		_frames = _shot
		_shot = []
		return _frames.pop_front()

	func _near_home() -> bool:
		if not is_instance_valid(_floater):
			return true
		var home: Vector2 = _floater.get("_home_position")
		return _floater.global_position.distance_to(home) < HOME_PX
