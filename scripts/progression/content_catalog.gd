extends RefCounted
class_name ContentCatalog

const SCHEMA_VERSION := 2
const LEGACY_SCHEMA_VERSION := 1

const ABILITY_IDS := [
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
	&"flux_shield",
	&"burst_beam",
	&"echo_scan",
]
const FLUX_ABILITY_IDS := [&"flux_shield", &"burst_beam", &"echo_scan"]
const FLUX_PICKUP_KINDS := FLUX_ABILITY_IDS + [&"flux_tank", &"flux_refill"]
# Tide Sockets and Tide Glyphs (docs/features/tide-modules.md); effects live in tide_catalog.gd.
const TIDE_PICKUP_KINDS := [
	&"tide_socket",
	&"glyph_quickstring",
	&"glyph_farcast",
	&"glyph_heavy_barb",
	&"glyph_brine_hide",
	&"glyph_ebb_mend",
	&"glyph_deep_pulse",
	&"glyph_spring_tide",
]
const BEAM_IDS := [&"base", &"ice", &"wave"]
const ENEMY_IDS := [
	&"crawler",
	&"ceiling_diver",
	&"vent_flyer",
	&"hopper",
	&"spitter",
	&"armored_guard",
	&"frost_floater",
	&"energy_parasite",
	&"shard_turret",
	&"burrower",
	&"grasshopper",
	&"shooting_gargoyle",
	&"lava_monster",
]
const BOSS_IDS := [&"stone_guardian", &"furnace_mother", &"tidal_heart"]
const ENERGY_CONTENT_IDS := [
	"UPG-ENERGY-01",
	"UPG-ENERGY-02",
	"UPG-ENERGY-03",
	"UPG-ENERGY-04",
	"UPG-ENERGY-05",
	"UPG-ENERGY-06",
]
const MISSILE_CONTENT_IDS := [
	"UPG-MISSILE-01",
	"UPG-MISSILE-02",
	"UPG-MISSILE-03",
	"UPG-MISSILE-04",
	"UPG-MISSILE-05",
	"UPG-MISSILE-06",
	"UPG-MISSILE-07",
	"UPG-MISSILE-08",
	"UPG-MISSILE-09",
	"UPG-MISSILE-10",
	"UPG-MISSILE-11",
	"UPG-MISSILE-12",
]
const FLUX_TANK_CONTENT_IDS := [
	"UPG-FLUX-TANK-01",
	"UPG-FLUX-TANK-02",
	"UPG-FLUX-TANK-03",
	"UPG-FLUX-TANK-04",
]
const CONTENT_IDS := (
	[
		"UPG-BEAM-BASE",
		"UPG-BEAM-LONG",
		"UPG-BEAM-ICE",
		"UPG-BEAM-WAVE",
		"UPG-MISSILES",
		"UPG-SLIPSTREAM",
		"UPG-BOMBS",
		"UPG-HIGH-JUMP",
		"UPG-PRESSURE-SEAL",
		"UPG-UNDERTOW",
		"UPG-FLUX-SHIELD",
		"UPG-BURST-BEAM",
		"UPG-ECHO-SCAN",
		"REF-ENERGY",
		"REF-MISSILE",
		"REF-FLUX",
	]
	+ ENERGY_CONTENT_IDS
	+ MISSILE_CONTENT_IDS
	+ FLUX_TANK_CONTENT_IDS
)
const PICKUP_KINDS := [
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
	&"energy_tank",
	&"missile_tank",
	&"energy_refill",
	&"missile_refill",
]

