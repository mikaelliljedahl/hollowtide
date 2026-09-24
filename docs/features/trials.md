# Feature design: Trials

Status: implemented on 2026-09-24 as an optional post-ending extra. Two modes, the Gauntlet and the
Boss Rush, reuse the D21 ambush arena and the three campaign bosses. Entry is a start-menu item that
appears only for a finished campaign save. Design accepted by the user on 2026-09-24; see
[Accepted Trials amendment](../implementation-decisions.md#accepted-trials-amendment).

## 1. Goal

The user wants more action after the campaign. The Trials give a finished save two replayable combat
runs with a clear time and a hit count, without adding content types, text in the game world, or a
second progression track.

Out of scope: new enemies or bosses, leaderboards, per-wave splits, and any change to how the
campaign itself plays or saves.

## 2. Vision fit

[vision.md](../vision.md) rules out "score screens that replace a world". The Trials never replace
the world: the campaign stays the game, the Trials are reached only from the title after the ending,
and the results are a menu screen outside the game world (like pause and settings). The world itself
carries no text: the arena seals, telegraphs and boss fights teach as in the campaign.

## 3. Rules

- **T1 Unlock.** The start menu shows `Trials` only when the campaign save loads and holds the
  `boss:tidal_heart` world flag (`TrialCatalog.UNLOCK_FLAG`, `scripts/trials/trial_catalog.gd:12`).
  The ending and credits set no flag of their own (`scripts/campaign/ending_trigger.gd:24`,
  `scripts/campaign/credits.gd:124`); the Tidal Heart victory writes an atomic autosave before the
  ending can be walked into, so that flag on disk is what "finished" means.
- **T2 Fixed kit.** Every trial starts from `TrialsEntry.apply_kit` (`scripts/trials/trials_entry.gd:64`):
  the ten campaign abilities (`TrialCatalog.KIT_ABILITIES`), six Heart Pearls (700 health) and twelve
  Bolt Quivers (60 bolts) at the catalog maxima, no Flux. A fixed kit keeps best times comparable
  between saves and needs no read of the save's own inventory. The kit carries no Tide Glyphs:
  `reset_progress` clears the Tide state, so the save's socketed loadout never reaches a trial and
  the Tide Sockets cannot be reached inside one (there is no save shrine). Decided here; see
  section 8.
- **T2a Assist.** The assist options (game speed, damage taken) apply in the Trials as everywhere
  else; they are settings, not save state. The clock runs on physics time, which the game-speed
  assist scales with the rest of the game, so a slower game does not shorten a clear time. The
  skip-ambushes assist does not apply: the gauntlet arena sets `assist_skippable = false`
  (`scripts/world/dynamic/ambush_arena.gd:52`), because the arena is the whole trial.
- **T3 Campaign untouched.** Entry loads the save and keeps its snapshot in
  `TrialsEntry.campaign_snapshot`. The kit lives only in memory. Before anything is written the
  snapshot is restored (`scripts/trials/trials_entry.gd:79`), so the only possible change to the save
  is a better `trial_bests` entry. Quitting from pause or the results panel saves nothing.
- **T4 Gauntlet.** One sealed arena, six escalating waves (triangle with a diamond finale, the ambush
  R1/R2 rules) that together use all twelve common enemies an ambush may spawn; the Lava Monster needs
  a lava basin and is left out (`TrialCatalog.WAVES`, `scripts/trials/trial_catalog.gd:17`). The
  last two waves spawn as elites (`TrialCatalog.ELITE_WAVES`; `EnemyElite.apply` on the arena's
  `spawned` signal, `scripts/trials/trials_root.gd:122`), with the elite health, pace, look and
  defeat refills of the revisit remix.
- **T5 Boss Rush.** Stone Guardian, Cinder Warden and Tidal Heart in that order, each in a closed
  room with its area's art (vaults, kiln, depths). After each of the first two a 4 s breather
  (`TrialCatalog.BREATHER_SECONDS`) with one full refill of health and bolts, then a fade to the next
  room. Each boss appears 1 s after its room fades in.
- **T6 Clock.** Physics time, so pausing stops it. The Gauntlet clock starts when the arena seals,
  the Boss Rush clock when the first boss appears; breathers count. It stops on the last clear.
- **T7 Hits.** Every drop in health while the clock runs is one hit (`TrialsRoot._on_health_changed`,
  `scripts/trials/trials_root.gd:228`).
- **T8 Failure.** Death, or a Gauntlet abort (the ambush stall backstop), ends the run as failed. A
  failed run records nothing.
- **T9 Best time.** A clear replaces the stored best only with a strictly shorter time; its hit count
  is stored with it. The save is written only when the best changes.

## 4. Flow

| Step | Where | What happens |
|---|---|---|
| Title | `scripts/ui/start_menu.gd:159` | `TrialsEntry.peek` reads the save and restores GameState afterwards; a finished save adds the `Trials` button. |
| Trials menu | `scripts/trials/trials_menu.gd` | Lists Gauntlet and Boss Rush with their best times; Back returns to the title column. |
| Start | `scripts/trials/trials_entry.gd:38` | Loads the save, keeps its snapshot, applies the kit, changes to `scenes/trials/trials.tscn`. |
| Run | `scripts/trials/trials_root.gd` | Builds the room(s), player, HUD and pause menu; runs the mode. |
| Results | `scripts/trials/trial_results_panel.gd` | After 1.2 s the game pauses, the HUD hides and the panel shows the title, clear time, hits and best time; Retry reapplies the kit and reloads the scene, Title restores the campaign snapshot and returns to the title. |

## 5. Rooms and arena

Rooms are ASCII grids in `TrialCatalog` built by `TrialRoomBuilder.build`
(`scripts/trials/trial_room_builder.gd:10`) with the campaign tile set and the area terrain kit, the
same way the campaign and the world-FX testbed render rooms. They are closed on all sides, so there is
no exit and no world transition.

- Gauntlet: 40 x 17 tiles in the nexus kit with three ledges. The `AmbushArena` covers the whole
  interior; its trigger is the middle third (`TrialCatalog.GAUNTLET_TRIGGER`), so the player commits
  by walking in from the start. Spawn point i belongs to spawn i: flyers take the air points, all others
  the floor points (`TrialsRoot.gauntlet_spawn_offsets`, `scripts/trials/trials_root.gd:104`), which
  is what the class-aware relocation in `AmbushRules.resolve_spawn` expects. `max_seconds` is raised to
  one hour so the arena never clears itself; the 40 s stall abort stays.
- Boss rooms: 34 x 17 tiles with a flat floor. The boss arena rectangle ends 16 px below the floor line
  because `Rect2.has_point` excludes the bottom edge where the player's feet stand (the same fix as the
  ambush leash). Bosses spawn through `scripts/trials/trial_boss_spawn.gd`, a subclass of the campaign
  `boss_spawn.gd` that always spawns (a finished save has every boss flag) and reports the victory
  without setting flags, moving the checkpoint or saving. The Tidal Heart keeps its campaign wave grate.

