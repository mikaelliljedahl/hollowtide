# Feature design: dash deflect

Status: implemented on a lane branch on 2026-09-24; design accepted by the user on 2026-09-24, see
[Accepted dash deflect amendment](../implementation-decisions.md#accepted-dash-deflect-amendment). Internal ID
`dash deflect`. Nothing in the game shows a name for it. If one is ever needed (help text, a
codex), use **Tide Turn**, in the D19 naming style.

## 1. Goal

The Undertow Dash already passes through harm. Starting the dash at the right moment should pay
out clearly more than plain dodging: an enemy shot that the body touches in the first moments of
the dash turns back along its own line as a player-owned shot and hits the shooter. The rule is one
button and one outcome, it teaches itself through what the player sees and hears, and it adds no
text.

Out of scope: new inputs, new enemy tells, a resource cost, reflecting hazards that are not shots
(stalactites, crushers, lava, contact damage).

## 2. Rules

- **R1 Window.** The window opens when a dash starts and lasts `WINDOW_SECONDS` = 0.10 s
  (`scripts/player/dash_deflect.gd:10`). At 60 Hz that is the start frame plus five more, about
  150 px of the 0.18 s, 270 px burst. The value is `COYOTE_TIME` from `docs/game-feel.md`, the
  timing slack the game already gives for jumps, so the timing feels familiar. It is not taken from
  another game's frame data. The window closes early if the dash ends early (wall, Slipstream form,
  death, reset).
- **R2 Touch.** An enemy shot counts as touched if it is inside the dash's swept body rectangle, or
  its next step would be, during the window (`scripts/player/dash_deflect.gd:52`). A shot whose own
  ray reaches the body first asks the player through `Player.try_deflect`
  (`scripts/player/player.gd:896`, called from `scripts/combat/enemy_projectile.gd:57`), so the
  result does not depend on node processing order. Every shot touched in the window turns, so a
  boss fan can turn several at once.
- **R3 Return.** The touched shot is removed. A `ReflectedShot` (`scripts/combat/reflected_shot.gd`)
  starts at the same point with the opposite heading, so it goes back along its incoming line to
  the shooter. It is player-owned (layer 16, mask world plus enemies), flies at 1800 px/s, faster
  than `DASH_SPEED`, so it leads the dash, and has a 960 px range. It deals `DAMAGE` = 30 with damage
  kind `beam`: three Seed Bolts, a little under the Harpoon's 35. Terrain, gates and grates treat it
  like a Seed Bolt.
- **R4 Outside the window.** Later in the dash, and in the 0.08 s grace, shots are passed through
  exactly as before: no damage, and the shot pops (`scripts/player/player.gd:175`).
- **R5 One input, one outcome.** While the window is open, every other action press (jump, beam,
  harpoon, Slipstream, beam cycle, Flux, a second dash) is dropped, not buffered. The jump buffer and
  queued presses are cleared (`scripts/player/dash_deflect.gd:42`), and Slipstream, crouch and weapon
  handling are skipped for those frames (`scripts/player/player.gd:112`). Held states (run, aim,
  holding Burst Beam) take effect again after the window, because they are not new presses. The
  frame that starts the dash is not inside the window, so a jump and a dash pressed on the same
  frame behave as before.
- **R6 Bosses.** Boss shots are ordinary `EnemyProjectile`s and turn the same way. Because the
  returned shot is a `beam` hit, every boss phase blocks it (the reaction matrix in
  `docs/content-catalog.md` lists Beam = I in all boss phases). A deflect near a boss protects the
  player and can hit other enemies, but it never gets around a phase guard. This follows the
  catalog rule that no weapon variant bypasses boss protection.
- **R7 Reaction matrix.** The returned shot follows the Seed Bolt column: the Crawler and the
  Armored Guard block it, a folded Shooting Gargoyle blocks it, and a Shard Turret or Leech
  Wisp (both immune to the dash itself) takes the damage. A turret can be beaten with its own
  shards.
- **R8 No cost.** No Flux, health or ammo cost and no reward drop. The payout is the 30-damage return
  hit plus the dash's normal protection.

## 3. Presentation

- **Turn ripple.** `DashFx.spawn_turn` (`scripts/combat/dash_fx.gd`) draws the protagonist's own
  undertow language at the touch point: a teal ripple ring squeezed along the new heading, a current
  that curls back around the turn point, and spray thrown forward. It uses the same palette as the
  dash's after-images and current streaks.
- **Returned shot.** The original shot's colours, wrapped in the dash current: trailing teal
  streaks and two arcs of water spinning around it (`scripts/combat/reflected_shot.gd:43`). Impacts
  make small water rings.
- **Sound.** `dash_deflect` (`scripts/autoload/audio.gd:56`) is generated in
  `tools/gen_audio.py:3288`: an undertow swirl that dips and swings back up, then a rising droplet.
  It has no metallic ring. The generator renders it last, so every earlier sound stays byte-identical.
- **Hit-stop.** 0.05 s through `GameJuice.hit_stop`, with the same cooldown and accessibility rules
  as other impacts. Off in tests.

## 4. Legal constraints (binding)

From the licence check dated 2026-09-24. It is not legal advice.

- **Patent design rule.** Koei Tecmo's pending application US20250090953A1 (US 18/613,164, JP
  priority 2023-150586) claims a window that player input opens, in which a counter fires, plus a
  second input inside that window that performs a different action. Hollowtide therefore keeps the
  deflect a single-input, single-outcome window (R5). No press inside the window starts another
  action, then or later. Never add a "press again to turn it into a dodge or other move" layer. Any
  change to R5 needs a new check against that application.
- **Monitor.** Before release, check US 18/613,164 and JP 2023-150586 on Google Patents or USPTO
  Patent Center. If the application is granted, compare the granted claims with the final build.
- **Names.** Never call it "parry", "melee counter", "deflect" or "mikiri" in text the player can
  see. Internal code IDs may say deflect.
- **Expression.** Do not copy another game's feedback: no glowing enemy tell before the shot, no
  white screen flash or metallic clang, no sword-clash sparks. The look and sound must come
  from Hollowtide's water and undertow dash (section 3). Timing comes from `docs/game-feel.md` (R1).

## 5. Verification

Suite `tools/check_dash_deflect.tscn` (registered as `dash deflect` in `tools/run_godot_check.py`):

| Case | Expectation |
|---|---|
| Window | `WINDOW_SECONDS` is 0.10. The window opens with the dash, stays open five frames after the start frame, and the dash ends normally. |
| Inside window | A Spitter shot touched on the first dash frame turns. The original is consumed. One returned shot flies along the reversed incoming line, on layer 16 with kind `beam`, and damages the Spitter by 30, capped at its health. The player loses no health. |
| After window | A shot touched while the dash is still active, after the window, does not turn. The player takes no damage and nothing else is hurt. |
| Other inputs | Jump, beam, harpoon, Slipstream, dash and cycle presses sent through real input events during the window start nothing inside it. The dash neither ends nor turns around. After the window, no shot has been fired, no harpoon spent, no Slipstream shift or jump done. Control: a jump pressed after the window still ends the dash. |
| Boss shot | A 1.6-scale shot aimed from a Stone Guardian turns and reaches the boss, and the boss's health is unchanged. |

The input rule was also tested by breaking it on purpose: with the gate disabled, four of the
"Other inputs" checks fail.

Not verified: hands-on feel of the 0.10 s window, the 30 damage balance, the hit-stop, and the
sound level in a real room.