# D19 (original arsenal): internal ids never change, so saves, campaign gates, the graph solver and
# tests stay compatible. Everything the player sees is resolved through these tables:
#   beam -> Seed Crossbow (base shot "Seed Bolt")
#   missiles -> Harpoon            missile_tank -> Bolt Quiver      missile_refill -> Quiver Cache
#   ice_beam / beam "ice" -> Bubble Snare     wave_beam / beam "wave" -> Echo Shot
#   bombs -> Resonance Pulse       long_beam -> Focus Lens          undertow_dash -> Undertow Dash
#   energy_tank -> Heart Pearl
# Gate kinds: missile -> harpoon socket, wave -> resonant membrane, bomb -> cracked crystal,
# undertow -> undertow barrier.
const DISPLAY_NAMES: Dictionary[StringName, String] = {
	&"beam": "Seed Crossbow",
	&"slipstream": "Slipstream",
	&"missiles": "Harpoon",
	&"long_beam": "Focus Lens",
	&"ice_beam": "Bubble Snare",
	&"wave_beam": "Echo Shot",
	&"bombs": "Resonance Pulse",
	&"high_jump": "Updraft Cloak",
	&"pressure_seal": "Pressure Seal",
	&"undertow_dash": "Undertow Dash",
	&"energy_tank": "Heart Pearl",
	&"missile_tank": "Bolt Quiver",
	&"energy_refill": "Vitality",
	&"missile_refill": "Quiver Cache",
	&"flux_shield": "Flux Shield",
	&"burst_beam": "Burst Beam",
	&"echo_scan": "Echo Scan",
	&"flux_tank": "Flux Tank",
	&"flux_refill": "Flux",
	&"tide_socket": "Tide Socket",
	&"glyph_quickstring": "Quickstring",
	&"glyph_farcast": "Farcast",
	&"glyph_heavy_barb": "Heavy Barb",
	&"glyph_brine_hide": "Brine Hide",
	&"glyph_ebb_mend": "Ebb Mend",
	&"glyph_deep_pulse": "Deep Pulse",
	&"glyph_spring_tide": "Spring Tide",
}
const BEAM_DISPLAY_NAMES: Dictionary[StringName, String] = {
	&"base": "Seed Bolt",
	&"ice": "Bubble Snare",
	&"wave": "Echo Shot",
}
const GATE_DISPLAY_NAMES: Dictionary[StringName, String] = {
	&"missile": "Harpoon Socket",
	&"wave": "Resonant Membrane",
	&"bomb": "Cracked Crystal",
	&"undertow": "Undertow Barrier",
}
const AMMO_NAME := "Bolts"

# Every runtime pickup visual is resolved here. These are single-frame 128px RGBA icons;
# generic pickup scenes must never slice them as animation strips. Arsenal art (D19) lives in
# assets/sprites/arsenal/ and falls back to the legacy dev-mode icon until it is delivered.
const ARSENAL_ICON_PATHS: Dictionary[StringName, String] = {
	&"missiles": "res://assets/sprites/arsenal/harpoon.png",
	&"missile_tank": "res://assets/sprites/arsenal/bolt_quiver.png",
	&"missile_refill": "res://assets/sprites/arsenal/quiver_cache.png",
	&"ice_beam": "res://assets/sprites/arsenal/bubble_snare.png",
	&"wave_beam": "res://assets/sprites/arsenal/echo_shot.png",
	&"bombs": "res://assets/sprites/arsenal/resonance_pulse.png",
	&"long_beam": "res://assets/sprites/arsenal/focus_lens.png",
	&"undertow_dash": "res://assets/sprites/arsenal/undertow_dash.png",
	&"energy_tank": "res://assets/sprites/arsenal/heart_pearl.png",
}
const PICKUP_ICON_PATHS: Dictionary[StringName, String] = {
	&"beam": "res://assets/sprites/devmode/beam.png",
	&"slipstream": "res://assets/sprites/devmode/slipstream.png",
	&"missiles": "res://assets/sprites/devmode/missiles.png",
	&"long_beam": "res://assets/sprites/devmode/long_beam.png",
	&"ice_beam": "res://assets/sprites/devmode/ice_beam.png",
	&"wave_beam": "res://assets/sprites/devmode/wave_beam.png",
	&"bombs": "res://assets/sprites/devmode/bombs.png",
	&"high_jump": "res://assets/sprites/devmode/high_jump.png",
	&"pressure_seal": "res://assets/sprites/devmode/pressure_seal.png",
	&"undertow_dash": "res://assets/sprites/devmode/undertow_dash.png",
	&"energy_tank": "res://assets/sprites/devmode/energy_tank.png",
	&"missile_tank": "res://assets/sprites/devmode/missile_tank.png",
	&"energy_refill": "res://assets/sprites/devmode/energy_refill.png",
	&"missile_refill": "res://assets/sprites/devmode/missile_refill.png",
	&"flux_shield": "res://assets/sprites/devmode/flux_shield.png",
	&"burst_beam": "res://assets/sprites/devmode/burst_beam.png",
	&"echo_scan": "res://assets/sprites/devmode/echo_scan.png",
	&"flux_tank": "res://assets/sprites/devmode/flux_tank.png",
	&"flux_refill": "res://assets/sprites/devmode/flux_refill.png",
	&"tide_socket": "res://assets/sprites/tide/tide_socket.png",
	&"glyph_quickstring": "res://assets/sprites/tide/glyph_quickstring.png",
	&"glyph_farcast": "res://assets/sprites/tide/glyph_farcast.png",
	&"glyph_heavy_barb": "res://assets/sprites/tide/glyph_heavy_barb.png",
	&"glyph_brine_hide": "res://assets/sprites/tide/glyph_brine_hide.png",
	&"glyph_ebb_mend": "res://assets/sprites/tide/glyph_ebb_mend.png",
	&"glyph_deep_pulse": "res://assets/sprites/tide/glyph_deep_pulse.png",
	&"glyph_spring_tide": "res://assets/sprites/tide/glyph_spring_tide.png",
}

