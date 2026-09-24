extends RefCounted
## Boss fight stages and attack rotations (docs/features/boss-rework.md). Pure data and rules:
## which stage a health ratio belongs to, which protection phase (B1/B2 of the content-catalog
## damage matrix) a stage uses, the attack rotation per stage, and every attack's telegraph,
## active and punish timing. Nothing here touches the scene tree.

const DESPERATION_STAGE := 4
## Health ratio at or below which each later stage starts (stage 2, 3, 4).
const STAGE_THRESHOLDS: Array[float] = [0.75, 0.5, 0.25]
## Stages from this one on use protection phase B2.
const ARMORED_STAGE := 3
const MIN_TELEGRAPH := 0.45
const DESPERATION_TELEGRAPH_SCALE := 0.8
const DESPERATION_PUNISH_SCALE := 0.85
## Armored stages open the weak point only during the punish window; it must be long enough
## for a harpoon to be aimed and to land.
const ARMORED_MIN_PUNISH := 1.4
const DESPERATION_MIN_PUNISH := 1.2
## Idle time between the end of one punish window and the next telegraph, per stage.
const IDLE_SECONDS: Array[float] = [1.1, 0.9, 0.8, 0.5]
## Breather after a stage transition before the first telegraph of the new stage.
const STAGE_BREATHER := 1.0

const TIMING := {
	&"boulder_volley": {"telegraph": 0.6, "active": 0.1, "punish": 0.9},
	&"fault_slam": {"telegraph": 0.7, "active": 0.2, "punish": 1.2},
	&"rockfall": {"telegraph": 0.8, "active": 0.4, "punish": 1.0},
	&"shoulder_charge": {"telegraph": 0.65, "active": 1.4, "punish": 1.8},
	&"ember_fan": {"telegraph": 0.55, "active": 0.1, "punish": 0.8},
	&"vent_burst": {"telegraph": 0.75, "active": 0.3, "punish": 1.0},
	&"scuttle_rush": {"telegraph": 0.6, "active": 1.3, "punish": 1.3},
	&"heat_ring": {"telegraph": 0.8, "active": 0.1, "punish": 1.6},
	&"tide_ring": {"telegraph": 0.6, "active": 0.1, "punish": 1.0},
	&"surge_lance": {"telegraph": 0.65, "active": 0.3, "punish": 1.0},
	&"crosscurrent": {"telegraph": 0.8, "active": 0.1, "punish": 1.1},
	&"maelstrom": {"telegraph": 0.8, "active": 1.2, "punish": 1.6},
}
## Desperation adds a follow-up burst to some attacks; the active time grows to cover it.
const DESPERATION_EXTRA_ACTIVE := {
	&"boulder_volley": 0.0,
	&"fault_slam": 0.85,
	&"rockfall": 0.2,
	&"ember_fan": 0.3,
	&"vent_burst": 0.2,
	&"heat_ring": 0.4,
	&"tide_ring": 0.35,
	&"surge_lance": 0.25,
	&"crosscurrent": 1.0,
	&"maelstrom": 0.0,
}
## Attacks that move the body instead of emitting projectiles.
const CHARGES: Array[StringName] = [&"shoulder_charge", &"scuttle_rush"]

