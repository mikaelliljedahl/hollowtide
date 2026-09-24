# Implementation decisions and accepted contract amendments

## Status and mandate

The user has ordered the documentation plan and selected:

- Compact finished game, about 3-5 hours, 4-5 areas and three bosses. The plan uses five.
- Slipstream has a regular grounded/coyote jump at unchanged base `JUMP_VELOCITY`; bomb lift remains a separate explosion impulse.
- The user's corrected keyboard controls are accepted and current: `A` is `Jump`, `Space` is `Alternate jump`, and `Z` is `Slipstream`.
- Developer track as first partial delivery, with all weapons, upgrades and monsters.
- High resolution cave graphics and accurate undertow jumping; existing sense of movement must be maintained.

Original P0 recommendations below remain decision history. Later accepted/live sections supersede
conflicts and describe implemented Phase 1 contract. Never use historical wording to overwrite current
normative contracts or user's explicit replacement decisions.

## Decision list for P0

| ID | Recommendation | What is to be determined? | Blocks |
|---|---|---|---|
| D01 | Keep 64px physics; separate larger terrain modules | P0 approves the sample's resource size, layout, and file owner. P2a builds image samples; the user approves the appearance before full production. | P2 full production/final delivery |
| D02 | Keep found Ice/Wave; select an active one. Long is a separate range layer. | Change via pause/equipment menu; no combined Ice+Wave shots; range/damage/cooldown in common table. | P4 |
| D03 | Twelve Bolt Quivers at +5, six Heart Pearls at +100 | First Bolt Quiver unlocks and fills +5. Tank fills energy completely. Other Bolt Quivers also add +5 to current ammo; refills never change capacity. | P1/P4 |
| D04-R1 | **Accepted replacement:** Slipstream may use A/Space (A primary; Space alternate) for a regular grounded/coyote jump at unchanged base `JUMP_VELOCITY` while retaining Ball form/collider. | No High Jump multiplier, wall jump, spin/Undertow, or midair double jump. Bomb lift remains separate and unchanged; no mandatory port requires advanced bomb chaining. | Implemented; F1 playtest |
| D05 | High Jump gives approximately 1.5 × measured base height | Own modifier to ground jump, not global change to gravity/apex or wall-jump impulse. Exact value is determined with current integrator. | P5 |
| D06 | Spin is basic animation; Undertow Dash grants attack during valid spin | State table below, collision/hurt priority, new sprite contracts. | P5 |
| D07 | Protection module without armor change | Halve valid damage rounded up; define heat, contact damage and exceptions. The crawler's outgoing base damage is still 12. | P4/P5 |
| D08 | Keep the crawler's missile exclusivity | Determine the remainder of the reaction matrix. No general Undertow Dash or bomb may bypass the crawler contract. | P6 |
| D09 | A saving slot + backup, versioned snapshot; isolated dev profile | Death/respawn, atomic save, validation, unknown version and new file owners. | P1/P3 |
| D10 | Frozen enemy can be platform | New collision layer/mask, freeze pivot, safe thaw, roof/crushing drop and projectile hit while freezing. | P4/P6 |
| D11 | Dev text only in explicit dev mode | Input Name, Menu Owner, Export Block and Allowed Diagnostic Labels. No tutorials in normal game world. | P3 |
| D12 | Linux desktop first release; other platforms separate decision | Reference machine, gamepad layout, export preset and verification environment. | P10/P11 |

D04-R1 replaces the original D04 no-ball-jump direction and is implemented; it is not an unresolved contradiction. D01 has two gates:
technical test mandate in P0, visual approval in P2a. Thus, P0 does not require that P2 already be
built. Final graphics direction is determined by image samples, not discussion of higher file resolution. The damage values of the catalogue,
freeze duration, and boss HP may be balanced in the owned data table after the first playtest; the table must have a single source and explicit version. No copied constants in individual enemy scripts.

## Suggested interface limits

This describes responsibility, not finished API code. P0 must write exact signatures/signals
before two agents build each side. Existing calls are kept compatible during migration.

