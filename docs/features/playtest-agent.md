# Feature design: playtest agent

Status: dev tool, implemented on branch `feature/playtest-agent` on 2026-09-24, not yet accepted as
a contract amendment. Everything lives in `tools/`; nothing in `scripts/` or `scenes/` changed, and
no player ever reaches it.

## 1. Goal

An AI player that plays the real campaign through real inputs and writes feedback reports that
drive design changes. Each decision it gets a compact structured game state and a short list of
labelled macro actions and picks one, the way TypeSafe's Jev played Doom from structured state. The
harness is backend-agnostic: a rule-based heuristic runs offline and in CI, a seeded random policy
is the baseline, and any out-of-process model (Jev or a local one) plugs in over a local socket.

Out of scope: learning or training, pathfinding across rooms, a player-visible mode, and any change
to game code.

## 2. Rules

- **R1 Inputs only.** The agent presses and releases the game's input actions with
  `Input.parse_input_event` and `Input.flush_buffered_events` (`tools/playtest_programs.gd:237`). It
  never moves the player, sets health or kills enemies. Setup is the only exception: the launch
  scene resets progress, grants the kit and sets the checkpoint before the campaign loads
  (`tools/playtest_agent.gd:86`).
- **R2 Save safety.** The launch scene refuses to run without `--test-mode` in a debug build
  (`tools/playtest_agent.gd:51`), so the player's own save is never written; the runner gives
  every run its own `--test-save-root`.
- **R3 Invisible.** Nothing is drawn and no text enters the game world. The harness is a scene in
  `tools/`, reached only from the command line.
- **R4 Determinism.** Headless runs use `--fixed-fps 60`; the heuristic is deterministic and the
  random policy is seeded, so a seed reproduces a run.
- **R5 Fail safe.** An external policy that is missing, slow or wrong never stalls the run: the
  decision falls back to the heuristic and the fallback is counted in the report.

## 3. Architecture

| Part | File | Role |
|---|---|---|
| Launch scene | `tools/playtest_agent.gd`, `tools/playtest_agent.tscn` | Parses flags, loads the campaign in one room with a kit, runs the loop, ends the run, writes the report and screenshots. |
| Loop | `tools/playtest_loop.gd:50` | Once per physics frame, before the player: when the current program is done, export state, build candidates, ask the policy, start the chosen program. |
| State exporter | `tools/playtest_state.gd:44` | One JSON-safe Dictionary per decision (section 4). |
| Candidates | `tools/playtest_actions.gd:63` | 5 to 14 labelled macro actions, each a per-frame program of held actions (section 5). |
| Programs and driver | `tools/playtest_programs.gd:179` | Builds the per-frame programs and plays them as input events. |
| Aim | `tools/playtest_aim.gd:50` | Which aim lines a bolt up with a point, where to stand for it, when a jump shot fires. |
| Crouch shot | `tools/playtest_crouch.gd:66` | What a shot hits on an enemy, whether it is below the standing shot, and the crouched level shot at it (section 23). |
| Boss facts | `tools/playtest_boss.gd:46` | Protection phase, open shell, opener table and arena for the state. |
| Refill reach | `tools/playtest_reach.gd:26` | Whether the straight steer arrives at a point: climb from the floor under her, line of sight, no deep gap on the way (section 24). |
| Boss dodges | `tools/playtest_dodge.gd:60` | The timed answer to a boss attack being telegraphed, the refill run's jump over a boss (section 20), and the enemy shot a curl or a dash answers. |
| Tidal Heart dodges | `tools/playtest_tide.gd` | The Tidal Heart's shot lines for the state and the spot off every line, or the lane jump (section 21). |
| Hazards | `tools/playtest_hazards.gd:43` | Hazard bodies as rects, shared by the state and the damage attribution. |
| Policies | `tools/playtest_policy.gd:62` | `heuristic` and `random`; `external` goes through the bridge. |
| Bridge | `tools/playtest_bridge.gd:53` | TCP client for the external policy (section 7). |
| Telemetry | `tools/playtest_telemetry.gd:61` | Signals and per-frame sampling (section 8). |
| Report | `tools/playtest_report.gd:10` | Findings, `report.json` and `report.md`. |
| Runner | `tools/playtest/run.py:70` | Launches Godot per seed, hosts the policy server, aggregates. |
| Policy server | `tools/playtest/policy_server.py:57` | Serves one game connection with a backend. |
| Jev backend | `tools/playtest/jev_backend.py:156` | Hosted Jev or any `/v1/systemone` server (section 12). |
| Jev request | `tools/playtest/jev_request.py:282` | Jev's compact state, the legal candidate filter, the rubric and the three questions (section 12). |
| Jev feedback | `tools/playtest/jev_feedback.py:103` | Confusion hotspots, danger peaks, disagreement (section 12). |
| Aggregate | `tools/playtest/aggregate.py:28` | Cross-run findings over several seeds or runs. |
| Jev critic | `tools/playtest/jev_critic.py` | Jev rates each room, arena and boss after a run (section 22). |

Decisions happen when the current program ends, at most every 6 physics frames (10 Hz at 60 Hz).
A jump is committed for 28 frames, so the effective rate is 3 to 10 Hz. While the tree is paused
(room fade, respawn) or the player is dead, all inputs are released and no decision is made.

## 4. State

Coordinates of other things are pixels relative to the player's feet (x right, y down); the
player's own position is room-local. Built by `tools/playtest_state.gd:44`.

