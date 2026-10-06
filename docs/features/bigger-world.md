# Bigger world: 16 to 48 rooms

Status: proposal, prepared for [plan-next.md](../plan-next.md) section 3. Not a normative contract; it
asks for no change to `docs/` contracts. Room sizes, origins and door cells below are the plan; the
solver (`tools/check_campaign_graph.py`) has the final word. Read
[phase-2-campaign.md](../phase-2-campaign.md) and [code-contract.md](../code-contract.md) first.

## 1. Current inventory (16 rooms)

| Area | Rooms (origin x,y size) | Pickups |
|---|---|---|
| fringe (5) | 01 (0,0 60x17), 02 (30,17 30x34), 03 (60,34 60x17), 04 (120,17 30x34), 05 (90,17 30x17) | Slipstream (02), Seed Crossbow (03), Resonance Pulse `bombs` (04), Focus Lens `long_beam` (05); 4 Bolt Quivers (01 x2, 03, 05); 2 Heart Pearls (01, 03); Tide Socket (04); glyphs deep_pulse (01), farcast (05), quickstring (03) |
| nexus (2) | 01 (120,51 60x34; save, refill, end gate), 02 (150,34 30x17) | 1 Pearl, 1 Quiver (02); glyphs brine_hide (01), heavy_barb (02) |
| vaults (3) | 01 (90,51 30x17), 02 (30,51 60x34), 03 boss (90,68 30x17) | Bubble Snare `ice_beam`, Updraft Cloak `high_jump`, 1 Pearl, 1 Quiver, Tide Socket (02); Quiver (01); glyph ebb_mend (01) |
| kiln (3) | 01 (180,51 60x17), 02 (240,51 30x34), 03 boss (180,68 60x17) | Pressure Seal, 1 Pearl, Tide Socket (01); Echo Shot `wave_beam`, 1 Quiver, glyph spring_tide (02) |
| depths (3) | 01 (135,85 45x34), 02 boss (180,102 45x17), 03 ending (225,85 30x34) | Undertow Dash, 1 Pearl, 1 Quiver (01) |

Totals: **6 Heart Pearls** (`energy_tank`, cap `MAX_ENERGY_TANKS` = 6, reached), **9 Bolt Quivers**
(`missile_tank`, cap `MAX_MISSILE_TANKS` = 12), 3 Tide Sockets (capacity 2 to 5, all placed), 7 glyphs
(all placed), 8 ability pickups. Saves: fringe_02, fringe_03, nexus_01, vaults_01, vaults_02 (two),
kiln_01, kiln_02, depths_01.

Required versus optional (from the solver constants `OPTIONAL_KINDS`, `REQUIRED_MISSILE_TANK`): required
are Seed Crossbow, Slipstream, Resonance Pulse, Bubble Snare, Echo Shot, Undertow Dash, Pressure Seal,
Updraft Cloak, the first Harpoon (`fringe_03.missile_01`, the only Quiver the no-optional run takes) and
both regional bosses plus Tidal Heart. Optional: all Pearls, all other Quivers, Focus Lens, sockets and
glyphs. Note the solver grants the Harpoon from the first `missile_tank` it sees, so every new Quiver
must be optional in practice: the solver ignores any Quiver except `fringe_03.missile_01` in its
no-optional run. Harpoon is needed by both regional bosses.

Area gates: nexus_01 north-east/south-east flag gate needs both regional bosses before depths; the two
regional branches (vaults, kiln) work in either order; each branch boss room has a flag-gate shortcut to
the hub (`tools/campaign_shortcuts.py`).

## 2. Reward budget decision

The runtime supports only these rewards in layouts (`PICKUP_KINDS` in `tools/campaign_layout.py`,
`ContentCatalog.PICKUP_KINDS`): ability pickups, `energy_tank`, `missile_tank`, `tide_socket`, seven
`glyph_*`. Stations supported by the layout tool: `save`, `refill`, `missilerefill` (Quiver Cache).
There is no map-reveal item (the map reveals a room on entry), no text prop and no lore prop kind.

Decision:

1. **Heart Pearls stay at 6, Tide Sockets at 3, glyphs at 7.** No new ones. The cap is not raised.
2. **Three new Bolt Quivers** to reach the documented 12: `nexus_04.missile_02` (secret),
   `kiln_08.missile_02` (challenge), `depths_06.missile_02` (secret). Final spread: fringe 4, nexus 2,
   vaults 2, kiln 2, depths 2.