| System | Own | May not do |
|---|---|---|
| `GameState` | Unlocked IDs, Capacity, Current Resources, Active Beam, World Persistent IDs | Read devpanel, control physics, know knockback or draw HUD. |
| Pickup/Progression System | Unique collection via an atomic operation | Double tank rewards on two contact calls or resets. |
| `Weapons` | Control of owned ability, cost, cooldown, spawn of projectile/bomb | Spend ammo if spawn is rejected; let the player pay the same missile again. |
| `Player` | Shape, spin, movement, damage immunity, own hurtbox/attack surface and visual state | Own missile accounting or write directly to UI. |
| Enemy/Status | HP, Resistance, Freeze, AI, Visible Reactions | Read the player's health; deal damage by bypassing `Player.take_damage`. |
| World/save | Room IDs, Persistent Doors, Checkpoints and Snapshots | Save Node credentials or mix dev profile with campaign. |
| Dev Panel | Ask for valid presets, reset, spawn and teleport | Own alternative version of a weapon or direct writing in the campaign save. |
| HUD/Map | Read state via signals, show quantity/capacity/selected weapon and discovered rooms | Duplicate permissions or change resources to correct the display. |

For each new API, the error outcome, signal order and owner are specified. Example: a missile pickup
posts its unique ID and increases capacity/resource exactly once, then emits one
coherent update; loading the same snapshot does not re-issue the pickup reward.

## Save domains and reset — suggested exact delimitation

- Active domain is selected once at startup: `campaign` or `dev`. Replacement requires return to
  start and full reinitialization of states; the dev panel cannot switch to the campaign domain.
- Suggested paths: `user://saves/campaign/slot_01.json` and
  `user://saves/dev/slot_01.json`. Backup and temporary file are in the same respective directory.
  No fallback searches in the other domain. Release builds only accept `campaign`.
- `GameState` only holds active domain's snapshot. The Save system owns the domain/path and
  receives a validated snapshot, never arbitrary path from panel or pickup.
- Write to temporary file, validate, keep last valid backup and replace accordingly
  target file atomically. Snapshot contains schema version and domain which is checked when reading.
- A corrupt master file permits restoration from a valid backup within the same domain. An unknown
  version is left untouched. If a valid backup is missing, menu error/new game selection is displayed without automatic deletion.
- **Station reset:** reset station volatiles, local test doors/blocks and
  station sandbox flags to saved station baseline. Keep selected preset and its
  resource levels as starting values. Never change anything on disk; campaign world is not affected.
- **All-reset in dev:** reset the entire active dev session including the dev-pickup ID,
  boss flags and map to chosen pure preset. Dev save file is changed only when explicitly
  save/delete-dev-profile; campaign save files must not be opened for writing.
- **Death/Reload:** use last session checkpoint after 0.45s, restore full health and keep current progress in memory. Do not load disk snapshot on death. This replaces the
  older wording on saving on death; explicit loading and process restart still follows
  active domain. The boss progression test runs without a station reset between victory and loading.

P1 tries, among other things, identical pickup IDs in both domains, tampered snapshot domain,
corrupt main file with valid backup and aborted write. The campaign file hash before and after the dev profile test
must be the same. Exact GDScript signatures are still being determined in P0.

## Later determined user decisions

The following decision applies to this integration delivery and replaces conflicting older wording:

- Runtime UI and visible game strings are in English. The project's documentation is in English.
  Help in start menu and pause are explicitly approved text outside the game world.
- Runtime controls are arrows for move/aim, Down crouch, Z Slipstream, Left Shift run,
  A jump (Space alternate), X beam/bomb/low crouched shot, C missile, V beam cycling, Q owned-Flux-module
  selection, F Flux activation/toggle, Esc pause/help and F1 dev panel. J/K are actual alternate
  beam/missile bindings.
- `make run` starts normal boot menu. `make dev` starts the same boot menu with dev flag.
- Phase 1 is implemented but F1 is awaiting playtests and ongoing integration. Phase 2 is not
  started.
- Normal spin is user approved. Other player, enemy, weapon, pickup, fixture, gate, and
  environment visuals are technically integrated but not finally user approved.
- Five original 48-second area melodies and gameplay/Flux/environment audio are integrated and await
  human listening. Splash and firing art are integrated; no endorsement beyond normal spin is claimed.

## Spin and Undertow Dash — suggested state table