const PICKUP_SOUND_CATEGORIES: Dictionary[StringName, StringName] = {
	&"beam": &"weapon_pickup",
	&"slipstream": &"orb_pickup",
	&"missiles": &"weapon_pickup",
	&"long_beam": &"weapon_pickup",
	&"ice_beam": &"weapon_pickup",
	&"wave_beam": &"weapon_pickup",
	&"bombs": &"weapon_pickup",
	&"high_jump": &"weapon_pickup",
	&"pressure_seal": &"weapon_pickup",
	&"undertow_dash": &"weapon_pickup",
	&"energy_tank": &"tank_pickup",
	&"missile_tank": &"tank_pickup",
	&"energy_refill": &"weapon_pickup",
	&"missile_refill": &"weapon_pickup",
	&"flux_shield": &"weapon_pickup",
	&"burst_beam": &"weapon_pickup",
	&"echo_scan": &"weapon_pickup",
	&"flux_tank": &"tank_pickup",
	&"flux_refill": &"weapon_pickup",
	&"tide_socket": &"tank_pickup",
	&"glyph_quickstring": &"weapon_pickup",
	&"glyph_farcast": &"weapon_pickup",
	&"glyph_heavy_barb": &"weapon_pickup",
	&"glyph_brine_hide": &"weapon_pickup",
	&"glyph_ebb_mend": &"weapon_pickup",
	&"glyph_deep_pulse": &"weapon_pickup",
	&"glyph_spring_tide": &"weapon_pickup",
}

const MAX_ENERGY_TANKS := 6
const MAX_MISSILE_TANKS := 12
const FLUX_BASE_MAX := 100
const FLUX_PER_TANK := 50
const MAX_FLUX := 300
const MAX_FLUX_TANKS := 4
const FLUX_TEMPORARY_REFILL := 10
const ECHO_SCAN_COST := 20
const BURST_BEAM_DAMAGE := 6
const BURST_BEAM_RANGE := 640.0
const BURST_BEAM_CADENCE := 0.075
const BURST_BEAM_DRAIN_PER_SECOND := 8.0
const FLUX_SHIELD_COST_PER_DAMAGE := 1
const ENERGY_PER_TANK := 100
const MISSILES_PER_TANK := 5
const ENERGY_REFILL_AMOUNT := 25
const MISSILE_REFILL_AMOUNT := 2
const DEFAULT_MAX_HEALTH := 100
const DEFAULT_MAX_MISSILES := 0
const BEAM_DAMAGE := 10
const WAVE_DAMAGE := 12
const MISSILE_DAMAGE := 35
const BOMB_DAMAGE := 20
const UNDERTOW_DAMAGE := 24
const BEAM_RANGE := 640.0
const LONG_RANGE_MULTIPLIER := 1.75
const BOMB_FUSE_SECONDS := 0.75
const BOMB_RADIUS := 72.0
const BOMB_LIFT_SPEED := 720.0
const MAX_ACTIVE_BOMBS := 3
const FREEZE_SECONDS := 4.0
# D19 arsenal behaviour. Harpoon (missiles): slower heavy bolt that leaves standable pegs in rock.
const HARPOON_SPEED := 980.0
const HARPOON_PEG_SECONDS := 5.0
const MAX_HARPOON_PEGS := 2
# Bubble Snare (ice): trapped enemies drift upward, capped so authored platform heights stay valid.
const BUBBLE_RISE_SPEED := 30.0
const BUBBLE_MAX_RISE := 56.0
# Echo Shot (wave): ricochets off terrain.
const ECHO_MAX_BOUNCES := 3
# Undertow Dash (undertow_dash): short horizontal burst, ground or air.
const DASH_SECONDS := 0.18
const DASH_SPEED := 1500.0
const DASH_COOLDOWN := 0.32
const DASH_INVULN_GRACE := 0.08
const HIGH_JUMP_IMPULSE := 1568.0
const PRESSURE_SEAL_DAMAGE_DIVISOR := 2
const DEFAULT_CHECKPOINT := {"room": "prototype", "x": 3360.0, "y": 448.0}