## Per boss, per stage (index 0 = stage 1): a cycle of chains. A chain is one or more attacks
## played back to back, each with its own telegraph; the punish window follows the last link.
const ROTATIONS := {
	&"stone_guardian":
	[
		[[&"boulder_volley"], [&"fault_slam"]],
		[[&"fault_slam"], [&"rockfall"], [&"boulder_volley"]],
		[[&"boulder_volley"], [&"shoulder_charge"], [&"rockfall"], [&"fault_slam"]],
		[
			[&"fault_slam", &"rockfall"],
			[&"shoulder_charge", &"boulder_volley"],
			[&"rockfall", &"shoulder_charge"]
		],
	],
	&"furnace_mother":
	[
		[[&"ember_fan"], [&"vent_burst"]],
		[[&"scuttle_rush"], [&"ember_fan"], [&"vent_burst"]],
		[[&"ember_fan"], [&"heat_ring"], [&"scuttle_rush"], [&"vent_burst"]],
		[
			[&"vent_burst", &"ember_fan"],
			[&"scuttle_rush", &"heat_ring"],
			[&"heat_ring", &"vent_burst"]
		],
	],
	&"tidal_heart":
	[
		[[&"tide_ring"], [&"surge_lance"]],
		[[&"crosscurrent"], [&"surge_lance"], [&"tide_ring"]],
		[[&"maelstrom"], [&"tide_ring"], [&"crosscurrent"], [&"surge_lance"]],
		[
			[&"maelstrom", &"crosscurrent"],
			[&"surge_lance", &"tide_ring"],
			[&"crosscurrent", &"surge_lance"]
		],
	],
}
## Idle movement speed per stage (px/s); Tidal Heart's value caps its drift.
const MOVE_SPEEDS := {
	&"stone_guardian": [92.0, 112.0, 138.0, 168.0],
	&"furnace_mother": [145.0, 170.0, 210.0, 250.0],
	&"tidal_heart": [105.0, 120.0, 150.0, 180.0],
}


static func stage_for(health: int, max_health: int) -> int:
	var ratio := float(health) / float(maxi(max_health, 1))
	var stage := 1
	for threshold in STAGE_THRESHOLDS:
		if ratio <= threshold:
			stage += 1
	return stage


static func protection_phase(stage: int) -> int:
	return 2 if stage >= ARMORED_STAGE else 1


static func chain_at(boss_id: StringName, stage: int, index: int) -> Array[StringName]:
	var stages: Array = ROTATIONS.get(boss_id, ROTATIONS[&"stone_guardian"])
	var cycle: Array = stages[clampi(stage, 1, stages.size()) - 1]
	var chain: Array[StringName] = []
	for attack: StringName in cycle[posmod(index, cycle.size())]:
		chain.append(attack)
	return chain


## Every attack a boss can use in a stage, in rotation order without repeats.
static func attacks_in_stage(boss_id: StringName, stage: int) -> Array[StringName]:
	var result: Array[StringName] = []
	var stages: Array = ROTATIONS.get(boss_id, [])
	if stages.is_empty():
		return result
	for chain: Array in stages[clampi(stage, 1, stages.size()) - 1]:
		for attack: StringName in chain:
			if not result.has(attack):
				result.append(attack)
	return result


static func telegraph_seconds(attack: StringName, stage: int) -> float:
	var seconds := float(TIMING[attack]["telegraph"])
	if stage >= DESPERATION_STAGE:
		seconds *= DESPERATION_TELEGRAPH_SCALE
	return maxf(seconds, MIN_TELEGRAPH)


static func active_seconds(attack: StringName, stage: int) -> float:
	var seconds := float(TIMING[attack]["active"])
	if stage >= DESPERATION_STAGE:
		seconds += float(DESPERATION_EXTRA_ACTIVE.get(attack, 0.0))
	return seconds


static func punish_seconds(attack: StringName, stage: int) -> float:
	var seconds := float(TIMING[attack]["punish"])
	if stage >= DESPERATION_STAGE:
		return maxf(seconds * DESPERATION_PUNISH_SCALE, DESPERATION_MIN_PUNISH)
	if stage >= ARMORED_STAGE:
		return maxf(seconds, ARMORED_MIN_PUNISH)
	return seconds


static func idle_seconds(stage: int) -> float:
	return IDLE_SECONDS[clampi(stage, 1, IDLE_SECONDS.size()) - 1]


static func move_speed(boss_id: StringName, stage: int) -> float:
	var speeds: Array = MOVE_SPEEDS.get(boss_id, MOVE_SPEEDS[&"stone_guardian"])
	return float(speeds[clampi(stage, 1, speeds.size()) - 1])


static func is_charge(attack: StringName) -> bool:
	return CHARGES.has(attack)