| Event/Mode | Spin | Undertow Dash |
|---|---|---|
| Ground jump with horizontal movement/input | Starts compact spin | Active only if upgrade is available. |
| Standing Vertical Jump / Go Over Edge | Standard Jump/Fall Pose | Inactive. |
| Wall jump | Starts a new spin after takeoff, with existing physics unchanged | Active if the upgrade is available. |
| Shoot or vertical aim during spin | Breaks spin into aiming pose for the rest of the air arc | Close the attack surface before the shot. |
| Landing, Slipstream, damage, death, or room change | Finishes spin | Attack surface and effect end immediately. |
| Quick turn of direction in the air | Continuous pivot, no size jump | No extra hit on the same target from a rendered frame. |
| Ball Shape / Bomb Lift | Ball animation, not humanoid spin | Inactive. |

State is updated in physics, animation follows. Rendered glow must not override one
enemy is met. A target takes at most one Undertow hit per contiguous overlap; exit and
new entry contact can provide next hit. On simultaneous contact, the attack wins against explicitly
vulnerable enemy, but immune enemy or danger can damage the player. No general invulnerability.

## Proposed expansion of file ownership

Today's code contract does not allocate all future files. The following areas need to be introduced
explicitly there before anyone writes code. No implementation may just assume that this
table is a new normative contract.

| Role | Proposed Allocation |
|---|---|
| Scaffold/system | `scripts/progression/**`, `scripts/world/**`, `scripts/save/**`, `scripts/dev/**`, `scenes/dev/**`, `resources/progression/**`, all pickup files and level scenes in addition to today's explicit list |
| Battle | Existing battle/enemy folders; new `resources/combat/**` and `resources/enemies/**` |
| Movement | Existing three player files; no parallel writers in `player.gd` |
| Graphics | `assets/sprites/**`, `assets/environment/**`, `tools/source_art/**`, `tools/gen_sprites.py`, new `tools/gen_terrain.py` |
| HUD/UI | Existing UI folders, including dev panel, pause, and map UI |
| Sound | `assets/audio/**`, `scripts/autoload/audio.gd`, `tools/gen_audio.py` |
| Integrator | Contract/status, export presets, test registration; `project.godot` is changed through the scaffold owner |

Dev logic belongs to scaffold; dev panel scene/script under `scenes/ui/` and `scripts/ui/`
belongs to HUD. Common interfaces must be delivered before parallel implementation.
Verification scripts have named data owners according to the code contract; they do not collectively belong
to the graphics role.

## Existing contract errors to be handled openly

- `asset-contract.md` says all `tools/` belongs to graphics. `code-contract.md` allows
  custom verification scripts. P0 should make the descriptions unambiguous, not stop test work.
- `code-contract.md` has legacy text about missing graphics and a fixed Muzzle position before
  later aiming section. The latter sight interface must be clearly normative.
- `game-feel.md` says 100 health/12 damage means eight hits to kill. Eight leaves
  4 health; the ninth kills. Keep the figures, correct the explanation in case of approved contract audit.
- The same document calls 0.18s damage input lock shorter than the wall jump's 0.14 s. Correct the text,
  not reconciled values.
- Historical no-ball-jump wording is replaced by D04-R1. Bomb lift remains a separate impulse, not a regular jump modifier.
- Undertow/bomb damage and frozen platform require supplemented damage IDs/collision rules.
- New assets require dimensions, pivot, layout and filename; no `preload()` against guessed files.

## Live determined decisions after the phase-1 work

The following decisions are accepted by the user for this delivery and **replace conflicting ones
older recommendations** in this file, roadmap or reports. They do not change tuned
motion, damage or collision constants unless otherwise stated here.

- All visible text in the game is in English. The documentation is in English. The start menu,
  pause and devpanel are allowed to show help text; the game world still doesn't get tutorials.
- Runtime controls are Down for crouch, Z for Slipstream, Left Shift held for run, A for jump (Space
  alternate), X for beam/bomb or a crouched low shot, C for missiles, V for cycling owned beams, Q for
  selecting an owned Flux module, F for activating/toggling Flux, Esc for pause/help and F1 for
  devpanel. J/K are alternate beam/missile bindings.
- Death uses current session checkpoint, waits 0.45s, gives full health and keeps
  progress in memory. Death does not load an older disk checkpoint.
- Music may draw on the general mood of classic atmospheric exploration games, but must be
  Hollowtide's own original composition and never copy melody, sound or visual expression.