3. **Quiver Caches** (`missilerefill`) and plain `refill` stations are the everyday payoff of secrets and
   challenges (ammo safety for bosses and arenas). Each optional challenge room holds one.
4. **Extra save shrines** (`S`, on rock) keep the solver's return-to-save rule satisfied; see section 5.
5. **Landmarks and vistas** pay with sight lines, `light` shafts and area art, never with text.
6. Not adopted because unsupported: map-revealing items, lore or environment props, extra sockets. They
   need a contract amendment (code, save or map changes) and are out of scope. The catalog also has
   `energy_refill` and `missile_refill` (Vitality, Quiver Cache pickups), but layouts and solver do not
   list them; the integrate lane may allow them later as a separate small change.

The bigger world is therefore deliberately sparse in pickups: rooms earn their place by routes,
landmarks, loops and encounters, not by loot (see "do not fill empty corridors" in phase-2-campaign.md).

## 3. Layout format in short

File `scenes/campaign/layouts/<area>_<NN>.txt`; `id:` must equal the file name and `area:` one of
fringe, nexus, vaults, kiln, depths. Header: `id`, `area`, `name`, `origin: X Y` (world position in
tiles; rooms abut exactly, no overlap). Grid: rows of equal width, at least 30 wide and 17 tall, one char
per 64 px tile. `#` rock, `.` air, any other char must be defined in the `legend:` block
(`  <char> <kind> <args> [key=value ...]`). Every legend char must appear in the grid.

Legend kinds (`ENTITY_KINDS`): `start` (once, only fringe_01), `save`, `refill`, `missilerefill` (these
three stand on rock, one row above `#`), `pickup <kind> <local_id>` (exactly once in the grid; world id
is `<room>.<local_id>`, must be unique), `enemy <id> [w=N h=N dir=-1]`, `floater`, `boss <id> arena=x,y,w,h
return=x,y`, `gate <missile|bomb|wave|undertow> [alcove|floor]` (solid until opened by Harpoon, Pulse,
Echo Shot, Undertow Dash), `flaggate <flags>` (e.g. `boss:stone_guardian` or
`regional:stone_guardian,regional:furnace_mother`), `lava`, `ending`, `light`, `timeddoor [seconds>=3]`
with a `switch door=<char>` (shootable; needs an air cell and a reachable standing spot), `crumble
[permanent]`, `stalactite` (hangs from rock), `crusher` (rectangle with rock above). Zone lines:
`heat: x y w h`, `ambush: x y w h wave=a,b [wave2= wave3= trigger= spawns= id=]`, `current: x y w h
dir=... strength=... [kind=water|wind|steam]` (side strength at most 360; upward at 500 or more lets the
body climb), `rising: x y w h kind=lava|water speed<=180 safe>=3` (h at least 8, stop line leaves air).
Enemy ids: use only `ENEMY_IDS` in `tools/campaign_layout.py`. Boss ids are `BOSS_IDS`.

Doors: an air cell on the room boundary is a door opening. A boundary opening needs the mirrored
opening (same world cells, same edge pair) in the neighbouring room, and one opening may not span two
rooms. A `gate`/`flaggate`/`timeddoor` cell on the boundary does not count as open, so seal by putting
the gate on the first interior cell behind the opening. Doors are derived; there is no link syntax.
Doorways are normally 3 cells high (1 cell for a Slipstream low tunnel, 64 px).

Toolchain:
- `tools/campaign_layout.py` parses and validates: headers, equal grid width, known chars, legend
  shape, pickup count, rock under stations, world-fx rules, ambush (`validate_ambush`), flood
  (`validate_flood`), door mirroring (`link_doors`), room overlap (`overlap_errors`).
- `python3 tools/build_campaign_rooms.py` writes `scenes/campaign/rooms/<id>.tscn` and the index
  `scripts/campaign/campaign_rooms.gd`. Never hand-edit generated files.
