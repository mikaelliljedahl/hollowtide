# Phase 1 — dev track as playable partial delivery

Status: Phase 1 integration is implemented in the working build. F1 remains open: playtesting and
integration work continue. Packages P0–P7 are defined in the [production plan](production-plan.md).
Phase 2 has not started.

This is a delivery status, not F1 approval. Claims about finished movement, combat, graphics, sound,
HUD, rooms, map, and saving still require verification in a real playthrough wherever the checklist
requires it. P8–P11 are blocked until the user has played and accepted the dev track.

## Purpose

The player should be able to try **every** weapon, upgrade, regular enemy, and boss without playing
the campaign. The dev track extends `scenes/levels/level_01.tscn`; it is not a standalone technology
demo. The original route—start to the right, orb to the left, ball passage, and first encounter—remains
a regression test.

## Start, isolation, and recovery

Current boot interface:
```sh
make run   # normal start menu
make dev   # normal start menu with the dev flag
```

`make dev` is the default route for dev testing. The normal start menu opens the dev route with an
explicit dev flag; the dev profile is isolated from the campaign profile.

- Normal start goes to the campaign start menu when Phase 2 exists. During Phase 1 it may still use
  the prototype route, but the dev panel requires explicit activation.
- Dev-mode data is stored separately from campaign save files and is never imported into the campaign.
  Release exports must not expose an enabled dev panel, even if the argument is passed.
- The panel pauses simulation while configuration changes. Presets apply atomically, followed by safe
  respawn; `GameState` is never half-updated during a physics tick.
- Deactivating Slipstream inside a tunnel first moves the player to a safe spawn. Removing High Jump,
  protection, or another ability must not leave the test mode locked.
- **Restore Station** resets local objects, blocks/doors, timers, and sandbox flags to the station
  baseline. **Reset All** also resets dev-session pickups and profile. Neither reset writes to the save
  file automatically. Domains and exact reset scope follow the [save section of the decision list](implementation-decisions.md).
- Death waits 0.45 seconds, restores full health at the last checkpoint, and keeps current progress in
  memory. Death does not load the disk save; this replaces the previous plan to save on death.
- Enemy spawning is limited to marked arenas. Reset releases the previous instance. There is no
  infinite spawn loop or hidden residual hit surface.

## Panel and presets

Text labels may appear in the dev panel, but not as tutorials in the game world.

| Control | Behavior and test |
|---|---|
| Start mode | No pickups; base health and zero missiles. The original route is playable. |
| All Abilities | All unlocked; full tanks; active beam selected separately. |
| One at a time | Select an exact ability and its explicit dependencies; panel shows what was added. |
| Campaign Stage | Regenerates state before and after each mandatory ability port in Phase 2. |
| Capacity/resource | Separate controls for Energy/Missile/Flux Tanks and current health/ammo/Flux. |
| Enemy/Boss | Choose catalog ID, reset arena, start the correct instance, and optionally select a boss phase. |
| Immortality/Infinite Ammo | Off by default; clearly indicated. Must not be active in acceptance tests. |
| Station/respawn | Move to safe ground with temporary permits cleared. |
| Test Overlay | Active abilities, spin/attack status, collision surfaces, damage, and spawn ID. Can be hidden. |

For example, one-at-a-time mode gives Slipstream as a dependency for bombs; Slipstream is not hidden
inside the bomb. Invalid state combinations must also be rejected.

## Stations on the same track

The core route is retained. Expansions are accessed through a test hub with a return path that does
not require the ability being tested. Boss arenas may be connected rooms; the dev hub should reach them all.

