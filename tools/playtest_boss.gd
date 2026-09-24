extends RefCounted
## Boss facts for the playtest state (docs/features/playtest-agent.md, "State"): the protection
## phase, whether the shell is open to the Harpoon, what opens it, and the arena the boss fights
## in. The opener table mirrors scripts/enemies/boss.gd (`receive_hit` for the Snare,
## `open_wave_window` through the WaveGrate, `_open_punish_window`); change both together.
## Read-only: it never changes game state.

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


## {phase, open, opener, arena_rel} for `boss`; positions relative to `feet`.
static func facts(boss: Node2D, feet: Vector2) -> Dictionary:
	var phase := int(boss.get("phase"))
	var result := {
		"phase": phase,
		"open": boss.get("_branch_open") == true,
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
	if opener["via"] == "grate":
		var grate := grate_of(boss)
		if grate == null:
			opener["owned"] = false
		else:
			point = grate.global_position
	opener["point_rel"] = [roundi(point.x - feet.x), roundi(point.y - feet.y)]
	result["opener"] = opener
	return result


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
