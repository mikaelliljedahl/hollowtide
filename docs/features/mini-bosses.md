# Feature design: mini-bosses

Status: proposal for [plan-next.md](../plan-next.md) section 4 ("one mid-boss per area"). Not a
normative contract; it asks for no change to `docs/` contracts except the two small additions in
section 9. Read [boss-rework.md](boss-rework.md) (the framework this reuses),
[bigger-world.md](bigger-world.md) (the rooms) and [content-catalog.md](../content-catalog.md) first.

## 1. Goal

The jump from common enemies and ambush waves to the three four-stage bosses is large. Each area gets
one optional, shorter boss in its optional challenge room. It teaches the area's boss vocabulary at
small scale, costs about 30 s, and pays with ammo or a station, never with a Heart Pearl. No mini-boss is
required; the solver's no-optional run never enters one.

Out of scope: new pickup kinds, new Heart Pearls, text, cutscenes, new sound design beyond reusing
existing boss cues, dev-track changes, Trials roster changes.

## 2. Rules (inherited and changed)

Kept from boss-rework: R1 locked truth, R2 telegraph first (at least 0.45 s, three cues at once), R3
punish window after the last attack of a chain, R6 transitions as a reward beat (1.0 s breather), R7 no
text, R8 openings pace the damage. Changed:

- **Two stages**, split at 50 % health (`MINI_STAGE_THRESHOLDS = [0.5]`). No desperation stage.
- **Three openings per stage** (`MINI_OPENINGS_PER_STAGE = 3`), so one opening takes one sixth of the
  health; a Harpoon (35) spends an opening on every mini except the last two, where weaker hits share it.
- Stage 1 uses protection row **M1**: Seed Bolt, Harpoon and Echo Shot hurt during an opening; Snare,
  Pulse and Dash glance. Stage 2 uses **M2**: Harpoon only during the punish window (an "armor" closes
  otherwise), matching B2. No per-boss puzzle trigger (no Snare or Echo opening), so a player with
  only the fringe kit can fight Fernmaw.
- Punish windows: at least 1.2 s in stage 1 and 1.4 s in stage 2 (`ARMORED_MIN_PUNISH`).
- Idle between chains: 1.1 s in stage 1, 0.8 s in stage 2.
- Stage 2 adds exactly one attack and keeps stage 1's; one chain of two known attacks ends its cycle.
- Assist options apply unchanged (damage taken, game speed). "Skip ambushes" does not skip a mini-boss:
  it is a boss, not an ambush (see [assist-options.md](assist-options.md)).

## 3. The five mini-bosses

Names are original and in the forest and tide register (D19). Internal ids are the lower-case words.
Stats sit below the main bosses (300/24, 360/28, 400/Heart); contact damage is 50-80 % of theirs.

| Area | Name (id) | Room | Health | Contact | Stage 1 / stage 2 |
|---|---|---|---|---|---|
| fringe | Fernmaw (`fernmaw`) | fringe_08 Hopper Pit (120,0 30x17) | 100 | 14 | 50 / 50 |
| nexus | Tollwing (`tollwing`) | nexus_09 Skyward Ledge (210,0 30x17) | 130 | 16 | 65 / 65 |
| vaults | Rimeweaver (`rimeweaver`) | vaults_08 Icicle Shaft (0,17 30x34) | 150 | 18 | 75 / 75 |
| kiln | Emberkite (`emberkite`) | kiln_08 Crucible Run (270,34 30x17, needs Pressure Seal) | 170 | 20 | 85 / 85 |
| depths | Lanternjaw (`lanternjaw`) | depths_08 Undertow Run (180,119 45x17) | 190 | 22 | 95 / 95 |

The mini-boss replaces the `ambush` zone of its room (ambush waves and a boss arena do not share a
room; the ambush validator is not run on these rooms). Each arena is the whole room minus the door
cells. Every room keeps its bigger-world Quiver Cache or Quiver (section 6).

### 3.1 Fernmaw (fringe)

