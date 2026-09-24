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
  `Input.parse_input_event` and `Input.flush_buffered_events` (`tools/playtest_programs.gd:198`). It
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
| Candidates | `tools/playtest_actions.gd:35` | 6 to 14 labelled macro actions, each a per-frame program of held actions (section 5). |
| Programs and driver | `tools/playtest_programs.gd:151` | Builds the per-frame programs and plays them as input events. |
| Aim | `tools/playtest_aim.gd:50` | Which aim lines a bolt up with a point, where to stand for it, when a jump shot fires. |
| Boss facts | `tools/playtest_boss.gd:41` | Protection phase, open shell, opener table and arena for the state. |
| Hazards | `tools/playtest_hazards.gd:43` | Hazard bodies as rects, shared by the state and the damage attribution. |
| Policies | `tools/playtest_policy.gd:44` | `heuristic` and `random`; `external` goes through the bridge. |
| Bridge | `tools/playtest_bridge.gd:53` | TCP client for the external policy (section 7). |
| Telemetry | `tools/playtest_telemetry.gd:61` | Signals and per-frame sampling (section 8). |
| Report | `tools/playtest_report.gd:10` | Findings, `report.json` and `report.md`. |
| Runner | `tools/playtest/run.py:70` | Launches Godot per seed, hosts the policy server, aggregates. |
| Policy server | `tools/playtest/policy_server.py:57` | Serves one game connection with a backend. |
| Jev backend | `tools/playtest/jev_backend.py:391` | Hosted Jev or any `/v1/systemone` server (section 12). |
| Jev feedback | `tools/playtest/jev_feedback.py:103` | Confusion hotspots, danger peaks, disagreement (section 12). |
| Aggregate | `tools/playtest/aggregate.py:28` | Cross-run findings over several seeds or runs. |

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
| `kit` | `abilities` (internal ids), the equipped `beam` and the owned `beams` in `cycle_beam` order (GameState ids `base`, `ice`, `wave`), `missiles`, `max_missiles`. |
| `enemies` | Up to 6, nearest first: stable per-run `id` (`e1`, ...), `type`, `rel`, `dist`, `health`, `max_health`, `is_boss`, `telegraph` (wind-up showing, a surprise enemy's wind-up glow included), `ambush`, `hurt_by` (damage kinds usable on it now, from the enemy's own `is_vulnerable_to`: the equipped beam kind, `missile` only while a shot's worth of Harpoons is left, `bomb`, `undertow`), `switch_to` (an owned, unequipped beam that hurts it when the equipped one does not, else ""), `visible` (no tile on the line from the crossbow). Bosses add `stage`, `attack`, `attack_state`, `engaged`, `phase` (protection phase), `open` (the shell is open to the Harpoon), `opener` (null, or `beam`, `via` body, grate or punish, `owned`, `point_rel`: where the opener must land) and `arena_rel` (the arena rect as x0, y0, x1, y1 relative to the feet). |
| `projectiles` | Up to 8 enemy shots within 900 px: `rel`, `vel`, `style`. |
| `ambush` | The room's arena or null: `id`, `state` (armed, sealing, fighting, cleared, intermission), `wave`, `waves`, `alive`, `trigger_rel`, `inside`. |
| `exits` | Doors from the room index: `id` (`edge:target`), `rel`, `gated`, `gate` kind. |
| `pickups` | Up to 4 uncollected progression pickups: `id`, `kind`, `rel`. |
| `hazards` | Up to 4 hazards within 1200 px of the player's hitbox, measured to the hazard's body rect (`tools/playtest_hazards.gd:43`): `kind` (lava, fire, steam from the `dev_hazard` group; stalactite, crusher, crumble, heat, rising_lava, rising_water), `rel` (nearest point of the body), `size`, `gap` (px between the hitboxes, 0 when touching) and `state` (a spike's, flood's or crusher's phase). |
| `refills` | Up to 3, nearest first: shrines in the room (`save`, `refill`, `missilerefill`) and dropped refills, with `kind`, `restores` (health, harpoons) and `rel`. |

## 5. Candidates

`idle` is always first and the two plain jumps always last; the rest follow a fixed priority and
the list is cut at 14 (`tools/playtest_actions.gd:35`). The fight options aim at one primary target:
the nearest visible enemy the kit can hurt, bosses always included (`tools/playtest_actions.gd:342`).

| Key | Offered when | Program |
|---|---|---|
| `approach:<id>` | An enemy exists | Walk toward it; jump when a wall blocks or it is above; wall-jump when clinging below it. For a boss: walk, never jump, to the spot where a grounded bolt lines up with its opener point while the shell is closed, else with its body (320 px off a level target, along the 45 degree aim for a higher one). |
| `retreat` | An enemy exists; for a live boss only while its arena reaches at least 160 px behind the player | Run away from it for 12 frames. |
| `open_boss:<id>:<aim>` | A closed boss whose opener beam is owned and equipped, and an aim whose bolt passes within 100 px of its body (Snare) or 72 px of its grate's centre (Echo) | Fire the opener along that aim. |
| `shoot:<id>:<aim>` | Beam owned, not in ball form, target within 1100 px and an aim reaches it (none when the player is grounded and the target is more than 160 px below the feet, none level at a target more than 80 px above the crossbow; for a boss the bolt line must pass within 100 px of its centre) | Face it, hold the aim (forward, up, diag_up, and down or diag_down in the air), tap `fire_beam`. |
| `jump_shoot:<id>` | Grounded, no standing aim reaches a non-boss target up to 240 px above the crossbow | Jump straight up and fire level on the frame the crossbow reaches its height (`tools/playtest_aim.gd`, Updraft Cloak speed when owned). |
| `harpoon:<id>:<aim>` | A shot's worth of Harpoons left, an enemy the Harpoon hurts that is a boss or immune to the beam, and an aim that reaches it | Same with `fire_missile`. |
| `pulse:<id>` | Resonance Pulse and Slipstream owned, the pulse hurts the target and the beam does not, target within 400 px and 96 px level, grounded or in ball form | Curl into ball form, roll toward it, drop the pulse (`fire_beam` in ball form), roll back 24 frames, stand up. |
| `select_beam:<beam>` | Per owned, unequipped beam while a target exists; the label says when it hurts or opens the target | Tap `cycle_beam` as often as the owned order needs. |
| `jump_over:<id>` | Grounded, target within 420 px, not a boss floating more than 160 px above the feet | Jump toward it, 20 frames held. |
| `dash_through` | Undertow Dash ready and a shot flying at the player within 420 px | Dash into the shot (the deflect window). |
| `wall_jump_up` | Airborne against a wall | Push in, jump away, steer back. |
| `go_to_refill:<kind>` | Out of Harpoons (with a quiver) or below a third of health, and a refill in `refills` restores it | Steer to it, running. |
| `go_to_ambush` | Armed arena, player not at its trigger | Steer to the trigger centre. |
| `pick_up:<id>` | Up to two pickups | Steer to it. |
| `go_to_exit:<edge:target>` | Up to three ungated exits, none while a boss is alive in the room (a boss room's goal is the fight) | Steer to the door, running. |
| `jump:left`, `jump:right` | Always | Plain jumps, used to break a stall. |

Stuck detection is positional: 3 s in which the player chose movement but stayed inside a 48 px
box (`tools/playtest_telemetry.gd:380`).

The driver sends `cycle_beam` presses when the physics step ends, after the player has moved
(`LATE_PRESSES`, `tools/playtest_programs.gd:19`). Measured in the check: a press sent before the
player counts twice for her (just pressed in that frame, then her queued `_input` press in the
next), so one tap stepped two beams. Every other press still goes out before the player; the second
count is absorbed by the fire cooldowns and the Slipstream curl.

## 6. Policies

- **heuristic** (`tools/playtest_policy.gd:44`): dash into incoming shots; when stuck, wall-jump or
  alternate jumps; go to a refill when one is offered and no close enemy is winding up; fight the
  primary target if it is visible, given up on no longer, or the arena is sealed, else go to the
  ambush trigger, a pickup or an exit. With a boss (`tools/playtest_policy.gd:128`): jump over or
  back off from a close wind-up, fire the opener, harpoon it while open, switch to the opener's
  beam, walk to where the opener lines up, and keep 360 px from a boss nothing hurts (the retreat
  falls back to the approach when the arena edge is behind). Otherwise: harpoon a beam-immune
  enemy, pulse a pulse-only one, switch to a beam that hurts it, shoot or jump-shoot, jump over
  rushers closer than 130 px, and walk closer after 2.5 s of shots that do not land (three such
  tries ignore that target for 15 s).
- **random** (`tools/playtest_policy.gd:39`): a seeded uniform pick; the baseline a smarter policy
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
one keep-alive connection opened before the first decision (`tools/playtest/jev_backend.py:349`).
The contract comes from `.agent-reports/jev-research.md` section 1.

Request (`tools/playtest/jev_backend.py:294`):

- `model`: default `jev-1.13.0`, pinned. On 2026-09-24 the API accepted it, `GET /v1/models` listed
  only the aliases `jev-latest` and `jev-preview`, and `jev-latest` answered as `jev-1.13.0`.
- `state` (`tools/playtest/jev_backend.py:236`): a compact view of section 4, not the raw export.
  A `goal` sentence (defeat the boss; start the armed arena by walking in; clear the running arena;
  or explore); `player` with `health_pct`, grounded, on_wall, facing, form, dash_ready and
  harpoons left, the equipped `bolt` and `bolts_owned` by player-facing name; up to 3 `threats` with `dx_tiles`/`dy_tiles`, a `where` phrase (left, right,
  above, below), a `range` word (touching, close, mid range, far), health %, winding up, whether
  the kit hurts it, `hurt_by_bolt` (the owned bolt that would), line of sight, whether it belongs to
  the arena, and boss stage, attack and `shell` (open, or closed and what opens it, in words); up to
  3 `incoming_shots` within 6 tiles with `approaching` computed in code; up to 2 `hazards` within 4
  tiles (kind, where, touching, state); `facts` (health word, nearest threat range and direction, any
  wind-up, shot incoming, in arena, arena wave line, boss stage, attack and shell, stalled, and what
  the room's refills restore); and `last_action` with how far the previous action moved the player.
  All arithmetic happens here, because Jev is weak at numbers.
- `questions`: `action` (`choice` over the candidate keys, each criterion the game's label plus a
  one-line rubric for its kind), `danger` (`score`: low, medium, high) and `unsure` (`noul`: stuck
  or unclear which action is right).
- Illegal candidates are removed in code before sending (`tools/playtest/jev_backend.py:143`): a
  harpoon without ammo, a shot or jump shot without the crossbow, a pulse without the Resonance
  Pulse, a dash that is not ready, a wall jump off the wall, a jump-over while airborne. Each new
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
| `--jev-hz` | 5 | At most this many requests per game second; decisions in between play the hint and are recorded as `skip:rate`. |

Sources per decision (`tools/playtest/jev_backend.py:532`): `jev`; `skip:rate`,
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
  `TYPESAFE_API_KEY` inside each request (`tools/playtest/jev_backend.py:361`), never stored,
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
  and their aggregate.
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