- Defeated-enemy drops are optional temporary resources: +25 energy, +2 missiles, or +10 Flux when
  Flux is owned and below capacity. They clamp to capacity, have no save ID, and cannot be mandatory
  progression.
- The entire arsenal should have separate icons, including High Jump, Pressure Seal and tanks. A generated
  image or a manifest does not count as runtime integration until a physical pickup displays its
  icon.
- Upgraded feedback is accepted direction: Undertow aura, small bomb explosion, distinct
  hit/death effects and relevant sounds should follow actual state/hit events without replacing crash evidence or creating a large screen flash.
- High resolution, soft color images and terrain modules are the right direction. 64 px physics grid,
  collision layers, hitboxes, and tuned movement/damage values remain unchanged.

These points are decided product requirements, while actual balance and final visual/acoustic
acceptance still requires F1 play test.

## Historical P0 delivery checklist

1. Baseline report with actual commands, errors and images; separate working code from playtests.
2. Approved contract diff for D01–D11 and ownership; D12 is determined at the latest before platform work.
3. A fixed content/reaction matrix and the single data source of the constants.
4. Test commands for formatting, lint, headless and document links, or explicitly
   decision to introduce missing control as first bounded implementation.
5. Then P1/P2 is started. Unresolved decisions block affected packets, not silent guesswork.

## Accepted control and Flux integration

Down crouch, Z Slipstream, A jump (Space alternate), Left Shift run, and grounded X low shot are implemented. Their F1 status is
pending hands-on approval, not implementation. Crouch collider/pose, muzzle origin, stand-up clearance,
and aim/fire/hurt/death transitions remain manual acceptance points.

Flux Shield, Burst Beam, and Echo Scan are implemented original Hollowtide systems sharing one finite
meter and one selected module. Q selects an owned module; F toggles Shield/Burst or pulses Echo Scan.
First Flux ownership provides 100 capacity; four Flux Tanks add 50 each for maximum 300. Echo costs 20;
temporary refill gives 10; Burst drains 8/s; Shield spends one Flux per absorbed damage. Save schema v2
persists Flux state and explicitly migrates valid v1 saves without latent Flux ownership. No world
tutorial text is added.

## Accepted current integration facts

- S0–S10 use fringe S0–S1, nexus S2–S3, vaults S4–S5, kiln S6–S7, and depths S8–S10.
- Five environment kits, authored boundary passages, gates, Wave Grate, shrines, sprint/wall poses,
  beam families, enemy/boss/pickup art, and Kiln lava/fire/steam presentation are implemented.
- All twelve dev-track Bolt Quivers retain stable IDs/count and have standing-safe collection and retreat.
- Five original 48-second area melodies are integrated. Human visual/audio approval remains pending.
- Latest integration gate passed `make f1-check` 37/37 with zero ObjectDB/resource diagnostics.

Hollowtide music must be original: never ship, sample, remix, or transcribe existing music. Other games may inform broad genre conventions only; do not copy their names, assets, UI, or distinctive mechanics.

## User decisions 2026-09-23 (supersede conflicting wording elsewhere)

- **D13 — Phase 2 runs in parallel with F1 polish.** The F1 block on P8–P11 is lifted. F1 hands-on
  approval is still open, but campaign work does not wait for it.
- **D14 — No agent-count limit.** The former "maximum two/three writing agents" rule is removed.
  Parallel agents work in separate git worktrees/branches with disjoint file ownership (see
  `code-contract.md` → "Parallel lanes 2026-09"); the integrator merges to `main`.
- **D15 — Lightweight verification.** Evidence manifests, committed videos and commit-bound JSONL logs
  are retired. A change is done when `make check` passes and the author has looked at real in-game
  screenshots of the affected scene. Screenshots/videos are working files and are not committed.
- **D16 — Phase 2 scope: compact mini-campaign.** First playable campaign is ~12–15 hand-authored rooms
  that pass through all five areas (fringe → nexus → vaults/kiln branches → depths) with real
  progression, save points, map, a boss per branch and an ending. It reuses Phase 1 systems. The
  48-room plan remains the long-term frame.
- **D17 — Area identity over facility uniformity.** Steel-facility terrain is no longer drawn over every
  area. Each area renders its own natural terrain; steel/industrial pieces appear only where an area's
  identity calls for it. Background art must read as five distinct worlds, and nothing may float
  unsupported (lava sits in basins at the bottom, fixtures meet real floors).
