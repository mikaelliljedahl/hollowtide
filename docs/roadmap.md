# Hollowtide — roadmap

## Current phase status

Phase 1 is done. Phase 2's 16-room mini-campaign (D16) is playable and has been beaten by the user;
round 2 (D19–D21) added the original arsenal, surprise enemies and living environment.

### Phase 1 — dev track, all systems and testable content

- [x] **P0** Baseline, contract extensions, file ownership, and verification commands — foundations and
  implementation exist; final full verification remains.
- [x] **P1** Content IDs, state, mapped pickups/capacity, save schema v2, and Flux persistence — implemented.
- [x] **P2** Five cave environment kits, transitions, landmarks, and presentation assets in real level —
  implemented; human review remains.
- [x] **P3** Dev mode, isolated profile, presets, S0–S10, authored passages/fixtures, and reset — implemented.
- [x] **P4** Full arsenal, tanks/refills, bombs, authored beam/gate families, and Flux package — implemented.
- [x] **P5** High Jump, normal spin, Undertow Dash, protection, crouch/run/wall poses, and accepted base Ball jump —
  implemented; normal spin is approved, other movement presentation awaits review.
- [x] **P6** Thirteen common enemy types and three fully testable bosses — implemented additively;
  the original eight plus authorized `shard_turret`, `burrower`, `grasshopper`,
  `shooting_gargoyle`, and `lava_monster`. Six surprise enemies added in round 2 (D20).
- [x] **P7** Integration, map/save v2, five 48-second melodies, five-area Phase 1 presentation, and
  phase-gate preparation — done.
- [x] **F1** Phase gate: dev track played through; Phase 2 proceeds (D13).

Specifications: [Phase 1](phase-1-devmode.md), [content catalog](content-catalog.md), and
[implementation decisions](implementation-decisions.md).

### Phase 2 — finished campaign and release (in progress)

- [~] **P8** Campaign graph, progression, two branch orders, and return paths — done for the 16-room
  mini-campaign with graph solver, save/continue, map and minimap; growing toward ~48 rooms remains.
- [~] **P9** Five areas with per-area art and music, surprise enemies and living environment — done
  for the mini-campaign; more landmarks, rooms and harder bosses remain.
- [ ] **P10** Balance, new-player testing, settings, and accessibility.
- [ ] **P11** Export, release verification, credits/provenance, and approved F2 gate.

Next: bigger world (~48 rooms), harder bosses, release export.

## Older epics — history and regression context

E-IDs are retained for older reports. P0–P11 is the current working order; do not run an old
epic in parallel as if it were a separate system build.

| Epic | Current status | Continued in |
|---|---|---|
| [E01 Rörelse](epics/E01-rorelse-game-feel.md) | Code exists; preserve balanced feel. | P0/P5/P7 regression |
| [E02 Slipstream](epics/E02-slipstream-forsta-scen.md) | Code and first gate available. | P3/P4/P7 |
| [E03 Grafikpipeline](epics/E03-grafikpipeline.md) | Pipeline exists; visual playtest remains. | P2/P5/P9 |
| [E04 Strid](epics/E04-strid.md) | Beam, missiles, crawler, and extended catalog available. | P1/P4/P6 |
| [E05 Sound](epics/E05-ljud-och-musik.md) | Code and assets available; listening test remains. | P7/P9 |
| [E06 Väggskutt](epics/E06-vaggskutt.md) | Implemented and headless-tested; not visually approved. | P0/P5/P7 |
| [E07 Scen 1](epics/E07-nivadesign-scen-1.md) | Reachability test passes; not a full campaign. | P3/P7 |
| E08 Health/damage | Health, death, and respawn implemented; user test remains. | P1/P3/P7 |
| E09 Abilities | Replaced by the full content directory. | P4/P5 |
| E10 Map | Full campaign map and minimap implemented. | P7, P8–P10 |
| E11 Save/load | Dev/campaign base available; full phase gate remains. | P1/P7, P8–P11 |
| E12 Coherent world | 16-room campaign implemented; expansion to ~48 rooms remains. | P7/P8/P9 |

Binding values come from [game-feel.md](game-feel.md) and [code-contract.md](code-contract.md).
See [state.md](state.md) for current state and next steps.
