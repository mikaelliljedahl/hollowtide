# Hollowtide — content catalog

Status: implemented in the Phase 1 dev track (S0–S10) and the playable 16-room Phase 2 mini-campaign.
Catalog includes the original arsenal (D19), Flux Shield/Burst/Echo with four Flux Tanks, thirteen
common enemy IDs, six surprise enemies (D20), living-environment elements (D21) and three bosses.
Goal: five contiguous areas, 3-5 hours first playthrough, 48 rooms as planning budget.
No tutorial text or pop-up instruction in the game world.

## Names and internal IDs (D19)

Hollowtide's arsenal is original. Player-visible names come from `DISPLAY_NAMES` in
`scripts/progression/content_catalog.gd`. Most internal IDs stayed when D19 renamed the arsenal; the
four that still echoed older genre names were renamed later (`slipstream`, `undertow_dash`,
`pressure_seal`, gate kind `undertow`, see [state.md](state.md#aggregate-status)). This catalog uses the
visible names; IDs appear in `code`.

| Internal id | Visible name | Function |
|---|---|---|
| `beam` (bolt `base`) | Seed Crossbow (Seed Bolt) | Base weapon, 10 damage. |
| `long_beam` | Focus Lens | Passive range upgrade for every bolt. |
| `ice_beam` (bolt `ice`) | Bubble Snare | Traps an enemy in a rising, standable air bubble. |
| `wave_beam` (bolt `wave`) | Echo Shot | Ricochets off terrain up to 3 times; passes resonant membranes. |
| `missiles` / `missile_tank` / `missile_refill` | Harpoon / Bolt Quiver / Quiver Cache | Heavy bolt; embeds in rock as a temporary peg (~5 s, max 2); opens Harpoon Sockets. |
| `bombs` | Resonance Pulse | Expanding ring from Slipstream form; cracks Cracked Crystal; lift impulse. |
| `undertow_dash` | Undertow Dash | Short horizontal dash (ground or one per air jump); damages enemies passed through; breaks Undertow Barriers. |
| `slipstream` | Slipstream | Compact water-droplet form for low tunnels. |
| `high_jump` | Updraft Cloak | Higher grounded jump plus jump-hold glide. |
| `pressure_seal` | Pressure Seal | Halves contact, projectile and environmental damage. |
| `energy_tank` | Heart Pearl | +100 max health. |

Gates: `missile` → Harpoon Socket, `wave` → Resonant Membrane, `bomb` → Cracked Crystal,
`undertow` → Undertow Barrier. Ammo is shown as "Bolts". Flux Shield, Burst Beam and Echo Scan keep
their names. "Freeze"/"frozen" below means trapped in a Bubble Snare bubble
(internal state name kept); Frost Floaters are presented as bubble floaters.

## Stable ID scheme

Content-ID describes the content type (`UPG-*`, `REF-*`, `EN-*`, `BOSS-*`). Each placed pickup
also has a separate, stable world-pickup-instance ID that records collection and tracks
its location when it moves. Never repurpose an existing ID; new variants receive new content IDs.
`fringe` / `nexus` / `vaults` / `kiln` / `depths` describe areas; `fringe_01` and equivalent
area prefixes describe rooms.

## Implemented operating values

Track `docs/game-feel.md` exactly for walk, standing/Ball jump, ball movement, wall jump, health 100,
crawler contact damage 12, invulnerability, knockback, and input lock. Values below are implemented
Phase 1 operating values; balance and human approval remain F1 work.

- Seed Crossbow damage 10; Focus Lens is passive 1.75× base/ice/wave range; Bubble Snare freezes `F` targets
  without harm; Echo Shot 12.
- Harpoon damage 35; pulse damage 20; Undertow Dash 24 per valid hit, maximum of one hit per
  coherent target overlap. Withdrawal and new contact can lead to a new hit.
- Pulse: 0.75 s fuse, 72 px radius, and separate bomb-lift impulse `velocity.y = -720`; affects
  ground and airborne enemies within radius. Only Slipstream form can place pulses.
- Slipstream regular jump: grounded/coyote A/Space (A primary, Space alternate) uses unchanged base
  `JUMP_VELOCITY` while retaining Ball form/collider. No Updraft Cloak multiplier, wall jump, spin/Dash, or midair double jump. Pulse lift
  remains independent and unchanged.
- Updraft Cloak: a dedicated grounded-jump modifier of about 1.5× measured base height. Exact impulse is determined
  in P0; do not overwrite the base constant `JUMP_VELOCITY`. Other gravity and terminal velocity
  follow game-feel.
- Pressure Seal per D07 halves valid contact, projectile, and environmental damage,
  rounded up.
- Heart Pearl +100 max health and full energy refill; Bolt Quiver +5 max harpoon bolts and refill
  according to D03. Basic max is 0 harpoon bolts.
- Six Heart Pearls give a maximum of 700 health. Twelve Bolt Quivers provide a maximum of 60 harpoon bolts; first
  Bolt Quiver unlocks harpoon bolts, gives +5 and refills current ammo with +5.
- Separate refill: energy +25, harpoon bolts +2; refill never changes maximum capacity and can recur
  after the room reset according to the pickup rule.
- Implemented enemy values: HP/contact `crawler 105/12`, `ceiling_diver 30/16`,
  `vent_flyer 20/10`, `hopper 24/14`, `spitter 28/10`, `armored_guard 60/20`,
  `frost_floater 32/12`, `energy_parasite 18/8`, `shard_turret 36/10`, `burrower 42/16`,
  `grasshopper 30/12`, `shooting_gargoyle 36/14`, and `lava_monster 48/16`.
- Implemented boss values: `stone_guardian 300/24`, `furnace_mother 360/28`, and
  `tidal_heart 400/20`. F1 may lead to deliberate balance changes through the catalog source of truth.
- Flux: first module gives 100 maximum/current; each of four tanks adds 50 and fully refills, maximum
  300. Refill gives 10; Echo costs 20; Burst drains 8/s; Shield costs one Flux per absorbed damage.

## Implemented common systems

| ID | System | Contract / concrete acceptance |
|---|---|---|
| SYS-STATE | GameState | Owns abilities, active beam, max/current energy and harpoon bolts as well as world state data; does not own serialization. |
| SYS-SAVE | Save System | Separate system serializes, validates and loads GameState/world snapshots atomically. |
| SYS-PICKUP | Pickup | Unique instance ID; pickup once; double pickup never doubles capacity. |
| SYS-REFILL | Refill | Separate from tanks; fills current resource, not maximum capacity. |
| SYS-WEAPON | Weapons | Owns projectiles and ammunition; player calls `Weapons.fire` and never owns ammo logic. |
| SYS-DAMAGE | Damage | Player owns invulnerability/knockback; enemies call `take_damage`; HUD follows signals. |
| SYS-BOMB | Pulse | Ball-only placement, block damage, fuse, lift and cleanup at reset. |
| SYS-FREEZE | Freezing | Freezes valid enemies into stable platforms; timer, defrosting and safe cleanup. |
| SYS-SPIN | Spin | Normal aerial somersault; never deals damage. |
| SYS-UNDERTOW | Undertow Dash | Damage only during an active dash; status is visible in dev overlay. |
| SYS-DEV | Dev Mode | Same pickups/system as campaign; separate profile, atomic preset, safe respawn. |
| SYS-RESET | Reset | Clears projectiles, pulses, drops, frozen bodies, enemies, blocks, doors and timers. |
| SYS-HUD | HUD | Health/ammo meters; no instructions. |
| SYS-MAP | Map | Small room connections in Phase 1; reads discovered rooms and system state. |
| SYS-GATE | Ability gate | Positive/negative test for each gate; no softlock after dev reset. |
| SYS-LOOT | Temporary combat loot | Common enemies may drop energy, harpoon, or Flux refills; +25 health, +2 harpoon bolts, or +10 Flux, clamped and without persistent pickup IDs. |
| SYS-FLUX | Shared Flux runtime | One owned module selected at a time: Shield/Burst toggle; Echo pulses. Capacity, drain, HUD, VFX/audio, reset, and save/load use schema v2. |

## Abilities, weapons, and capabilities

Active beam is exactly one of `base`, `ice`, `wave`. Focus Lens is a permanent passive
range modifier for all three active variants, not an active beam variant. Found beams are
retained permanently; swap changes active variant, not ownership. Seed Crossbow is an early pickup. Phase 1 includes authored ability/beam gates and resonant grate test fixtures;
Phase 2 placement remains unstarted. Each ability/container has pickup, icon/animation, sound, dev
selection, reset, and save/load coverage. `UPG-MISSILES` is the system unlock from `UPG-MISSILE-01`,
not another pickup or extra capacity.

| ID | Pickup, dependency, gate | Function | Positive test | Negative test |
|---|---|---|---|---|
| UPG-BEAM-BASE | Early pickup; no dependencies; authored beam gate | Ground shot, 10 damage | Shot hits target and can open authored beam gate | Before pickup: firing does nothing |
| UPG-BEAM-LONG | Beam; authored long-range target | Passive 1.75× range on base/ice/wave | Focus Lens target is hit with each owned active beam | Before pickup range misses the same target |
| UPG-BEAM-ICE | Beam; authored freezing target | Freezes `F` targets without damage | Enemy becomes platform during timer without HP loss | Non-freezable enemy does not change status |
| UPG-BEAM-WAVE | Beam; authored marked resonant grate/relay | 12 damage; passing marked channel | Hits switch behind marked grate | Solid unmarked wall blocks the shot |
| UPG-MISSILES | Beam; authored harpoon socket; first tank unlocks | 35 damage, ammo spent | `spend_missile()` decrements by 1; crawler at 105 HP requires 3 × 35 hits | Empty ammo or locked harpoon bolts do not fire |
| UPG-SLIPSTREAM | Orb; existing 1-tile passage | Slipstream shape, 56×56 hitbox; grounded/coyote base jump while retaining form/collider | Pass 64px opening and jump at base impulse | Standing form does not pass; no Ball Updraft Cloak, wall jump, spin/Dash, or double jump |
| UPG-BOMBS | Slipstream; pulse block | Fuse, explosion, radius, and separate pulse lift | Pulse damages block/targets and explosion lifts Ball | Humanoid cannot place pulses; regular jump never triggers pulse lift; targets outside radius are not hit |
| UPG-HIGH-JUMP | No new ability; authored height gate | Ground jump approximately 1.5× measured height after pickup | Authored height gate is reached; wall jumps retain their rules; global impulse does not change | Before pickup, use measured base jump height |
| UPG-PRESSURE-SEAL | No new ability; authored environmental hazard | Contact, projectile, and environmental damage ×0.5, rounded up | Valid damage 11 becomes 6 | Excluded damage sources are not reduced |
| UPG-UNDERTOW | No new ability; Undertow Barrier | Dash deals 24 damage and breaks barriers | Enemy is hit once per dash | Spin, walking, Slipstream and protected boss contact deal no dash damage |
| UPG-FLUX-SHIELD | No dependency on other Flux modules | Absorbs valid damage at 1 Flux per damage | F toggles shield; meter drains by absorbed amount | Zero Flux disables it; no hidden health mutation |
| UPG-BURST-BEAM | No dependency on other Flux modules | Rapid 6-damage beam, 0.075 s cadence, 8 Flux/s | F toggles sustained burst while selected | Zero Flux stops Burst; normal beam ownership rules remain |
| UPG-ECHO-SCAN | No dependency on other Flux modules | F spends 20 for 900 px reveal pulse | Reveals nearby registered signals/secret surfaces | Below 20 Flux produces no pulse |
| UPG-FLUX-TANK-01–04 | Any owned Flux module | +50 max and full refill, maximum 300 | Four unique tanks reach 300 | Repeated ID and fifth tank add nothing |
| REF-FLUX | Any owned Flux module | +10 current Flux, clamped | Partly empty meter increases by 10 | No ownership or full meter gives no excess resource |
| UPG-ENERGY-01 | Well; optional side reward, no HP gate | Max health +100 and full energy refill | Max 200, pickup saved and energy filled | Double pickup does not max out at 300 |
| UPG-ENERGY-02 | Well; optional side reward | Max health +100 and full energy refill | Max example 300 after unique pickup | Number does not require UPG-ENERGY-01 |
| UPG-ENERGY-03 | Well; optional side reward | Max health +100 and full energy refill | Max example 400 after unique pickup | Refill does not increase max |
| UPG-ENERGY-04 | Well; optional side reward | Max health +100 and full energy refill | Max example 500 after unique pickup | Rejecting invalid dev ID leaves state intact |
| UPG-ENERGY-05 | Well; optional side reward | Max health +100 and full energy refill | Max example 600 after unique pickup | Death/respawn restores last saved capacity |
| UPG-ENERGY-06 | Well; optional side reward | Max health +100 and full energy refill | Max example 700 after unique pickup | Max cannot exceed 700 via tank pickup |
| UPG-MISSILE-01 | Beam; before first authored harpoon socket, no harpoon required | +5, caps `has_missiles` and refills current ammo +5 | Max 5, one shot can be spent | Before pickup fire does nothing; double pickup does not give +10 |
| UPG-MISSILE-02 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 10 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-03 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 15 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-04 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Maximum example 20 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-05 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 25 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-06 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 30 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-07 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 35 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-08 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 40 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-09 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 45 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-10 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 50 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-11 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 55 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| UPG-MISSILE-12 | Only `has_missiles`; authored harpoon socket test | +5 max harpoon bolts and refill +5 | Max example 60 | Previous tank numbers are not required; repeated ID/reset does not duplicate |
| REF-ENERGY | Refill point | +25 current health, clamped | Injured player gains health | Full health does not exceed maximum |
| REF-MISSILE | Quiver cache point | +2 current ammo, clamped | Ammo increases by 2 | Before harpoon unlock, refill grants no hidden ammo |

### Unlocking and status rules

- `UPG-MISSILE-01` is placed before all authored harpoon socket tests; no circular gate. It is the only row
  that both gives capacity and sets `has_missiles`; `UPG-MISSILE-02`–`12` require only
  the unlock, never a tank number. The maximum examples indicate number, not order of collection.
- Each Heart Pearl fills energy completely according to D03. Each Bolt Quiver provides +5 current ammo;
  the first container also unlocks harpoon bolts. Refill never changes capacity.
- Heart Pearls are optional side rewards. No first tank or energy gate may
  require higher maximum health.
- `UPG-BEAM-*` sets ownership separately. Active selection is saved, and switching is not pickup.
- Slipstream safely aborts on dev-reset; player is moved to safe spawn before ability is removed.
- All twelve dev-track Bolt Quivers retain stable IDs and count. Runtime TileMap audit confirms each
  has standing-safe collection overlap, retreat space, and a return to main route.
- Flux module/tank/refill state is persisted in schema v2. Valid v1 saves migrate with no Flux ownership
  or latent charge.
- Resonance Pulses and projectiles cannot remain after room change, death, load, or station reset.

### Tide Sockets and Tide Glyphs

Accepted 2026-09-24; design in [features/tide-modules.md](features/tide-modules.md). Two pickup kinds,
registered in `ContentCatalog.TIDE_PICKUP_KINDS` and collected like every unique pickup:
`tide_socket` (+1 capacity, three in the campaign, capacity 2 to 5) and `glyph_<id>` (one each of seven
glyphs, costs 1 to 3). All ten are optional campaign pickups; none depends on a sequence break. Glyphs
are socketed only at save shrines and each pairs a gain with a downside; numbers live only in
`scripts/progression/tide_catalog.gd`. Names avoid charm, notch, badge, BP, shard, chip and ring slots.

## Spin and Undertow Dash

`spin` is the normal aerial somersault (D06) and deals no damage. Undertow Dash (`undertow_dash`)
replaces the old spin attack: a short, fast horizontal dash on the ground or once per airborne jump.
During the dash the player passes through enemies and deals 24 damage, at most one hit per target per
dash, and breaks Undertow Barriers. Slipstream form cannot dash. Pause, death, room change and reset
end a dash. Dash is ignored against a protected boss phase.

## Phase 1 expansion: five additive regular enemies and occasional loot

The live decisions expand the original eight common enemy types with five custom types. They are not new
campaign systems and do not change stable ability IDs or boss budgets. Existing IDs remain stable:

| Runtime ID | Visible Name | Current Behavior | Current data |
|---|---|---|---|
| `shard_turret` | Shard Turret | Stationary turret with telegraphed directional three-fragment volley. Can be frozen and defeated according to common battle matrix. | 36 HP, 10 contact |
| `burrower` | Burrower | High alert → emergency → short vulnerable window → retreat. Can be frozen and defeated according to common battle matrix. | 42 HP, 16 contact |
| `grasshopper` | Grasshopper | Fast ground skitter, readable compression, direction-locked long leap, then landing recovery. | 30 HP, 12 contact |
| `shooting_gargoyle` | Shooting Gargoyle | Folded armor blocks attacks; wake/charge telegraphs expose it before one aimed projectile and recovery. | 36 HP, 14 contact/projectile |
| `lava_monster` | Lava Monster | Submerged movement is a true miss; bubbles precede a surface window. Snare quenches it into a platform. | 48 HP, 16 contact |

Enemy loot is temporary and does not affect the save profile. Current drop chance is 0.34 for common
enemies and 0.70 for bosses. When Flux is owned and below capacity, Flux refill has 0.18 first-pass
weight; remaining result selects harpoon at 0.28 or energy. Energy restores 25 health, harpoon restores
2 harpoon bolts, and Flux restores 10; all are clamped
to existing capacity. Dropped loot waits to land on terrain, has a limited lifetime, and is
cleared on reset/death. These are implemented working values, not user balanced F1 values.

## Reaction matrix

`D` = implemented catalog damage, `F` = freezes without damage, `I` = immune/bounce, `—` = none
here, and `G` = selected grid/switch track only. The pulse's `D` applies to ground and air targets within
the radius; distances outside the radius do not result in a hit. Snare gives `F` on all freezeable targets and `I` on
crawler. Dash only applies to `undertow_active`.

| Target | Seed Bolt | Snare | Echo | Harpoon | Pulse | Dash |
|---|---:|---:|---:|---:|---:|---:|
| EN-CRAWLER | I | I | I | D | I | I |
| EN-CEILING-DIVER | D | F | D | D | D | D |
| EN-VENT-FLYER | D | F | D | D | D | D |
| EN-HOPPER | D | F | D | D | D | D |
| EN-SPITTER | D | F | D | D | D | D |
| EN-ARMORED-GUARD | I | F | I | D | D | I |
| EN-FROST-FLOATER | D | F | D | D | D | D |
| EN-ENERGY-PARASITE | D | F | D | D | D | I |
| EN-SHARD-TURRET | D | F | D | D | D | I |
| EN-BURROWER | D | F | D | D | D | I |
| EN-GRASSHOPPER | D | F | D | D | D | D |
| EN-SHOOTING-GARGOYLE (folded) | I | I | I | I | I | I |
| EN-SHOOTING-GARGOYLE (open) | D | F | D | D | D | D |
| EN-LAVA-MONSTER (submerged) | — | — | — | — | — | — |
| EN-LAVA-MONSTER (surface) | D | F | D | D | D | I |
| EN-LAVA-MONSTER (quenched) | D | F | D | D | D | D |

So `EN-CRAWLER` can only be killed by harpoon bolts. Beam hit gives clear bounce/clunk, never
HP loss. Snare `F` deals no HP damage. Frozen target follows the same damage matrix for all other attacks; harpoon bolts can thus damage
or kill it. Another Snare hit restarts the freeze clock with no HP damage. No HP reset on defrost. Frozen enemies cannot damage or pinch the player while
they are platforms; contact damage is disabled.

### Boss phase protection

Bosses react only to the specified damage type or trigger during each opening. All other
damage types are `I` (immune) in that phase; no weapon variant bypasses protection. Phases are selected in dev mode
but full boss round must also be tested.

| Boss ID | Phase | Allowed damage hit / trigger | All other types of damage |
|---|---|---|---|
| BOSS-STONE-GUARDIAN | B1 body open | Harpoon or Dash | Beam, Snare, Echo, Pulse = I |
| BOSS-STONE-GUARDIAN | B2 stone armor | Harpoon only during the opening | Beam, Snare, Echo, Pulse, Dash = I |
| BOSS-FURNACE-MOTHER | B1 core exposed | Echo or Harpoon | Beam, Snare, Pulse, Dash = I |
| BOSS-FURNACE-MOTHER | B2 overheated | Harpoon only during the cooling window | Beam, Snare, Echo, Pulse, Dash = I |
| BOSS-TIDAL-HEART | B1 pulse point | Snare freezes the pulse point without damage and opens a harpoon window; then Harpoon | Beam, Echo, Pulse, Dash = I |
| BOSS-TIDAL-HEART | B2 tidal shield | Echo through the marked breaker path opens a window without damage; then Harpoon | Beam, Snare, Pulse, Dash = I |

Regional bosses' paths must not require other branches' upgrades: Stone Guardian does not require
Echo and Cinder Warden does not require Snare/Updraft Cloak. Phase 1 arenas implement catalog HP and a
guaranteed recurring quiver cache so mandatory fights do not depend on random drops. Campaign
placement remains P8/P9 work.
Stone Guardian pursues on the arena floor, Cinder Warden scuttles and reverses within its lane, and
Tidal Heart drifts within its bounded chamber. Their health bars and authored-silhouette projectile
hurtboxes make accepted damage observable; protected hits remain distinct from misses. These movement
and targeting repairs do not change HP, damage matrices, progression IDs, flags, or save semantics.
Each missile-requiring boss arena has a guaranteed, recurring refill source reachable below
the battle without harpoon payment. Test with only the first container's capacity (5), zero ammo
on entry, and missed shots. Optional tanks must not become a hidden mandatory HP/ammo requirement.

## Freezable platforms — default

Only `freeze_capable = true` targets can be frozen when their current state exposes a target: ceiling
divers, vent flyers, hoppers, spitters, armored guards, frost floaters, Leech Wisps,
`shard_turret`, `burrower`, `grasshopper`, an open `shooting_gargoyle`, and a surfaced
`lava_monster`. The Frost Floater is a central freezing platform and is
freezable by Snare (`F`), not immune to Snare. Snare freezes without damage according to the matrix. Frozen body becomes solid
platform with the same collision width as the target, stops at the current location and gets a fixed maximum life
`FREEZE_TIME = 4.0 s` (implemented). The platform thaws with short notice, without teleport or
damage.

The player must not get stuck: when defrosting, the AI will only reset when its damaging collision shape
does not overlap the player. Standing on top does not count as body overlap; when the platform disappears, the player falls normally. No teleport as standard solution. Frozen target cannot move, shoot or give
contact damage; contact is disabled. Harpoon can hit frozen target and deal matrix harpoon damage.
HP is retained while freezing and resumed on thawing, without HP reset or double hit. Reset
clears frozen bodies.

## Common enemies

All thirteen enemy types are selectable in the dev track and reuse their campaign-ready factory scenes,
with contact damage, cleanup, reset, loot rules, and an overlay ID. S7 keeps a readable isolated
catalog cell instead of rendering all thirteen on top of one another. Grasshopper, Shooting Gargoyle,
and Lava Monster also have natural Phase 1 encounters in S3, S2, and S6 respectively. This is the
bounded Phase 1 expansion; it adds no campaign package.

| ID | Type | Behavior and special rules |
|---|---|---|
| EN-CRAWLER | Crawler | Follows surfaces across floor, wall, and ceiling; does not chase; only harpoon bolts deal damage. |
| EN-CEILING-DIVER | Ceiling Diver | Hangs from the ceiling, dives toward the player's last position, then returns. |
| EN-VENT-FLYER | Vent Flyer | Flies a short path between marked vents; deals contact damage; pulses hit within radius. |
| EN-HOPPER | Hopper | Jumps toward the player; can be frozen into a platform. |
| EN-SPITTER | Spitter | Stationary; fires an aimed projectile after a telegraph. |
| EN-ARMORED-GUARD | Armored Guard | Patrols; beam/wave bounce; harpoon/pulse bypass armor; can be frozen. |
| EN-FROST-FLOATER | Frost Floater | Central freeze-platform target in wet/frost zones; Snare freezes it; pulses hit within radius. |
| EN-ENERGY-PARASITE | Leech Wisp | Seeks the player; deals contact damage; can be frozen; immune to Undertow Dash. |
| EN-SHARD-TURRET | Shard Turret | Stationary turret with a telegraphed three-fragment volley. |
| EN-BURROWER | Burrower | Telegraphs, emerges into a short vulnerable window, then retreats underground. |
| EN-GRASSHOPPER | Grasshopper | Skitters rapidly, compresses visibly, commits to a long leap, and recovers on landing. |
| EN-SHOOTING-GARGOYLE | Shooting Gargoyle | Folded perch blocks hits; wake and charge expose it before one aimed shot. |
| EN-LAVA-MONSTER | Lava Monster | Tracks below lava, bubbles before surfacing, and becomes a frozen quenched platform under Snare. |

### Elite variants on revisits

Accepted 2026-09-24; design in [features/revisit-remix.md](features/revisit-remix.md). In the campaign
only, after each boss victory a common enemy in a room the player is revisiting may spawn as an elite:
chance 0.25, 0.40 and 0.55 per common spawn after one, two and three bosses. An elite keeps its ID,
AI, telegraphs, reaction matrix and damage; it has catalog health x1.6 (rounded up), x1.15 speed for
Hopper, Grasshopper, Armored Guard, Leech Wisp, Lava Monster and Crawler, attack and jump
cooldowns x0.8, a rose tint with a pulsing magenta rim, and drops two refills instead of the random
roll. First visits, surprise enemies, ambush waves, bosses and the dev track are never remixed, and an
enemy the current kit cannot beat is never made elite.

## Bosses

| ID | Arena / Readable Core | Phase structure |
|---|---|---|
| BOSS-STONE-GUARDIAN | Stone arena; body, armor, and readable opening | B1 open body; B2 armor opens after an attack, per matrix. |
| BOSS-FURNACE-MOTHER | Furnace chamber; heat cycle and cooling window | B1 exposed core; B2 overheat, Echo trigger, and harpoon window. |
| BOSS-TIDAL-HEART | Tidal arena; pulse point and switch path | B1 Ice-triggered pulse point; B2 shield and marked Echo channel, then harpoon. |

Each boss requires spawn/reset, a full defeat sequence, loot or persistent gate state, and save/load tests
and test negative against all shielded weapons. Phase lesson does not replace a full test round.
Phase 1 places Stone Guardian naturally in S5, Cinder Warden naturally in S7, and Tidal Heart naturally
in S8. Each has a checkpoint/refill approach and remains separately spawnable through the developer panel.
Kiln lava in S6 and the S7 catalog cell occupies carved floor basins with collision-aligned fluid surfaces
and jumpable basalt stepping cells; it is never presented on a suspended channel slab.

### Boss stages

Accepted 2026-09-24; design in [features/boss-rework.md](features/boss-rework.md). Each boss fight
runs four stages by health: stage 1 above 75 %, stage 2 above 50 %, stage 3 above 25 %, stage 4
(desperation) at 25 % and below. Stages 1 and 2 use the B1 row of the phase-protection matrix and
stages 3 and 4 the B2 row, so B1 still turns into B2 at half health. In B2 the Stone Guardian's armor
and the Cinder Warden's cooling window open during the punish window after each attack chain instead
of on a fixed cycle; the Tidal Heart keeps its Snare and Echo openings. Each of stages 1 to 3 adds an
attack; stage 4 chains two known attacks. HP, contact damage, the matrix, IDs and flags are unchanged.

## Surprise enemies (D20)

Six additive types; they appear once or twice per room in the campaign and are selectable in the dev panel.
Each telegraphs before it attacks.

| Runtime ID | Visible name | Behaviour |
|---|---|---|
| `bat_swarm` | Bat Swarm | Sleeping ceiling cluster that bursts into individual bats (`bat`) on proximity. |
| `mimic` | Mimic | Disguised as rock or a fake pickup; lunges when approached. |
| `drop_spider` | Drop Spider | Hidden above; drops on a thread when the player passes under. |
| `surface_eel` | Surface Eel | Lurks in a water or lava basin and strikes above the surface. |
| `stalker` | Stalker | Area hunter that follows between rooms (re-enters from the used door, keeps its HP); defeat is saved per area; never enters boss arenas or the ending. |
| `chasm_sniper` | Chasm Sniper | Hides in a chasm wall, exposes itself and fires aimed shots. |

Existing enemies were also made faster, with telegraphed charges (guard, Leech Wisp lunge, hopper).
Bubble Snare sizes its bubble to each surprise enemy.

## Living environment (D21)

Authored per room in campaign layouts; each has a headless check and procedural SFX. No dark zones.

| Element | Behaviour |
|---|---|
| Ambush arena | Carved slabs seal every opening once the player is inside, until the wave is beaten. |
| Timed door | Shoot the crystal-eye switch; a light gauge counts down while the slab is open. |
| Crumbling floor | Cracked tiles give way shortly after being stood on, then reform. |
| Stalactite | Loose spike with a glowing fracture; rattles, then falls when she passes under. |
| Crusher | Piston head with a fixed, safe 3.6 s rhythm and telegraph. |
| Push current | Water, wind or steam flow that pushes the player sideways or up. |
| Rising shaft | Lava or water that rumbles, then rises at 110 px/s — slower than a climbing player. |

The tide mechanic is postponed.

## Areas and room budget

Phase 1 builds hubs, test stations and connected exam rooms; phase 2 places the content without new systems. The campaign plan uses 48 rooms across five contiguous areas. No additional optional
maps.

| ID | Area | Room | Main function / boss |
|---|---|---:|---|
| `fringe` | Fringe Cavern | 10 | Start, Seed Crossbow, Slipstream, first Bolt Quiver, pulses and Focus Lens on side path. |
| `nexus` | The resonance hub | 10 | Hub, return paths, tanks and visible final gate. |
| `vaults` | Drop Vault | 10 | Snare, Updraft Cloak, bubble floaters and the Stone Guardian. |
| `kiln` | The glow passages | 10 | Pressure Seal, Echo and Cinder Warden. |
| `depths` | The Deep Chamber | 8 | Undertow Dash, final encounters, and Tidal Heart. |

## Gate for bounded implementation

1. Scaffold: record the content ID, world-pickup-instance-ID, state, pickup/reset, and capacity rules.
2. Weapons: beam values, Focus Lens as a passive range layer, projectiles, harpoon bolts, pulses, and the reaction matrix; preserve base movement.
3. Movement/graphics: create spin-state and spin-animation in P5; connect Updraft Cloak and Undertow Dash via agreed state.
4. Enemies/bosses: one spawnable scene per ID, then HP/status/drop and full cleanup.
5. Dev track: selectable stations, presets and safe respawns; campaign profile separately.
6. Verify each table cell positive and negative in real TileMap/scene; headless alone is not enough.

Catalog approval means all IDs can be selected, pickups can be reset, save/load works,
all thirteen enemies and three bosses are defeatable, the crawler remains beam-immune, spin never deals
damage, Undertow Dash deals damage only during an active dash, and Phase 2 hides no unfinished core system.