A squat, moss-backed leaper with a ring of fern fronds for a mouth, hanging from the pit ceiling roots
until the fight starts. Silhouette: wide low oval with two heavy hind legs; fronds flare before each
attack. Theme: the hopper family grown large.

| Attack | Stage | Telegraph | Active | Punish | What happens |
|---|---|---|---|---|---|
| Spore Lob | 1 | 0.60 s: fronds lift, three floor marks | 0.10 s | 1.2 s | Three spores arc to the locked marks (player spot, 192 px either side) and burst into short-lived puffs |
| Pounce | 1 | 0.65 s: crouch, floor arrow | 0.80 s | 1.4 s | Leaps along the arrow and lands 128 px short of the first wall (pocket rule) |
| Root Burst | 2 | 0.75 s: fronds slam, floor circles | 0.30 s | 1.4 s | Root spikes under the player's spot and 256 px either side |

Rotation: stage 1 Lob, Pounce; stage 2 Root Burst, Pounce, Lob, then Pounce then Lob (chain).

### 3.2 Tollwing (nexus)

A bell-shaped resonant crystal with two glassy wings, hanging from the top of the ledge room and
chiming between attacks. Silhouette: tall teardrop with a clapper that swings before a release.

| Attack | Stage | Telegraph | Active | Punish | What happens |
|---|---|---|---|---|---|
| Toll Ring | 1 | 0.60 s: bell swells, radial lines | 0.10 s | 1.2 s | Eight radial chime drops with a 60 degree gap toward the player |
| Shard Drop | 1 | 0.75 s: glint on the ceiling, floor circles | 0.30 s | 1.3 s | Crystal shards drop on the player's spot and 224 px either side |
| Swoop | 1 | 0.65 s: tips back, floor arrow | 1.00 s | 1.4 s | Dives along the arrow, rises on the far side; ends over open floor, never in a pocket |
| Peal Lane | 2 | 0.80 s: dashed lane across the room | 0.10 s | 1.5 s | A low stream of chimes sweeps from the far wall (jump); a second one 0.6 s later |

Rotation: stage 1 Ring, Drop, Swoop; stage 2 Peal, Ring, Swoop, Drop then Ring (chain).

### 3.3 Rimeweaver (vaults)

A pale, long-legged limestone weaver that clings to the shaft walls. Silhouette: thin cross of legs
around a small cold body, icicle-tipped. Theme: the frost crust given arms.

| Attack | Stage | Telegraph | Active | Punish | What happens |
|---|---|---|---|---|---|
| Needle Line | 1 | 0.60 s: one aim line | 0.20 s | 1.2 s | Three icicle needles along the locked line |
| Icicle Drop | 1 | 0.80 s: ceiling cracks, floor circles | 0.40 s | 1.3 s | Icicles fall in three columns, 160 px apart, under and beside the player |
| Wall Skitter | 1 | 0.65 s: legs fold, arrow up the wall | 1.10 s | 1.5 s | Runs up one wall and down the other along the locked path; leaves no hazard |
| Frost Ring | 2 | 0.80 s: ring of dots with a bright gap | 0.10 s | 1.5 s | Ten frost shards with a 77 degree gap toward the player |

Rotation: stage 1 Needle, Drop, Skitter; stage 2 Ring, Needle, Skitter, Drop then Needle (chain).

### 3.4 Emberkite (kiln)

A bird-shaped cinder flyer with a hooked beak and a glowing keel, perched on a basalt stump. The room
is hot (Pressure Seal required, as for kiln_08). Silhouette: sharp swept triangle, ember tail streaming.

| Attack | Stage | Telegraph | Active | Punish | What happens |
|---|---|---|---|---|---|
| Ember Fan | 1 | 0.55 s: pulse, aim lines | 0.10 s | 1.2 s | Three-way fan (reuses `ember_fan`) |
| Flare Dive | 1 | 0.65 s: banks back, floor arrow | 1.00 s | 1.4 s | Dives along the arrow and pulls up 128 px short of the first wall |
| Vent Column | 1 | 0.75 s: floor circles | 0.30 s | 1.3 s | Fire pillars under the player and 256 px either side (reuses `vent_burst`) |
| Cinder Rain | 2 | 0.85 s: dotted columns across the room, one bright gap | 0.50 s | 1.5 s | Four ember columns fall, the gap is the answer |

