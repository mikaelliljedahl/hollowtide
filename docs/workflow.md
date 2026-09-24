# Hollowtide — workflow

Short and practical. Decisions D14 (parallel lanes) and D15 (lightweight verification) in
[implementation-decisions.md](implementation-decisions.md) are the basis for this page.

## Lanes and worktrees

- Work is split into **lanes** with disjoint file ownership; the table lives in
  [code-contract.md](code-contract.md) → "Parallel lanes 2026-09". There is no agent-count limit.
- Each lane works in its own git worktree on branch `lane/<id>`:

  ```sh
  git worktree add ../hollowtide-lanes/<id> -b lane/<id> main
  cd ../hollowtide-lanes/<id> && make import
  ```

- Write only files your lane owns. Need a change elsewhere? Put it under "Requests to other lanes"
  in your report, or ask the integrator. Build against the cross-lane interfaces in the code
  contract with `has_method()` / null-checked `load()` until the other side is merged.
- Read `AGENTS.md`, the relevant normative contracts and [state.md](state.md) before you start.
  Do not change tuned values in [game-feel.md](game-feel.md).
- Commit small, logical commits on your branch. Never push, never touch `main` or another worktree,
  never rewrite history.

## How to verify

A change is done when **`make check` passes** and **you have looked at real in-game screenshots**
of what you changed.

1. `make check` — import, docs links, format-check, lint, and the headless regression suites
   (movement, wall jump, progression, save/persistence, combat outcomes, …). Run it once before you
   change anything so you know which failures already exist. `make test` runs only the suites;
   `python3 tools/run_godot_check.py <name-filter>` runs a subset while iterating.
   The runner starts every Godot suite with a fixed 60 fps physics/frame rate (`--fixed-fps 60`), so
   results don't depend on machine speed, and runs suites in parallel.
2. Screenshots — write a small capture scene (see `tools/check_cave_preview.gd`) that saves
   `get_viewport().get_texture().get_image()`, and run it windowed:

   ```sh
   godot --path . --windowed --resolution 1920x1080 res://tools/<capture>.tscn -- --dev-mode
   ```

   Save PNGs to a scratch directory (or `proofs/`, which is git-ignored) and actually look at them
   as a player would: floating props, seams, overlaps, unreadable HUD, clashing colors.
3. Movement and feel: play it with `make dev`. Movement logic lives in `_physics_process`.

Do not run asset generators just to
tick a box; generators are for producing content your lane owns.

Verification is deliberately light: no evidence videos, proof manifests or recorded clips.
Screenshots and videos are working files. **Never commit them.** Read the Godot log, not only the
exit code: `SCRIPT ERROR` and leaked-resource warnings fail the runner.

### Adding a check

Suites are registered in one list, `SUITES` in `tools/run_godot_check.py` — one line per suite
(a `.tscn` scene, a `.gd` script, or a `tools/*.py` script). Suites run in parallel, each with its own
save root and `user://` directory, so a suite must not depend on another suite's output. Delete the
line when you delete the test. Checks that pin exact asset hashes or document wording are not
wanted; test behaviour.

## Writing a report

At the end of a lane task write a short report (about a page) with:

- What changed, from the player's point of view.
- Decisions you made and why (you have autonomy inside your lane; do not wait for answers).
- Files touched, and how you verified (which screenshots you looked at, `make check` result).
- Known issues and "Requests to other lanes" (exact file + what is needed).

`.agent-reports/session-handoff.md` is the only standing report in the repo; update it when the
overall picture changes. Per-task reports belong outside the repo (the lane report directory).

## How the integrator merges

1. Read the lane report and `git log main..lane/<id>`.
2. Merge lanes one at a time into `main` (`git merge --no-ff lane/<id>`), resolving conflicts in the
   runner list or docs by hand.
3. Run `make check` on `main` after each merge and look at the affected scenes with `make dev`.
4. Apply requests to other lanes and doc updates (`docs/` belongs to the integrator unless a lane owns
   a file), then remove the worktree: `git worktree remove ../hollowtide-lanes/<id>`.
