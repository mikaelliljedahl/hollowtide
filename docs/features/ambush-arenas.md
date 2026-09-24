# Feature design: ambush arenas

Status: design basis for ambush arenas, accepted by the user on 2026-09-23, and implemented in the
D21 arena `scripts/world/dynamic/ambush_arena.gd` with its pure rules in
`scripts/world/dynamic/ambush_rules.gd`. Arenas are authored with `ambush:` lines in campaign layouts.
An earlier parallel implementation (`scripts/world/ambush_*.gd`) was retired on merge; its rules
(sections 3 and 5) were ported into the D21 arena, and sections 4–9 describe the ported version.

## 1. Goal

Hollowtide should lean toward action over puzzles. An ambush arena is a room section that seals when
the player commits to it, runs two or three waves of existing enemies, and reopens when the last
enemy falls. It creates short action peaks inside the exploration loop without text, cutscenes or new
content types. Each area of the campaign is expected to hold one or two (see
[phase-2-campaign.md](../phase-2-campaign.md) room budget); this document defines the system they
will all use.

Out of scope: enemy AI changes, new enemy types, boss changes, HUD elements, campaign placement.

## 2. Research basis

Sources gathered with Firecrawl on 2026-09-23.

| Source | Finding | Rule it produces |
|---|---|---|
| Game Developer, "The Art and Science of Pacing and Sequencing Combat Encounters" | Intensity is how often the player must re-plan. The triangle pattern (more enemies each wave) is the common default; the diamond pattern (fewer but stronger enemies late) suits mini-boss finales. Too many types at once overwhelms; mixing a close and a mid-range threat forces the most re-planning. | R1, R2 |
| SMU Guildhall thesis, "Best Practices for Spatial Composition for a Pacing Curve in Combat Design" | Breaks in intensity are essential and make the next peak land harder ("restrained pacing"). | R3 |
| The Level Design Book, "Encounter" | The "door problem": players fight from the doorway unless drawn in. Start empty, trigger past a midfield threshold, and commit the player (door closes behind). Ambushes lose their surprise after the first attempt, so they must not be very difficult or they become trial and error. | R4, R5 |
| Amini Allight, "The Soft Lock Trap" | Lock-in plus checkpoint failure plus a fixed challenge that the player's current kit cannot beat creates a game that runs but cannot be progressed. | R6, R7 |
| Spawn-indicator practice (Unity tutorial, GameMaker forum threads in the same search) | Telegraph spawns and never materialize an enemy on the player. | R8 |

## 3. Design rules

- **R1 Wave shape.** Waves grow (triangle). A final wave may shrink in count but raise threat (diamond).
- **R2 Mix.** At most three enemy types per wave; pair a rusher (Hopper, Grasshopper, Energy
  Parasite) with a ranged threat (Spitter, Shard Turret, Shooting Gargoyle).
- **R3 Breather.** A short intermission (default 0.8 s) separates waves so the next spawn is a new beat.
- **R4 Commit threshold.** The trigger zone sits inside the room, past the doorway, so the player is
  already in the arena when the seals close. Seals never close on top of the player.
- **R5 Forgiving.** Ambushes use catalog enemies at catalog HP; they are action beats, not gear checks.
- **R6 Always winnable.** A spawn is only created when the player's current kit can defeat it
  (section 5). An encounter with no winnable spawns never seals.
- **R7 Never trapped.** Death, or leaving the arena by any means (dev teleport, respawn), aborts the
  encounter: seals open, ambush enemies are removed, and the arena re-arms. As a backstop, a wave in
  which no ambush enemy loses health for `stall_seconds` (40 s) is aborted the same way.
- **R8 Fair spawns.** Every spawn point shows a telegraph before the enemy appears. A spawn point
  closer to the player than the safe distance moves to the nearest other authored spawn point of the
  same ambush that is far enough away (or else the farthest one). Spawns never move to invented
  geometry: an earlier mirror-and-clamp rule put a campaign Hopper in a door corridor behind a closed
  missile gate, where the player could not reach it.
- **R9 Reward aggression.** Clearing drops one guaranteed refill (missiles if they are owned and not
  full, otherwise energy) at the authored spawn point nearest the player.
- **R10 No text.** The seals, telegraphs, sound and reward teach the rule. No tutorial text.

## 4. State machine

| State | Entered when | Behavior | Leaves to |
|---|---|---|---|
| `ARMED` | Scene start with no clear flag; after an abort | Watches the trigger (the `trigger_rect`, else the arena minus one tile at each side); the body must also be 96 px clear of every opening | `SEALING` when the player is committed, has left the trigger since the last abort, and at least one spawn is winnable |
| `SEALING` | Trigger accepted, or a breather ended | Seals closed; the current wave's spawns are telegraphed one after another (0.55 s slam delay for wave 1, then 0.32 s apart), each enemy appearing 0.5 s after its telegraph | `FIGHTING` once every spawn of the wave exists |
| `FIGHTING` | Wave spawned | Counts living ambush enemies each physics frame; runs the stall backstop | `INTERMISSION` when none remain and waves are left; `CLEARED` after the last wave |
| `INTERMISSION` | Wave defeated | 0.8 s breather | `SEALING` for the next wave |
| `CLEARED` | Last wave defeated, `max_seconds` failsafe, or clear flag already set at start | Seals open, one refill drops, world flag saved | terminal |