## 6. Save format

Optional snapshot key `trial_bests`, schema version unchanged (2):
`{"gauntlet": {"time_ms": int, "hits": int}, "boss_rush": {...}}`. Rules in `TrialRecords`
(`scripts/trials/trial_records.gd`): only known modes, `time_ms` 1 to 86 400 000, `hits` 0 to 100 000;
anything else makes the snapshot invalid, like any other bad field.

`GameState` changes are limited to the key: the variable (`scripts/autoload/game_state.gd:40`),
clearing it on `reset_progress` (line 307), writing it only when non-empty (line 347), restoring it
(line 391), and accepting it as one more optional v2 key next to `map_pins`, `activated_stations`
and `tide_modules` (line 638), validated with the other fields (line 697). Saves without the key, v2
or v1, load as before with no bests. Every other unknown key is still rejected.

## 7. Implementation

- `scripts/trials/trial_catalog.gd`: modes, waves, boss order and areas, kit, grids, arena geometry.
- `scripts/trials/trial_records.gd`: record validation, better-than rule, time formatting.
- `scripts/trials/trials_entry.gd`: unlock check, start, kit, record-and-save, leave.
- `scripts/trials/trials_root.gd` with `scenes/trials/trials.tscn`: the run; debug launch with the
  user argument `--trial=boss_rush` or `--trial=gauntlet`.