| Key | Contents |
|---|---|
| `tick`, `t` | Decision number and game seconds since the agent started. |
| `room` | `id`, `area`, `size` in px. |
| `player` | `pos`, `cell`, `vel`, `health`, `max_health`, `grounded`, `on_wall`, `facing`, `form` (standing, crouching, ball), `dash_ready`. |
| `kit` | `abilities` (internal ids), the equipped `beam` and the owned `beams` in `cycle_beam` order (GameState ids `base`, `ice`, `wave`), `missiles`, `max_missiles`, `harpoons_flying` (fired Harpoons still in the air). |
| `enemies` | Up to 6, nearest first: stable per-run `id` (`e1`, ...), `type`, `rel`, `dist`, `health`, `max_health`, `is_boss`, `telegraph` (wind-up showing, a surprise enemy's wind-up glow and the surface eel's boiling liquid included), `ambush`, `hurt_by` (damage kinds usable on it now, from the enemy's own `is_vulnerable_to`: the equipped beam kind, `missile` only while a shot's worth of Harpoons is left, `bomb`, `undertow`), `switch_to` (an owned, unequipped beam that hurts it when the equipped one does not, else ""), `visible` (no tile on the line from the crossbow; a grate the Harpoon passes right now does not count), `span_rel` (top and bottom y of what a shot hits on it, its art's projectile hurtbox, relative to the feet) `platform` (campaign mode: a frost floater an upcoming route hop stands on, frozen or not; it gets no fight options and Jev reads it as `route_platform`) and `low` (a level shot from her standing crossbow, 161 px up, passes over that span while a crouched one, 72 px up, hits it; `tools/playtest_crouch.gd:24`). A surprise or combat enemy winding up adds `wind_up_left` (seconds). Bosses add `stage`, `attack`, `attack_state`, `attack_left` (telegraph seconds left), `attack_elapsed` (seconds since the release), `columns_rel` (the floor columns Rockfall and Vent Burst locked when their telegraph began, x relative to the feet), `shots_rel` (the Tidal Heart's lines: every shot of its locked plan while it telegraphs, then the shots still to come and every enemy shot in flight within 1,600 px, each as origin x and y relative to the feet, direction x and y, seconds until it flies, speed and lifetime; `tools/playtest_tide.gd`), `engaged`, `phase` (protection phase), `opening` (the current opening still takes damage, boss-rework R8), `open` (the Harpoon hurts it now: shell open and opening unspent), `opener` (null, or `beam`, `via` body, grate or punish, `owned`, `point_rel`: where the opener must land, `visible`: the opener bolt reaches it from here, and while it does not, `spot_rel`: the nearest standing spot in the arena it lines up from in sight) and `arena_rel` (the arena rect as x0, y0, x1, y1 relative to the feet). |
| `projectiles` | Up to 8 enemy shots within 900 px: `rel`, `vel`, `style`. |
| `ambush` | The room's arena or null: `id`, `state` (armed, sealing, fighting, cleared, intermission), `wave`, `waves`, `alive`, `trigger_rel`, `inside`. |
| `exits` | Doors from the room index: `id` (`edge:target`), `rel`, `gated`, `gate` kind. |
| `pickups` | Up to 4 uncollected progression pickups: `id`, `kind`, `rel`. |
| `hazards` | Up to 4 hazards within 1200 px of the player's hitbox, measured to the hazard's body rect (`tools/playtest_hazards.gd:43`): `kind` (lava, fire, steam from the `dev_hazard` group; stalactite, crusher, crumble, heat, rising_lava, rising_water), `rel` (nearest point of the body), `size`, `gap` (px between the hitboxes, 0 when touching) and `state` (a spike's, flood's or crusher's phase). |
| `refills` | Up to 3, nearest first: shrines in the room (`save`, `refill`, `missilerefill`) and dropped refills, with `kind`, `restores` (health, harpoons) and `rel`. |

## 5. Candidates

`idle` is always first and the two plain jumps always last; the rest follow a fixed priority and
the list is cut at 14 (`tools/playtest_actions.gd:63`). The fight options aim at one primary target:
the nearest visible enemy the kit can hurt, bosses always included (`tools/playtest_actions.gd:470`).

| Key | Offered when | Program |
|---|---|---|
| `approach:<id>` | An enemy exists | Walk toward it; jump when a wall blocks, it is above (under a low ceiling, first walk out to open sky) or floor lava or fire lies one step ahead; wall-jump when clinging below it. From outside a live boss's arena: walk toward the boss to enter it. For a boss: walk, never jump, to the spot where a grounded bolt lines up with its opener point while the shell is closed, else with its body (320 px off a level target, along the 45 degree aim for a higher one), but no closer than 48 px to the arena's edge; while the opener is out of sight, steer to its `spot_rel` instead, climbing to it. |
| `dodge:<attack>` | Standing (not curled) on the ground in a live boss's arena while it telegraphs or releases an attack with a known answer (section 20); for the Tidal Heart while any of its lines still crosses the floor within 348 px of her | Wait for the moment the answer needs, then play it: a jump in place, a double jump in desperation, a walk to the nearest gap between locked columns, a curl and roll under a low roof, a curl in place until a fan has passed, a run into the wall's pocket, standing still, or for the Tidal Heart a step to the nearest spot off every line (standing, else curled) or a jump over a low Crosscurrent lane with a curl under the high one. |
| `retreat` | An enemy within 420 px and no wall 24 px behind the player; for a live boss only while its arena reaches at least 160 px behind the player | Run away from it for 12 frames. |
| `open_boss:<id>:<aim>` | The player inside the boss's arena, a closed boss with its opening unspent, a Harpoon left, the opener beam owned and equipped, the opener point in sight, and an aim whose bolt passes within 100 px of its body (Snare) or 72 px of its grate's centre (Echo) | Fire the opener along that aim. |
| `shoot:<id>:<aim>` | Beam owned, not in ball form, not at a boss from outside its arena, target within 1100 px and an aim reaches it (none when the player is grounded and the target is more than 160 px below the feet, none level at a target more than 80 px above the crossbow or at a `low` one, none whose bolt line passes more than 120 px from an ordinary enemy, none at a frost floater the route is freezing; for a boss the bolt line must pass within 100 px of its centre) | Face it, hold the aim (forward, up, diag_up, and down or diag_down in the air), tap `fire_beam`. |
| `jump_shoot:<id>` | Grounded, no standing aim reaches a non-boss target up to 240 px above the crossbow | Jump straight up and fire level on the frame the crossbow reaches its height (`tools/playtest_aim.gd`, Updraft Cloak speed when owned). |
| `harpoon:<id>:<aim>` | A shot's worth of Harpoons left, an enemy in sight that the Harpoon hurts and that is a boss or immune to the beam, an aim that reaches it (none level at a `low` one), and for a boss the player inside its arena and no Harpoon already flying (one opening takes one) | Same with `fire_missile`. |
| `crouch_shot:<id>:<weapon>` | Standing or crouching on the ground, a `low`, visible, non-boss primary target within 1100 px, and a weapon that hurts it: `bolt` when the equipped bolt damages it, else `harpoon` when a shot's worth is left, else `bolt` when the Snare freezes it | Face it, hold `move_down` 3 frames to crouch, tap the fire action level while crouched, stay down 3 frames. |
| `pulse:<id>` | Resonance Pulse and Slipstream owned, the pulse hurts the target and the beam does not, target within 400 px and 96 px level, grounded or in ball form | Curl into ball form, roll toward it, drop the pulse (`fire_beam` in ball form), roll back 24 frames, stand up. |
| `select_beam:<beam>` | Per owned, unequipped beam while a target exists; the label says when it hurts or opens the target | Tap `cycle_beam` as often as the owned order needs. |
| `jump_over:<id>` | Grounded, target within 420 px, not a boss floating more than 160 px above the feet | Jump toward it, 20 frames held. |
| `duck` | Slipstream owned, standing on the ground, and a shot within 300 px that will cross her column 80 to 200 px above the feet | Curl into ball form in place, stay curled 45 frames, stand up. |
| `dash_through` | Undertow Dash ready, a shot flying at the player within 420 px, and a live boss's arena reaching at least 384 px that way | Dash into the shot (the deflect window). |
| `wall_jump_up` | Airborne against a wall | Push in, jump away, steer back. |
| `go_to_refill:<kind>` | Out of Harpoons (with a quiver) or below a third of health, and a refill in `refills` restores it that the steer arrives at: no more than 320 px above the floor under her, not behind rock at crossbow height and at a jump's apex, and no gap on the way whose floor lies more than 320 px below it (section 24) | Steer to it, running; with a live boss standing between on the floor and 240 px of free air above its body, run and jump over it. |
| `go_to_ambush` | Armed arena, player not at its trigger; in campaign mode only with the trigger within 160 px of her height (the route leads there otherwise) | Steer to the trigger centre. |
| `pick_up:<id>` | Up to two pickups, each only where the steer arrives (as for `go_to_refill`) | Steer to it. |
| `go_to_exit:<edge:target>` | Up to three ungated exits the steer arrives at (as for `go_to_refill`), none while a boss is alive in the room (a boss room's goal is the fight) | Steer to the door, running. |
| `jump:left`, `jump:right` | Always | Plain jumps, used to break a stall. |

Stuck detection is positional: 3 s in which the player chose movement but stayed inside a 48 px
box (`tools/playtest_telemetry.gd:380`). `retreat` does not count as movement: backed into a boss
arena's pocket it holds her there on purpose.

A player still curled when the policy picks a move that needs her standing (approach, retreat, the
shots and the crouch shot, a beam switch, a jump over, a refill run or idle) stands up first: one Slipstream tap and
the curl's frames (`StandFirst`, `tools/playtest_programs.gd`).

The driver sends `cycle_beam` presses when the physics step ends, after the player has moved
(`LATE_PRESSES`, `tools/playtest_programs.gd:24`). Measured in the check: a press sent before the
player counts twice for her (just pressed in that frame, then her queued `_input` press in the
next), so one tap stepped two beams. Every other press still goes out before the player; the second
count is absorbed by the fire cooldowns and the Slipstream curl.

## 6. Policies

- **heuristic** (`tools/playtest_policy.gd:62`): take a boss dodge when one is offered; dash into incoming shots, else duck under them; when stuck, wall-jump or
  alternate jumps; go to a refill when one is offered and no close enemy is winding up (in campaign
  mode only within 512 px, except the Harpoon refill of a live boss's room); fight the
  primary target if it is visible, given up on no longer, or the arena is sealed, else go to the
  ambush trigger, a pickup or an exit. With a boss (`tools/playtest_policy.gd:231`): walk into its arena while it is disengaged; jump over or
  back off from a close wind-up, fire the opener, harpoon it while open, switch to the opener's
  beam, walk to where the opener lines up, and keep 360 px from a boss nothing hurts (the retreat
  falls back to the approach when the arena edge is behind). Otherwise: fire crouched at a `low`
  target, harpoon a beam-immune enemy, pulse a pulse-only one, switch to a beam that hurts it, shoot or jump-shoot, jump over
  rushers closer than 130 px, and walk closer after 2.5 s of shots that do not land (three such
  tries ignore that target for 15 s).
- **random** (`tools/playtest_policy.gd:57`): a seeded uniform pick; the baseline a smarter policy
  must beat.
- **external**: the bridge in section 7. The heuristic's pick travels along as `hint` and is used
  on any failure.

## 7. Wire format

TCP on 127.0.0.1 only. The game is the client; the policy server listens (the runner picks a free
port and passes `--playtest-port`). One UTF-8 JSON object per line, newline-terminated. Protocol 1.

| Direction | `type` | Fields |
|---|---|---|
| game to server | `hello` | `protocol`, `run_id`, `room`. Sent once after connecting. |
| game to server | `decide` | `tick`, `state` (section 4), `candidates` (list of `key`, `kind`, `label`), `hint` (heuristic's key). |
| server to game | `action` | `tick` (must echo the request), `key` (one of the candidate keys). |
| game to server | `bye` | `summary` with `end_reason`, `seconds`. Sent once at the end; the server may close. |

The game waits at most `--playtest-timeout-ms` (default 1000) per decision while the game is frozen
(`tools/playtest_bridge.gd:53`), so latency costs wall time, not fairness. Fallback reasons, each
counted per run: `not_connected` (no server at start), `timeout`, `disconnected`, `bad_reply` (not
JSON, not `action`, or a non-string `key`), `unknown_key`. A reply whose `tick` is older than the
current request is skipped as a late answer. A backend exception in the Python server is answered
with a null key, so the game falls back at once (`tools/playtest/policy_server.py:109`).

## 8. Telemetry

Recorded per run by `tools/playtest_telemetry.gd`:

- deaths with room, cell, killer (the last hit within 1.5 s), boss stage or ambush wave;
- damage by source and every hit (time, room, cell, source, amount);
- kills by enemy type; time per room; stuck episodes (room, cell, start, seconds);
- ambush fights: arena, outcome (cleared, died, aborted, left_room, unfinished), seconds, wave
  reached, damage taken;
- boss attempts: outcome, seconds, stage reached, seconds per stage, boss health left, attacks
  released, damage by attack; plus boss damage taken while the player was outside its arena;
- deflects: deliberate `dash_through` attempts and turned shots (the dash's own counter);
- pickups collected; sequence-break attempts (a jump or dash within 1.5 tiles of a break start from
  `tools/campaign_breaks.py`, passed in by the runner);
- decisions per policy with mean and max latency and fallbacks by reason, and action counts.

The game does not report who hit the player, so the source is attributed by proximity when health
drops (`tools/playtest_telemetry.gd:447`): a hazard whose body overlaps the player's hitbox
(`hazard:lava`, `hazard:stalactite`, `hazard:rising_water`, ...); a shot within 170 px, credited to
a boss attack if a boss released one in the last 3 s; then a boss within 420 px, credited to its
charge while one runs and to `contact` otherwise; then a boss attack released in the last 3 s; then
the nearest enemy within 280 px; then the nearest hazard body within 320 px of her hitbox; else
`unknown`. Hazards are measured to their body rects, not their node origins: a flood's origin is its
top-left corner, a stalactite's the ceiling, and campaign lava is a `DevHazard` in `dev_hazard`,
which round 2 did not look at. Before round 2, contact within 3 s of any release was
credited to that attack. Every boss node is watched as it appears (`tools/playtest_telemetry.gd:274`),
so a boss rebuilt after a death still reports its stages and defeat.

## 9. Reports

Each run writes to its output directory (default `user://playtest/<run_id>`, the runner's default
is a new directory under the system temp dir; never the repo): `report.json` (meta, telemetry,
findings), `report.md`, `decisions.jsonl` (one line per decision with state, candidates, choice,
policy, latency and fallback; usable as a dataset, but never with Jev's answers as labels, see
section 13) and, in windowed runs, `shots/`. The runner adds `godot.log` (capped at 4 MB) and
`aggregate.json` and `aggregate.md` over all runs. A jev run also gets a `jev` field on each line of
`decisions.jsonl`, a `jev` section in `report.json`, a "Jev policy" section in `report.md` and
`aggregate.md`, and `jev_request_sample.json` (the first request body, Authorization redacted).

Findings are derived automatically, most severe first (`tools/playtest_report.gd:10`, cross-run in
`tools/playtest/aggregate.py:104`): boss win rate, the stage that killed most and the attack that
hurt most; boss damage taken while disengaged; ambush outcome, length and damage; killers; top
damage source; stalls of 3 s or more with their cell; deflect success; sequence-break attempts;
external fallbacks.

## 10. How to run

- Several seeds, heuristic, headless: `python3 tools/playtest/run.py --room fringe_03 --kit beam
  --seeds 1,2,3` with `GODOT` pointing at the editor binary.
- A boss with a fitting kit: `--room vaults_03 --spawn 3,5 --kit
  beam,slipstream,bombs,missiles,missile_tank:1`. The kit takes ability ids and pickup kinds;
  `kind:count` collects that many pickups (for example `energy_tank:2`); `missiles` means one Bolt
  Quiver, and counts add up: `missiles,missile_tank:1` is two quivers, ten Harpoons (before round 2
  the ids collided and it granted one).
- Screenshots: add `--windowed --shots 1.5` (real time, 1920x1080, one PNG every 1.5 s and one at
  each death).
- External policy: `--policy external --backend passthrough` (the passthrough answers with the hint
  and proves the bridge end to end), or `--policy external --backend jev` (section 12).
- Direct launch without the runner: `godot --path . res://tools/playtest_agent.tscn -- --test-mode
  --test-save-root=<dir>` plus `--playtest-<name>=<value>` flags: `room`, `spawn` (feet cell
  `x,y`), `kit`, `seed`, `seconds` (default 90), `policy`, `port`, `timeout-ms`, `out`, `run-id`,
  `goal` (auto, ambush, boss, none; auto ends on the room's arena clear or boss defeat plus 1 s),
  `max-deaths` (default 3), `breaks`, `shots` (`tools/playtest_agent.gd:20`).
- Re-aggregate existing runs: `python3 tools/playtest/aggregate.py <run dirs> --out <dir>`.

## 11. Adding a backend

Subclass `Backend` in `tools/playtest/policy_server.py:20`, implement `decide(state, candidates,
hint)` to return one candidate key (and optionally `start` and `close`), and register the class in
`BACKENDS`; `--backend <name>` selects it. A backend that needs settings is built by the runner
instead, as `jev` is (`tools/playtest/run.py:74`). A backend should use the labels and `hint` as
context, return quickly (the default game timeout is 1 s), and never raise for a model error:
return the hint or let the server's null-key fallback count it.

## 12. Jev backend

`--policy external --backend jev` asks TypeSafe's hosted Jev (a System One model) for each decision:
one `POST {base_url}/v1/systemone` with `Authorization: Bearer <key>`, standard library only, over
one keep-alive connection opened before the first decision (`tools/playtest/jev_backend.py:114`).
The contract comes from `.agent-reports/jev-research.md` section 1.

Request (`tools/playtest/jev_request.py:282`):

- `model`: default `jev-1.13.0`, pinned. On 2026-09-24 the API accepted it, `GET /v1/models` listed
  only the aliases `jev-latest` and `jev-preview`, and `jev-latest` answered as `jev-1.13.0`.
- `state` (`tools/playtest/jev_request.py:221`): a compact view of section 4, not the raw export.
  A `goal` sentence (defeat the boss; start the armed arena by walking in; clear the running arena;
  or explore); `player` with `health_pct`, grounded, on_wall, facing, form, dash_ready and
  harpoons left, the equipped `bolt` and `bolts_owned` by player-facing name; up to 3 `threats` with `dx_tiles`/`dy_tiles`, a `where` phrase (left, right,
  above, below), a `range` word (touching, close, mid range, far), health %, winding up, whether
  the kit hurts it, `hurt_by_bolt` (the owned bolt that would), `below_standing_shot` (the state's
  `low`), line of sight, whether it belongs to
  the arena, and boss stage, attack and `shell` (open, or closed and what opens it, in words); up to
  3 `incoming_shots` within 6 tiles with `approaching` computed in code; up to 2 `hazards` within 4
  tiles (kind, where, touching, state); `facts` (health word, nearest threat range and direction, any
  wind-up, shot incoming, in arena, arena wave line, boss stage, attack and shell, stalled, and what
  the room's refills restore); and `last_action` with how far the previous action moved the player.
  All arithmetic happens here, because Jev is weak at numbers.
- `questions`: `action` (`choice` over the candidate keys, each criterion the game's label plus a
  one-line rubric for its kind), `danger` (`score`: low, medium, high) and `unsure` (`noul`: stuck
  or unclear which action is right).
- Illegal candidates are removed in code before sending (`tools/playtest/jev_request.py:90`): a
  harpoon without ammo, a shot or jump shot without the crossbow, a pulse without the Resonance
  Pulse, a dash that is not ready, a wall jump off the wall, a jump-over while airborne, a crouch
  shot while airborne, its Harpoon without ammo or its bolt at a target the bolt does not change, and
  an approach to a boss no bolt hurts while the quiver is empty and the Harpoon refill run is offered
  (the state's `facts` then say `quiver: empty`). Each new
  round 3 kind has its own rubric line and feedback group. The hint always stays. With one option left no request is sent.

The answer's `choice` is played when it is a sent key and its `confidence` is at least
`--jev-min-confidence`; otherwise the hint is played and the reason recorded. The game is frozen
while it waits, so latency costs wall time only; the runner raises `--timeout-ms` to at least
`--jev-timeout-ms` plus 700 ms so the game does not give up first.

| Flag | Default | Meaning |
|---|---|---|
| `--jev-base-url` | `TYPESAFE_BASE_URL` or `https://api.typesafe.ai` | Server root; `/v1/systemone` is appended. |
| `--jev-model` | `jev-1.13.0` | Model id sent in each request. |
| `--jev-timeout-ms` | 800 | Per request, no retry; a late answer is a `timeout` fallback. |
| `--jev-min-confidence` | 0.35 | Below it the heuristic's hint is played (`low_confidence`). |
| `--jev-hz` | 5 | At most this many requests per game second; decisions in between repeat Jev's last answer while it is offered (`held`), else play the hint, and are recorded as `skip:rate`. |
| `--jev-budget-usd` | none | Estimated spend per run after which the hint is played (`skip:budget`). |

Sources per decision (`tools/playtest/jev_backend.py:184`): `jev`; `skip:rate`,
`skip:single_option`, `skip:no_room`; `fallback:<reason>` with `timeout`, `network`,
`low_confidence`, `bad_choice`, `bad_response`, `http_<status>`, `cooldown` (after a 429 or 529,
honouring `retry-after` up to 10 s), `rate_limit` (the 1,200 requests per minute cap, counted in
wall time) and `disabled`. A 4xx other than 429, or a missing key, disables the backend for the
rest of the run and makes the runner stop the remaining seeds, printing the status and the server's
message (scrubbed of the key, cut at 300 characters); nothing is retried.

Recorded per decision on the `jev` field of `decisions.jsonl`: chosen key, source, hint, removed
keys, confidence, the full choice probability map, danger score (0 to 2), unsure probability,
latency, input and output tokens, answering model, and the nearest threat and boss attack.

Jev feedback (`tools/playtest/jev_feedback.py:103`), in `report.md` and `aggregate.md`:

- **Confusion hotspots**: 3 by 3 tile clusters where at least two decisions had confidence below
  the threshold or a top two within 0.15 between conflicting actions (attack, close in, evade,
  travel, wait, or jumps in opposite directions). Read as "the right move is not legible here".
- **Danger peaks**: each hit is compared with Jev's highest danger score in the 1.5 s before it.
  Low danger then a hit is an unreadable hit (strengthen the telegraph); high danger then a hit is
  readable but not avoided (check the dodge window); high danger with no hit in the next 1.5 s
  counts as a working telegraph. Hits without a rating in the window are counted, not judged.
- **Disagreement**: the share of answered decisions where Jev's action differs from the
  heuristic's, with the most common pair and the threat in play.
- **Stats**: requests, answers, skips, fallback rate by reason, mean and p95 latency, tokens and an
  estimated cost at $0.042 per million input tokens (output tokens free; TypeSafe's published price
  on 2026-09-24, marked as an estimate because it can change).

Jev reads the structured state, not the screen: "readable" means the state carried a wind-up flag,
a close threat or an incoming shot, not that the visuals do. Confirm a finding in a windowed run.

Cost: a request is about 850 to 1,200 input tokens, so 5 requests per second is roughly 20M tokens
or $0.85 per hour of play (estimate). The first real runs are in section 16.

Switching to a local server: any server that speaks the same `/v1/systemone` contract works with
`--jev-base-url http://127.0.0.1:<port>` (or `TYPESAFE_BASE_URL`), for example the openjev shim or
Open-Jev-2B's `jev.server` (`.agent-reports/jev-research.md` section 3; check each model's licence
first). The backend still sends the header, so set `TYPESAFE_API_KEY` to any placeholder for a
local server that ignores it.

## 13. Data boundary

- The heuristic and random policies and the passthrough backend send nothing off the machine; the
  socket binds 127.0.0.1 only.
- A hosted backend (Jev or any API) sends, per decision, only the game state of section 4 and the
  candidate list. Never repository contents, source, logs, paths or save files.
- It needs the user's own API key, read from the environment at the moment of use and never passed
  as a command-line flag, written to a report or put in a prompt. Without the key the backend must
  refuse to start rather than fall back silently.
- Using a hosted backend is the user's explicit choice per run; the runner defaults to no network.
- Jev specifically (the user accepted this outbound edge on 2026-09-24): per request the compact
  state of section 12 (room id, relative tile positions, enemy types, health, arena and boss
  status) and the candidate keys with their labels go to `api.typesafe.ai`. The key is read from
  `TYPESAFE_API_KEY` inside each request (`tools/playtest/jev_backend.py:126`), never stored,
  printed, logged, written or passed on a command line; the Authorization header is redacted in
  `jev_request_sample.json`, and server error text is scrubbed of the key.
- TypeSafe's terms, per `.agent-reports/jev-research.md` section 4: customer requests are not used
  to train its models; retention has no fixed period ("as long as necessary"); TypeSafe may derive
  telemetry (logs, statistics, classifications) from requests and use it without restriction, in
  perpetuity. Zero retention exists only for enterprise customers on request.
- **No distillation.** TypeSafe's Master Customer Agreement forbids using its output to train a
  model that imitates it. Never train or fine-tune any model, local ones included, on Jev's
  answers: not on the `jev` fields of `decisions.jsonl`, not on its probabilities or danger scores.

## 14. Tests

- `tools/check_playtest_critic.py` (suite `playtest critic`): the Jev critic against a local stub
  `/v1/systemone` (no network): segments cut from a report (a room leaves its arena and boss
  windows out, a boss's attacks seen against landed, retries, foreseen hits), the request's five
  Scores and one Choice, answers parsed into named levels, goodness and flags, a bad answer or a
  401 recorded per segment, the budget stop, a missing key, and no key in any written file.
  `tools/check_playtest_dodge.gd` covers the boss recorder's `attacks_landed`.
- `tools/check_playtest_agent.gd` (suite `playtest agent`): option parsing and refusals, state keys
  and JSON round trip, candidate count, unique keys and real input actions only, the heuristic kills
  a hopper in a small real room built with `tools/worldfx_testbed.gd` through inputs only, telemetry
  records the kill and a shot's damage source, the bridge round-trips hello, decide and bye with a
  stub server, a silent server times out within the bound and falls back, and a missing server
  falls back. Round 2 adds: no shot at a boss far below a grounded player, no exit while a boss
  lives, a twitching drop spider exported as winding up, and kit pickups that stack. Round 3
  (`tools/check_playtest_round3.gd`, run by the same suite): the kit's beams; a closed Tidal Heart
  offers the Snare, the heuristic switches, real `cycle_beam` taps equip it, and the opener is then
  offered and chosen; a real Tidal Heart reads closed with the Snare as opener and its grate is
  found; no harpoon without bolts; a floating boss gets no jump-over and an approach without jumps;
  a Resonance Pulse is offered, chosen and really placed through inputs; the Harpoon leaves
  `hurt_by` at zero bolts; a real refill shrine is exported, walked to and refills; low health
  offers the health refill; real lava and a real falling stalactite are in the state and credited
  as `hazard:lava` and `hazard:stalactite`; a target 232 px up gets a jump shot instead of a level
  shot, and the real jump fires about 132 px up; no retreat out of a live boss's arena; at most 14
  candidates with the jumps last.
- `tools/check_playtest_bridge.py` (suite `playtest bridge`): the Python server's wire format, the
  null key on a backend error, the runner's argument vector (always `--test-mode`), and the
  cross-run findings; round 3's shell, bolt, hazard and refill facts in Jev's compact state, and
  the new kinds' rubric lines, feedback groups and legality. The jev backend runs against a stub `/v1/systemone` on 127.0.0.1, never the
  network: request shape (path, bearer header, the three questions, illegal candidates removed,
  compact state in tiles), answer parsing, the rate cap, the timeout and low-confidence fallbacks,
  a missing key (error names the variable only, no request, backend disabled), a 401 whose body
  echoes the key (backend disabled, and no written file contains the key), and the Jev findings
  and their aggregate. The crouch shot has its rubric line, feedback group and legality (dropped
  while airborne and, for its Harpoon, at zero bolts), and a low threat reads `below_standing_shot`.
- `tools/check_playtest_crouch.gd` (suite `playtest agent`): an armored guard held still 256 and
  448 px ahead on the check room floor is `low`, gets `crouch_shot:<id>:harpoon` and no standing
  Harpoon, the heuristic picks it, and its loop's crouched Harpoon hits the guard through real
  inputs (60 to 25); a spitter is not low and keeps its standing shot. On the code before the crouch
  shot all ten guard checks fail (standing `harpoon:<id>:forward` picked, 60 to 60).
- `tools/check_playtest_dodge.gd` (suite `playtest agent`): a real Stone Guardian forced into a
  stage 3 Fault Slam, Rockfall and Boulder Volley in the check room; the heuristic loop picks
  `dodge:<attack>` and takes no damage through real inputs (without the dodge it takes 24 from the
  slam and the volley); the refill run jumps over the boss under open sky and not under a roof.
- Harness round 4 (`tools/check_playtest_dodge.gd`): a real Tidal Heart forced into each
  desperation attack exports its lines, and the heuristic loop answers with `dodge:<attack>` and
  takes no damage; against the round 3 dodge it picks `approach` all four times and the
  Crosscurrent hits it.
- The refusal without `--test-mode` was run by hand: exit code 2 and the message "refusing to run
  without --test-mode (it would write to the real save)".

## 15. Known limits

- Navigation is local steering plus jumps; the agent does not path across rooms or through ball
  tunnels, so a stall can be a navigation limit rather than a level trap. Read the stuck cell and
  `decisions.jsonl` before calling it a design finding.
- Damage attribution is a proximity guess (section 8).
- The heuristic is tuned to be competent, not human-like; win rates and fight lengths describe the
  bot, and are best compared between builds or against the random baseline.

## 16. First results (2026-09-24)

- `fringe_03` with the Seed Crossbow: the beam trial clears in 5.4 s of fighting with 16 damage
  taken, all from the ceiling diver, identically over seeds 1 to 3 and through the external bridge.
  The random baseline died twice to the hopper in wave 1 in both of its runs.
- `vaults_03` entered from the west door with five Harpoons (the kit said ten; see section 10): the Stone Guardian falls in 8.9 s
  (stage 3 lasted 2.2 s, stage 4 0.8 s) with 72 damage taken, all from Boulder Volley.
- `vaults_03` started at the boss room's return point (feet exactly on the arena's bottom edge):
  the boss did not engage while the player stood still, and took 175 damage from Harpoons without
  fighting back (arena `Rect2.has_point` excludes the floor line, as the ambush leash did before
  `LEASH_FLOOR_MARGIN`).
- Hosted Jev (`jev-1.13.0`, from Europe): mean latency 245 to 256 ms, p95 284 to 410 ms, no timeout
  or HTTP error over 1,123 requests; eight 90 s runs cost about $0.05 in total (estimate).
- Jev on `fringe_03`, first request design: it chose `approach` toward the dormant ceiling diver
  nine tiles overhead in 183 of 200 decisions and never started the arena. With the armed-arena
  goal sentence and the `arena_enemy` flag it clears the beam trial in 11.9 s and 6.8 s (seeds 1
  and 2; the heuristic takes 5.4 s), with 18 and 30 % low-confidence fallbacks. Its confusion
  hotspots are cells (31, 13) and (37, 13), split between approaching and shooting the drop
  spider.
- Jev on `vaults_03` from the west door (`beam,slipstream,bombs,missiles,missile_tank:2`): three
  boss attempts per run, no win, one death per run to Shoulder Charge at stage 4. Boulder Volley and
  Fault Slam were rated high danger 28 and 22 times but only half and a third of those passed
  without damage; Rockfall was rated high 19 times and 17 passed (a working telegraph).
- The heuristic with the same kit left `vaults_03` after 4.1 s and did not return in 90 s, unlike
  the earlier win above; boss scripts were being changed on the branch at the same time, so the
  two vaults results are not yet a clean comparison.

## 17. Results round 2 (2026-09-24)

Same setups and seeds as section 16: `fringe_03` with `--kit beam`, and `vaults_03` with `--spawn
3,5 --kit beam,slipstream,bombs,missiles,missile_tank:1` (ten Harpoons now; round 1's Jev and
heuristic runs also had ten), seeds 1 and 2, heuristic and Jev.

Causes found in round 1 and what changed:

- **The heuristic left the boss room; no game regression.** From the ledge at the spawn the
  Stone Guardian is 484 px below; the only aim a grounded player has is forward, so every Harpoon
  missed. With ten Harpoons (five in the section 16 win) it was still on the ledge when a rock
  knocked it back to the west door, the boss dropped out of sight and `go_to_exit` won. Commit
  10a4cae only widens the arena test at the floor line and did not change this. Fixes: no shot
  or Harpoon is offered without an aim that reaches the target, and no exit while a boss lives.
- **Jev had actually won once per run.** A boss rebuilt after a death had no telemetry signals,
  so its defeat read as `left_room` and the goal never ended the run; a dead player also opened a
  0.8 s ghost attempt. Both are fixed, and body contact is no longer credited to the last attack.
- **Danger peaks.** A scripted dodge probe in the real arena (see
  [boss-rework.md](boss-rework.md#5-stone-guardian)) showed that Fault Slam and Rockfall have
  fair answers the agent did not choose, and that the stage 3-4 volley and the Shoulder Charge at
  the west end had none. Only those two changed.
- **Drop spider.** The state never flagged its twitch, and with the real art the twitch drew no
  visible change (glow and eye glint exist only in the placeholder), so only the creak warned.
  Now the state carries the wind-up, and the twitch shakes the body, brightens the thread and
  draws a dashed line to the locked stop point. Its 0.3 s timing is unchanged.

| Measure | Round 1 | Round 2 |
|---|---|---|
| fringe_03 heuristic | 2/2 cleared, 5.4 s, 16 damage (ceiling diver), 0 deaths | unchanged |
| fringe_03 Jev | 2/2 cleared, 11.9 / 6.8 s, 128 damage (drop spider 98, diver 16, hopper 14), 0 deaths | 2/2 cleared, 8.0 / 6.2 s, 86 damage (hopper 42, drop spider 28, diver 16), 0 deaths |
| Jev hotspot (31, 13) | 16 of 22 unsure, mean confidence 0.42 | 3 of 10, 0.57 |
| Jev hotspot (37, 13) | 10 of 12 unsure, 0.32 | 5 of 8, 0.35 |
| vaults_03 heuristic | 0/2 won, left the room at 4.1 s, 24 damage each, ran out the 90 s | 2/2 won in 8.9 s, 48 damage each (volley 24, slam 24), 0 deaths |
| vaults_03 Jev | no win recorded, 1 death per run (Shoulder Charge), 90 s, 344 damage (contact 144, volley 120, slam 48, rockfall 24, charge 8) | 2/2 won at the first attempt, 10.4 / 9.7 s, 0 deaths, 144 damage (contact 72, volley 24, slam 24, charge 24) |
| Jev danger peaks passed unhurt | volley 15/28, slam 7/22, rockfall 17/19, charge 0/4 | volley 10/14, slam 0/6, rockfall 5/5, charge 1/3 |
| Jev cost (estimate) | $0.034 | $0.008 |

Read with care: round 2 fights are short, so the peak counts are small; the attribution change
moves contact damage out of the attack rows; and a danger peak is keyed on the boss's last attack
even while it idles, so "slam 0/6" counts contact and other hits within 1.5 s of a slam. The probe
gives Fault Slam 0.33 to 0.67 s jump windows; in round 1 Jev answered it with `retreat`.

## 18. Results round 3 (2026-09-24)

Round 3 answers the harness findings of the sweep reports (`.agent-reports/jev-sweep-*.md`): beam
switching and boss openers, the Resonance Pulse, ammo truth and refills, lava and falling spikes in
the state and the damage record, the jump shot, and boss-room bounds. Setup as the sweep:
`depths_02` from the west door (`--spawn 1,14`) with the first-arrival kit
`slipstream,beam,long_beam,bombs,pressure_seal,ice_beam,wave_beam,high_jump,undertow_dash,missile_tank:7,energy_tank:3`
(Echo equipped at the start, 35 Harpoons, 400 health), 150 s; the Boss Rush on its own kit, 300 s.
Headless, one run at a time. Runs are under `/Volumes/Personal/Tools/hollowtide-runs/harness/`.

| Run | Sweep (before) | Round 3 |
|---|---|---|
| depths_02 heuristic s1 | died at 142.8 s, Tidal Heart 400/400; 400 damage (contact 270) | won in 10.7 s (stages 5.7 / 1.2 / 1.3 / 2.5 s), 0 damage |
| depths_02 Jev s1 | 400/400, left the room at 110.7 s; 320 damage (contact 270) | won in 12.7 s, reached stage 4, 10 damage (Crosscurrent) |
| depths_02 Jev s2 | 400/400, left the room at 116.9 s; 380 damage (contact 290) | won in 12.6 s, reached stage 4, 0 damage |
| Boss Rush heuristic s1 | not finishable (Tidal Heart invulnerable) | cleared in 40.25 s, 3 hits, 34 damage |
| Boss Rush Jev s1 | Tidal Heart untouched for 270 s | cleared in 40.2 s, all three bosses to stage 4, 5 hits, 62 damage (Ember Fan 28) |

- Jev picked the openers itself: in the two depths_02 runs its own answers included
  `select_beam` 2 and 2 times and `open_boss` 7 and 6 times; in the Boss Rush `select_beam` 5 and
  `open_boss` 4 times. Fallbacks: 4 of 49 and 2 of 50 calls on depths_02, 29 of 150 in the Boss
  Rush. Estimated cost: $0.0047 for both depths_02 runs, $0.0066 for the Boss Rush.
- Body contact with the Tidal Heart dropped from 270 to 290 per run to 0: the approach no longer
  jumps into a floating boss.
- For the room owners (not a harness change): with a working opener the bot beats the Tidal Heart
  in about 11 to 13 s with at most 10 damage, and stage 1 lasts 5.7 s in every run. Compare with a
  human run before reading it as a balance finding.

## 19. Campaign mode and run safety (2026-09-28)

`python3 tools/playtest/run.py --campaign` starts a new game in the start room with an empty kit
(no teleports, no grants) and plays toward the ending. `tools/playtest/campaign_route.py` plans
the objectives with the campaign graph solver and writes one flow field per objective; the game
side (`tools/playtest_campaign.gd:100`) adds the goal to the state and offers `go_to_objective`,
`go_to_door`, `open_gate`, `freeze` and `fast_travel`. The planner only sets goals; the policy
picks the move. While a gate or a floater on the route can be handled from where the player
stands, `go_to_objective` is not offered, since following the route cannot get past it; while it
is offered, the route's own `go_to_door` plays the same route-following program. An
objective has 300 game seconds; a timed-out objective is set aside, a second timeout ends the run
(`tools/playtest_progress.gd:30`). Deaths do not end a campaign run; the 2,700 s cap does.
Like a player, the route also takes a Bolt Quiver or an energy tank lying within 50 solver steps
while a boss is still ahead (`EXTRA_DETOUR` in `tools/playtest/campaign_route.py`; on the current
map the vaults_02 quiver, the kiln_01 energy tank and the kiln_02 quiver, 16 objectives in all).
Such an objective is `optional`: it gets 120 s and is left behind after one timeout. `run.py
--minimum-kit` plans the required items only (13 objectives), the question round 1 left open.

Navigation fixes from the first full runs (`tools/playtest_nav.gd`): a jump peaking below a target
straight overhead steers into the nearer shaft wall so the wall jump the solver planned happens
(`_wall_start`, line 242); a player on a ledge's lip above a drop steps on with a 1 px dead zone
instead of 10; a one-frame touchdown on a cell the hop passes keeps the hop (`_on_hop`, line 125);
a straight jump blocked because the body overlaps a wall column above first steps to the cell's
centre (`_takeoff_side`, line 357); in the air, flying a row above a hop cell counts as passing it,
so the target no longer stays behind her and pulls her back into a lava pit (`control`, line 165).

Run safety: the launch scene ends a run as `hung` when no decision is made for
`--playtest-hang-ms` of wall time (default 30 s) and writes `hang.json` with the pause, root
flags, open menu, program, held and pressed actions (`tools/playtest_agent.gd:250`). It writes
`heartbeat.txt` every 20 s of wall time; the runner kills a process whose heartbeat and output
have been silent for 120 s, or that passes `--wall-limit` (`tools/playtest/run.py:44`). Piped Godot
output is block-buffered, so the heartbeat file, not stdout, is the liveness signal. The Jev
backend stops calling after an estimated `--jev-budget-usd` and plays the hint (`skip:budget`,
`tools/playtest/jev_backend.py:220`). The runner starts Godot with its own HOME and XDG folders
under the run directory (`tools/godot_env.py`), so user:// (settings.cfg, logs) never lands in the
player's folder, and it leaves the Jev key out of Godot's environment.

First full runs (seed 1, `/Volumes/Personal/Tools/hollowtide-runs/full2/`, not in the repo): Jev
reached 11 of 13 objectives in 1,949 game seconds and stopped at the Tidal Heart (two 300 s
timeouts; 20 deaths; about $0.19). The heuristic stalled earlier on the same build.

Round 2 (2026-09-28, `/Volumes/Personal/Tools/hollowtide-runs/full3/`, not in the repo). Probes in
the real rooms found harness gaps, not game faults, at the Tidal Heart (Harpoons fired through
rock, in volleys within one opening, openers from under the ledge, no refill walk from far away)
and the Cinder Warden (no way to curl under the Ember Fan, shots from outside the arena), and a
layout fault in kiln_01 (both vent flyers patrolled above lava; moved, and the graph check now
refuses it). With the minimum-route kit Jev beat the Tidal Heart in a room probe on its third try
(113.5 s). Three full campaign runs then stopped at 4, 5 and 6 of 13 objectives, each on a new
harness defect fixed afterwards: the route's door steered in place above a floor gate, shots
whose line missed the enemy, and a health refill 600 px straight up; the last fix has checks
only, no full run.

## 20. Boss dodges (2026-09-29)

Round 3's first full Jev run (`jev-r1`, `/Volumes/Personal/Tools/hollowtide-runs/round3/`) stopped
at the Stone Guardian with the minimum kit (100 health, 5 Harpoons): 16 attempts, 15 deaths, 12 of
them in stage 3; damage contact 628, Fault Slam 408, Boulder Volley 316, Rockfall 196. Jev mostly
chose `retreat`, which only pressed her into the west pocket; the plain jumps it had were labelled
stall breakers, `jump_over` jumps toward the boss, and a 3 s stall in the pocket made the hint jump
into the boss.

A dodge probe in the real vaults_03 arena (real player, stage 3 attack forced, 13 responses at 17
start times each, 0.1 s apart) found an answer to every attack in both places the fight happens:

| Attack | West pocket (feet x 284, boss stopped 192 px away) | Open floor (boss 416 px away) |
|---|---|---|
| Fault Slam | jump in place, started 0 to 0.8 s into the telegraph (9/17) | jump in place 0.5 to 1.3 s in (9/17), a short jump 0.2 to 1.4 s in |
| Boulder Volley | jump 0.1 to 0.7 s in (7/17), roll under the low roof 0 to 0.7 s | run away (17/17), jump 0.6 to 1.3 s in |
| Rockfall | curl and roll under the low roof (14/17); every step toward the boss is hit | step about 110 px away (13/17) |
| Shoulder Charge | stand still (17/17): it stops short of the pocket | run away 0 to 0.9 s in (10/17) |

So the fight is fair at 100 health; the agent lacked the answers. `dodge:<attack>`
(`tools/playtest_dodge.gd:60`) plays them: jumps start 0.45 s before the shockwave or the rock
reaches her (0.15 to 0.9 s cleared), with a second jump 0.85 s later for the desperation double
slam; Rockfall and Vent Burst walk to the nearest spot at least 92 px from every locked column and
140 px from the boss body, or roll under a low roof when none is on her floor; the charge runs into
the pocket no closer than 60 px to the arena edge. The labels say what the move does and that a
retreat does not outrun the slam; Jev's rubric asks to prefer it while it is offered.

Also from the same runs: an empty quiver in the west pocket walks through the boss to the arena's
Quiver Cache (24 contact per trip); under the west platform there is no room to jump the body, so
the refill run jumps it only where 240 px of air is free above it. The boss approach kept stepping
out of the 260 px deep east pocket for its 320 px firing range, disengaging the boss each time (a
Jev probe looped there for 180 s); it now stops 48 px inside the arena.

Room probes, vaults_03 from the west door with the objective-7 kit (100 health, 5 Harpoons), 240 s,
5 deaths at most (`sg-*` under the round 3 directory):

| Run | Before | After |
|---|---|---|
| heuristic | 0 of 5 won, all died in stage 2 (contact 252, slam 2 kills) | won the first attempt in 53.6 s, 96 damage (contact 72 from refill trips) |
| Jev | 0 of 16 in `jev-r1` | 0 of 5 won, all reached stage 4 (boss 37 to 75 health left); contact from refill trips the main loss |
| Jev, 10 Harpoons | not run | won the first attempt in 50.0 s, 72 damage |

Later round 3 runs added more:

- `jev-r2` (16-objective route) stopped in vaults_02 on the Updraft Cloak: at 10 health Jev chose
  `retreat` from a bat 500 px away 1,554 times, pressed into the east wall, and the held intent
  repeated it for 500 s. `retreat` is now offered only from a threat within 420 px and never with a
  wall 24 px behind her; a boss pinned too close falls back to `idle`, not `approach`.
- `jev-r3` stopped in fringe_03 on the first Bolt Quiver: the beam trial aborted, re-armed, and Jev
  chose `go_to_ambush` 2,900 times from a ledge straight above its trigger, where the straight steer
  stands still. In campaign mode `go_to_ambush` is offered only on the trigger's floor.
- Cinder Warden room probes (objective-12 kit: 200 health, 15 Harpoons): a heuristic win, then Jev
  idling 268 s 28 px outside the arena once the retreat was withheld there (the heuristic now walks
  into a disengaged boss's arena, and the label says so), then Jev rolling for 110 s in ball form
  after a missed stand-up tap (fixed by `StandFirst`). A dodge probe at cell 26 found the Ember Fan
  cleared by curling in place (15/17), the Heat Ring by standing (17/17) and the Scuttle Rush by
  running away within 0.9 s (10/17); those answers joined the dodge table. Jev then beat the Cinder
  Warden at the first attempt in 69.1 s (182 damage).

With these fixes `jev-r4` (seed 1, fresh new game, 16-objective route) reached the ending at 754.2
game s with 10 deaths: Stone Guardian on the second attempt (50.4 s), Cinder Warden on the second
(75.7 s), Tidal Heart on the first (85.2 s); about $0.10.

Most of that run's damage was in vaults_01/02 (objective 4: 641 damage, 4 deaths in the vaults_01
ambush, 621 of it from armored guards) while Jev shot the ambush's other enemies. A charge probe on
the vaults_01 floor (real player, guard 384 px away, 9 start times per response) found the answer:
a jump toward the guard started 0.05 to 0.3 s into its 0.42 s wind-up cleared 6 of 9; standing or
curling 0 of 9. So the guard is fair, and a winding-up guard on her floor now gets
`dodge:<id>` (jump toward it about 0.85 s before the charge would reach her). A Jev vaults_01
ambush probe afterwards cleared it on the third try with 94 guard damage over three tries; the full
run was not repeated (all four runs used). The heuristic's full run on the final build before the
guard dodge stopped at 5 of 16 in vaults_02 (13 deaths, 1,536 damage in the vaults, the floater chain
at (28, 13) again).

## 21. Harness round 4 (2026-09-30)

**Tidal Heart dodges.** Round 3 left the Tidal Heart without answers. A dodge probe in the real
depths_02 arena (real player, attack forced at stage 3 and 4, 14 scripted responses at 17 start
times 0.1 s apart, six player and boss positions; outputs under
`/Volumes/Personal/Tools/hollowtide-runs/harness2/probe/`) found:

| Attack | What clears it |
|---|---|
| Tide Ring | standing or curling in place wherever she is off the radial lines (17/17 at most spots) |
| Surge Lance | leaving the locked line: a step, a run or a roll away (9 to 17 of 17); standing or curling in place never |
| Crosscurrent | curling in place under a lane that passes above the ball (17/17); a low lane on a flat floor needs a jump as the beads arrive; the pillars block the low lane for most floor spots |
| Maelstrom | curling in place under a boss above her (17/17); with the boss 600 px away only running or rolling away (17/17) |

Every Tidal Heart shot is a point on a straight line (`scripts/combat/enemy_projectile.gd` hits by
raycast), and the plan locks each line at the telegraph, so the answer is geometry, not a table:
`tools/playtest_tide.gd` takes `shots_rel` and picks the spot nearest her feet (up to 320 px, never
past or under a low body) where no line reaches the standing body before rock stops it, else the
curled one, and holds there until the last line has passed; with no such spot, a low horizontal
lane is jumped 0.2 s before its first bead and a high lane after it is curled under on landing.
The same probe with the heuristic loop as the response (the agent starting at each of the 17
times, 8 positions, stages 3 and 4, 1,088 cases): 504 clear with the round 3 harness, 1,007 with
the dodge; all 81 remaining hits land within 0.3 s of the agent's start, before any answer can
move her.

**vaults_02 floater chain.** heur-r1 (round 3) died five times at vaults_02 (28, 13): the frozen
floater it stood on had sunk 34 px below the solver's resting row, the feet cell read one row too
low, so the route status was `off_field`, the rejoin steer aimed at the spot it already stood on,
and it waited until the floater thawed under it. The navigator already read feet up to 32 px into
the next row as the row above (`FLOATER_SAG`); that margin is now 48 px (feet on real ground sit
64 px into their row), in `tools/playtest_nav.gd`. `tools/check_playtest_campaign.gd` covers it
(34 px reads as the row above, 64 px does not; the first case fails at 32).

**Heuristic campaign run** (`heur-h1`, seed 1, fresh new game, 16-objective route, both fixes;
`/Volumes/Personal/Tools/hollowtide-runs/harness2/heur-h1/`): reached the ending at 1,399.9 game
seconds, 16 of 16 objectives, 16 deaths. heur-r1 had stopped at 5 of 16 on the floater chain.
Stone Guardian and Cinder Warden fell at the first attempt; the Tidal Heart took 577 s (one 300 s
timeout, 2 deaths, 700 damage). Deaths: 10 to armored guards in the vaults_01 ambush, 2 falls
from the floater chain at (24, 15) (it got past both times), 1 each to a stalker and a guard in
vaults_02, 2 at the Tidal Heart.

Open: in heur-h1 most Tidal Heart damage (28 of 42 hits, credited to Surge Lance) came while a
`dodge:crosscurrent` program was still running: behind a depths_02 pillar the answer to a lane
that crosses the whole arena is to stand still for up to 5 s, and the next attack starts before
that. Ending a dodge when the boss telegraphs its next attack is the likely fix; two check-room
setups (a stage 4 chain, and a stage 2 rotation behind a pillar) did not reproduce the hit on the
current code, so it is not in this round.

## 22. Jev critic (2026-09-30)

`--critic` on `tools/playtest/run.py` (or `python3 tools/playtest/jev_critic.py <run dir>...` on a
finished run) asks Jev to rate every segment of the run: each room's traversal, each arena and
each boss fight, one entry per id in play order. It runs after the game has ended, from the run's
`report.json` and `decisions.jsonl`, so no rating request competes with the policy's real-time
decisions; the summary is the same one a live hook would send.

Per segment, code builds the state: seconds (a room's time minus its fights), attempts and
retries (a room counts its failed objective attempts), deaths, damage by source, hits, stuck
seconds, the arena's best wave or the boss's best stage, per boss attack how often it was seen,
landed and escaped (a landed attack is one that dealt damage, counted once however many hits it
dealt; `attacks_landed` in the boss telemetry), the run's median time for the same kind of
segment, and Jev's own play there (`jev_play`: decisions, mean confidence, low-confidence share,
mean danger and high-danger share, and hits foreseen or not, as in the danger peaks of section 12).

One POST per segment asks five Scores with three described levels each, difficulty (too easy,
fair, too hard), fairness (were the hits avoidable: no, partly, yes), readability (unclear, some
unclear, clear), pacing (boring, good, hectic) and fun (low, medium, high), and one Choice for the
main problem over none, unfair_hit, unclear_warning, too_long, too_short, navigation_confusing,
too_hard and too_easy. Every probability and confidence is kept in `ratings.json`; `ratings.md`
has one row per segment and the scorecard. Composite scoring happens in code: a dimension's
goodness in 0..1 is P(fair) for difficulty, P(good) for pacing and score / 2 for the others, and
the overall is weighted 0.25 difficulty, 0.25 fairness, 0.2 readability, 0.15 pacing, 0.15 fun.
A segment is flagged when Jev puts at least 0.4 on too hard, unfair (no), unclear or boring, or
its main problem is unfair_hit, unclear_warning, too_long, too_hard or navigation_confusing with
confidence 0.4 or more. A flag is a lead for a probe in the real room, never a change on its own.

Jev reads numbers, not the screen: "readability" is judged from whether its own danger rating was
high before a hit, and "fun" is a guess from the same facts. The critic stops at
`--critic-budget-usd` (default $0.05 per run) and uses the policy's key handling (section 13).

**Rated runs 2026-09-30** (seed 1, fresh new game, 16-objective route, Jev policy and critic;
`/Volumes/Personal/Tools/hollowtide-runs/critic/`). `full-jev-a` stopped at 11 of 16 objectives:
it spent 120 s firing the Snare at an already frozen kiln_01 mimic and never took the energy tank,
then lost all 12 Cinder Warden attempts with 100 health. Critic overall 0.68; worst the Warden
(0.29: too hard 1.00, pacing boring 0.98, main problem too_hard 0.92). Two harness fixes and one
game fix followed. The Jev backend drops a crossbow shot at an ordinary enemy that no bolt hurts,
or at one the equipped Snare has already frozen (`_bolt_matters` in `jev_backend.py`; the heuristic
never fires these; it also cost 40 s of seed bolts at a vaults_01 armored guard). The critic keeps
a death that lands a rounding step past a fight's end, and stuck time inside a fight, out of the
room's numbers (the room had read as navigation_confusing from an arena's stuck time). The Warden's
patrol now turns at the charge pocket ([boss-rework.md](boss-rework.md#6-cinder-warden)).
`full-jev-b`, same seed with all three: the first Jev run to reach the ending, 16 of 16 in 974.8
game seconds, 7 deaths, every boss at the first attempt (Warden 65.7 s). Critic overall 0.68, boss
group 0.53 to 0.83.

Standing shots pass over the armored guard and often over the stalker: a real-input probe in the
vaults_01 pit (guard held still 256 to 560 px ahead) hurt it with 0 of 3 standing Harpoons and 1 of
3 crouched ones, and bolts never (by design). Crouched low fire is the intended answer (game-feel
contract, grounded crouch shots), and the agent has no crouch-shot program yet, so its slow, costly
vaults_01 arena and vaults_02 (both rated too hard and too long in `full-jev-b`) are an agent
limit, not a game change. Adding a crouched shot for targets below the eye line is the next
harness step.

`full-jev-d` (seed 2, all fixes) reached 14 of 16: Stone Guardian and Cinder Warden fell at the
first attempt, then the Tidal Heart objective timed out after 582.6 s in stage 2 with no death
(critic: too_long, boring). For 570 s the agent stood at depths_02 cell (27, 10) facing left with
the boss 160 px to its right, choosing `open_boss` (a Snare shot forward) 1,127 times; the shot
program presses `move_right` for two frames first, yet the state never showed her facing right.
Two real-input probes in that room (boss held at stage 2, 15 offsets) could not turn her either,
so no shot ever flew toward the boss. The cause is not isolated (a probe artifact after
`reset_for_spawn` is not ruled out); it is the first item for the next round, with no change
made. `min-jev-c` (`--minimum-kit`, seed 1) stopped at 5 of 13: 300 s in vaults_02 alternating
`go_to_refill` with the route to the Updraft Cloak (an agent loop, no game change). Estimated Jev
spend for all rated runs, probes excluded (they use no Jev): $0.49.

## 23. Crouch shot (2026-09-30)

Standing shots pass over the armored guard: its art, and so its projectile hurtbox, reaches 130 px
above its floor, while the standing crossbow fires 161 px up (the Harpoon's 14 px body leaves a gap
of about 24 px). The shot visibly flies over the art, so this is not a readability defect; the
game-feel contract's grounded crouch shot (72 px up) is the answer, and the agent had no program
for it. Measured in the same pit: a grasshopper (top 132 px up), a crawler (71) and a burrower (73)
are low too; a spitter (174) and a hopper (origin 90 px up, top 247) are not.

`crouch_shot` (section 5) fixes it. Real-input probe in the vaults_01 pit (guard held still 192 to
560 px ahead, six distances, the harness's own programs): standing Harpoons hit 0 of 6, crouched
ones 6 of 6. Heuristic room run of the vaults_01 arena (seeds 1 and 2, 90 s, kit beam, slipstream,
bombs, missiles, missile_tank:1): before, cleared 0 of 4 fights, the guard never killed and the
arena's stall abort after 45.2 s; after, cleared 2 of 2 in 8.4 s with 38 damage and the guard
killed.

## 24. Refill reach (2026-09-30)

`min-jev-c` (section 22) stopped in vaults_02 at 12 health with no Harpoons. Its decisions show two
loops, both the refill run: from t=351 s to the end at 804 s Jev chose `go_to_refill:save` in the
shaft between the lower hall and the upper floor (cells 36 to 38, rows 20 to 24), wall-jumping
between its walls toward the save shrine behind the shaft's east wall; earlier it ran from the
upper floor at (33, 14) toward the upper shrine, fell down the shaft, and the route climbed back.
The heuristic never chose these runs (its campaign limit of 512 px kept them out); Jev did (0.71 at
t=352.8 s). The cause is in the harness, not the game: the run is a straight steer that runs and
jumps what blocks it, yet it was offered for any refill no more than 320 px above the feet,
measured from feet in the air, through walls and across gaps.

`tools/playtest_reach.gd` now offers it only where that steer arrives: the climb is measured from
the floor under her, a line at crossbow height or at a jump's apex must be free of rock, and no
floor sample on the way may lie more than 320 px below the refill. The refill check covers each
case in a built room (wall, gap, mid-air above the floor) and a block a jump clears.

Real-input probe in vaults_02 (min-jev-c kit and route, 12 health, no Harpoons, enemies removed but
the frost floaters, a policy that takes any offered refill, 60 game seconds, no Jev): before, 230
of 233 decisions were `go_to_refill`, the route never got closer than 66 steps and the agent ended
in the shaft; after, none were, and the route reached the floaters at (28, 13), 26 steps from the
Updraft Cloak, where the floater crossing is the next obstacle. The same straight steer drives
`pick_up` and room-mode `go_to_exit`, and a room-mode probe steered 161 of 161 decisions at the
vaults_02 energy tank behind the shaft wall; both now take the same reach test. The same probe
afterwards chose neither in 400 decisions (room mode has no route, so she stands). The reach check
(`tools/check_playtest_reach.gd`) covers all three steers; on the old code it fails six cases.

The rated run `t4-full-s1` (seed 1, round 5) then stopped at 5 of 16 in vaults_02 on the same
floater crossing: for 450 s the agent froze the floater at (28, 13), stood on it with its feet
6 to 34 px into the row below the solver's resting row, and walked west for the hop's running
takeoff. At the next column the feet cell (27, 13) was neither a field entry nor on the hop, since
only the feet cell itself was read one row up (section 21), so the program ended off the route, she
turned back, and the floater thawed and dropped her into the hall. The lip probe and the hop check
now read the row above too (`_rest_rows` in `tools/playtest_nav.gd`). Real-input probe from
(33, 14) with that run's route and kit, enemies removed but the floaters, four floater phases:
before, the Updraft Cloak took 118.1, 119.1, 116.6 and 26.4 s; after, 27.9, 26.9, 25.4 and 5.3 s.

**Opener out of line.** `t4-min-s1` (`--minimum-kit`, seed 1) reached 11 of 13 and then held the
Tidal Heart in stage 3 for 585 s: from depths_02 (38 to 39, 14) its grate was in sight 740 px across
and 352 px up, which no grounded aim lines up with, so neither `open_boss` nor a firing spot was
offered, and Jev chose `shoot` at the closed boss 2,605 times. The opener now counts as `visible`
only when a grounded aim also lines up with it (`tools/playtest_boss.gd`), so the state names the
firing spot, and the Jev backend drops a bolt shot at a boss no bolt hurts, as it already did for
ordinary enemies (`_bolt_matters` in `tools/playtest/jev_request.py`). Room runs from (39, 14)
with that kit, Jev policy and critic, 300 s: before, 0 of 3 attempts won, 2 deaths, rated 0.38
(too hard, boring); with the spot only, 0 of 2, 1 death, 0.58, 899 body shots; with both, won the
first attempt in 106.1 s with no death, rated 0.82 (fair, good pacing, fun high).

## 25. Harness round 6 (2026-09-30)

**Empty quiver at a boss.** `t4-min-s1b` (section 24) held the Tidal Heart at stage 1 for 300 s:
with no Harpoons Jev chose `approach` 1,880 times at depths_02 (24 to 25, 10) while
`go_to_refill:missilerefill` was offered and was the hint. A room run from (24, 10) with the
minimum kit (Jev policy, 150 s) reproduced it: of the decisions with the refill run offered, 198
were `approach`, 100 of them Jev's own answer at about 0.65 confidence and the rest held between
calls; the boss was unfinished at stage 2. Nothing in Jev's state said that closing in is useless
with an empty quiver. The Jev backend now drops that approach (`_refill_first` in
`tools/playtest/jev_request.py`) and the facts carry `quiver: empty`. The same room run afterwards:
no approach while the refill run was offered (29 refill runs), boss defeated in 99.4 s, no death.
`test_empty_quiver_at_a_boss_takes_the_refill_run` in `tools/check_playtest_bridge.py` fails on the
old code.

**Frozen floaters shot down.** The first minimum-kit run of this round (`r6-min-s1`) stopped at 5
of 13 in vaults_02 (two 300 s timeouts on the Updraft Cloak). After freezing the floater at
(28, 13) the `freeze` candidate was no longer offered, so the platform guard of section 5 lapsed:
Jev switched to the seed bolt ("it hurts frost_floater") and shot the frozen floaters, killing all
four; from then on every route walk west from (31, 14) fell to the hall at row 31 and climbed back,
for 580 s. The state now marks a floater an upcoming hop stands on as `platform` whether frozen or
not (`Floaters.platforms`, `tools/playtest_loop.gd`), and such a floater gets no fight options. A
new case in `_test_shots_that_can_land` (`tools/check_playtest_campaign.gd`) fails on the old code
(an approach and a shot at the frozen platform floater).