Rotation: stage 1 Fan, Vent, Dive; stage 2 Rain, Fan, Dive, Vent then Fan (chain).

### 3.5 Lanternjaw (depths)

A blind deepwater predator with a single violet lure hanging in front of a wide jaw. Silhouette:
long tapered body, hinged jaw, lure as the brightest thing in the room. The room's push current stays
on; the fight uses it.

| Attack | Stage | Telegraph | Active | Punish | What happens |
|---|---|---|---|---|---|
| Lure Pulse | 1 | 0.60 s: lure swells, radial lines | 0.10 s | 1.2 s | Eight radial drops, offset on the second use (reuses `tide_ring`) |
| Bite Lunge | 1 | 0.70 s: jaw opens, floor arrow | 0.90 s | 1.5 s | Lunges along the arrow, stops 128 px short of the first wall |
| Dark Lance | 1 | 0.65 s: one aim line | 0.30 s | 1.2 s | Three fast bolts on the locked line (reuses `surge_lance`) |
| Undertow Pull | 2 | 0.80 s: dashed lane toward the jaw | 1.20 s | 1.5 s | A current of 300 px/s drags toward the mouth inside the lane; dash out or hold a wall |

Rotation: stage 1 Pulse, Lunge, Lance; stage 2 Pull, Lance, Lunge, Pulse then Lance (chain).

## 4. Framework reuse

Reused as is: `EnemyFactory.create` and the boss scene wiring, the `idle/telegraph/active/recover`
state machine and its cancel rules (`scripts/enemies/boss.gd`), the signals `stage_changed`,
`attack_telegraphed`, `attack_released`, `defeated`, `EnemyProjectile`, `boss_telegraphs.gd` markers
(aim line, floor lane, floor circle, ring gap), `boss_motion.gd` charges with the 128 px pocket rule,
the opening budget logic (`opening_damage`), arena gating (the boss is frozen and glances hits while the
player is outside), defeat rewards (`defeat_rewards.gd`), and `assist` damage scaling.

Needs new code:

- **Stage count.** `boss_patterns.gd` hardcodes four stages. Add `stage_count(id)` (2 for mini ids, 4
  otherwise) with `MINI_STAGE_THRESHOLDS`; `stage_for`, `stage_floor`, `protection_phase` and the
  health-bar notches take it. Main bosses keep their results exactly.
- **Data.** `TIMING`, `ROTATIONS`, `MOVE_SPEEDS` entries for the new attacks; a registry
  `scripts/enemies/mini_boss_patterns.gd` merges one table per boss from `scripts/enemies/mini/<id>.gd`.
- **New emissions** in `boss_attacks.gd` (through a `mini/<id>.gd` hook, not more branches): Spore Lob
  arc, Root Burst, Toll Ring gap, Wall Skitter path, Cinder Rain columns, Peal Lane, Undertow Pull
  current. Everything else maps to an existing emission (section 3 marks the reuses).
- **Spawn.** `scripts/campaign/mini_boss_spawn.gd` extends `boss_spawn.gd` (the pattern of
  `scripts/trials/trial_boss_spawn.gd`): `flag_id()` returns `mini:<id>`, no `regional:` flag, no grate,
  and it does not call `on_boss_defeated`, so the ending, boss shortcuts and fast travel never see a
  mini-boss.
