# Hollowtide — game-feel specification (normative)

This document is the **authoritative specification** for how the game should feel. All numbers here are intentional and
designed to provide classic metroidvania movement: weight in the fall, control in the air, and a
jump that peaks smoothly instead of turning sharply.

**Rule for implementers:** copy the constants exactly. Do not change them because something
"feels better" locally — the feeling is tuned as a whole. If you have objections, report them,
do not change.

## Base units

| Quantity | Value | Note |
|---|---|---|
| Tick | 60 Hz fixed (`physics_ticks_per_second = 60`) | All movement in `_physics_process` |
| Tile | 64 × 64 px | |
| Resolution | 1920 × 1080, `canvas_items`, `keep` | True high definition. No Pixel Art Upscaling |
| Player hitbox (standing) | 56 wide × 176 high | Origin at the feet. The rendered player is 192 px tall = 3 tiles |
| Player hitbox (ball) | 56 × 56 | 8 px margin in a 64 px opening |

All speeds are in px/second; all acceleration is in px/second².

**About the scale:** these numbers are the original set multiplied by four, afterward,
the game went from 480×270 to true 1920×1080. Because everything — tiles, player, speed,
gravity — scaled by the same factor, the feel is identical; only the pixel density was changed.
The tile coordinates of the levels are therefore unchanged.

## Walking (standing form)

```
WALK_MAX        = 480.0
GROUND_ACCEL    = 4000.0
GROUND_FRICTION = 6000.0     # deceleration without input
AIR_ACCEL       = 3040.0
AIR_FRICTION    = 1760.0      # deliberately weaker than on the ground
TURN_BOOST      = 1.8        # acceleration multiplier when input opposes current velocity
```

`TURN_BOOST` is important: without it, turns feel tough. Apply it only when
`sign(input) != sign(velocity.x)` and `velocity.x != 0`.

## Jump

The jump is derived from the desired height and time to apex, not guessed:
apex height 256 px (4 tiles), time to apex 0.40 s.

```
JUMP_VELOCITY     = 1280.0    # upward; -1280 on Godot’s y-axis
GRAVITY_RISING    = 3200.0
GRAVITY_FALLING   = 4640.0   # 1.45× — falling is faster than rising
TERMINAL_VELOCITY = 1760.0
JUMP_CUTOFF       = 0.40     # velocity.y multiplier when the jump button is released while rising
COYOTE_TIME       = 0.10     # seconds after leaving the ground during which jumping still works
JUMP_BUFFER       = 0.12     # seconds before landing during which a press is buffered
```

### Apex hanger — non-negotiable

This is the single most important detail for the jump to feel right.
When `abs(velocity.y) < APEX_THRESHOLD`, apply:

```
APEX_THRESHOLD   = 160.0
APEX_GRAVITY_MUL = 0.75      # gravity is reduced near the apex
APEX_ACCEL_MUL   = 1.15      # control is improved there
```

The effect is that the player gets a short moment of extra control at the top of the arc. Without it
the jump feels mathematically correct but lifeless.

### Jump logic order

Exactly this order, otherwise subtle bugs occur:
1. Read input; update coyote and buffer timers.
2. Trigger the jump when the buffer is active and the player is grounded or coyote time is active. Reset both timers.
3. Apply cutoff if the jump button was released and `velocity.y < 0`.
4. Select gravity: ascending / descending / apex.
5. Integrate and clamp to terminal velocity.
6. `move_and_slide()`.

## Wall jump

The player jumps against a wall, presses jump again, and pushes off to reach higher. The same wall
can be used over and over again — it should be possible to climb a vertical shaft this way.

```
WALL_SLIDE_SPEED    = 680.0    # falling speed against a wall; slows the fall but remains visibly downward (user 2026-09-23: 420 felt too slow)
WALL_JUMP_VELOCITY  = 1280.0   # upward; IDENTICAL to JUMP_VELOCITY — see below
WALL_PUSH_VELOCITY  = 620.0    # outward, away from the wall
WALL_INPUT_LOCK     = 0.14     # seconds horizontal input is ignored after the wall jump
WALL_COYOTE         = 0.10     # seconds after wall contact ends during which the jump still works
WALL_CHECK_OFFSET   = 88.0     # height above the feet where wall detection is checked (torso center)
```

### Why these three in particular

**`WALL_JUMP_VELOCITY` is IDENTICAL to the regular jump, and that is the point.**
The height gain is positional: the wall jump gives the same impulse from the height the player has already reached.
If you make the impulse stronger, the element of skill disappears.

The consequence is that timing determines everything. Triggering the wall jump near the jump apex
preserves almost the full height. Triggering it halfway down loses much of that gain and reaches only
about 1.5 times a single jump. This is correct behavior and must not be "improved" locally — that is
why `WALL_SLIDE_SPEED` slows but never stops the fall.

**`WALL_INPUT_LOCK` is the detail everyone misses.** Without it, the player still holds direction
into the wall when the wall jump is triggered, immediately gets stuck again, and the wall jump appears to do nothing.
With a lock that is too long, the player instead feels like it is slipping. 0.14 s is balanced: just enough to break free, too short to be marked as loss of control.