const PICKUP_DATA := {
	&"beam": {"content_id": "UPG-BEAM-BASE", "kind": &"beam"},
	&"slipstream": {"content_id": "UPG-SLIPSTREAM", "kind": &"slipstream"},
	&"missiles": {"content_id": "UPG-MISSILES", "kind": &"missiles"},
	&"long_beam": {"content_id": "UPG-BEAM-LONG", "kind": &"long_beam"},
	&"ice_beam": {"content_id": "UPG-BEAM-ICE", "kind": &"ice_beam"},
	&"wave_beam": {"content_id": "UPG-BEAM-WAVE", "kind": &"wave_beam"},
	&"bombs": {"content_id": "UPG-BOMBS", "kind": &"bombs"},
	&"high_jump": {"content_id": "UPG-HIGH-JUMP", "kind": &"high_jump"},
	&"pressure_seal": {"content_id": "UPG-PRESSURE-SEAL", "kind": &"pressure_seal"},
	&"undertow_dash": {"content_id": "UPG-UNDERTOW", "kind": &"undertow_dash"},
	&"flux_shield": {"content_id": "UPG-FLUX-SHIELD", "kind": &"flux_shield"},
	&"burst_beam": {"content_id": "UPG-BURST-BEAM", "kind": &"burst_beam"},
	&"echo_scan": {"content_id": "UPG-ECHO-SCAN", "kind": &"echo_scan"},
	&"flux_tank": {"content_id": "UPG-FLUX-TANK-01", "kind": &"flux_tank"},
	&"energy_tank": {"content_id": "UPG-ENERGY", "kind": &"energy_tank"},
	&"missile_tank": {"content_id": "UPG-MISSILE", "kind": &"missile_tank"},
	&"energy_refill": {"content_id": "REF-ENERGY", "kind": &"energy_refill"},
	&"missile_refill": {"content_id": "REF-MISSILE", "kind": &"missile_refill"},
	&"flux_refill": {"content_id": "REF-FLUX", "kind": &"flux_refill"},
}

const CONTENT_TO_PICKUP := {
	"UPG-BEAM-BASE": &"beam",
	"UPG-BEAM-LONG": &"long_beam",
	"UPG-BEAM-ICE": &"ice_beam",
	"UPG-BEAM-WAVE": &"wave_beam",
	"UPG-MISSILES": &"missiles",
	"UPG-SLIPSTREAM": &"slipstream",
	"UPG-BOMBS": &"bombs",
	"UPG-HIGH-JUMP": &"high_jump",
	"UPG-PRESSURE-SEAL": &"pressure_seal",
	"UPG-UNDERTOW": &"undertow_dash",
	"UPG-FLUX-SHIELD": &"flux_shield",
	"UPG-BURST-BEAM": &"burst_beam",
	"UPG-ECHO-SCAN": &"echo_scan",
	"UPG-FLUX-TANK-01": &"flux_tank",
	"UPG-FLUX-TANK-02": &"flux_tank",
	"UPG-FLUX-TANK-03": &"flux_tank",
	"UPG-FLUX-TANK-04": &"flux_tank",
	"UPG-ENERGY": &"energy_tank",
	"UPG-MISSILE": &"missile_tank",
	"UPG-ENERGY-01": &"energy_tank",
	"UPG-ENERGY-02": &"energy_tank",
	"UPG-ENERGY-03": &"energy_tank",
	"UPG-ENERGY-04": &"energy_tank",
	"UPG-ENERGY-05": &"energy_tank",
	"UPG-ENERGY-06": &"energy_tank",
	"UPG-MISSILE-01": &"missile_tank",
	"UPG-MISSILE-02": &"missile_tank",
	"UPG-MISSILE-03": &"missile_tank",
	"UPG-MISSILE-04": &"missile_tank",
	"UPG-MISSILE-05": &"missile_tank",
	"UPG-MISSILE-06": &"missile_tank",
	"UPG-MISSILE-07": &"missile_tank",
	"UPG-MISSILE-08": &"missile_tank",
	"UPG-MISSILE-09": &"missile_tank",
	"UPG-MISSILE-10": &"missile_tank",
	"UPG-MISSILE-11": &"missile_tank",
	"UPG-MISSILE-12": &"missile_tank",
	"REF-ENERGY": &"energy_refill",
	"REF-MISSILE": &"missile_refill",
	"REF-FLUX": &"flux_refill",
}

