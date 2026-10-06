extends RefCounted
## The armed ambush arena in the playtest agent (docs/features/playtest-agent.md, "Harness round
## 11"): `go_to_ambush` walks to the trigger's floor and keeps walking until the arena seals.
## r8-full-s2 spent 150 s in kiln_02 at cells 13 to 17, 31 switching between `go_to_ambush` and
## `go_to_objective`: each walk toward the trigger lasted one 12-frame step before the route
## pulled her back, and the trigger's centre, 160 px above its floor, read as a ledge to jump to.

const Programs = preload("res://tools/playtest_programs.gd")
## A trigger whose floor is this far (px) or more above or below the feet is not on her floor.
const AMBUSH_FLOOR := 160.0
## Within this of the trigger's floor point (px, x and y) she stands in it.
const AT_TRIGGER := Vector2(48.0, 64.0)


## The point her feet reach standing in the middle of `arena`'s trigger (the whole arena without
## one): the bottom centre, which every campaign trigger lays on its floor.
static func trigger_floor(arena: AmbushArena) -> Vector2:
	var zone := arena.arena_rect_global()
	if arena.trigger_rect.has_area():
		zone = Rect2(arena.global_position + arena.trigger_rect.position, arena.trigger_rect.size)
	return Vector2(zone.get_center().x, zone.end.y)


## `go_to_ambush` for an armed arena she is not standing in and the kit can start (an arena with
## no winnable wave never seals: a rooms run chose it 1,288 times at fringe_03's beam trial before
## the beam), or {}. In campaign mode only on the trigger's own floor: the route reaches it
## otherwise, and a straight steer at a trigger far below stood still on the ledge above it (jev-r3
## spent 550 s in fringe_03).
static func candidate(state: Dictionary, player: Player, campaign: bool) -> Dictionary:
	var arena = state["ambush"]
	if arena == null or arena["state"] != "armed":
		return {}
	var trigger := Vector2(float(arena["trigger_rel"][0]), float(arena["trigger_rel"][1]))
	if at_trigger(trigger) or (campaign and absf(trigger.y) >= AMBUSH_FLOOR):
		return {}
	var node := _arena_node(player.get_tree())
	if node != null and node.plan_waves().is_empty():
		return {}
	return {
		"key": "go_to_ambush",
		"kind": "go_to_ambush",
		"label": "walk into the arena",
		"program":
		(
			Commit.new(player, node, trigger_floor(node))
			if node != null
			else Programs.steer(player, trigger, false)
		),
	}


static func at_trigger(rel: Vector2) -> bool:
	return absf(rel.x) < AT_TRIGGER.x and absf(rel.y) < AT_TRIGGER.y


static func _arena_node(tree: SceneTree) -> AmbushArena:
	for node in tree.get_nodes_in_group(&"worldfx_ambush"):
		var arena := node as AmbushArena
		if arena != null and not arena.is_queued_for_deletion():
			return arena
	return null


## Steers to the trigger's floor until the arena leaves its armed state, she stands in the trigger,
## she stalls, or FRAMES pass; a jump is flown to its landing.
class Commit:
	extends RefCounted

	const FRAMES := 300
	const STALL_FRAMES := 45

	var finished := false
	var _player: Player
	var _arena: AmbushArena
	var _target := Vector2.ZERO
	var _step: Array = []
	var _frames_left := FRAMES
	var _still := 0
	var _last := Vector2.INF

	func _init(player: Player, arena: AmbushArena, target: Vector2) -> void:
		_player = player
		_arena = arena
		_target = target

	func next() -> Array:
		_frames_left -= 1
		if (
			not is_instance_valid(_arena)
			or _arena.state != AmbushArena.State.ARMED
			or (_frames_left <= 0 and _player.is_on_floor())
		):
			finished = true
			return []
		var position := _player.global_position
		_still = _still + 1 if position.distance_to(_last) < 6.0 else 0
		if _still == 0:
			_last = position
		if _still >= STALL_FRAMES:
			finished = true
			return []
		if _step.is_empty():
			var rel := _target - position
			if _player.is_on_floor() and absf(rel.x) < AT_TRIGGER.x and absf(rel.y) < AT_TRIGGER.y:
				finished = true
				return []
			_step = Programs.steer(_player, rel, false)
		return _step.pop_front()
