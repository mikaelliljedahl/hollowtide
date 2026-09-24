# Hollowtide — current status

## Aggregate status

**Phase 1 (dev track S0–S10) is done. Phase 2's compact mini-campaign is playable and the user has
beaten it.** The campaign has 16 connected rooms across five areas (fringe 5, nexus 2, vaults 3,
kiln 3, depths 3) with save/continue, a full map with unexplored-exit markers, a minimap, per-area art
and music, three bosses and an ending with credits. `make check` passes.

Round 2 (D19–D21) replaced the genre-default arsenal with an original one, added surprise enemies
and a living environment. Internal IDs are unchanged, so saves, gates, the campaign graph and tests
still work; see the name table in [content-catalog.md](content-catalog.md#names-and-internal-ids-d19).

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
- **Presentation:** per-area painted art (`assets/environment/areas/<area>/`), background coverage,
  lava basins, light shafts, decor; round-2 art from Codex GPT-image (`assets/sprites/arsenal/`,
  `assets/sprites/enemies_new/`, `assets/worldfx/`).
- **Audio:** five area themes, ambience, procedural SFX for arsenal, surprise enemies and worldfx.
- **Saving:** dev/campaign domains, schema v2; death restores at the checkpoint without loading disk.

## Ambush arenas (branch `feature/ambush-arenas-v2`)

The D21 arena (`scripts/world/dynamic/ambush_arena.gd`) is the one ambush system, with its pure rules
in `scripts/world/dynamic/ambush_rules.gd`. It now runs the design in
[features/ambush-arenas.md](features/ambush-arenas.md): several telegraphed waves with a 0.8 s
breather, a per-spawn kill filter (an arena with no winnable spawn never seals), spawns only on
authored points at least 256 px from the player, abort on death, on leaving the arena or after 40 s
without damage, and one refill on clear. Layouts declare waves with `wave=`, `wave2=`, ... plus
optional `trigger=` and `spawns=` rectangles (`tools/campaign_ambush.py`). Placements: `fringe_03.beam_trial`,
`nexus_02.loft`, `vaults_01.threshold`, `kiln_02.antechamber`, `depths_01.undertow_hall` (two waves
each, all cleared by a real-input bot) and the dev-track S3 arena (three waves, flag `dev:S3:ambush`).
Suites `ambush rules`, `ambush rules dev` and `ambush campaign` cover the rules and every placement. Not
done: a hands-on playtest and a visual capture of the telegraphs.

The Armored Guard leash fix is live in `EnemyAi.armored_guard`: a patrol also turns at its arena leash
edge, so leashed guards (for example in `vaults_02` and `depths_01`) no longer park at the edge.

## Known gaps

- Bosses are logic-tested, not balance-tested, and should be harder.
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
- `player.gd` is at the 1000-line lint limit; new player features belong in separate modules.

## Next steps

1. Bigger world: grow the campaign toward ~48 rooms (see [phase-2-campaign.md](phase-2-campaign.md)),
   with more landmarks and revisit rewards.
2. Harder bosses: more phases/patterns and a real balance pass.
3. Release: Linux export without dev mode, provenance/credits review, F2 gate.

Detailed contracts: [Phase 1](phase-1-devmode.md), [Phase 2](phase-2-campaign.md),
[content catalog](content-catalog.md), [game feel](game-feel.md), [visual plan](visual-plan.md), and
[implementation decisions](implementation-decisions.md).
