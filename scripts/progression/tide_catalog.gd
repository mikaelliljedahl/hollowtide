extends RefCounted

## Tide Glyphs: passive modules socketed at save shrines (docs/features/tide-modules.md).
## Every glyph bends one part of the arsenal and pays for it elsewhere. All numbers live here;
## TideModules turns the socketed set into stat multipliers that combat code reads.

const BASE_CAPACITY := 2
const MAX_SOCKETS_FOUND := 3
const MAX_CAPACITY := BASE_CAPACITY + MAX_SOCKETS_FOUND
const SOCKET_KIND := &"tide_socket"
const GLYPH_PREFIX := "glyph_"

## Stats a glyph may modify. Multipliers compose by product; `_add` stats compose by sum.
const STATS := [
	&"crossbow_damage",
	&"crossbow_reload",
	&"crossbow_speed",
	&"crossbow_range",
	&"harpoon_damage",
	&"harpoon_bolt_add",
	&"pulse_damage",
	&"pulse_fuse",
	&"damage_taken",
	&"ambush_heal_add",
]

## Order is the menu order. `upside` and `downside` are the player-visible menu lines.
const GLYPHS: Dictionary[StringName, Dictionary] = {
	&"quickstring":
	{
		"name": "Quickstring",
		"cost": 1,
		"upside": "Crossbow bolts fly 35% faster and reload 40% faster",
		"downside": "Crossbow bolts deal 30% less damage",
		"mods": {&"crossbow_speed": 1.35, &"crossbow_reload": 0.6, &"crossbow_damage": 0.7},
	},
	&"farcast":
	{
		"name": "Farcast",
		"cost": 1,
		"upside": "Crossbow bolts reach 40% farther",
		"downside": "Crossbow reloads 60% slower",
		"mods": {&"crossbow_range": 1.4, &"crossbow_reload": 1.6},
	},
	&"heavy_barb":
	{
		"name": "Heavy Barb",
		"cost": 2,
		"upside": "Harpoon hits 60% harder",
		"downside": "Every harpoon shot spends two bolts",
		"mods": {&"harpoon_damage": 1.6, &"harpoon_bolt_add": 1},
	},
	&"brine_hide":
	{
		"name": "Brine Hide",
		"cost": 1,
		"upside": "Take 25% less damage from hits",
		"downside": "Crossbow and Harpoon deal 20% less damage",
		"mods": {&"damage_taken": 0.75, &"crossbow_damage": 0.8, &"harpoon_damage": 0.8},
	},
	&"ebb_mend":
	{
		"name": "Ebb Mend",
		"cost": 2,
		"upside": "Clearing an ambush restores 50 health",
		"downside": "Take 20% more damage from hits",
		"mods": {&"ambush_heal_add": 50, &"damage_taken": 1.2},
	},
	&"deep_pulse":
	{
		"name": "Deep Pulse",
		"cost": 2,
		"upside": "Resonance Pulse deals 75% more damage",
		"downside": "Resonance Pulse takes 50% longer to burst",
		"mods": {&"pulse_damage": 1.75, &"pulse_fuse": 1.5},
	},
	&"spring_tide":
	{
		"name": "Spring Tide",
		"cost": 3,
		"upside": "Crossbow and Harpoon hit 35% harder",
		"downside": "Take 35% more damage from hits",
		"mods": {&"crossbow_damage": 1.35, &"harpoon_damage": 1.35, &"damage_taken": 1.35},
	},
}


static func is_glyph(id: StringName) -> bool:
	return GLYPHS.has(id)


static func is_add_stat(stat: StringName) -> bool:
	return String(stat).ends_with("_add")


static func cost(id: StringName) -> int:
	return int(GLYPHS[id]["cost"]) if GLYPHS.has(id) else 0


static func glyph_name(id: StringName) -> String:
	return String(GLYPHS[id]["name"]) if GLYPHS.has(id) else String(id)


static func pickup_kind(id: StringName) -> StringName:
	return StringName(GLYPH_PREFIX + String(id))


## Glyph id for a pickup kind, or &"" when the kind is not a glyph pickup.
static func glyph_for_kind(kind: StringName) -> StringName:
	var text := String(kind)
	if not text.begins_with(GLYPH_PREFIX):
		return &""
	var id := StringName(text.trim_prefix(GLYPH_PREFIX))
	return id if GLYPHS.has(id) else &""


static func is_pickup_kind(kind: StringName) -> bool:
	return kind == SOCKET_KIND or glyph_for_kind(kind) != &""
