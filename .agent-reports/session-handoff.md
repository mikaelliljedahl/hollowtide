# Session handover

## Current reality (2026-09-23)

- Phase 1 (S0–S10 developer world) is implemented. F1 hands-on approval is still open, but per
  **D13** Phase 2 runs in parallel with F1 polish.
- Work runs in parallel **lanes** (**D14**): `env`, `audio`, `combat`, `ui`, `campaign`, `process`,
  each in its own worktree under `../hollowtide-lanes/<id>` on branch `lane/<id>`, with disjoint file
  ownership (`docs/code-contract.md` → "Parallel lanes 2026-09"). The integrator merges to `main`.
- Verification is lightweight (**D15**): `make check` passes and the author has looked at real
  in-game screenshots. Evidence manifests, committed videos and JSONL route logs are retired;
  screenshots/videos are never committed (`proofs/` is a git-ignored local capture directory).
- Phase 2 target is a compact ~12–15 room mini-campaign through all five areas (**D16**); each area
  gets its own natural look instead of steel-facility terrain everywhere (**D17**); area music may be
  regenerated for variety (**D18**).
- Controls: arrows move/aim, Down crouch, A jump, Space alternate jump, Z Slipstream, Left Shift run,
  X beam/bomb, C missile, V beam cycle, Q/F Flux, Esc pause/help, F1 developer panel.

## Implementation notes worth keeping

- Real traversable floor contact is `y=1152`, not the obsolete `y=1088` support line.
- `scripts/dev/dev_runtime_arena.gd` must keep enemy arena bounds inclusive of floor-standing
  players or stateful enemies appear inert.
- S7's lava basin must retain an open lead cell before its raised stepping stones.
- Immune armor stays health-immune while Ice can still apply its freeze/status.
- Tidal Heart: phase 1 is Ice→Missile, phase 2 is Wave through the grate→Missile. Readability of its
  vulnerable state is still a hands-on follow-up.
- Do not import or derive from any existing (non-Hollowtide) audio.
- Godot 4.7.2 has a threaded importer crash; the audio fixture runs with `--single-threaded-scene`.

## Verification

```sh
make check                                   # import, docs, format, lint, all suites (~35 s)
python3 tools/run_godot_check.py combat      # subset while iterating
make dev                                     # play it and look
```

## Next

1. Integrator merges the lane branches and runs `make check` on `main`.
2. User plays `make dev` for F1 look/sound/feel feedback; campaign work continues meanwhile.