Abort path (R7): from `SEALING`, `FIGHTING` or `INTERMISSION`, `GameState.player_died`, the player's
body centre leaving the arena rectangle, or `stall_seconds` (40 s) in which no ambush enemy loses health
or dies returns the arena to `ARMED` after removing its enemies and opening its seals. It re-seals
only after the player has left the trigger and come back.

An enemy counts as defeated when its node is freed, its `health` is at or below zero, or it has stayed
more than 192 px outside the arena rectangle for 2 s. The last clause covers physics escapes, so an
escaped enemy can never hold the doors shut.

## 5. Winnability table (R6)

Derived from the reaction matrix in [content-catalog.md](../content-catalog.md#reaction-matrix).
"Any damage" means owning `beam` (base, Wave and Burst all damage), `missiles`, `bombs` or
`undertow_dash`.

| Enemy ID | Required kit |
|---|---|
| `crawler` | `missiles` |
| `armored_guard` | `missiles` or `bombs` |
| `lava_monster` | never spawned by ambushes (it needs an authored lava basin) |
| all other common enemies | any damage |
| bosses | never spawned by ambushes |

A skipped spawn is dropped silently; the rest of the wave still runs. A wave left empty is skipped.
The rules live in `AmbushRules.requirements` and `AmbushRules.can_defeat_enemy`; `AmbushArena.can_defeat`
keeps its old meaning (every enemy of a list is winnable). Layout validation also rejects the Lava
Monster and bosses in any wave.

## 6. Authoring contract

An ambush is one `AmbushArena` node (`scripts/world/dynamic/ambush_arena.gd`). Its position is the arena
centre; every rectangle and point is relative to it.

| Property | Meaning |
|---|---|
| `arena_size` | Enemy leash (passed to each enemy's `configure_arena`) and abort boundary. |
| `wave`, `extra_waves` | Wave 1, then later waves in order. |
| `spawn_offsets` | Authored spawn points; spawn i of all waves in order uses point i (wrapping). R8 only ever moves a spawn between these points. |
| `door_rects` | Openings to seal; each becomes a `SealSlab` (`scripts/world/dynamic/seal_slab.gd`). |
| `trigger_rect` | Commit zone (R4); empty means the arena minus one tile at each side. |
| `local_id`, `flag_id` | The clear flag is `<room_id>.ambush.<local_id>` inside a campaign room, or `flag_id` when set. |
| `max_seconds`, `stall_seconds` | Failsafe clear (120 s) and stall abort (40 s). |

Campaign rooms author ambushes as `ambush:` lines in their layouts (`scenes/campaign/layouts/*.txt`,
built by `tools/build_campaign_rooms.py`); the syntax is documented in the `tools/campaign_layout.py`
docstring and the rules live in `tools/campaign_ambush.py`:

| Option | Meaning |
|---|---|
| `x y w h` | Arena rectangle in room tiles. Every open border cell that leads out becomes a seal; runs longer than four cells are rejected, so borders must be walls with narrow openings. |
| `wave=`, `wave2=`, `wave3=` ... | Comma-separated enemy IDs per wave, numbered without gaps. |
| `trigger=x,y,w,h` | Optional commit zone inside the arena. A save may sit in the arena, never in the trigger. |
| `spawns=x,y,w,h` | Optional area inside the arena where the builder picks spawn cells (floor cells for walkers, open air for flyers), so no spawn lands in a sealed side chamber. |
| `id=` | Local ID used in the clear flag. |

Level rules for authors:

1. Every opening of the arena gets a seal; check the tile map for gaps a Slipstream can use.
2. The trigger sits past the doorway and well clear of every seal.
3. Keep `spawns=` to space the player can reach and shoot from the trigger without new abilities.
4. A checkpoint or refill is reachable before the arena. Missile-only waves need a guaranteed
   missile refill on the approach, as for bosses.
5. Place the ambush where the room is already worth passing through; never in a dead end whose only
   content is the ambush.

The first campaign ambush is `fringe_03.beam_trial`: the arena covers the whole room interior, the
room's two resident Hoppers became wave 1, and wave 2 is two Hoppers and a Ceiling Diver in the lower
corridor. The trigger (cells 10–20, rows 10–14) starts just east of the beam pickup, so without the
beam the player never commits (R6) and with it the arena seals at once. The seals close the west
one-tile Ball tunnel (cell 1, row 11) and the east door behind the missile gate (cell 58, rows 12–14).

Placements in the other areas (two waves each, kit on arrival in brackets):

| Arena | Where | Waves |
|---|---|---|
| `nexus_02.loft` | Whisper Loft, just out of the High Jump crack; seals the crack (fringe kit plus High Jump) | Grasshoppers; then Spitter, Vent Flyer, Grasshopper |
| `vaults_01.threshold` | Cold Threshold pit floor; seals the west door and the east ledge door (fringe kit) | Hoppers; then Shard Turret, Armored Guard, Hopper |
| `kiln_02.antechamber` | Furnace Shaft landing below the heat zone; seals the west entry and the lower west door (vaults kit plus Pressure Seal) | Vent Flyers; then Shooting Gargoyle and two Vent Flyers |
| `depths_01.undertow_hall` | Pressure Descent lower hall; seals the entry shaft mouth and the east door behind the undertow gate (kiln kit) | Leech Wisps; then Shard Turret and two Leech Wisps |

A scripted real-input bot (scratch tool, not in the repo) plays each campaign arena. Its first runs
found three defects, now fixed at the root: every Ceiling Diver's dive stopped after one frame
(`EnemyAi.ceiling_diver` now tracks the dive and the climb back), R8 could move a walker onto a
flyer's air point (relocation now stays within the movement class, `AmbushRules.AIR_ENEMIES`), and
because arenas end on the floor line, a player standing on the floor was outside every ambush
enemy's leash (the leash now reaches 16 px below it).

## 7. Dev track placement

S3 ("Ball / Bombs") holds the dev-track arena, built by `DevStationLayout._add_s3_ambush`
(`scripts/dev/dev_station_layout.gd`) in groups `dev_owned` and `dev_ambush`, so resetting the dev
runtime rebuilds it. S3 is the first station the dev route reaches with a weapon.

- The arena is the whole station; seals close the ground-level doorways in both side walls (rows 14–17).
- The trigger covers local x 704–1216 above the floor, short of the raised bomb-block platform
  (x 1280+), so the platform's fixtures stay reachable without starting the fight.
- Wave 1: two Hoppers. Wave 2: two Hoppers and a Spitter on the high platform. Wave 3: an Armored
  Guard and two Vent Flyers (the guard is skipped without missiles or bombs).
- The clear flag is `dev:S3:ambush`. The arena is not built when the user arguments contain
  `--evidence-run=`, because scripted evidence routes cannot fight.

## 8. Implementation

- `scripts/world/dynamic/ambush_rules.gd`: winnability, per-spawn filtering, authored-point spawn
  resolution and the reward choice, with no scene access apart from reading `GameState`.
- `scripts/world/dynamic/ambush_arena.gd`: the section 4 state machine in `_physics_process`, telegraphs
  that reuse the dust and emerge-flash effects, spawning through `EnemyFactory`, aborts, and the clear
  refill through `CombatLoot`.
- `tools/campaign_ambush.py` and `tools/campaign_worldfx.py`: layout validation and scene emission.

## 9. Verification

Suite `tools/check_ambush_rules.tscn` (registered as `ambush rules` in `tools/run_godot_check.py`):

| Case | Expectation |
|---|---|
| Rules | Relocation never crosses between air and floor points; no weapon beats nothing; the beam beats common enemies only; bombs beat the Armored Guard; missiles beat the Crawler; Lava Monster and bosses never pass; a far spawn stays, a close one moves to the nearest far authored point, with none far enough the farthest wins; the reward kind follows missile state. |
| Waves | Two waves in a test room: a telegraph precedes each spawn, a spawn on the player moves, no spawn during the breather, every spawn lands on an authored point, the clear sets the flag, opens the seals and drops exactly one energy refill. |
| Kit filter | No weapon never seals; with the beam only, a wave of Armored Guard, Crawler and Hopper spawns just the Hopper and a Crawler-only wave is skipped; owned, non-full missiles give a missile refill; a Guard-plus-Crawler ambush never seals. |
| Death abort | Death opens the seals and removes the enemies; standing in the trigger does not re-seal until the player has left and returned. |
| Leave abort | Moving the player out of the arena aborts without setting the clear flag. |
| Stall abort | With `stall_seconds` shortened, damage resets the timer and an untouched wave is aborted. |
| Campaign arenas (`tools/check_ambush_campaign.tscn`) | Each of the four area arenas: no seal with the move-test kit, seals with the arrival kit and blocks physics, both waves clear on authored points, the flag persists across a reload. |
| Dev S3 (suite `ambush rules dev`) | Exactly one S3 arena; no seal without a weapon; seals both doorways with the beam; all three waves run and clear; the flag is saved. |
| Campaign `fringe_03` | No seal without the beam; with it both openings block physics queries; both waves clear with all five spawns on authored points; the flag persists across a room reload that leaves the arena open. |

`tools/check_worldfx.tscn` still covers the single-wave arena and `tools/check_worldfx_layout.py` the
layout validation and emission of waves and triggers.

Not verified: a real-input playthrough and a native visual capture of the D21 port (the retired
implementation's results no longer apply), and the hands-on feel of seal timing, telegraph
visibility, wave pacing and the reward drop.

## 10. Follow-ups

- A real-input playthrough of the S3 dev arena.
- A map icon for uncleared ambush rooms, only if playtests show players want to find them again.