| Station | Contents | Mandatory evidence |
|---|---|---|
| S0 Original Cave | Spawn, orb, 64 px passage, weapon, and crawler | Basic movement and first ability port work without dev help. |
| S1 Movement | Normal jump, wall jump, low tunnel, isolated height target | High Jump on/off; spin in both directions; no accidental base-jump change. |
| S2 Shooting range | Near/Far Targets, Solid Wall, Missile Door, Targets in line of sight | Short/Long Beam, Ice/Wave, missiles, empty ammo, and blocked muzzle. |
| S3 Ball/bomb | Bomb Block, Tunnel, Protected Drop Surface, Bomb Lift Ledge | Base grounded/coyote Ball jump retains form/collider; no Ball High Jump/wall jump/spin/double jump; bomb lift remains separate; reset restores blocks. |
| S4 Energy/Protection | Contact damage, projectile, environmental hazard, tanks, and refill | Capacity separate from current resource; protection exemptions; death/respawn. |
| S5 Freezing / Stone Guardian | Freezable moving enemies, platform jumps, checkpoint/refill, and natural Stone Guardian arena | Enemy becomes a stable platform and thaws safely; boss defeat/reset/save remains deterministic. |
| S6 Undertow / Lava | Regular enemies, grounded lava basins, jumpable basalt steps, Lava Monster, and protected targets | Spin without upgrade does no damage; visible fluid matches hazard geometry; active attack hits only valid targets. |
| S7 Bestiary / Cinder Warden | Readable catalog cell with all thirteen panel-selectable IDs plus a natural Cinder Warden arena | Full reaction matrix, AI, contact, drops, cleanup, safe boss approach, and deterministic reset. |
| S8 Tidal / Boss Debug | Natural Tidal Heart arena and isolated three-boss phase selection | Full battle from start to death without cheats; phase selection does not replace full testing. |
| S9 World Test / Flux | Connected rooms, map, save point, Shield/Burst, Flux Tanks, shrine, and shortcut | Flux selection/toggle, drain, schema-v2 round trip, death, reload, and dev/campaign isolation. |
| S10 Graphics / Echo | Five-area presentation endpoint, Echo Scan, Flux Tanks, landmarks, passages, and fixtures | Echo pulse/reveal plus normal-camera seams, scale, silhouette, transitions, and detail. |

## Delivery order within the phase

1. P0: run and document the baseline; approve new contracts and ownership.
2. P1–P3: build the permit foundation, graphics sample, and test hub; deliver the first testable dev build.
3. P4: add the arsenal and capabilities, one catalog entry at a time, with dedicated tests.
4. P5: add movement extensions and animations; keep the player file with one owner.
5. P6: build enemies and bosses in waves; start with a beam-sensitive enemy as a positive counter-test
   to the crawler's immunity. Complete boss logic, not only visual placeholders.
6. P7: test the whole combination, sound, HUD, rooms, and saving. Only then begin Phase 2.

## Fixed user decisions for this delivery

- Runtime UI and documentation are English. Start-menu and pause help are approved outside world;
  no tutorial text is added to world.
- Runtime controls: arrows move/aim; Down crouch; Z Slipstream; Left Shift run; A jump (Space alternate);
  X beam/bomb/low crouched shot; C missile; V cycle beam; Q select owned Flux module; F activate/toggle
  Flux; Esc pause/help; F1 dev panel. J/K remain alternate beam/missile bindings.
- Slipstream has accepted regular grounded/coyote base jump while retaining form/collider. No Ball
  High Jump multiplier, wall jump, spin/Undertow, or double jump. Bomb lift is separate and unchanged.
- Normal spin is user-approved. No other human visual/audio approval is claimed.
- Five original 48-second area melodies and all current presentation/audio systems await human review.

## Phase gate F1

- [ ] All abilities, weapons, and containers in the catalog have pickup/unlock, feature, icon/animation,
  sound, dev selection, reset, and positive/negative tests. Refills have equivalent resource samples;
  enemies and bosses are tested through spawning and the reaction matrix, not pickups.
- [ ] All thirteen enemies and three bosses are in the dev track and use the shared factory/scenes.
- [ ] Weapon/Flux changes, death, room changes, freezing, and reset leave no active ghost items.
- [ ] Repeat pickups do not double capacity; missiles cannot go below zero or above maximum.
- [ ] Basic movement is compared before and after; standing/wall/Ball jump rules and Slipstream passage are tested in real TileMap.
- [ ] The Undertow Jump silhouette rotates around the body, rather than being an upright sprite or ball image.
- [ ] Undertow Dash follows the actual attack window, not only the visible effect.
- [ ] Cave graphics are approved at 1920×1080 in-game, not only as an atlas image.
- [ ] Ten complete station trips leave no enemies, drops, or projectiles behind.
- [ ] Save/load and process restart correctly render unique pickups and resources.
- [ ] Boss progression is tried in S8/S9: one regional boss flag does not open the end gate; both flags
  do. Run both schemes from clean state. Boss victory autosaves the flag, updated arena, and safe return
  point; death and process restart/load preserve them. A defeated boss does not respawn without explicit
  dev reset. The final boss's final flag is also tested.