- `python3 tools/check_campaign_graph.py [--verbose] [--show=<room>]` is the graph solver: parse,
  overlap, mirrored doors, unique pickup ids, generated files not stale, boss-room refill, walk-in
  lava, and three cell-level runs (vaults-first, kiln-first, no-optional). It proves every reachable
  state at every progression stage can walk back to a save shrine with the abilities held then, that
  each area has a save, that each branch boss keeps its hub shortcut, that sequence breaks are
  intended, and that the campaign ends. Movement model is conservative: body 1x3, jump 3 cells (Updraft
  5), 3 cells of drift, wall jumps only in chimneys (walls within 3 cells), heat cells impassable
  without Pressure Seal.
- `tools/check_progression.gd` asserts catalog counts (6 Pearl ids, 12 Quiver ids, 13 abilities); its
  numbers must not change with this expansion. Also affected: `tools/check_campaign_map.gd`,
  `tools/check_campaign_moves*.gd`, `tools/check_ambush_campaign.gd`, `tools/check_worldfx_layout.py`.
- Author loop: edit your own layouts, run `python3 tools/check_campaign_graph.py`. A lane cannot
  regenerate scenes (the index file is shared), so in a lane worktree expect only "is stale" errors;
  the integrate lane rebuilds.

## 4. Area plan (16 to 48 rooms)

Target: fringe 9, nexus 9, vaults 10, kiln 10, depths 10 = 48. Origins are tile coordinates on free
space next to the existing world (verified non-overlapping); sizes are (w x h). "Seam" means a door whose
two sides belong to different lanes (section 5). Timed doors are opened by a switch on the far side so
they act as shortcuts; all gates below use abilities the player holds on that route. A required ability
is named only when the gate itself needs it.

### Fringe (+4: 06 to 09)

| Id | Origin, size | Attaches to | Gate | Purpose | Holds |
|---|---|---|---|---|---|
| fringe_06 Skylight Atrium | 60,0 60x17 | fringe_01 east wall (rows 5-7) and fringe_05 north | Slipstream (1-cell tunnel at the fringe_01 door) | Landmark: collapsed ceiling, light shafts, first look at the wider cavern; closes the fringe loop 01-06-05-04-03-02-01 | none |
| fringe_07 Root Cistern | 60,17 30x17 | fringe_02 east wall (rows 0-3 local y 17-20); one-way floor drop into fringe_03 (round 12) | Resonance Pulse (`bomb` gate at the fringe_02 side) | Secret pocket; its floor drop is the way back out (phase-2-campaign.md, Encounter pacing) | `missilerefill`, save |
| fringe_08 Hopper Pit | 120,0 30x17 | fringe_04 north, fringe_09 via nexus_08 east | none | Optional challenge: ambush arena (hopper, ceiling_diver) on the north loop | `missilerefill` |
| fringe_09 Thread Fall | 150,17 30x17 | fringe_04 east (rows 17-30), nexus_02 north | timed door at the nexus_02 end, switch on the fringe_04 side | Shortcut from the fringe back to the hub; loop A (fringe_04-09-nexus_02-nexus_01-fringe_04) | none |

### Nexus (+7: 03 to 09)

| Id | Origin, size | Attaches to | Gate | Purpose | Holds |
|---|---|---|---|---|---|
| nexus_03 Chime Gallery | 180,34 30x17 | nexus_02 east, kiln_01 north (seam) | none | Loop B: nexus_01-kiln_01-03-02-01; safe for either branch order | none |
| nexus_04 Membrane Gallery | 210,34 30x17 | nexus_03 east (dead end) | Echo Shot (`wave` gate, plus one extra Echo Shot membrane as a readable hint) | Secret, reached after the kiln branch | Bolt Quiver `missile_02` |
| nexus_05 Listening Spire | 180,0 30x34 | nexus_03 north; nexus_08 west | none (upper ledge needs Updraft Cloak, vista only) | Landmark: tall echo shaft with light shafts and a view of the final gate direction | none |
| nexus_06 Seep Crossing | 210,17 30x17 | nexus_05 east (lower), kiln_05 east-west door (seam) | timed door at the kiln_05 end, switch on the kiln_05 side | Shortcut from the kiln back to the hub; loop C | none |
| nexus_07 Undercroft | 90,85 45x17 | nexus_01 south (west part of its south edge), vaults_05 east | timed door at the vaults_05 end, switch on the vaults side | Loop D: hub to vaults by the south, second entry into vaults_02 | none |
| nexus_08 Cistern Crown | 150,0 30x17 | fringe_08 east, nexus_05 west | none | Loop E: fringe_04-08-nexus_08-05-03-02-01; connects the two north bands | none |
| nexus_09 Skyward Ledge | 210,0 30x17 | nexus_05 east (upper), nexus_06 north, kiln_10 west (seam) | none | Optional challenge: crusher and crumble-floor gauntlet | `missilerefill` |

