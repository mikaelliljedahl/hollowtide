# Hollowtide

A 2D metroidvania in Godot 4.7/GDScript. An unarmored protagonist with her own identity, a coherent
underground world, skill-driven exploration and environmental storytelling without tutorial text.

## Status

Phase 1 (developer track) is done. Phase 2's 16-room mini-campaign is playable from start to
credits. See [current status](docs/state.md).

- Five connected areas with their own painted art and music; save/continue, full map and minimap.
- Original arsenal: Seed Crossbow, Harpoon, Bubble Snare, Echo Shot, Resonance Pulse, Focus Lens,
  Undertow Dash, Slipstream, Updraft Cloak, Pressure Seal, Heart Pearls and Bolt Quivers.
- Thirteen common enemies, six surprise enemies (bats, mimic, drop spider, surface eel, stalker,
  chasm sniper) and three bosses.
- Living environment: ambush and timed doors, crumbling floors, stalactites, crushers, currents and
  a rising shaft.

## Run

With Godot 4.7 on `PATH`, from the repo root:

```sh
make run    # normal start menu
make dev    # developer track (--dev-mode)
make check  # import, docs, lint and headless test suites
```

`./start.sh` and `godot --path .` also start the game normally.

## Documentation

- [Roadmap](docs/roadmap.md) and [production plan](docs/production-plan.md)
- [Phase 1: developer track](docs/phase-1-devmode.md) · [Phase 2: campaign](docs/phase-2-campaign.md)
- [Content catalog](docs/content-catalog.md) · [Visual plan](docs/visual-plan.md)
- [Implementation decisions](docs/implementation-decisions.md) · [Workflow](docs/workflow.md)

Read [AGENTS.md](AGENTS.md) before starting work. Movement, assets and file ownership are regulated by
[game-feel](docs/game-feel.md), [asset-contract](docs/asset-contract.md) and
[code-contract](docs/code-contract.md).

## License

MIT — see [LICENSE](LICENSE). Covers code, graphics, audio and docs.
