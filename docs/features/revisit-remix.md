# Feature design: revisit remix

Status: implemented for the Phase 2 campaign. Rules live in `scripts/campaign/revisit_remix.gd`, the
elite variant in `scripts/enemies/effects/enemy_elite.gd`, and the suite in
`tools/check_revisit_remix.gd`. Design accepted by the user on 2026-09-24; see
[Accepted revisit remix amendment](../implementation-decisions.md#accepted-revisit-remix-amendment).

## 1. Goal

Backtracking should bring new fights, not empty walking. Once a boss falls, rooms the player has
already visited may return some of their common enemies as elites: tougher, quicker variants of the
same species with a readable look and a better drop. The principle is a common genre convention:
revisited areas hold newer, stronger enemies. It serves the user's direction of more action and
fewer puzzles, and it adds no text, no new species and no save state.

Out of scope: new enemy types, surprise enemies (D20), bosses, ambush waves, damage values, HUD.

## 2. Design rules

- **M1 Same species.** An elite is one of the thirteen common enemy IDs with scaled numbers; it keeps
  its AI, telegraphs, reaction matrix and damage.
- **M2 Earned by bosses.** The tier is the number of defeated bosses; tier 0 remixes nothing.
- **M3 Revisits only.** A spawn is only remixed in a room that was already discovered when it loaded,
  so a first visit always shows the room as authored.
- **M4 Stable.** Which spawn is elite depends only on room, spawn node and tier; a save meets the same
  elites every time, and every elite of a tier stays elite at the next.
- **M5 Always winnable.** The ambush kill filter applies, plus an ammo rule (section 6). An enemy the
  current kit cannot beat is never made elite.
- **M6 Fair.** Telegraph durations never shrink; only cooldowns between attacks do.
- **M7 Rewarding.** An elite drops a guaranteed refill pair instead of the 0.34 random drop.
- **M8 Campaign only.** Never in the dev track (S0 to S10) or in `--evidence-run=` sessions.

## 3. Tier table

The tier is counted from the existing `boss:<id>` world flags that the boss spawn sets on victory
(`scripts/campaign/boss_spawn.gd:59`), over `BOSS_IDS` in `scripts/progression/content_catalog.gd`.

| Tier | Bosses defeated | Elite chance per common spawn |
|---:|---|---:|
| 0 | none | 0.00 |
| 1 | one | 0.25 |
| 2 | two | 0.40 |
| 3 | all three | 0.55 |

Source: `TIER_CHANCE` at `scripts/campaign/revisit_remix.gd:10`. With the current layouts, 27 of the
40 authored campaign enemy spawns are common enemies; with the full kit, 9, 12 and 18 of them are
elite at tiers 1, 2 and 3 (printed by the suite).

## 4. Elite variant

| Property | Normal | Elite | Source |
|---|---|---|---|
| Health | catalog | catalog x1.6, rounded up | `scripts/enemies/effects/enemy_elite.gd:13` |
| Movement speed | catalog | x1.15 for Hopper, Grasshopper, Armored Guard, Leech Wisp, Lava Monster and Crawler | `scripts/enemies/effects/enemy_elite.gd:14` |
| Attack and jump cooldowns | catalog | tick 1.25x faster (cooldown x0.8) | `scripts/enemies/effects/enemy_elite.gd:16` |
| Telegraphs | catalog | unchanged | M6 |
| Contact and projectile damage | catalog | unchanged | M1 |
| Defeat drop | 0.34 chance of one refill | always two refills | section 7 |

Elite health, for reference: crawler 168, ceiling diver 48, vent flyer 32, hopper 39, spitter 45,
armored guard 96, frost floater 52, leech wisp 29, shard turret 58, burrower 68, grasshopper 48,
shooting gargoyle 58, lava monster 77.

Speed is applied around `move_and_slide` (`scripts/enemies/combat_enemy.gd:171`), so it only covers
movers whose velocity is integrated. Position-driven movers (Vent Flyer, Frost Floater, Burrower) and
the aimed Ceiling Diver dive keep their paths, since scaling them would overshoot the authored path.
Cadence scales the `_attack_timer` and `_jump_timer` decay (`scripts/enemies/combat_enemy.gd:161`,
`scripts/enemies/combat_enemy.gd:164`). The Shooting Gargoyle, Burrower and Lava Monster run their
attack cycle on state timers that also time their vulnerable window, so they keep their catalog cycle:
a shorter cycle would shrink the player's opening.

## 5. Visuals

An elite reads at a glance without a flash or text:

- A rose tint on the sprite (`self_modulate`, `TINT` at `scripts/enemies/effects/enemy_elite.gd:22`),
  which survives the per-frame presentation reset because that reset only touches `modulate`.
- A pulsing magenta rim about 4 screen pixels wide, drawn behind the sprite with the same frame by
  `resources/combat/elite_outline.gdshader` through the `Rim` node
  (`scripts/enemies/effects/enemy_elite.gd:87`). It follows texture swaps, facing and animation frames.

The colour pair is distinct from the orange attack telegraph, the white hit flash, the pale Bubble
Snare look and every area palette. Verified in a real windowed run with normal and elite Hopper,
Armored Guard, Spitter and Grasshopper side by side in dev station S1.

## 6. Determinism and winnability

A spawn is elite when all of these hold (`is_elite_spawn`, `scripts/campaign/revisit_remix.gd:55`):

1. Remix is enabled: a campaign root exists and no `--evidence-run=` argument is present
   (`scripts/campaign/revisit_remix.gd:26`). The dev track has no campaign root.
2. The tier is above 0 and the room was already discovered when it loaded. The spawn reads this in
   `_ready`, before the campaign root records the visit (`scripts/campaign/enemy_spawn.gd:18`,
   `scripts/campaign/campaign_root.gd:414`).
3. The enemy ID is one of the thirteen common enemies.
4. The spawn's fixed roll is below the tier's chance. The roll is the first 32 bits of the MD5 of
   `<room_id>|<spawn node name>` scaled to [0, 1) (`scripts/campaign/revisit_remix.gd:40`). MD5 is used
   because `String.hash()` correlates near-identical names such as `Enemy01` and `Enemy02`.
5. The kit can beat the elite (`kit_can_beat`, `scripts/campaign/revisit_remix.gd:47`): the ambush
   filter (`scripts/world/dynamic/ambush_rules.gd:39`) passes, and when harpoon bolts are the only owned
   way to hurt the enemy, a full quiver covers the elite's health. A 5-bolt quiver deals 175, which
   covers an elite Crawler (168); a smaller quiver never meets one.

No save state is added. Enemies already respawn on every room load, and the tier is derived from
existing flags, so older saves need no migration.

## 7. Reward

On defeat an elite drops two refills side by side instead of the random roll: the refill the player
needs most (bolts when owned and not full, else energy, as `AmbushRules.reward_kind` at
`scripts/world/dynamic/ambush_rules.gd:107`) plus an energy refill (`spawn_reward`,
`scripts/enemies/effects/enemy_elite.gd:62`). Values stay +25 energy and +2 bolts per refill, and the
drops are ordinary temporary loot without save IDs. Combat enemies route through
`scripts/enemies/defeat_rewards.gd:27`; the Crawler, which has no random drop, calls it from its
death (`scripts/enemies/crawler.gd:289`).

## 8. Verification

`tools/check_revisit_remix.tscn`, registered as suite `revisit remix` in `tools/run_godot_check.py`:

| Case | Function |
|---|---|
| Boss flags give tiers 0 to 3; chance rises with the tier | `tools/check_revisit_remix.gd:80` |
| Tier 0 rolls nothing; tiers 1 to 3 repeat exactly and match pinned probe rolls | `tools/check_revisit_remix.gd:97` |
| Every authored campaign spawn: tier 0 none, surprise enemies never, first visits never, tiers nest | `tools/check_revisit_remix.gd:111` |
| Kill filter and ammo rule (beam only, 5 versus 4 bolts, pulses) | `tools/check_revisit_remix.gd:164` |
| Elite stats for all thirteen IDs, damage unchanged, rim and tint, speed and cadence ratios | `tools/check_revisit_remix.gd:226` |
| Refill pair from a combat elite and from an elite Crawler | `tools/check_revisit_remix.gd:297` |
| Dev track (no campaign root) and evidence runs never remix | `tools/check_revisit_remix.gd:331` |
| Real campaign room: tier 3 revisit spawns exactly the predicted elites; tier 0 and a first visit none | `tools/check_revisit_remix.gd:370` |

## 9. Contract notes and follow-ups

- Needs a short entry in `implementation-decisions.md` and a line in `content-catalog.md` (common
  enemies), since elites change enemy HP, speed, cadence and drops in the campaign.
- Ambush waves are not remixed; they are their own action peak with catalog HP (ambush rule R5).
- Dying in a first-visit room reloads it as discovered, so at tier 1 or above its elites appear on
  the respawn. This matches "revisit" loosely and is accepted.
- Tier 3 is only reachable if play continues after the final boss.
- Balance (chances and multipliers) is working data pending the F1 play test.