### Vaults (+7: 04 to 10)

| Id | Origin, size | Attaches to | Gate | Purpose | Holds |
|---|---|---|---|---|---|
| vaults_04 Stalagmite Steps | 30,85 30x17 | vaults_02 south (x30-59), vaults_05, vaults_10 | none | Descent with armored guard and bats; loop D west leg | none |
| vaults_05 Drip Basin | 60,85 30x17 | vaults_02 south, vaults_04, nexus_07 east, vaults_09 | none | Hub of the lower vaults; shortcut leg to the hub through nexus_07 | none |
| vaults_06 Hanging Garden | 0,51 30x34 | vaults_02 west wall (ledge door) | Updraft Cloak (ledge at least 4 cells up; revisit reward) | Landmark: hanging formations, light shafts | none |
| vaults_07 Lichen Undercut | 0,85 30x17 | vaults_06 south | Resonance Pulse (`bomb` gate) | Secret, dead end | `missilerefill`, save |
| vaults_08 Icicle Shaft | 0,17 30x34 | vaults_06 north; fringe_01 south (seam, cut at x5-8) | timed door at the fringe_01 end, switch on the vaults_08 side (opens from below) | Optional challenge: ambush arena with armored_guard; loop F start-area to vaults | `missilerefill` |
| vaults_09 Plumb Line | 60,102 60x17 | vaults_05 south, nexus_07 south | none | Sump loop under the lower vaults; quiet recovery | `refill` |
| vaults_10 Pale Gallery | 30,102 30x17 | vaults_04 south; depths_07 north (seam) | `flaggate regional:stone_guardian,regional:furnace_mother` at the depths_07 opening | Loop H: depths back to vaults (late backtracking) | save |

### Kiln (+7: 04 to 10)

| Id | Origin, size | Attaches to | Gate | Purpose | Holds |
|---|---|---|---|---|---|
| kiln_04 Vent Stack | 240,34 30x17 | kiln_02 north, kiln_05 north, kiln_08 east | timed door at the kiln_02 end, switch on the kiln_02 side | Steam updraft climb; north kiln band stays shut until opened from inside | none |
| kiln_05 Steam Loft | 240,17 30x17 | kiln_04, nexus_06 (seam), kiln_09, kiln_10 | none (no heat) | Shortcut from the kiln to the hub | none |
| kiln_06 Great Bellows | 270,51 30x34 | kiln_02 east wall | Pressure Seal (heat zone) | Landmark: glowing bellows chamber, light shafts | none |
| kiln_07 Ash Pocket | 270,85 30x17 | kiln_06 south | Resonance Pulse (`bomb` gate) | Secret, dead end | `missilerefill` |
| kiln_08 Crucible Run | 270,34 30x17 | kiln_04 east, kiln_06 north | Pressure Seal (heat zone) | Optional challenge: ambush (shooting_gargoyle, vent_flyer) in heat | Bolt Quiver `missile_02` |
| kiln_09 Cooling Pool | 270,17 30x17 | kiln_05 east, kiln_08 north | none (no heat) | Loop G inside the kiln (02-04-08-06-02); rest stop | save |
| kiln_10 Skylight Flue | 240,0 30x17 | nexus_09 east (seam), kiln_05 north | none (no heat) | Loop C2 between the north nexus and kiln | none |

### Depths (+7: 04 to 10)

All depths rooms hang off depths_01 (the boss room depths_02 and the ending room depths_03 stay sealed
from them) so nothing needs anything beyond Undertow Dash, which depths_01 supplies.

