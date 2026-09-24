extends RefCounted
## Playtest agent hazard geometry (docs/features/playtest-agent.md, "State" and "Telemetry"),
## shared by the state export and the damage attribution. Every hazard is measured by the rect of
## its body, not its node origin: a flood's origin is its top-left corner, a stalactite's is the
## ceiling, and a lava pool's body is wider than any fixed radius around its centre.
## Read-only: it never changes game state.

## Group -> fallback kind label. `dev_hazard` holds campaign lava, fire and steam (DevHazard).
const GROUPS: Array[StringName] = [
	&"dev_hazard",
	&"worldfx_crusher",
	&"worldfx_stalactite",
	&"worldfx_rising_shaft",
	&"worldfx_crumble",
	&"campaign_heat",
]
## Groups whose members never hurt the player (a crumbling floor only drops her).
const HARMLESS: Array[StringName] = [&"worldfx_crumble"]
const DEV_KINDS := {
	&"lava_surface": "lava",
	&"fire_small": "fire",
	&"fire_vent": "fire",
	&"steam_embers": "steam",
	&"steam_vent": "steam",
}
## Standing and ball hitboxes (docs/game-feel.md), origin at the feet.
const BODY := Vector2(56, 176)
const BALL := Vector2(56, 56)
const CRUMBLE_SIZE := Vector2(128, 64)
const STALACTITE_STATES := ["armed", "shaking", "falling", "gone", "regrowing"]
const SHAFT_STATES := ["armed", "warning", "rising", "stopped", "draining"]
const CRUSHER_PHASES := ["rest", "telegraph", "slam", "hold", "rise"]


## The player's hitbox in world space.
static func body_rect(player: Player) -> Rect2:
	var size := BALL if player.is_ball else BODY
	return Rect2(player.global_position - Vector2(size.x * 0.5, size.y), size)


## Hazards whose body lies within `radius` px of `body`, nearest first:
## [{kind, rect (world), gap (px between the rects, 0 when touching), state, node}].
static func near(tree: SceneTree, body: Rect2, radius: float, harmful_only: bool) -> Array:
	var found: Array = []
	for group in GROUPS:
		if harmful_only and group in HARMLESS:
			continue
		for node in tree.get_nodes_in_group(group):
			var hazard := node as Node2D
			if hazard == null or hazard.is_queued_for_deletion() or not _harmful(hazard):
				continue
			var rect := rect_of(hazard, group)
			var distance := gap(body, rect)
			if distance > radius:
				continue
			(
				found
				. append(
					{
						"kind": kind_of(hazard, group),
						"rect": rect,
						"gap": distance,
						"state": state_of(hazard),
						"node": hazard,
					}
				)
			)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["gap"] < b["gap"])
	return found


## World rect of the part of `hazard` that hurts.
static func rect_of(hazard: Node2D, group: StringName) -> Rect2:
	var origin := hazard.global_position
	if hazard is RisingShaft:
		var shaft := hazard as RisingShaft
		var whole := shaft.shaft_rect_global()
		var top := clampf(shaft.surface_global_y(), whole.position.y, whole.end.y)
		return Rect2(whole.position.x, top, whole.size.x, whole.end.y - top)
	if hazard is Stalactite:
		var spike := hazard as Stalactite
		var tip := spike.tip_global()
		return Rect2(origin.x - spike.width * 0.5, origin.y, spike.width, tip.y - origin.y)
	if hazard is Crusher:
		return (hazard as Crusher).block_rect_global()
	if hazard is DevHazard:
		var size: Vector2 = (hazard as DevHazard).hazard_size
		return Rect2(origin - size * 0.5, size)
	if group == &"campaign_heat":
		var zone: Vector2 = hazard.get("zone_size")
		return Rect2(origin - zone * 0.5, zone)
	return Rect2(origin - CRUMBLE_SIZE * 0.5, CRUMBLE_SIZE)


static func kind_of(hazard: Node2D, group: StringName) -> String:
	if hazard is DevHazard:
		var kind := (hazard as DevHazard).kind
		return DEV_KINDS.get(kind, String(kind))
	if hazard is RisingShaft:
		return "rising_%s" % ("lava" if (hazard as RisingShaft).kind == &"lava" else "water")
	match group:
		&"campaign_heat":
			return "heat"
	return String(group).trim_prefix("worldfx_")


## A moving hazard's phase ("falling", "rising", "slam", ...); "" for static ones.
static func state_of(hazard: Node2D) -> String:
	if hazard is Stalactite:
		return STALACTITE_STATES[(hazard as Stalactite).state]
	if hazard is RisingShaft:
		return SHAFT_STATES[(hazard as RisingShaft).state]
	if hazard is Crusher:
		return CRUSHER_PHASES[(hazard as Crusher).phase]
	return ""


## Pixels between two rects along the shortest axis-aligned gap; 0 when they touch or overlap.
static func gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dy := maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return Vector2(dx, dy).length()


## The point of `rect` nearest to `point`.
static func nearest_point(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y)
	)


static func _harmful(hazard: Node2D) -> bool:
	if hazard is DevHazard:
		var dev := hazard as DevHazard
		return dev.contact_enabled and dev.damage > 0
	# A shattered spike keeps its fallen length until it regrows, but nothing is there.
	if hazard is Stalactite:
		return (hazard as Stalactite).state != Stalactite.State.GONE
	return true
