# Feature design: assist options

Status: implemented on 2026-09-24 as decision D22 and accepted by the user on 2026-09-24 (see
[implementation-decisions.md](../implementation-decisions.md), "Accepted assist options amendment").
Gameplay reads the options only through `scripts/progression/assist.gd`; the settings menu writes
them through `scripts/ui/game_settings.gd`.

## 1. Goal

The action round (bosses with four stages, elites on revisits, ambush arenas) makes Hollowtide harder
on purpose. Assist options let a player who finds the action too hard still finish the game, and let
playtests reach late rooms quickly. They are plain settings in a menu, outside the game world, so
they add no text, no pop-up and no judgement to the world itself.

Out of scope: a difficulty preset, assist-only content, invulnerability, infinite ammo, skipping
bosses, and any mark on saves or Trials results that assists were used (section 7).

## 2. Rules

- **A1 Menu only.** The options live in the Settings screen, section "Assist", which the start menu
  and the pause menu both open (`scripts/ui/settings_menu.gd:123`). Nothing in the game world
  mentions them.
- **A2 Tested steps.** Each numeric option is a button that cycles through fixed values, so a player
  can only pick a step the checks cover (`_step_row`, `scripts/ui/settings_menu.gd:228`).
- **A3 Defaults are the designed game.** Game speed 100 %, damage taken 100 %, skip ambushes off
  (`DEFAULTS`, `scripts/progression/assist.gd:15`).
- **A4 Settings, not progress.** The options are stored with the other player settings, never in a
  save slot, so they apply to every slot and never change the save format.
- **A5 Deterministic checks.** Test runs (`--test-mode` or `--benchmark-cave`) always read the
  defaults (`is_test_run`, `scripts/progression/assist.gd:47`); a check sets values explicitly
  through `Assist.forced`.
- **A6 Never below the floor.** Game speed is clamped to 0.5 to 1.0 and damage taken to 0 to 1 when
  read (`scripts/progression/assist.gd:22`, `:26`), so a hand-edited settings file cannot speed the
  game up or heal the player through damage.

## 3. Options

| Row | Steps | Effect | Read at |
|---|---|---|---|
| Game speed | 100, 90, 80, 70, 60, 50 % | Sets the engine base speed (`Engine.time_scale`), so movement, enemies, timers and physics all slow together | `apply_game_speed`, `scripts/progression/assist.gd:43` |
| Damage taken | 100, 50, 25, 0 % | Multiplies every hit and heat tick the player takes (section 4) | `scale_damage`, `scripts/progression/assist.gd:35` |
| Skip ambushes | Off, On | Ambush arenas never seal, except an arena that opts out (section 6) | `_skipped_by_assist`, `scripts/world/dynamic/ambush_arena.gd:331` |

The rows are built at `scripts/ui/settings_menu.gd:124` to `:139`.

## 4. Damage order

A hit reaches the player through `Player.take_damage` (`scripts/player/player.gd:171`). Every enemy
contact, enemy and boss shot, crusher, stalactite and rising shaft uses it. The order is:

1. No damage at all while invulnerable, dead, under the dev cheat, or while the Undertow Dash
   protects (`scripts/player/player.gd:176`).
2. Pressure Seal divides the hit, rounded up.
3. The assist multiplier, rounded up, so any setting above 0 still hurts at least 1; 0 blocks the
   hit (`scripts/player/player.gd:182`).
4. The Tide Glyph `damage_taken` multiplier, rounded to nearest without dropping a positive hit to
   zero (`PlayerFluxRuntime.absorb_damage`, `scripts/player/player_flux_runtime.gd:72`, using
   `TideModules.scale_int`, `scripts/progression/tide_modules.gd:131`).
5. The Flux Shield absorbs what is left, one Flux per point.

A hit that ends at 0 returns before knockback, input lock and invulnerability, so at 0 % damage taken
the player is also never knocked back. This order matches [tide-modules.md](tide-modules.md),
section 3.