- **D18 — Music variety.** Area music may be regenerated/extended so areas differ in instrumentation,
  tempo and structure; the former "frozen approved bytes" status of the five melodies is lifted.
  Originality rules still apply.

## User decisions 2026-09-23, round 2 — originality and liveliness

- **D19 — Replace the genre-default arsenal with an original one (iteration 1: weapons + Undertow Dash).** Player-visible names,
  art, sound and behaviour change; **internal IDs stay** (`missiles`, `ice_beam`, …) so saves, gates, the
  campaign graph and tests remain compatible. Mapping (internal id → new ability):
  | Internal id | New ability | Behaviour |
  |---|---|---|
  | `missiles` / `missile_tank` / `missile_refill` | **Harpoon** / **Bolt Quiver** / **Quiver cache** | Heavy bolt, slower than the beam, same damage role. Embeds in plain rock walls and becomes a small temporary standable peg (~5 s, max 2 at once). Opens "harpoon sockets" (former missile locks). |
  | `ice_beam` | **Bubble Snare** | Traps an enemy in an air bubble that drifts slowly upward for the former freeze duration; the bubble is a standable platform. Ice floaters become bubble floaters. |
  | `wave_beam` | **Echo Shot** | Ricochets off terrain up to 3 times and passes through resonant grates (former wave grates). |
  | `bombs` | **Resonance Pulse** | Placed/emitted in compact form (still Slipstream this iteration) as an expanding ring; cracks brittle crystal (former bomb blocks), keeps the lift impulse. |
  | `long_beam` | **Focus Lens** | Range upgrade, unchanged function. |
  | `undertow_dash` | **Undertow Dash** | Replaces the spin attack: a short fast horizontal dash (ground or air, one air dash per jump) that passes through enemies dealing damage and breaks "undertow barriers". Normal (non-attack) spin jump stays. |
  | `energy_tank` | **Heart Pearl** | +100 health, unchanged. |
  Slipstream, High Jump and Pressure Seal are kept for now (later iteration). The tide mechanic is postponed.
- **D20 — Surprise enemies.** New enemy types allowed beyond the thirteen: ceiling bat swarm (bursts out on
  proximity), mimic (rock or fake pickup), drop spider on thread, surface eel (water/lava), area stalker
  that follows between rooms, chasm sniper. Existing enemies may become faster/more aggressive with fair
  telegraphs.
- **D21 — Living environment.** Ambush doors (seal until the wave is beaten), timed doors (switch + race),
  collapsing floors, falling stalactites, crushing ceilings with safe rhythm, push currents (water/wind),
  rising lava/water chase shafts. No dark zones in this iteration.

## Accepted ambush arena amendment

Accepted by the user on 2026-09-23, who authorized amending the contracts for it. Ambush arenas are a
reusable world system for action peaks: a room section seals when the player commits, runs waves of
existing catalog enemies, and reopens on clear. It implements the D21 ambush doors. Full design, rules and verification plan:
[features/ambush-arenas.md](features/ambush-arenas.md).

- The one ambush system is `scripts/world/dynamic/ambush_arena.gd` (D21, generated from campaign
  layouts by `tools/campaign_worldfx.py`). A parallel implementation under `scripts/world/ambush_*.gd`
  was retired when the branches met; its rules (multiple telegraphed waves, per-spawn kill filter,
  authored-point spawns, stall/leave release, clear reward) are built into the D21 arena, with the
  pure rules in `scripts/world/dynamic/ambush_rules.gd`.
- No weapon, HP, damage-matrix or save-schema change. Clears persist as world flags
  `<room_id>.ambush.<local_id>` in the existing schema.
- One enemy behavior fix: the Armored Guard patrol now also reverses at its arena leash edge
  (`EnemyAi.armored_guard` calls `at_leash_edge` in `scripts/enemies/effects/enemy_placement.gd`). Arena clamping stopped the body before
  any wall, so a guard in any arena narrower than its room walked to the edge and stayed there.
  Cinder Warden already reversed at its bounds; no other patrol relied on walls alone.
- Softlock rules are binding for every placement: only spawns the current kit can defeat are created,
  an encounter with none never seals, and death or leaving the arena aborts and re-arms it.