- **Layout.** New legend kind `miniboss <id> arena=x,y,w,h return=x,y` (not the `boss` kind, to keep
  the solver's boss-room refill and hub-shortcut rules off it), emitted by the build tool to
  `mini_boss_spawn.gd`. `MINI_BOSS_IDS` in `tools/campaign_layout.py`.
- **Catalog.** `MINI_BOSS_IDS`, stats and `DISPLAY_NAMES` in `scripts/progression/content_catalog.gd`;
  a scene or factory entry per id in `scripts/enemies/enemy_factory.gd`; visuals in
  `scripts/enemies/effects/mini_visuals.gd` (shapes drawn in code first, art batch later).

## 5. Flags and save

World flag `mini:<id>` (for example `mini:fernmaw`), set by `mini_boss_spawn.gd` on defeat through the
existing `GameState.set_world_flag`. World flags are already a free-form set in the save, so there is no
schema change and no save-version bump; old saves simply lack the flags. Boss health, stage and
openings are not saved (a fight restarts when the room is re-entered, like the main bosses). The safe
return point is set inside the arena exactly as `boss_spawn.gd` does. Flag names must not start with
`boss:` or `regional:`: `TrialCatalog.UNLOCK_FLAG`, revisit-remix counting and boss shortcuts read
those.

## 6. Rewards

No new pickup kinds, no new Heart Pearls, and the bigger-world Quiver budget stays at 12. The reward is
that the room's existing payoff is sealed behind the boss:

| Mini-boss | Reward (already in the bigger-world budget) | How it is gated |
|---|---|---|
| Fernmaw | Quiver Cache in fringe_08 | In a side alcove behind `flaggate mini:fernmaw` |
| Tollwing | Quiver Cache in nexus_09 | In an alcove behind `flaggate mini:tollwing` |
| Rimeweaver | Quiver Cache in vaults_08 | Behind `flaggate mini:rimeweaver`; the timed door to fringe_01 stays openable from below |
| Emberkite | Bolt Quiver `kiln_08.missile_02` | The pickup sits behind `flaggate mini:emberkite` |
| Lanternjaw | Quiver Cache in depths_08 | Behind `flaggate mini:lanternjaw` |

The door cells of the rooms are never gated, so the player can always leave. The gated cache is the
prize, not the fight's supply: the player arrives with Harpoons from the shrine or cache one room away
(fringe_07, vaults_09, kiln_09 and depths_09 are neighbours), and the campaign graph check applies the
boss-room refill and pocket rules to these rooms (section 7).
The solver treats `mini:*` flaggates as optional: nothing required sits behind them.

## 7. Test plan

Suite `tools/check_mini_bosses.tscn`, registered as `mini bosses` in `tools/run_godot_check.py`, one
case file per boss under `tools/mini_cases/<id>.gd` plus a shared rules case.

| Case | Expectation |
|---|---|
| Rules | Two stages split at 50 %, M1 then M2; stage 2 adds one attack; every telegraph at least 0.45 s; punish at least 1.2 s (stage 1) and 1.4 s (stage 2); health and contact below the main bosses |
| Main bosses unchanged | `stage_for`, thresholds, rotations and the `boss rework` suite give the same results as before |
| Pacing | A player who lands a Harpoon in every opening kills each mini in 25 to 45 s and sees every attack released in both stages; Seed Bolts alone cannot finish stage 2 |
| Stage transition | A hit across 50 % drops a wind-up unfired; 1.0 s breather; no damage carries into stage 2 |
| Engagement | With the player outside the arena every mini takes no damage (same as the main bosses) |
| Pocket fairness | Each charge (Pounce, Swoop, Skitter, Dive, Lunge) stops 128 px short of a wall or step; a probe finds an unhurt response at both arena ends |
| Cycles | Every attack is released after its telegraph by at least 0.45 s; projectiles appear only while active |
| Flags | Defeat sets `mini:<id>` and no `boss:` or `regional:` flag; reload keeps the flag and the boss does not respawn; `flaggate mini:<id>` opens; the ending and boss shortcuts are not affected |
| Save | A save written by the previous build loads unchanged; a save with `mini:` flags loads on this build |
| Campaign graph | `python3 tools/check_campaign_graph.py` passes: doors mirror, every mini room can walk back to a save, no required item behind a `mini:` gate, the four-room shrine spacing holds |
| Layout | Each of the five layouts parses, has one `miniboss` entry with a valid id and the arena inside the room, and no `ambush` |
| Assist | Damage taken and game speed scale a mini-boss fight; skip ambushes does not skip it |
| Visual | Screenshots of each telegraph and each silhouette via `tools/capture_combat.gd` (`--shots=telegraphs`), looked at by a person |

## 8. Implementation work packages

Order: WP1 first (foundation and Fernmaw), then WP2 to WP5 in parallel. The registry and stub files
are created in WP1 so later packages edit only their own files and never `boss_patterns.gd`.

| WP | Scope | Files it writes |
|---|---|---|
| WP1 foundation and Fernmaw | Two-stage support, registry, `mini_boss_spawn.gd`, `miniboss` legend kind, catalog ids, factory, shared rules and flag cases, Fernmaw data, emissions, visuals, layout, tests | `scripts/enemies/boss_patterns.gd`, `scripts/enemies/boss.gd`, `scripts/enemies/boss_attacks.gd` (hook only), `scripts/enemies/mini_boss_patterns.gd`, `scripts/enemies/mini/fernmaw.gd` and four empty stubs (`tollwing.gd`, `rimeweaver.gd`, `emberkite.gd`, `lanternjaw.gd`), `scripts/enemies/effects/mini_visuals.gd`, `scripts/enemies/enemy_factory.gd`, `scripts/campaign/mini_boss_spawn.gd`, `scripts/progression/content_catalog.gd`, `tools/campaign_layout.py`, `tools/build_campaign_rooms.py`, `scenes/campaign/layouts/fringe_08.txt`, `tools/check_mini_bosses.tscn`, `tools/check_mini_bosses.gd`, `tools/mini_cases/fernmaw.gd`, `tools/run_godot_check.py` |
| WP2 Tollwing | Nexus data, emissions (Toll Ring gap, Peal Lane), visuals, room layout, test case | `scripts/enemies/mini/tollwing.gd`, `scripts/enemies/effects/mini_visuals_tollwing.gd`, `scenes/campaign/layouts/nexus_09.txt`, `tools/mini_cases/tollwing.gd` |
| WP3 Rimeweaver | Vaults data, emissions (Wall Skitter path, Frost Ring), visuals, layout, test case | `scripts/enemies/mini/rimeweaver.gd`, `scripts/enemies/effects/mini_visuals_rimeweaver.gd`, `scenes/campaign/layouts/vaults_08.txt`, `tools/mini_cases/rimeweaver.gd` |
| WP4 Emberkite | Kiln data, emissions (Cinder Rain), visuals, layout with heat zone and gated Quiver, test case | `scripts/enemies/mini/emberkite.gd`, `scripts/enemies/effects/mini_visuals_emberkite.gd`, `scenes/campaign/layouts/kiln_08.txt`, `tools/mini_cases/emberkite.gd` |
| WP5 Lanternjaw | Depths data, emissions (Undertow Pull current), visuals, layout keeping the push current, test case | `scripts/enemies/mini/lanternjaw.gd`, `scripts/enemies/effects/mini_visuals_lanternjaw.gd`, `scenes/campaign/layouts/depths_08.txt`, `tools/mini_cases/lanternjaw.gd` |

The integrate lane (not a package) owns the rebuilt generated files (`scenes/campaign/rooms/*`,
`scripts/campaign/campaign_rooms.gd`), the solver treatment of `mini:*` gates in
`tools/check_campaign_graph.py`, `docs/state.md`, and the amendments below. The layout packages assume
the bigger-world rooms exist (they edit the room file the area lane created); if a room is not yet
built, the package waits for that lane.

## 9. Contract amendments proposed

- [content-catalog.md](../content-catalog.md) "Bosses": add "Optional mini-bosses (one per area, two
  stages, flag `mini:<id>`) are defined in `docs/features/mini-bosses.md`; they are not counted as
  bosses by the ending, shortcuts or Trials."
- [bigger-world.md](bigger-world.md) section 4: the five optional challenge rooms (fringe_08, nexus_09,
  vaults_08, kiln_08, depths_08) hold a mini-boss instead of an ambush zone; rewards and the Quiver
  budget are unchanged.

Open questions: whether the Trials should one day include a mini-boss rush (not proposed here); and
whether the ambush arena of each room should move to another room to keep the encounter count (not
needed for the solver, a pacing call for the user).