- [ ] Campaign save-file content is unchanged after a dev session. Corrupt saves, backups, unknown versions,
  and wrong domains produce safe outcomes according to the decision list.
- [ ] A full trial round without immortality or infinite ammo is completed.
- [ ] Run log, image/video for each visual test, and the catalog test matrix are included in the report.

## Implementation results and deviations

The following are delivered in the working build after P1–P7, but do not constitute automatic F1 acceptance:

- The original eight-enemy roster is expanded additively with `shard_turret`, `burrower`,
  `grasshopper`, `shooting_gargoyle`, and `lava_monster`. Catalog, factory, selector, natural
  placements, and battle logic use thirteen stable IDs.
- Physical pickups include complete arsenal, six Heart Pearls, twelve Bolt Quivers, Flux Shield,
  Burst Beam, Echo Scan, and four Flux Tanks across S1–S10. All twelve dev-track Bolt Quivers retain
  stable IDs/count and have audited standing-safe collection and retreat. Main floor remains safe;
  authored ability/beam gates and Wave Grate occupy bounded test pockets.
- Death/respawn uses the session checkpoint and restores full health after 0.45 seconds; the disk save is
  not loaded on death. Boss and transient cleanup are available in the implementation.
- Temporary enemy drops include energy +25, missile +2, and owned-system Flux +10, clamped with no
  persistent pickup IDs. Weighting and drop chance still require playtesting.
- English start/splash/pause/help/HUD/dev panel, mapped pickup icons, thirteen-enemy selector, authored
  muzzle/beam families, sprint/wall poses, gates, Wave Grate, shrines, and passage arches are integrated.
- Flux Shield/Burst/Echo, four Flux Tanks, schema v2 persistence, and Q/F controls are integrated.
- Area routing/presentation: fringe S0–S1, nexus S2–S3, vaults S4–S5, kiln S6–S7, depths S8–S10.
  Five environment kits, transitions, landmarks, ambience, and five area melodies render; Kiln uses
  visible basalt/lava/fire/steam. This is Phase 1 presentation, not campaign P9.
- High-resolution terrain, figure, arsenal, enemy/boss/pickup, and fixture assets render. Physics grid,
  standing jump, wall jump, damage constants, and Ball collider are unchanged.
- Latest integration gate before this documentation refresh passed `make f1-check` 37/37 suites.
  The runner now fails on ObjectDB/resource teardown diagnostics; the current gate reports zero.

## Open F1 gate inventory

- [ ] Manual normal/dev playthrough S0→S10 without cheats: safe route, ordered capabilities,
  standing-safe Bolt Quiver collection/retreat, Flux modules, and boss approach without instant death.
- [ ] Death, paused death, session checkpoint, full health, progress retention, and input after respawn.
- [ ] Visual sample at 1920×1080: five environments/transitions, Kiln hazards, passages/gates/shrines,
  terrain/collision, spin/Undertow, sprint/wall poses, beam families, pickups, all enemies/bosses, and splash.
- [ ] All physical pickups and drops are visible, correctly mapped, and collectable exactly once; ammo
  never exceeds capacity; new enemy IDs load their images.
- [ ] Human audio review of all five 48-second area melodies, ambience, Flux cues, and movement/combat
  mix. Nexus and Vaults were rewritten after hands-on feedback and still need user listening approval.
- [x] Current automated integration gate passes 37/37 suites with zero teardown diagnostics.
  Headless/native technical PASS does not
  replace manual gameplay, visual, or audio approval.

F1 must not be approved if the panel alone provides a capability while its real pickup or interaction is
missing. Phase 2 should deploy completed systems, not finish half an arsenal.

## Implemented controls and systems awaiting F1 approval

Down crouch, Z Slipstream, A jump (Space alternate), Left Shift run, crouched X low shot, Q Flux selection, and F Flux activation
are live. Manual acceptance still covers crouch clearance, visible muzzle origin, both firing directions,
aim/fire/hurt/death transitions, sprint/wall poses, and regression of tuned standing/wall movement.

Flux Shield, Burst Beam, Echo Scan, four Flux Tanks, shared meter, HUD/dev controls, VFX/audio, and
schema-v2 persistence are live. Phase 2 remains blocked because implementation is not user acceptance.

All music is original. Existing music must never be copied, imported, shipped, sampled, remixed, or
transcribed. Runtime contains five original 48-second area
melodies; human listening approval remains pending.