Heat exposure is ambient and bypasses `take_damage`: `HeatZone` drains health directly each tick,
scaled only by the assist multiplier (`scripts/campaign/heat_zone.gd:68`). Glyphs and the Flux Shield
do not touch it, and the Pressure Seal still switches it off entirely, so the kiln gate is unchanged.
The only other direct health change is the developer panel's health setter.

## 5. Game speed and hit-stop

Hit-stop (`GameJuice.hit_stop`, `scripts/effects/game_juice.gd:78`) slows time to 0.25 of the base
speed, not of full speed (`scripts/effects/game_juice.gd:95`). Releasing it, and the safety net that
restores time after a scene change, both return to the assist speed
(`scripts/effects/game_juice.gd:110`, `:117`). Before this change a hit-stop reset the game to full
speed.

Storage: the options are the `[assist]` section of `user://settings.cfg`
(`scripts/ui/game_settings.gd:8`). Changing a row saves the file and mirrors all three values to the
ProjectSettings keys `assist/game_speed`, `assist/damage_taken` and `assist/skip_ambushes`, then
applies the game speed (`apply_assist`, `scripts/ui/game_settings.gd:159`). The start and pause menus
apply all settings once per process when they open. `Assist` reads ProjectSettings first and falls
back to the settings file once when nothing has been mirrored yet (`_value`,
`scripts/progression/assist.gd:52`).

## 6. Skip ambushes

While the option is on, an armed ambush arena ignores the player (`scripts/world/dynamic/ambush_arena.gd:159`):
it never seals, spawns nothing, sets no clear flag and drops no clear refill, so the Ebb Mend glyph
heals nothing there either. The check runs only in the armed state, so turning the option on during a
fight does not end that fight; the next death or leave abort re-arms the arena and it then stays open.
Turning the option off lets every uncleared arena seal again on the next commit.

No progression depends on an ambush clear flag (the only flag gates are boss and regional flags), and
the graph solver already treats arenas as never blocking movement, so skipping is always safe for
the campaign. Fast travel refuses trips only while an arena is sealing or fighting, so skipped arenas
never block it.

An arena that is the whole point of its room sets `assist_skippable` to false
(`scripts/world/dynamic/ambush_arena.gd:50`) and ignores the option. The Trials Gauntlet is that
case: skipping it would leave a run that never starts.

## 7. Known interactions

- **Trials.** The Gauntlet arena opts out of Skip ambushes (section 6); suite `trials` checks that
  the option does not skip it. Game speed does not change Trials times, because the clock counts
  physics time. A damage setting below 100 % lowers hits and makes runs easier, and Trials results
  do not record assist use. The last two points are read from the code, not checked.
- **Elites and bosses.** Assists change nothing about enemies: elite health, boss stages and
  telegraph lengths are the same; only the player's side is helped (and game speed slows everyone).

## 8. Verification

Suite `tools/check_assist.tscn` (registered as `assist` in `tools/run_godot_check.py:97`):

| Case | Expectation |
|---|---|
| Defaults | A test run reads full speed, full damage and ambushes on (`tools/check_assist.gd:42`). |
| Damage scaling | 50 % halves a hit, a 1-point hit stays 1, 0 % blocks a 40-point hit, a value above 1 is capped at full damage (`tools/check_assist.gd:49`). |
| Game speed | A value of 0.1 reads as the 0.5 floor; 0.7 sets the engine speed; releasing a hit-stop returns to 0.7, not 1.0 (`tools/check_assist.gd:59`). |
| Player damage | A real `take_damage(20)` costs 10 health at 50 % and nothing at 0 % (`tools/check_assist.gd:92`). |
| Skip ambushes | With the option on, a one-Hopper arena stays armed and spawns nothing while the player stands in it; with the option off the same arena seals (`tools/check_assist.gd:121`). |

Not verified: the heat-zone scaling and the stacking with Pressure Seal and glyphs are read from the
code, not checked by this suite (the glyph order is covered in suite `tide modules`); the settings
rows were not driven with real input; hands-on feel of 50 % game speed with audio.

## 9. Follow-ups

- If Trials results should stay comparable, record whether an assist below the default was active
  during a run.