const WEAPON_DATA := {
	&"base": {"damage": BEAM_DAMAGE, "range": BEAM_RANGE},
	&"ice": {"damage": 0, "range": BEAM_RANGE, "freezes": true},
	&"wave": {"damage": WAVE_DAMAGE, "range": BEAM_RANGE},
	&"missile": {"damage": MISSILE_DAMAGE, "range": BEAM_RANGE},
	&"bomb": {"damage": BOMB_DAMAGE, "radius": BOMB_RADIUS},
	&"flux_burst": {"damage": BURST_BEAM_DAMAGE, "range": BURST_BEAM_RANGE, "kind": &"beam"},
	&"undertow": {"damage": UNDERTOW_DAMAGE, "radius": 82.0},
}

const ENEMY_DATA := {
	&"crawler": {"max_health": 105, "contact_damage": 12, "freeze_capable": false},
	&"ceiling_diver": {"max_health": 30, "contact_damage": 16, "freeze_capable": true},
	&"vent_flyer": {"max_health": 20, "contact_damage": 10, "freeze_capable": true},
	&"hopper": {"max_health": 24, "contact_damage": 14, "freeze_capable": true},
	&"spitter": {"max_health": 28, "contact_damage": 10, "freeze_capable": true},
	&"armored_guard": {"max_health": 60, "contact_damage": 20, "freeze_capable": true},
	&"frost_floater": {"max_health": 32, "contact_damage": 12, "freeze_capable": true},
	&"energy_parasite": {"max_health": 18, "contact_damage": 8, "freeze_capable": true},
	&"shard_turret":
	{
		"display_name": "Shard Turret",
		"max_health": 36,
		"contact_damage": 10,
		"freeze_capable": true
	},
	&"burrower":
	{"display_name": "Burrower", "max_health": 42, "contact_damage": 16, "freeze_capable": true},
	&"grasshopper":
	{"display_name": "Grasshopper", "max_health": 30, "contact_damage": 12, "freeze_capable": true},
	&"shooting_gargoyle":
	{
		"display_name": "Shooting Gargoyle",
		"max_health": 36,
		"contact_damage": 14,
		"freeze_capable": true
	},
	&"lava_monster":
	{
		"display_name": "Lava Monster",
		"max_health": 48,
		"contact_damage": 16,
		"freeze_capable": true
	},
}

const BOSS_DATA := {
	&"stone_guardian": {"max_health": 300, "contact_damage": 24},
	&"furnace_mother": {"max_health": 360, "contact_damage": 28},
	&"tidal_heart": {"max_health": 400, "contact_damage": 20},
}


static func is_ability(id: StringName) -> bool:
	return ABILITY_IDS.has(id)


static func is_flux_ability(id: StringName) -> bool:
	return FLUX_ABILITY_IDS.has(id)


static func is_flux_pickup_kind(kind: StringName) -> bool:
	return FLUX_PICKUP_KINDS.has(kind)


static func is_beam(id: StringName) -> bool:
	return BEAM_IDS.has(id)


static func is_pickup_kind(kind: StringName) -> bool:
	return PICKUP_KINDS.has(kind) or FLUX_PICKUP_KINDS.has(kind) or TIDE_PICKUP_KINDS.has(kind)


static func pickup_icon_path(kind: StringName) -> String:
	var arsenal_path: String = ARSENAL_ICON_PATHS.get(kind, "")
	if not arsenal_path.is_empty() and ResourceLoader.exists(arsenal_path):
		return arsenal_path
	return PICKUP_ICON_PATHS.get(kind, "")


## Player-visible name for an ability/pickup id (see the D19 mapping above).
static func display_name(id: StringName) -> String:
	if DISPLAY_NAMES.has(id):
		return DISPLAY_NAMES[id]
	return String(id).replace("_", " ").capitalize()


static func beam_display_name(beam_id: StringName) -> String:
	return BEAM_DISPLAY_NAMES.get(beam_id, "Seed Bolt")


static func pickup_texture(kind: StringName) -> Texture2D:
	var path := pickup_icon_path(kind)
	if path.is_empty():
		return null
	return load(path) as Texture2D


static func pickup_sound_for_kind(kind: StringName) -> StringName:
	return PICKUP_SOUND_CATEGORIES.get(kind, &"")


static func pickup_kind_for_content(content_id: String) -> StringName:
	return CONTENT_TO_PICKUP.get(content_id, &"")
