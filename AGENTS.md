# Hollowtide — agent input

Hollowtide is a 2D metroidvania in Godot 4.7 with a focus on movement and exploration.
The world is coherent and non-linear; abilities open previously unseen paths.
Isolation, atmosphere and environmental storytelling outweigh dialogue and cutscenes.
The protagonist is an unarmored woman with her own identity who builds up her equipment during the course of the game.
The normative contracts in `docs/` are binding; other documents guide the work.

| File | Contents |
|---|---|
| [docs/vision.md](docs/vision.md) | Game vision, design pillars and clear boundaries. |
| [docs/roadmap.md](docs/roadmap.md) | Active two-phase roadmap and legacy epic history. |
| [docs/production-plan.md](docs/production-plan.md) | Plan from minimal prototype to finished game; packages P0–P11. |
| [docs/phase-1-devmode.md](docs/phase-1-devmode.md) | First installment: developer track with full content catalog. |
| [docs/phase-2-campaign.md](docs/phase-2-campaign.md) | Five interconnected areas, progression and release gate. |
| [docs/content-catalog.md](docs/content-catalog.md) | Weapons, upgrades, containers, ten enemy types and three bosses. |
| [docs/visual-plan.md](docs/visual-plan.md) | High resolution cave modules, correct spin and visual acceptance tests. |
| [docs/implementation-decisions.md](docs/implementation-decisions.md) | Proposed contract amendments and decisions that must be determined before code. |
| [docs/state.md](docs/state.md) | Current working state, flaws, agents and next steps. |
| [docs/pitfalls.md](docs/pitfalls.md) | Previous traps, causes, consequences and countermeasures. |
| [docs/workflow.md](docs/workflow.md) | Practical way of working for parallel agents and verification. |
| [docs/game-feel.md](docs/game-feel.md) | Normative results for movement, jump, ball shape and camera. |
| [docs/asset-contract.md](docs/asset-contract.md) | Normative results for the format, measurements and layout of the graphics. |
| [docs/devmode-contract.md](docs/devmode-contract.md) | Activated integration contract for phase 1; new APIs and file owners. |
| [docs/code-contract.md](docs/code-contract.md) | Normative findings for file ownership, interfaces and collision rules. |
| [docs/features/ambush-arenas.md](docs/features/ambush-arenas.md) | Feature design for sealed wave encounters (ambush arenas); rules, state machine and tests. |
| [docs/features/assist-options.md](docs/features/assist-options.md) | Feature design for assist options (game speed, damage taken, skip ambushes); damage order and tests. |
| [docs/features/map-pins.md](docs/features/map-pins.md) | Feature design for player map pins; rules, controls, save key and tests. |
| [docs/features/revisit-remix.md](docs/features/revisit-remix.md) | Feature design for elite enemies in revisited rooms after each boss; tiers, stats and tests. |
| [docs/features/boss-rework.md](docs/features/boss-rework.md) | Feature design for four-stage boss fights; telegraphs, punish windows, attack tables and tests. |
| [docs/features/dash-deflect.md](docs/features/dash-deflect.md) | Feature design for turning enemy shots with the Undertow Dash; binding patent and naming constraints. |
| [docs/features/fast-travel.md](docs/features/fast-travel.md) | Feature design for fast travel between save shrines and boss shortcuts; refusal rules and tests. |
| [docs/features/sequence-breaks.md](docs/features/sequence-breaks.md) | Feature design for three intended sequence breaks; routes, solver model and tests. |
| [docs/features/tide-modules.md](docs/features/tide-modules.md) | Feature design for Tide Sockets and Tide Glyphs; catalogue, save key and binding legal constraints. |
| [docs/features/trials.md](docs/features/trials.md) | Feature design for the post-ending Trials (Gauntlet, Boss Rush); rules, flow, save key and tests. |
| [docs/epics/E01-rorelse-game-feel.md](docs/epics/E01-rorelse-game-feel.md) | PRD for completed movement base. |
| [docs/epics/E02-slipstream-forsta-scen.md](docs/epics/E02-slipstream-forsta-scen.md) | PRD for finished slipstream and first ability port. |
| [docs/epics/E03-grafikpipeline.md](docs/epics/E03-grafikpipeline.md) | PRD for finished graphics pipeline. |
| [docs/epics/E04-strid.md](docs/epics/E04-strid.md) | Historical PRD for beam, missile code and creep enemy; full pickup loop missing. |
| [docs/epics/E05-ljud-och-musik.md](docs/epics/E05-ljud-och-musik.md) | PRD for complete sound and music base. |
| [docs/epics/E06-vaggskutt.md](docs/epics/E06-vaggskutt.md) | PRD for implemented wall shot; final visual verification remains. |
| [docs/epics/E07-nivadesign-scen-1.md](docs/epics/E07-nivadesign-scen-1.md) | PRD for ongoing feasible scene 1. |

## Current delivery note
- Visible runtime UI should be in English. The project's documentation is in English.
- Normal boot runs with `make run`; development start runs with `make dev`. Help in start menu/pause is
  approved text outside the game world; don't put tutorial text in the game world.
- Phase 1 is done. Phase 2's 16-room mini-campaign is playable (beaten by the user); next is a bigger
  world, harder bosses and a release export. Player-visible names follow D19; internal IDs are unchanged except four renamed ones (see `docs/state.md`).

## Absolute work rules
- Read relevant normative contracts before code or graphics work; never guess dimensions, paths or interfaces.
- Only write to files that `docs/code-contract.md` assigns to your role.
- Do not change normative contracts or agreed operating values locally; report objections.
- Never put tutorial text, pop-up instructions or other text-based game teaching in the game.
- Put movement logic in `_physics_process` and verify visually, not just with measurements.