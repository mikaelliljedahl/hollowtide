class_name TrialCatalog
extends RefCounted
## Fixed data for the post-ending Trials (docs/features/trials.md): the two modes, the gauntlet
## waves, the boss order, the fixed kit and the ASCII rooms. Pure data, no scene access.

const GAUNTLET := &"gauntlet"
const BOSS_RUSH := &"boss_rush"
const MODES: Array[StringName] = [GAUNTLET, BOSS_RUSH]
const TITLES := {GAUNTLET: "Gauntlet", BOSS_RUSH: "Boss Rush"}
## World flag in the campaign save that unlocks the Trials: set by the Tidal Heart victory, whose
## autosave is on disk before the ending can play.
const UNLOCK_FLAG := "boss:tidal_heart"
const SCENE := "res://scenes/trials/trials.tscn"

## Escalating waves (triangle, diamond finale; docs/features/ambush-arenas.md R1/R2). Together they
## use all twelve common enemies an ambush may spawn; the Lava Monster needs a lava basin.
const WAVES: Array = [
	["hopper", "hopper", "spitter"],
	["grasshopper", "grasshopper", "vent_flyer", "spitter"],
	["crawler", "crawler", "ceiling_diver", "ceiling_diver", "shard_turret"],
	["armored_guard", "grasshopper", "grasshopper", "shooting_gargoyle"],
	["burrower", "burrower", "frost_floater", "frost_floater", "spitter"],
	["armored_guard", "armored_guard", "shooting_gargoyle", "energy_parasite"],
]
## Waves (by index) whose enemies spawn as elites (EnemyElite): the last two.
const ELITE_WAVES: Array[int] = [4, 5]

const BOSSES: Array[StringName] = [&"stone_guardian", &"furnace_mother", &"tidal_heart"]
const BOSS_AREAS := {
	&"stone_guardian": &"vaults",
	&"furnace_mother": &"kiln",
	&"tidal_heart": &"depths",
}
## Local boss spawn positions in the boss room; the Tidal Heart floats.
const BOSS_POSITIONS := {
	&"stone_guardian": Vector2(1600, 864),
	&"furnace_mother": Vector2(1600, 864),
	&"tidal_heart": Vector2(1792, 608),
}
## Time between a boss falling and the next boss appearing, refill included.
const BREATHER_SECONDS := 4.0
## Delay before the first boss appears, so the room reads before the fight.
const BOSS_INTRO_SECONDS := 1.0

## Fixed full kit: every campaign ability (Flux is not part of the campaign) at the catalog
## container maxima, so best times are comparable between saves.
const KIT_ABILITIES: Array[StringName] = [
	&"beam",
	&"slipstream",
	&"missiles",
	&"long_beam",
	&"ice_beam",
	&"wave_beam",
	&"bombs",
	&"high_jump",
	&"pressure_seal",
	&"undertow_dash",
]

const TILE := 64.0
## Feet cell of the player at the start of every trial room.
const START_CELL := Vector2i(3, 14)

## Gauntlet room: closed 40 x 17 cave with three ledges. '#' is rock.
const GAUNTLET_GRID := [
	"########################################",
	"########################################",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#................######................#",
	"#......................................#",
	"#......................................#",
	"#......#####..................#####....#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"########################################",
	"########################################",
]
const GAUNTLET_AREA := &"nexus"
## Arena covering the whole interior; the trigger is the middle third, so the player commits by
## walking in from the start ledge.
const GAUNTLET_ARENA_CENTRE := Vector2(1280, 544)
const GAUNTLET_ARENA_SIZE := Vector2(2432, 832)
const GAUNTLET_TRIGGER := Rect2(-448, -416, 896, 832)
## Authored points relative to the arena centre, by movement class.
const GAUNTLET_FLOOR_POINTS: Array[Vector2] = [
	Vector2(704, 368), Vector2(-512, 368), Vector2(1024, 368), Vector2(160, 368), Vector2(-896, 368)
]
const GAUNTLET_AIR_POINTS: Array[Vector2] = [
	Vector2(576, -160), Vector2(-384, -160), Vector2(96, -288), Vector2(896, -32)
]

## Boss room: closed 34 x 17 cave, flat floor, used with each boss's area art.
const BOSS_GRID := [
	"##################################",
	"##################################",
	"##################################",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"#................................#",
	"##################################",
	"##################################",
]
## Ends 16 px below the floor line: Rect2.has_point excludes the bottom edge, where the feet stand.
const BOSS_ARENA := Rect2(64, 192, 2048, 784)


static func title(mode: StringName) -> String:
	return String(TITLES.get(mode, "Trial"))


static func is_mode(mode: StringName) -> bool:
	return MODES.has(mode)


## Every spawn of every wave in order, as the arena's class-aware relocation expects.
static func all_spawn_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for wave in WAVES:
		ids.append_array(PackedStringArray(wave))
	return ids
