# Hollowtide — plan for the next rounds

Written 2026-09-24 after the user beat the full campaign (action round included). This is the lead's
view of what to do next and in what order; [state.md](state.md) keeps the factual status and known gaps.
Nothing here is decided until the user picks it up.

## 1. Stabilise what exists (small, do first)

- **Save safety after renames.** The id rename (morph_ball → slipstream etc.) silently broke every save
  for players with an older slot: autosaves failed and boss victories were rolled back, sealing doors.
  Fixed by archiving stale slots (`slot_01.stale.*.json`). Rule from now on: any change to ids that end up
  in saves needs a check in `tools/check_progression.gd` that an old slot still loads or is archived.
- **Hands-on balance pass** of the action round (four-stage bosses, elites, deflect timing, glyphs,
  Trials). The AI playtest agent (Jev) finds softlocks; it cannot judge fun or fairness.
- **Readability:** the boss-sealed hatch now has its own stone-seal look so it is not confused with the
  Undertow barriers. Similar audits: every gate kind should be recognisable at a glance and on the map.
- **Tooling hazards:** `tools/gen_sprites.py` still regenerates the player sheets from old sources and
  would overwrite the crossbow poses; retire the player part of it. After swapping any sprite, run
  `make import` before trusting a test (a stale `.godot` import cache made a passing art change look
  broken, and could hide a real break).

## 2. Originality pass, round 3

Names and art are now original. What still reads as "genre default" is mostly behaviour and HUD:

- Ceiling diver (hangs, dives), hopper (big jumper), frost floater (freezable floater) and Leech Wisp
  (seeks the player) follow classic genre archetypes. Give each a twist that fits the forest/tide theme,
  e.g. the diver drops seed pods instead of itself, the floater is a drifting spore cloud that bursts.
- HUD: a single "vitality" bar with tank pips is the genre's signature layout. Consider heart-pearl
  icons or a vine/tide gauge instead.
- Ability-coloured doors are fine as a genre convention; keep the art clearly our own.

Legal note: the repo is MIT-licensed and public-ready; before a commercial release, re-check the dash
deflect patent application noted in state.md and get a proper freedom-to-operate review.

## 3. Bigger world (~48 rooms)

- Grow each of the five areas from ~3 to ~9–10 rooms: one landmark room, one secret, one shortcut back to
  the hub, and one optional challenge per area. Keep the two branch orders (vaults/kiln) and add at
  least two more loops so backtracking is short.
- Build it the way the 16 rooms were built: ASCII layouts → `tools/build_campaign_rooms.py`, the graph
  solver and the move checks as the safety net. One lane per area in parallel, each with its own Codex art
  batch for landmarks; one integrate lane owns the world graph, map and save-shrine spacing.
- Decide the Heart Pearl / Bolt Quiver budget for the bigger world first (the six-pearl cap is reached).

## 4. Bosses and set pieces

- The boss rework (four stages, telegraphs, punish windows) is in; tune it by hand first.
- Add one mid-boss per area in the bigger world so the jump between common enemies and bosses is smaller.
- The original "rising tide" mechanic (D21, postponed) could become the depths set piece: the whole area
  floods and drains on a rhythm. Dark zones stay out unless the user asks.

## 5. Release

- Linux and Windows exports without dev mode, a settings/controls screen check, credits and provenance
  review, and an F2 gate playthrough by someone who has never seen the game.
- Publish on itch.io (free) once the bigger world is in; make the GitHub repo public when the user is happy.

## How to run the work

Parallel lanes in git worktrees (`hollowtide-lanes/<lane>`), Codex image agents for art from written
briefs, the lead merging with `make check` green. Keep verification light: tests plus looking at real
screenshots, no videos or proof manifests in git. Coordinate with the co-developer through PRs on the
new repo only; never merge anything from the archived history.
