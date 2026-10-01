extends RefCounted
## Boss facts for the playtest state (docs/features/playtest-agent.md, "State"): the protection
## phase, whether the shell is open to the Harpoon, what opens it, and the arena the boss fights
## in. The opener table mirrors scripts/enemies/boss.gd (`receive_hit` for the Snare,
## `open_wave_window` through the WaveGrate, `_open_punish_window`); change both together.
## Read-only: it never changes game state.

const Aim = preload("res://tools/playtest_aim.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TILE := 64.0
## A firing spot the boss's body can reach counts as this much farther away (px).
const UNSHIELDED_PENALTY := 4096.0
## Her body's centre above the feet when standing (PlayerConfig.STANDING_HEIGHT / 2).
const BODY_CENTRE := Vector2(0, -88)
## How far below a ledge's end the climb point's floor may lie (tiles).
const CLIMB_DROP_ROWS := 8
## How far along the ledge its end is looked for (tiles).
const CLIMB_SCAN_COLUMNS := 24
## Boss id -> protection phase -> opener. `beam` is the GameState beam id the opener needs ("" for
## none), `via` says where it lands: "body" (a hit on the boss), "grate" (a shot through its Echo
## grate) or "punish" (the recovery after one of its attacks; nothing to fire).
const OPENERS := {
	"tidal_heart": {1: {"beam": "ice", "via": "body"}, 2: {"beam": "wave", "via": "grate"}},
	"stone_guardian": {2: {"beam": "", "via": "punish"}},
	"furnace_mother": {2: {"beam": "", "via": "punish"}},
}
## GameState beam id -> ability that unlocks it, in the order `cycle_beam` steps through them
## (scripts/player/player.gd `_cycle_beam`).
const BEAM_ORDER := ["base", "ice", "wave"]
const BEAM_ABILITY := {"base": "beam", "ice": "ice_beam", "wave": "wave_beam"}


## Owned beams in cycle order ("base", "ice", "wave").
static func owned_beams() -> Array:
	var owned: Array = []
	for beam in BEAM_ORDER:
		if GameState.has_ability(StringName(BEAM_ABILITY[beam])):
			owned.append(beam)
	return owned


## Taps of `cycle_beam` that turn `active` into `wanted` over `owned`; -1 when not owned.
static func cycle_taps(owned: Array, active: String, wanted: String) -> int:
	var from := owned.find(active)
	var to := owned.find(wanted)
	if from < 0 or to < 0:
		return -1
	return posmod(to - from, owned.size())


## {phase, open, opening, opener, arena_rel} for `boss`; positions relative to `feet`. `opening`
## is false once the current opening has taken its share (boss-rework R8): nothing hurts it and
## no opener helps until its next punish window, so `open` (the Harpoon hurts it now) needs both.
static func facts(boss: Node2D, feet: Vector2) -> Dictionary:
	var phase := int(boss.get("phase"))
	var opening := int(boss.get("_opening_damage")) > 0
	var result := {
		"phase": phase,
		"open": boss.get("_branch_open") == true and opening,
		"opening": opening,
		"opener": null,
		"arena_rel": null,
	}
	var bounds = boss.get("arena_bounds")
	if bounds is Rect2 and (bounds as Rect2).size != Vector2.ZERO:
		var arena := bounds as Rect2
		result["arena_rel"] = [
			roundi(arena.position.x - feet.x),
			roundi(arena.position.y - feet.y),
			roundi(arena.end.x - feet.x),
			roundi(arena.end.y - feet.y),
		]
	var by_phase: Dictionary = OPENERS.get(String(boss.get("enemy_id")), {})
	if not by_phase.has(phase):
		return result
	var opener: Dictionary = by_phase[phase].duplicate()
	var beam: String = opener["beam"]
	opener["owned"] = beam.is_empty() or owned_beams().has(beam)
	var point := boss.global_position
	var grate: Node2D = null
	if opener["via"] == "grate":
		grate = grate_of(boss)
		if grate == null:
			opener["owned"] = false
		else:
			point = grate.global_position
	opener["point_rel"] = [roundi(point.x - feet.x), roundi(point.y - feet.y)]
	# In sight is not enough: with no grounded aim lining up from here the opener is never offered,
	# so she needs the firing spot (t4-min-s1 fired 2,605 useless bolts up at the closed Tidal
	# Heart from depths_02 (39, 14), its grate in sight 740 px across and 352 px up).
	var radius := Aim.GRATE_RADIUS if grate != null else Aim.BOSS_RADIUS
	opener["visible"] = (
		_opener_in_sight(boss, feet + Aim.EYE, point, beam, grate)
		and not (
			Aim.line_up(point - feet, true, radius, Catalog.BEAM_RANGE, grate != null).is_empty()
		)
	)
	if not opener["visible"] and opener["owned"] and opener["via"] != "punish":
		var spot = _firing_spot(boss, feet, point, beam, grate, opener["via"] == "grate")
		if spot is Vector2:
			opener["spot_rel"] = [roundi(spot.x - feet.x), roundi(spot.y - feet.y)]
			var climb = _climb_point(boss, spot)
			if climb is Vector2:
				opener["climb_rel"] = [roundi(climb.x - feet.x), roundi(climb.y - feet.y)]
	result["opener"] = opener
	return result


## True when an opener bolt from `eye` reaches `point`: no tile in between, and no grate but one
## that lets that bolt through (the target grate itself counts as reached). A Jev probe in
## depths_02 fired the Echo 368 times from under the ledge the grate hangs over; it never opened.
static func _opener_in_sight(
	boss: Node2D, eye: Vector2, point: Vector2, beam: String, target: Node2D
) -> bool:
	var query := PhysicsRayQueryParameters2D.create(eye, point, 1)
	var passable: Array[RID] = []
	for node in boss.get_tree().get_nodes_in_group(&"projectile_grate"):
		var body := node as CollisionObject2D
		if body == null:
			continue
		if body == target:
			passable.append(body.get_rid())
		elif not beam.is_empty() and body.call(&"can_pass_projectile", StringName(beam)):
			passable.append(body.get_rid())
	query.exclude = passable
	return boss.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## The standing spot in the boss's arena nearest `feet` from which a grounded opener shot lines up
## with `point` in sight (feet position, global), or null. Only scanned while the opener is out
## of sight, so the approach can climb to it (the Tidal Heart's grate hangs just above a ledge).
## A spot with rock or a grate between it and the boss's body, and a climb point, comes first: the
## floating Tidal Heart follows her and cannot pass its grate, and in r7-min-s1h 26 of its 42 hits
## were contact on the climb to the nearest spot, the ledge end under it.
static func _firing_spot(
	boss: Node2D, feet: Vector2, point: Vector2, beam: String, target: Node2D, grate: bool
) -> Variant:
	var bounds = boss.get("arena_bounds")
	if not bounds is Rect2 or (bounds as Rect2).size == Vector2.ZERO:
		return null
	var arena := bounds as Rect2
	var space := boss.get_world_2d().direct_space_state
	var radius := Aim.GRATE_RADIUS if grate else Aim.BOSS_RADIUS
	var best: Variant = null
	var best_score := INF
	for row in range(1, roundi(arena.size.y / TILE) + 1):
		for column in roundi(arena.size.x / TILE):
			var spot := arena.position + Vector2((column + 0.5) * TILE, row * TILE)
			var score := spot.distance_to(feet) + UNSHIELDED_PENALTY
			if score - UNSHIELDED_PENALTY >= best_score or not _stands(space, spot):
				continue
			if _shielded(boss, spot) and _climb_point(boss, spot) is Vector2:
				score -= UNSHIELDED_PENALTY
			if score >= best_score:
				continue
			if Aim.line_up(point - spot, true, radius, Catalog.BEAM_RANGE, grate).is_empty():
				continue
			if _opener_in_sight(boss, spot + Aim.EYE, point, beam, target):
				best = spot
				best_score = score
	return best


## True when rock or a grate stands between the boss's body and her body at `spot`.
static func _shielded(boss: Node2D, spot: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(boss.global_position, spot + BODY_CENTRE, 1)
	return not boss.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Where to climb to a raised `spot` from without passing under the boss: the floor one tile past
## the end of the spot's ledge on the side away from the boss (global feet), or null.
static func _climb_point(boss: Node2D, spot: Vector2) -> Variant:
	var space := boss.get_world_2d().direct_space_state
	var away := Vector2(TILE if spot.x >= boss.global_position.x else -TILE, 0)
	var edge := spot
	for _column in CLIMB_SCAN_COLUMNS:
		if not _stands(space, edge + away):
			break
		edge += away
	var below := edge + away
	for _row in CLIMB_DROP_ROWS:
		below.y += TILE
		if _stands(space, below):
			return below
	return null


## True when feet at `spot` stand on rock with room for the body above.
static func _stands(space: PhysicsDirectSpaceState2D, spot: Vector2) -> bool:
	return (
		_solid(space, spot + Vector2(0, TILE * 0.5))
		and not _solid(space, spot - Vector2(0, TILE * 0.5))
		and not _solid(space, spot - Vector2(0, TILE * 1.5))
	)


static func _solid(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = at
	query.collision_mask = 1
	return not space.intersect_point(query, 1).is_empty()


## The WaveGrate that relays Echo shots to `boss`, or null.
static func grate_of(boss: Node2D) -> Node2D:
	for node in boss.get_tree().get_nodes_in_group(&"projectile_grate"):
		var grate := node as WaveGrate
		if (
			grate != null
			and not grate.is_queued_for_deletion()
			and grate.get("_relay_target") == boss
		):
			return grate
	return null