| Id | Origin, size | Attaches to | Gate | Purpose | Holds |
|---|---|---|---|---|---|
| depths_04 Pressure Cathedral | 180,85 45x17 | depths_01 east (upper) | Undertow Dash (`undertow` gate) | Landmark: largest vault, dark water, mineral glow; wall on the depths_03 side | none |
| depths_05 Sump Crossing | 135,119 45x17 | depths_01 south | none | Branch hub with water currents | none |
| depths_06 Drowned Gallery | 90,119 45x17 | depths_05 west | Undertow Dash (`undertow` gate) | Secret, dead end | Bolt Quiver `missile_02` |
| depths_07 Brine Lift | 45,119 45x34 | depths_09 west; vaults_10 north (seam) | timed door at the depths_09 end, switch on the depths_07 side | Shortcut: long way from the deep back to vaults and the hub (loop H) | none |
| depths_08 Undertow Run | 180,119 45x17 | depths_05 east (dead end) | none | Optional challenge: ambush arena (energy_parasite, shard_turret) with push current | `missilerefill` |
| depths_09 Low Sluice | 90,136 45x17 | depths_10 west, depths_07 | none | Connector with a rising-water cell and the depths save | save |
| depths_10 Sump Gauge | 135,136 45x17 | depths_05 south, depths_09 east | none | Current gauntlet; second loop (05-10-09-07) | none |

Checks for order and gates: vaults_06 and its secret need Updraft Cloak and Pulse, both found before
the vaults boss; kiln north-band rooms are heat-free and kiln_06/08 need Pressure Seal, found in
kiln_01; nexus_04 needs Echo Shot (kiln) and is optional; every cross-area seam into the depths is a
flag gate on both regional bosses, so neither branch order can reach Undertow Dash early, and the new
kiln north band cannot drop into kiln_02 before the player opened it from inside (heat is impassable
without Pressure Seal in the solver anyway). Cross-area loops: A, B, C, D, E, F, H (at least two are
required; B and D are the ones that shorten the critical backtracking).

## 5. Rules for parallel lanes

Lanes: fringe, nexus, vaults, kiln, depths, integrate. Use separate worktrees (`hollowtide-lanes/<lane>`).

- **Area lane** writes only `scenes/campaign/layouts/<own area>_*.txt`, existing and new. It may cut an
  opening into its own existing rooms for a seam, using the world cells in this table, and may not edit
  another area's layout. Seam ownership: each lane cuts its own side at the world cell range given by
  the two origins, three rows or columns wide unless the table says 1; the integrate lane
  reconciles mismatches.
- Seam owners: fringe_01/vaults_08 cut (fringe_01 south x5-8, vaults_08 north), nexus_03/kiln_01 (both
  lanes), nexus_06/kiln_05, nexus_09/kiln_10, vaults_10/depths_07, nexus_07/vaults_05,
  nexus_01 south and nexus_01 east/west edge openings belong to the nexus lane.
- Pickup ids are `<room>.<local>`; never move or rename an existing pickup. No new `energy_tank`,
  `tide_socket` or `glyph_*`; only the three Quivers named above. Never raise `MAX_ENERGY_TANKS`.
- Every new room needs: a reachable return to a save with the abilities held at the point of entry,
  no enemy that blocks a door unwinnably, `ambush` only with a kill filter and an `id`, no heat hot
  enough to need an ability the player lacks, no tutorial text, English room names.
- Landmark art (Codex batch per lane) is delivered as an asset request under `assets/environment/areas/<area>/`
  only after layouts are accepted; lanes do not touch `tools/build_area_art.py` or the catalog.
- **Integrate lane owns**: generated `scenes/campaign/rooms/*`, `scripts/campaign/campaign_rooms.gd`
  (via `tools/build_campaign_rooms.py`), the world graph and solver constants in
  `tools/check_campaign_graph.py`, `tools/campaign_shortcuts.py`, `tools/campaign_breaks.py`, the map
  (`scripts/campaign/campaign_map*.gd`, `tools/check_campaign_map.gd`), minimap, save-shrine spacing and
  fast-travel stations, `tools/check_progression.gd` (counts stay 6 and 12), `docs/state.md` and
  `docs/phase-2-campaign.md` updates, the `AGENTS.md` index entry for this file, and the merge order.
- Save-shrine spacing (integrate lane): at most about four rooms of walking between shrines on any
  route, a shrine before each boss and in each area, none in a room that is an ambush arena. Shrines in
  this plan: fringe_07, vaults_07, vaults_10, kiln_09, depths_09, plus the existing ones.
- Merge order: fringe, nexus (hub seams), vaults, kiln, depths, then integrate runs the build,
  `python3 tools/check_campaign_graph.py` and `make check`. A failing solver run is fixed in the lane
  that owns the failing room, never by loosening the solver.