**`WALL_COYOTE` makes the difference between fun and frustrating.** Just like the ground coyote
time, a press shortly after wall contact ends should still trigger the wall jump.

### Rules

- Wall sliding applies only when the player is FALLING (`velocity.y > 0`) and input points toward the wall.
  Rising against a wall must not be slowed; that would kill the jump arc.
- Wall jumps require no directional input. The jump button alone is enough; direction comes from the
  contacted wall. Requiring simultaneous "away from the wall" input recreates the notorious
  difficulty of older wall jumps; Hollowtide uses a modern interpretation.
- **Wall jump never works in Slipstream form.** Regular grounded/coyote Ball jump is separate.
- The same wall may be used repeatedly. No forced switching between walls.
- The Apex hang also applies after a wall jump — it is the same jump arc.

### Graphics

Authored wall-slide and wall-jump poses are integrated and mirrored from wall contact. They are visual
only: wall-jump physics constants and timing remain authoritative above. Human contact/timing review
remains part of F1.

## Slipstream form (after the orb is picked up)

The ball should feel **heavier and more slippery** than walking — it has momentum.

```
ROLL_MAX      = 580.0    # faster than walking; the upgrade should feel rewarding
ROLL_ACCEL    = 2600.0    # slower to accelerate
ROLL_FRICTION = 2160.0    # slower to stop; it keeps rolling
```

Gravity and terminal velocity are the same as standing form.

### Rules

- **Accepted replacement for former no-ball-jump rule:** A/Space triggers a regular grounded or
  coyote jump using unchanged base `JUMP_VELOCITY`; A is primary and Space is the alternate. Ball form
  and 56×56 collider remain active.
- High Jump does not multiply Ball jump. Slipstream has no wall jump, humanoid spin/Undertow Dash,
  or midair double jump. Jump buffer, cutoff, coyote timing, gravity, apex, and terminal velocity use
  base jump rules.
- Bomb lift remains separate and unchanged; regular jump input never creates bomb lift.
- Press Z while grounded to enter Slipstream; press Z again to return, **but only if there is headroom**.
  Check clearance with an upward ShapeCast; otherwise refuse silently.
- Transition takes 0.12 s with movement allowed. No controller lock.
- `velocity.x` is preserved through transition both ways. Momentum must not be discarded.

## Camera

```
position_smoothing_enabled = true
position_smoothing_speed   = 8.0
```

Look-ahead: shift the camera 128 px in the facing direction, interpolated over 0.4 s. This provides
visibility in the direction of movement without making the camera feel detached from the player.

## Input

| Action | Primary control |
|---|---|
| Move/aim | Arrow keys |
| Crouch | Down |
| Slipstream | Z |
| Run | Hold Left Shift |
| Jump | A |
| Alternate jump | Space |
| Beam / bomb | X |
| Missile | C |
| Cycle owned beam | V |
| Select owned Flux module | Q |
| Activate/toggle Flux | F |
| Pause/help | Esc |
| Developer panel (debug dev mode) | F1 |

J/K remain alternate beam/missile bindings. Jump input must use `just_pressed` for buffering and `is_pressed` for cutoff; neither signal alone is sufficient.

## Acceptance criteria for scene 1

1. The player starts on the right and moves **left** through a short cave.
2. The orb lies in a niche. Contact collects it: particle burst, light, and a brief sound — no on-screen text or popup. The environment teaches the interaction.
3. After pickup, Slipstream form is unlocked.
4. The way back is blocked by a **1 tile high** (64 px) opening that only Slipstream form can pass through.
This is the scene's proof that the ability matters.
5. No tutorial texts anywhere. The niche and the low opening will teach themselves.

## Aim poses

The weapon is aimed with the directional controls while firing. Aiming must **never** lock or brake
movement: the player can aim during a jump or turn without losing speed. This separates the modern
interpretation from the stiffness of the original reference.

| Mode | Input | Direction |
|---|---|---|
| Forward | no vertical input | `(facing, 0)` — default |
| Diagonal up | `move_up` + `move_left`/`move_right` | normalized `(facing, -1)`, 45° |
| Straight up | `move_up` alone | `(0, -1)` |
| Diagonal down | `move_down` + `move_left`/`move_right`, **airborne only** | normalized `(facing, 1)`, 45° |
| Straight down | `move_down` alone, **airborne only** | `(0, 1)` |

`move_down` on the ground crouches in the target contract. A grounded crouched player may aim and fire horizontally at low targets. Downward aiming remains an airborne action; it is a deliberate limitation, not a loophole.

Aiming never changes `facing`. Holding `move_up` while moving right preserves rightward movement
and fires straight up. Aiming and movement read the same controls independently.

### Muzzle

`Muzzle` must be where the weapon is actually pointing, not a fixed point. Start at shoulder height
and place the muzzle `AIM_MUZZLE_DISTANCE` units along the aim direction:

```
AIM_SHOULDER_OFFSET   = Vector2(0, -120)   # shoulder, relative to the player origin at the feet
AIM_MUZZLE_DISTANCE   = 52.0               # from the shoulder along the aim direction
```

The projectile must begin where it visibly leaves the weapon. If an upward shot appears at hip height
in front of the player, it immediately looks wrong even when the viewer cannot explain why.

## Implemented Flux systems

One shared finite **Flux** meter powers one selected module:

- **Flux Shield:** F toggles absorption; costs one Flux per valid damage absorbed.
- **Burst Beam:** F toggles rapid fire; drains 8 Flux/s.
- **Echo Scan:** F spends 20 for one 900 px reveal pulse.

Q cycles owned modules. First module initializes 100 Flux; four tanks add 50 each to maximum 300;
temporary refill gives 10. Save schema v2 persists module/resource state and migrates valid v1 saves
without latent Flux ownership. These systems add no tutorial text to world. Human feel/audio/visual
approval remains part of F1.

## Damage and invulnerability

The player starts with 100 health. Contact with a crawler deals 12 damage, so death takes nine hits.
This makes mistakes matter without allowing one accidental contact to end a playthrough.

```
MAX_HEALTH          = 100
CRAWLER_CONTACT     = 12
INVULN_TIME         = 1.00   # seconds of invulnerability after a hit
HURT_KNOCKBACK_X    = 520.0  # away from the damage source
HURT_KNOCKBACK_Y    = -480.0 # upward, always — even when standing still
HURT_INPUT_LOCK     = 0.18   # seconds horizontal input is ignored
INVULN_FLASH_HZ     = 15.0
```

**Invulnerability time isn't politeness, it's readability.** Without it, you can lose all health
in a second by lingering against an enemy, and the death feels arbitrary. A whole second is
also long enough to get out of a tight passage.

Knockback always points upward and away. The upward component lifts the player from the surface a
crawler occupies, reducing immediate repeated contact.

`HURT_INPUT_LOCK` is a separate hurt-control interval; it must not be confused with wall-jump input lock. The player should be pushed, not lose
control — 0.18 s is enough for the push to be seen and felt, but not to become a penalty.

During invulnerability, the player flashes at `INVULN_FLASH_HZ`. The blink is the in-world signal that
temporary protection is active; without it, the health meter appears broken.


## Phase 1 — Bounded Ability Additions

`devmode-contract.md` defines High Jump as a separate standing ground-jump modifier,
spin/Undertow Dash, protection, bomb lift, and accepted regular Ball jump. Base constants above do not
change. Ball jump and bomb lift are distinct impulses and tests.

## Implemented crouch, Slipstream, and run controls

Down crouches and supports grounded horizontal low fire; Z toggles Slipstream; A jumps and Space is the
alternate jump; Left Shift holds run.
Runtime help reflects these bindings. Acceptance still requires hands-on review of crouch collider/pose,
visible low-shot muzzle, stand-up clearance, aim/fire/hurt/death transitions, sprint/wall poses, and
preserved tuned walk, jump, and wall-jump behavior. Implementation is complete; F1 approval is not.

## Updraft Cloak glide

The Updraft Cloak (internal ability id `high_jump`) keeps the higher ground jump (`HIGH_JUMP_IMPULSE`)
unchanged and adds a gentle glide: while the cloak is owned, she is airborne in standing form (not
ball, not wall sliding), falling, and jump is held, fall speed is capped at **260 px/s**
(`UpdraftCloak.GLIDE_FALL_SPEED`). Releasing jump returns normal falling immediately. A soft wind
whoosh and a few rising wind streaks play while gliding; the worn cloak trails from her shoulders and
billows against her velocity, and is hidden in ball form. The glide only eases traversal — no route may
require it. Logic lives in `scripts/player/updraft_cloak.gd`, called once from `Player._physics_process`
after gravity. Verified by `tools/check_updraft_glide.tscn`.

## Undertow Dash (D19, internal id `undertow_dash`)

Replaces the Undertow Dash spin attack; the ordinary spin jump stays and deals no damage.

```
DASH_ACTION          = "dash"   # B, alternate L, gamepad RB (rebindable)
DASH_SECONDS         = 0.18     # burst length (~270 px at full speed)
DASH_SPEED           = 1500.0   # px/s horizontal, fixed for the whole burst
DASH_COOLDOWN        = 0.32
DASH_INVULN_GRACE    = 0.08     # damage ignored during the dash plus this grace
```

- Ground or air. In the air the dash holds altitude (no gravity during the burst). One air dash per
  airtime; landing or touching a wall restores it.
- Direction: held horizontal input, else facing; while clinging to a wall in the air it goes away
  from the wall.
- Ends early on hitting a wall, on jumping (the jump keeps at most `RUN_MAX`), on entering Slipstream,
  on death/reset. On normal end the speed drops to `RUN_MAX` so the dash never extends jump distance.
- Passes through enemies dealing 24 damage (damage kind `undertow`, once per target per dash) and opens
  undertow barriers ahead of the body before moving, so it carries through them.
- Movement constants above do not change any other tuned value in this document.
