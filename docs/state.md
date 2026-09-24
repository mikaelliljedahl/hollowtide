# Hollowtide — current status

## Aggregate status

**Phase 1 (dev track S0–S10) is done. Phase 2's compact mini-campaign is playable and the user has
beaten it.** The campaign has 16 connected rooms across five areas (fringe 5, nexus 2, vaults 3,
kiln 3, depths 3) with save/continue, a full map with unexplored-exit markers, a minimap, per-area art
and music, three bosses and an ending with credits. `make check` passes.

Round 2 (D19–D21) replaced the genre-default arsenal with an original one, added surprise enemies
and a living environment. Most internal IDs are unchanged, but four that echoed older genre names were
renamed afterwards: `morph_ball` became `slipstream`, `screw_attack` became `undertow_dash`, `varia`
became `pressure_seal`, and the `screw` gate kind became `undertow` (with its flags and the
`depths_01.undertow_hall` arena). Old saves that store a previous ability id are not migrated: the
ability check at `scripts/autoload/game_state.gd:731` rejects the snapshot, so Continue fails
(`scripts/campaign/campaign_entry.gd:43`). `furnace_mother`, `energy_parasite`, `energy_tank` and
`missile_tank` keep their ids. See the name table in
[content-catalog.md](content-catalog.md#names-and-internal-ids-d19).

The action round (goal set 2026-09-24, branch `feature/action-round`) added nine features, each
accepted as a contract amendment in [implementation-decisions.md](implementation-decisions.md) with a
design in `docs/features/`: assist options, map pins, revisit elites, four-stage bosses, dash
deflect, fast travel with boss shortcuts, three intended sequence breaks, Tide Sockets and Trials.
Save schema stays 2. Every feature is logic-tested by its own suite; none is balance-tested by hand.

## Start and controls

```sh
make run    # normal start menu (campaign)
make dev    # boot with --dev-mode; Start Dev Track
make check  # import, docs, lint, and all headless suites
```

Default controls (rebindable in settings; the pause/start-menu help shows the live bindings):

- arrows: move and aim; Down crouches; Left Shift: hold to run
- A: jump (Space alternate); Z: Slipstream form
- X: Seed Crossbow / Resonance Pulse / low shot; C: Harpoon; V: cycle bolt; B: Undertow Dash
- Q: cycle Flux module; F: activate/toggle Flux
- Esc: pause; F1: developer panel (dev mode only)
- Up on a save shrine: shrine menu (Travel, Tide Sockets); on the map, X places or cycles a pin and
  C removes it

Visible runtime text and documentation are English. No tutorial text in the game world.

## What is in the game

- **World:** 16-room campaign (`scenes/campaign/layouts/*.txt`, built by
  `tools/build_campaign_rooms.py`) plus the S0–S10 dev track. Both branch orders (vaults/kiln) work;
  a graph solver check validates reachability.
- **Arsenal (D19):** Seed Crossbow base weapon, Harpoon with Bolt Quivers (rock pegs, Harpoon
  Sockets), Bubble Snare (standable bubbles), Echo Shot (ricochet, resonant membranes), Resonance
  Pulse (cracks crystal), Focus Lens, Undertow Dash (replaces the old spin attack), Heart Pearls, Slipstream
  water form, Updraft Cloak (higher jump + glide), Pressure Seal (damage halving). Flux Shield/Burst
  Beam/Echo Scan remain.
- **Enemies:** thirteen common types (sped up, with telegraphed charges), six surprise enemies (D20):
  bat swarm, mimic, drop spider, surface eel, area stalker that follows between rooms, chasm sniper;
  three bosses: Stone Guardian, Cinder Warden, Tidal Heart.
- **Living environment (D21):** ambush doors, timed doors, crumbling floors, falling stalactites,
  crushers, push currents, rising lava/water shaft. No dark zones. The tide mechanic is postponed.
- **Ambush arenas:** one D21 system with telegraphed waves, a kill filter so an arena never seals
  unwinnable, abort on death or leaving, and a refill on clear; five campaign arenas and one in dev
  station S3 ([features/ambush-arenas.md](features/ambush-arenas.md)).
- **Action round (2026-09-24):**
  - Assist options: game speed, damage taken, skip ambushes, in Settings only
    ([features/assist-options.md](features/assist-options.md)).
  - Map pins: up to 12 player pins of three kinds on the map and minimap
    ([features/map-pins.md](features/map-pins.md)).
  - Revisit elites: after each boss, some common enemies in revisited rooms return tougher with a
    rose tint and magenta rim ([features/revisit-remix.md](features/revisit-remix.md)).
  - Bosses: four stages each, telegraphed attack chains, punish windows and a desperation stage
    ([features/boss-rework.md](features/boss-rework.md)).
  - Dash deflect: an enemy shot touched in the first 0.10 s of a dash turns back as a player shot
    ([features/dash-deflect.md](features/dash-deflect.md)).
  - Fast travel between activated save shrines; both branch bosses open a shortcut to the hub
    ([features/fast-travel.md](features/fast-travel.md)).
  - Three intended sequence breaks with exclusive rewards in `fringe_01`, `vaults_02`, `depths_01`
    ([features/sequence-breaks.md](features/sequence-breaks.md)).
  - Tide Sockets: seven trade-off glyphs socketed at save shrines, capacity 2 to 5
    ([features/tide-modules.md](features/tide-modules.md)).
  - Trials: Gauntlet and Boss Rush with best times, unlocked by a finished save
    ([features/trials.md](features/trials.md)).
- **Presentation:** per-area painted art (`assets/environment/areas/<area>/`), background coverage,
  lava basins, light shafts, decor; round-2 art from Codex GPT-image (`assets/sprites/arsenal/`,
  `assets/sprites/enemies_new/`, `assets/worldfx/`).
- **Audio:** five area themes, ambience, procedural SFX for arsenal, surprise enemies and worldfx.
- **Saving:** dev/campaign domains, schema v2 with optional keys `map_pins`, `activated_stations`,
  `tide_modules` and `trial_bests`; death restores at the checkpoint without loading disk.

## Known gaps

- Balance is untested by hand for the whole action round: boss stages, telegraph and punish timing;
  elite chances and multipliers; the 0.10 s deflect window and its 30 damage; the Tide Glyph numbers;
  the Trials wave counts, breather and run length. None has had a real-input playthrough.
- Trials results do not record whether an assist option below the default was active.
- The sequence breaks bring the campaign to six Heart Pearls, the `MAX_ENERGY_TANKS` cap; any further
  Heart Pearl in the expansion needs a budget decision.
- `tools/check_campaign_graph.py` (665 lines) and the generated `scripts/campaign/campaign_rooms.gd`
  (1140 lines, lint-exempt) are over the line guidance; split the graph check at a real seam before
  it grows further.
- Rooms are sparse on landmarks; single-cell ceiling stubs render as boxy nubs; platform ends are square.
- Tidal Heart's grate floats and is mostly hidden by the heart sprite.
- Gliding keeps the tuck/spin pose, so the Updraft Cloak is partly occluded; a glide pose is wanted.
- Echo Shot and the harpoon peg are small at 1920 width; the bubble visual is larger than its collider.
- Surface eel only looks right on a liquid surface (rises out of the floor in the dev panel);
  Leech Wisps have no pathfinding; stalker follow was tested with a fake campaign root.
- Worldfx: crumble tiles are darker than terrain; a faint seam between fluid strip and flood body.
- Audio mix is tuned numerically; needs a listening pass. Ambience slider needs an `Ambience` bus.
- Map panning uses physical arrow keys; gate badges get busy when small.
- `player_run_sprint_armed.png` is unused and still shows the pistol.
- `player.gd` is at 965 of the 1000-line lint limit; new player features belong in separate modules.
- Before release: check the pending patent application US 18/613,164 (dash deflect) again, and have a
  patent attorney run a freedom-to-operate search (see the action-round decisions).

## Next steps

1. Hands-on balance pass of the action round: bosses, elites, deflect timing, glyph numbers and
   Trials length, with a real-input playthrough of each.
2. Bigger world: grow the campaign toward ~48 rooms (see [phase-2-campaign.md](phase-2-campaign.md)),
   with more landmarks, a save shrine near each boss shortcut, and a Heart Pearl budget decision.
3. Release: Linux export without dev mode, provenance/credits review, patent re-check, F2 gate.

Detailed contracts: [Phase 1](phase-1-devmode.md), [Phase 2](phase-2-campaign.md),
[content catalog](content-catalog.md), [game feel](game-feel.md), [visual plan](visual-plan.md), and
[implementation decisions](implementation-decisions.md).
