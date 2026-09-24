# Hollowtide — plan to finish the game

## Current delivery status

Phase 1 S0–S10 is implemented on current main and awaits user's hands-on approval. Latest
`make f1-check` passed 37/37 suites with zero ObjectDB/resource diagnostics. Manual playthrough,
human listening, and visual verification remain. Phase 2 P8–P11 has not started and is blocked until
explicit F1 acceptance. See
[state.md](state.md) and [roadmap.md](roadmap.md) for current package status.

## Assignment and reading order

This is a **production plan, not a description of finished features**. The starting point is a
minimal prototype. The sense of movement must be preserved; the existing scripts do not measure
how complete the game is.

The user has chosen a compact, complete campaign: **about 3–5 hours for a first playthrough,
five connected areas, and three bosses**. Playing time is a goal to measure with new players,
not a promise based on room count.

Read in order:

1. [Current state](state.md), then the three existing normative contracts.
2. This plan and the [content catalog](content-catalog.md).
3. [Phase 1: dev track](phase-1-devmode.md) or [Phase 2: campaign](phase-2-campaign.md).
4. [Visual plan](visual-plan.md) and [implementation decisions](implementation-decisions.md).
5. [Agent workflow](workflow.md).

New paths, numbers, and APIs in this plan are **proposed targets**, not existing resources or
permission to break the contracts. If documents contradict one another, today's normative
contract applies. Package P0 resolves and commits extensions before affected implementation.

## Two delivery phases — not two parallel games

| Phase | Delivery | End gate |
|---|---|---|
| **1. Dev track** | Rebuilt `level_01`, five-area presentation, full arsenal plus Flux, thirteen common enemy types, and three bosses. All can be selected, reset, and tested on shared save/world foundation. | Entire catalog runs in one executable; tuned base constants remain unchanged, including accepted base-impulse Ball jump; no approval from automation alone. |
| **2. Finished campaign** | The same systems and resources are used in five interconnected areas with meaningful progression, map, save, start, and ending. | New players can complete the game without developer tools, softlocks, or tutorial text. Release build is controlled. |

**Phase 1 is a product part:** it should remain usable during and after Phase 2. There is no
separate cheat implementation of weapons, enemies, or pickups. The developer panel calls the same
systems as the campaign. Campaign balance and placement happen in Phase 2; all types already work
in Phase 1.

## Delimitation

- The arsenal covers familiar metroidvania roles (a compact ball form, explosives, ammo weapon,
  beam modifiers, higher jump, heat protection, an attack dash, ammo and health containers) with
  Hollowtide's own names, art and behaviour. The protagonist and world are original.
- The existing wall jump, modern aiming, map, and save system remain Hollowtide choices. They must
  not be described as mechanics borrowed from another game.
- No heavy ammo variant, large area bomb, grapple, speed-run charge, infinite jump, multiplayer, crafting,
  dialogue tree, procedurally generated campaign, or additional biome in this plan.
- No tutorial text in the game world. Menus, settings, and the developer panel are not game
  teaching. Developer-panel technical labels appear only in explicit dev mode.
- Existing movement values, 64 px collision grid, figure scale, and 1920×1080 resolution remain.
  Graphical detail must not be purchased by changing physics scale or pixel scaling.

## Working order and dependencies

Each package is divided into small agent tasks according to [workflow.md](workflow.md). A package
is not automatically a single agent call. Owners refer to roles; new file ranges require P0.

| Package | Contents | Requires | Responsible role | Done when |
|---|---|---|---|---|
| P0 | Baseline, contract decisions, file ownership, and test commands | — | Integrator + user | Decision list established; no unowned files or conflicting APIs for the next package. |
| P1 | Data directory, stable content IDs, state, pickup/capacity model, and save format | P0 | Scaffold/system | Unique pickups, recovery, storage, and validation have automatic tests. |
| P2 | Cave/environment kits, render samples, character/presentation animations | P0 | Graphics + scaffold in separate files | Five kits and presentation pipeline are integrated/reproducible; human approval occurs at F1. |
| P3 | Dev start, isolated profile, test stations, safe presets, and recovery | P1 | Scaffold + HUD | Empty, full, and arbitrary conditions can be recreated without campaign impact. |
| P4 | All weapons, containers, bombs, and reaction matrix | P1, P3 | Battle + scaffold | Positive and negative cases for each catalog entry pass. |
| P5 | High Jump, spin animation, Undertow Dash, and protection | P2, P4 | Movement + graphics + combat, sequentially per interface | Spin looks correct; attack window, damage, and interruption are verified. |
| P6 | Thirteen enemy types, three bosses, and common status reactions | P4, P5 | Combat + graphics | All can be spawned, restored, defeated, and produce the correct response. |
| P7 | Phase 1 integration, room coupling, map/save sample, Flux, audio/HUD, regression | P2–P6 | Integrator/verifier | S0–S10 implementation and automated gate pass; F1 still requires user evidence/acceptance. |
| P8 | Campaign graph, gray box, progression, and all ability ports | P7 | Level/scaffold | Main route, return routes, and both branch orders are playable. |
| P9 | Five areas: final content, secrets, graphics, and audio | P8 | Level + graphics + sound | All rooms have finished content without new system scope. |
| P10 | Balance, comprehensibility, user testing, accessibility, and settings | P9 | Integrator + tester | New players progress; mandatory resources cannot run out permanently. |
| P11 | Release, export, regression, credits/provenance, and final documentation | P10 | Integrator | Phase 2 release gate passes; known deficiencies are reported. |

P1 and P2 can run in parallel after P0. Roster design and source inventory can run in parallel
with P4, but not implementation against guessed interfaces. P4/P5/P6 must not simultaneously
write player code or shared battle files. Graphics delivery and code integration are separate tasks.

## Budget rules

- **Luna** handles bounded inventory, PRD specification, implementation, and verification.
- **Astra** is used for a phase gate, severe contract conflicts, or the same error after two
  limited repair attempts—not as a constant intermediary for every file.
- Parallel writing agents are allowed (D14) in disjoint ownership areas and separate worktrees. Reading reviews
  can run alongside. Report diffs and proofs, not full transcripts.
- Do not prepare work explicitly outside scope. New requests replace other scope or require a new
  decision; they do not expand Phase 1.
- Do not guess a time or token budget for the complete game. Measure P1–P3 cost and use the actual
  rate to forecast P4 and P8.

## Common definition of done

1. Implemented in the correct file area; contract and catalog match current construction.
2. Automatic tests include error paths, reset, and reload, not only the success case.
3. Verified in a real TileMap/scene, not only in a standalone test body.
4. Visually approved: movement, wall jump, projectile origin, hits, and graphics quality.
5. Relevant sound and HUD react to the same state as the game.
6. No new parse/runtime errors; format/lint run where tools exist. Missing controls are explicitly
   stated, never presented as approved.
7. Report includes build/checkpoint, command, result, image/video, and remaining defects. Only the
   integrator updates aggregate status after review.
