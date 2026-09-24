# Feature design: boss rework

Status: implemented on a feature branch; design accepted by the user on 2026-09-24, see
[Accepted boss rework amendment](../implementation-decisions.md#accepted-boss-rework-amendment). Code: `scripts/enemies/boss.gd` (state machine), `scripts/enemies/boss_patterns.gd`
(stages, rotations, timing), `scripts/enemies/boss_attacks.gd` (plans and emissions),
`scripts/enemies/boss_motion.gd` (movement and charges), `scripts/enemies/effects/boss_telegraphs.gd`
(poses and markers) and `scripts/enemies/effects/boss_visuals.gd` (existing presentation).

## 1. Goal

[state.md](../state.md) lists the three bosses (Stone Guardian, Cinder Warden, Tidal Heart) as
logic-tested but too easy, and the user wants more action and fewer puzzles. Each boss keeps its
arena, damage matrix, weapon requirement, HP, contact damage, IDs, signals and save flags, and gains
a fight that escalates through four stages of readable, telegraphed attack patterns with a clear
opening after every big attack.

Out of scope: new boss art, new sound effects, arena layouts, HP or damage-matrix changes, campaign
placement, HUD elements.

## 2. Design basis

The rules come from an analysis of widely praised 2D action bosses. Only the principles are used;
no names, art or attack designs are taken from any game.

| Principle | Rule it produces |
|---|---|
| Difficulty should come from reading and answering patterns, not from surprise. | R1, R2 |
| Every big attack needs a visible wind-up and a moment afterwards where the attacker is exposed. | R2, R3 |
| Fights stay fresh when later phases add a pattern or combine known ones instead of inventing noise. | R4 |
| A last stand below a quarter of health raises tension by speed and density while staying fair. | R5 |
| A phase change is a reward beat, not an ambush. | R6 |

## 3. Design rules

- **R1 Locked truth.** Aim, lanes, floor targets and ring gaps are chosen when the telegraph starts
  and never move afterwards (`scripts/enemies/boss_attacks.gd:35`). The markers show exactly where
  damage goes.
- **R2 Telegraph first.** Every attack telegraphs for at least 0.45 s (`MIN_TELEGRAPH`,
  `scripts/enemies/boss_patterns.gd:12`); no projectile or charge exists before the telegraph ends.
  The telegraph is always three things at once: a wind-up pose, a body glow ending in a release flash
  in the last 0.12 s, and a marker (aim line, floor lane, floor circle, ring gap or spiral).
- **R3 Punish window.** The last attack of every chain is followed by a recover step in which the boss
  holds still (Tidal Heart sinks toward its home height) and starts nothing. In armored stages
  (B2) the Stone Guardian's armor and the Cinder Warden's shell are open for the whole window and
  closed otherwise; the window is at least 1.4 s (1.2 s in desperation) so a harpoon can land.
  Tidal Heart keeps its Snare and Echo openings; its recover step is the calm in which to use them.
- **R4 Escalation.** Each of stages 1-3 adds at least one attack the boss has not used before. Stage 4 adds no
  new attack but chains two known attacks back to back, each with its own telegraph.
- **R5 Desperation.** At or below 25 % health: telegraphs are 0.8 times as long (never under 0.45 s),
  idle gaps shrink to 0.5 s, several attacks add a second burst, movement is faster, and punish
  windows are 0.85 times as long (never under 1.2 s). The body pulses and a ring pulses around it.
- **R6 Stage transitions.** Crossing a threshold drops the current wind-up unfired, plays the
  existing phase burst and stagger, and gives a 1.0 s breather before the next telegraph.
- **R7 No text.** Poses, markers, the release flash, the health-bar notches (one per stage still
  ahead) and sound teach the fight.

## 4. Stages and state machine

| Stage | Health | Damage matrix | Idle between chains |
|---|---|---|---|
| 1 | above 75 % | B1 | 1.1 s |
| 2 | 75 % to above 50 % | B1 | 0.9 s |
| 3 | 50 % to above 25 % | B2 | 0.8 s |
| 4 (desperation) | 25 % and below | B2 | 0.5 s |

`phase` stays the B1/B2 protection phase of the damage matrix and is derived from the stage
(`scripts/enemies/boss_patterns.gd:108`), so B1 turns into B2 at half health exactly as before.
Stages only advance; `set_test_phase` keeps working (phase 1 is stage 1, phase 2 is stage 3) and
`set_test_stage` (`scripts/enemies/boss.gd:148`) reaches any stage for tests and dev tools.

| State | Behavior | Leaves to |
|---|---|---|
| `idle` | Normal movement; the idle timer runs | `telegraph` with the next chain of the stage rotation |
| `telegraph` | Holds still in the wind-up pose; markers drawn; `attack_telegraphed` emitted on entry | `active` when the telegraph time is over |
| `active` | `attack_released` emitted; timed shots fire or the charge runs | next link's `telegraph`, or `recover` after the last link |
| `recover` | Punish window: still, B2 weak point open | `idle` |

Leaving the arena, a stage transition, death and `reset_runtime` cancel to `idle` without firing
(`scripts/enemies/boss.gd:363`). The loop lives in `scripts/enemies/boss.gd:292`.

## 5. Stone Guardian

Rock projectiles. Floor lanes are jumped; rock drops are side-stepped.

| Attack | Stage added | Telegraph | Punish (st 1-2 / 3 / 4) | What happens |
|---|---|---|---|---|
| Boulder Volley | 1 | 0.6 s: pulse, aim lines | 0.9 / 1.4 / 1.2 s | 1 aimed rock; 3 in stage 3, 5 in stage 4, the first on the aim line and the rest fanning below it toward the floor (0.22 rad apart, 0.2 in stage 4), so one jump over the aim line clears them all |
| Fault Slam | 1 | 0.7 s: rises tall, floor lanes to both walls | 1.2 / 1.4 / 1.2 s | A floor shockwave runs to each wall; desperation sends a second pair 0.85 s later |
| Rockfall | 2 | 0.8 s: rises tall, floor circles | 1.0 / 1.4 / 1.2 s | Rocks drop on the player's spot and 220 px either side (5 columns in desperation) |
| Shoulder Charge | 3 | 0.65 s: crouches back, floor arrow along the lane | 1.8 / 1.8 / 1.53 s | Charges toward the player and stops 128 px of floor short of the first wall (a low roof or step counts) or the lane end, where the arrow ends; a player backed against that wall is out of reach. Then stands stunned with the armor cracked open |

Rotation: stage 1 Volley, Slam; stage 2 Slam, Rockfall, Volley; stage 3 Volley, Charge,
Rockfall, Slam; stage 4 Slam then Rockfall, Charge then Volley, Rockfall then Charge.

Playtest round 2 (2026-09-24, [playtest-agent.md](playtest-agent.md#17-results-round-2-2026-09-24)): a scripted
dodge probe in the real `vaults_03` arena (real player, forced attacks, 110 input responses per
case) found no escaping response to a centred stage 3-4 volley at 600 px and to a Shoulder Charge
at the arena's west end, where a 118 px tunnel stops the bodies and a platform at y 640 caps jumps
at 134 px. Fault Slam (single or double jump, 0.33-0.67 s windows) and Rockfall (side-step) were
fair and are unchanged. The volley's shape and the charge's stop point live in
`scripts/enemies/boss_attacks.gd` (`_fan_below`, `CHARGE_WALL_POCKETS`, `_first_wall_x`); no
telegraph or punish time changed. Scuttle Rush keeps the old stop point and has not been probed.

## 6. Cinder Warden

Fire projectiles. Vents are read on the floor; the heat ring is escaped through its gap.

| Attack | Stage added | Telegraph | Punish (st 1-2 / 3 / 4) | What happens |
|---|---|---|---|---|
| Ember Fan | 1 | 0.55 s: pulse, aim lines | 0.8 / 1.4 / 1.2 s | 3-way fan; 5-way from stage 3; desperation fires it twice 0.3 s apart |
| Vent Burst | 1 | 0.75 s: rises, floor circles | 1.0 / 1.4 / 1.2 s | Fire pillars erupt from the circles: under the player and 300 px either side (5 circles 210 px apart in desperation) |
| Scuttle Rush | 2 | 0.6 s: crouches back, floor arrow | 1.3 / 1.4 / 1.2 s | Rushes the lane toward the player's side at 580 px/s |
| Heat Ring | 3 | 0.8 s: swells, ring of dots with a bright gap toward the player | 1.6 / 1.6 / 1.36 s | 12 embers in a ring with a 77 degree gap; desperation adds a second, offset ring 0.4 s later |

Rotation: stage 1 Fan, Vent; stage 2 Rush, Fan, Vent; stage 3 Fan, Ring, Rush, Vent; stage 4
Vent then Fan, Rush then Ring, Ring then Vent.

## 7. Tidal Heart

Water projectiles. It floats, so its answers are movement and ducking rather than a ground lane.

| Attack | Stage added | Telegraph | Punish (st 1-2 / 3 / 4) | What happens |
|---|---|---|---|---|
| Tide Ring | 1 | 0.6 s: swells, radial lines | 1.0 / 1.4 / 1.2 s | 8 radial drops, 10 from stage 3; desperation adds an offset ring 0.35 s later |
| Surge Lance | 1 | 0.65 s: pulse, one aim line | 1.0 / 1.4 / 1.2 s | 3 fast bolts along the locked line (5 in desperation) |
| Crosscurrent | 2 | 0.8 s: swells, dashed lane across the arena | 1.1 / 1.4 / 1.2 s | A low stream (30 px above the floor, jump it) sweeps from the far wall; desperation adds a high stream (140 px, crouch or roll under it) 1.0 s later |
| Maelstrom | 3 | 0.8 s: swells, rotating spiral arms | 1.6 / 1.6 / 1.36 s | Two arms (three in desperation) of drops wind out over 1.2 s, starting a quarter turn away from the player |

Rotation: stage 1 Ring, Lance; stage 2 Crosscurrent, Lance, Ring; stage 3 Maelstrom, Ring,
Crosscurrent, Lance; stage 4 Maelstrom then Crosscurrent, Lance then Ring, Crosscurrent then Lance.

Snare still opens the B1 pulse point and Echo through the grate still opens the B2 shield, each for
2.0 s, independent of the attack cycle.

## 8. Implementation notes

- All timing lives in `TIMING`, `ROTATIONS` and the stage constants of
  `scripts/enemies/boss_patterns.gd:24`; balance changes happen there.
- Shots are plain `EnemyProjectile` instances (`scripts/combat/enemy_projectile.gd`) with the
  boss's contact damage; speed, lifetime and size come from the emission table in
  `scripts/enemies/boss_attacks.gd:127`.
- Without arena bounds (test benches) bosses do not move and charges stay in place, matching the
  previous movement rule.
- New signals `stage_changed`, `attack_telegraphed` and `attack_released` are additive; `defeated`
  is unchanged.

## 9. Contract amendment needed

The content catalog's boss table describes two phases. Proposed addition to
[content-catalog.md](../content-catalog.md) under "Bosses", for the integrator to accept:
"Each boss fight runs four stages by health (above 75 %, above 50 %, above 25 %, 25 % and below).
Stages 1-2 use the B1 row of the phase-protection matrix and stages 3-4 the B2 row; B1 still turns
into B2 at half health. In B2 the Stone Guardian's armor and the Cinder Warden's cooling window open
during the punish window after each attack instead of on a fixed two-second cycle. Design:
`docs/features/boss-rework.md`."

## 10. Verification

Suite `tools/check_boss_rework.tscn` (registered as `boss rework` in `tools/run_godot_check.py`):

| Case | Expectation |
|---|---|
| Rules | Stage thresholds at 75/50/25 %; stages 1-2 are B1 and 3-4 B2; each of stages 1-3 adds a new attack; every telegraph is at least 0.4 s and every punish window at least 0.8 s in every stage; every boss has at least four attacks and desperation chains. |
| Thresholds | Real harpoon hits (with the Snare, Echo or punish opening each stage needs) take every boss through stages 2, 3 and 4 once each with one phase burst per transition; stage and phase match health after every hit; desperation starts at or below 25 %; the boss dies. |
| Transition | A hit across 75 % during a wind-up drops it unfired and nothing fires during the breather. |
| Fair answers | Every Boulder Volley rock flies on or below the locked aim line (stages 1, 3, 4); a Shoulder Charge plans and runs to a stop 128 px short of a low roof. Both fail on the pre-round-2 code. |
| Cycles | In a walled test arena, for every boss and stage: every attack of the stage is released; every release follows its own telegraph by at least 0.4 s; every projectile appears only while an attack is active; every punish window lasts its table time; B2 armor is open in each punish window and closed during every wind-up; charges carry the body along the lane; desperation chains a telegraph straight after an attack. |

Existing suites `combat devmode`, `combat integration`, `combat presentation`, `campaign flow`,
`playability`, `dev world` and `world persistence` cover the unchanged damage matrix, the Tidal Heart
openings, reset, defeat and save flags. Telegraph screenshots come from
`tools/capture_combat.gd` with `--shots=telegraphs`.

Not verified: a real-input playthrough of the reworked fights, and the hands-on feel of speeds,
telegraph lengths and punish windows in the campaign arenas.