- `scripts/trials/trial_room_builder.gd`, `trial_boss_spawn.gd`, `trial_results_panel.gd`,
  `trials_menu.gd`: rooms, bosses, results screen, start-menu overlay.
- `scripts/ui/start_menu.gd`: the `Trials` item and its overlay.
- `scripts/world/dynamic/ambush_arena.gd`: the `spawned` signal (elite waves) and the
  `assist_skippable` export (gauntlet ignores the skip-ambushes assist).

## 8. Decisions

| Question | Decision | Reason |
|---|---|---|
| Kit | Fixed full kit (T2) | Comparable times; a save that skipped optional upgrades is not punished; no read of inventory. |
| Tide Glyphs | None (T2) | Follows from the fixed kit: a glyph loadout would make times depend on the save again. |
| Assist | Game speed and damage taken apply; skip ambushes does not (T2a) | Assist is accessibility, not progress; skipping the gauntlet's only arena would leave nothing to run. |
| Elites | Waves 5 and 6 | The finale escalates with the existing elite variant instead of new enemy types. |
| Unlock signal | Saved `boss:tidal_heart` flag | The ending sets no flag; the boss autosave is the persistent, atomic proof. |
| Where results live | Campaign save, optional key | As requested; one slot, no second file to keep in sync. New Game clears the bests with the rest of the save. |
| Tie | Keeps the stored best | "Best time kept only when better". |
| Breathers in the clock | Counted | Fixed length, same for every run; simpler to explain than a paused clock. |

## 9. Verification

Suite `tools/check_trials.tscn` (registered as `trials` in `tools/run_godot_check.py`):

| Case | Expectation |
|---|---|
| Record rules | m:ss.cc formatting; first clear becomes best; slower and equal times keep it; faster replaces it with its hits; invalid records rejected; the waves use the twelve spawnable common enemies with one authored point per spawn. |
| Hidden before the ending | No save and an unfinished save: locked, no start-menu item, a trial cannot start. Finished save: unlocked without changing GameState, the item opens the Trials menu with both modes. |
| Gauntlet | Fixed kit equipped; the arena waits until the player walks in; the seal starts the clock; a hit is counted; all six waves run in order and each spawns exactly its catalog enemies, elites in the last two waves only; the clear records a new best in the save, nothing else in the save changes, the campaign state is restored, and the results panel shows time and hits over a paused game. |
| Gauntlet death | With the skip-ambushes assist forced on the gauntlet still seals; death ends the run as failed and saves nothing. |
| Boss Rush | The three bosses appear in order in their own area art, each of the first two followed by a breather with a full refill; hits are counted across the rush; the clear stores its best next to the Gauntlet's; boss flags and checkpoint in the save are unchanged. |
| Best kept only when better | A slower clear is reported with the previous best and not saved; a faster one replaces time and hits on disk. |
| Save round trip and old saves | Bests survive save/load; a v2 save without the key and a v1 save load; empty bests are not written; invalid bests and other unknown keys are rejected. |

The suite kills enemies and bosses directly (boss `_die`), so it proves the flow, not the fights.
Not verified: a real-input playthrough of either mode, their difficulty and length, and the Retry and
Title buttons (they change scene, which ends a test run).

## 10. Follow-ups

- A real-input playthrough to tune wave counts, spawn points and the breather.
