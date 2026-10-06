# Phase 2 — compact, finished campaign

Status: **mini-campaign done and beaten by the user** (D16): 16 rooms (fringe 5, nexus 2, vaults 3,
kiln 3, depths 3) with the full progression graph below, three bosses, save/continue, full map and
minimap, per-area art and music, surprise enemies (D20) and living environment (D21). Remaining for
F2: grow toward ~48 rooms, harder bosses, balance/new-player tests and release export.
Phase 2 builds on [Phase 1](phase-1-devmode.md). D19–D21 added the original arsenal, surprise
enemies and living environment; finished systems receive world, location, and balance work.

## Content budget

**Suggested production framework:** 48 rooms distributed across five areas, including boss rooms,
save rooms, and connections. A room is a bounded map node, not necessarily one screen wide. Adjust
size and rhythm after playtesting; do not fill empty corridors to reach 3–5 hours.

| Area / ID | Rooms | Visual identity | Function and content |
|---|---:|---|---|
| Fringe Cavern / `fringe` | 10 | Wet blue-grey stone, remains of the surface | Start, Seed Crossbow, Slipstream, first Bolt Quiver, pulses, Focus Lens on a side path. |
| Resonance Hub / `nexus` | 10 | High cracks, echoes, streams of water | Interconnecting hubs; two open branches, return paths, tanks, and visible final gate. |
| Drop Vaults / `vaults` | 10 | Cold limestone, hanging formations | Bubble Snare, Updraft Cloak, Bubble Floaters, Stone Guardian. |
| Glow Passages / `kiln` | 10 | Hot rock, steam, glowing cracks | Pressure Seal against dangerous heat, Echo Shot, Cinder Warden. |
| Deep Chamber / `depths` | 8 | Pressure, dark water, pulsating mineral | Undertow Dash, final combinations, Tidal Heart, and ending. |
| **Total** | **48** | | **Thirteen common enemy types and three bosses, reused from the dev track.** |

Preliminary reward budget: **six Heart Pearls** and **twelve Bolt Quivers** in the initial unlock
set, plus four implemented Flux Tanks for systems carried from Phase 1. Operating values are +100
health, +5 harpoon bolts, and +50 Flux per unique container, for maxima 700 health, 60 harpoon bolts, and 300
Flux. The mini-campaign places a subset; full placement follows the 48-room expansion. No hidden boss-ability bonuses.

## Progression graph

```text
Fringe Cavern: start → Slipstream + Seed Crossbow → first Bolt Quiver → Resonance Pulse
                                        ↓
                                  Resonance Hub
                            ↙                       ↘
Drop Vaults: Snare → Updraft       Glow Passages: Pressure Seal → Echo
                    ↓                                  ↓
            Stone Guardian                     Cinder Warden
                            ↘                       ↙
                         both persistent boss flags
                                        ↓
                              Deep Chamber: Undertow Dash
                                        ↓
                           Tidal Heart → ending
```

- Arrows show availability, not separate levels or automatic transport. All areas are connected;
  revisits and shortcuts are part of the main experience.
- Drop Vaults and Glow Passages can be completed in **any order**. Neither branch requires the other's
  upgrade. Each branch has a shortcut back to the hub after its boss.
- Snare and protection come before their local mandatory gates. Updraft Cloak must not be locked behind a
  jump that already requires Updraft Cloak. Undertow Dash is ahead of its first required use.
- Focus Lens is optional but useful. No mandatory battle requires a missed optional upgrade.
- New areas show at least one inaccessible side path before the relevant ability and at least one
  revisit reward afterward. The map marks discovered openings, not unseen solutions.
- Boss flags change the world; they are not additional collectibles.

## Gates and protection against false gating

| Gate | Opening rule | Protection against errors/softlocks |
|---|---|---|
| Low Tunnel | Slipstream, 64 px height | No standing passage; free return in ball; safe place to rise. |
| Cracked crystal | Pulse | Recovery/persistence defined; pulse jump may provide skill shortcuts. |
| Harpoon Socket | One harpoon opens it permanently (suggested) | Guaranteed refill is reached before the lock; no random drop required. |
| Snare mechanism | A frozen enemy keeps the highlighted mechanism active | Not only a height gate that wall jumps can bypass; the missing enemy can respawn. |
| Jump ledge | Updraft Cloak facilitates it; mandatory test without wall support | Wall jumps and pulse jumps are tested. Accidental shortcuts must not block later progression. |
| Heat exposure | Protection makes exposure bearable | No automatic death on area change; last safe room and return route before danger. |
| Resonant membrane | Echo Shot passes through a readable grid | Plain stone stops the beam; the rule is shown locally, not through an invisible special flag. |
| End gate | Both regional boss flags | Opening is saved; no dependency on replaying a boss death animation. |
| Undertow barrier | Active Undertow Dash while spinning | Normal jump, ball, and passive contact do not open it. Safe retake. |

Heat exposure should not act alone as an absolute ability gate: Heart Pearls can enable skill paths.
Critical order is secured by geometry and persistent locks. Do not force order through arbitrary dead
zones or by weakening the existing wall jump.

P8 supplies a room list with IDs (`fringe_01`, etc.), neighbors, entrances, return paths, ability
requirements, pickups, save point, enemies, and visual landmark. Review it before final graphics. All
unique pickups receive stable world IDs; if a pickup moves, it retains its ID.

## Encounter pacing

Direction: more action, fewer puzzles. No stretch of 24 columns along a room's long axis (12 rows
in a room taller than wide, since a climb is slower than a walk) is empty of threats: each needs a resident enemy or an ambush arena's spawn area. In a room without an ambush a
stalactite also counts, because the rooms before the first weapon (fringe_01, fringe_02) may only
hold threats the player can dodge (stalactites and Crawlers, which no early weapon harms and she
jumps over); every other enemy must be beatable with the kit on first arrival. Boss
rooms, the ending room and the hub are exempt. `tools/campaign_pacing.py` enforces the rule inside
`tools/check_campaign_graph.py`.

Jev round 9 (2026-10-01) filled the walks the critic rated lowest (rounds 6 to 8: no enemy within
640 px of the route, fun 0.39 to 0.46):

| Room | Added | Why |
|---|---|---|
| `fringe_01` Surface Breach | Stalactites over the start basin (cell 22, 3) and the shelf walk (34, 2), (39, 2), (44, 2) | Only the exit's Mimic Lure stood in the 60-cell start room, and she has no weapon yet. |
| `fringe_02` Drip Shaft | Stalactites under the shaft ledges (21, 9), (13, 12), (22, 15) | The descent was empty above row 24; still no weapon here. |
| `fringe_03` Echo Gallery | Spitter on the lower floor (36, 14); Hopper past the save (52, 14) | After the beam trial the east third was an empty walk to the missile gate; a ground rusher and a ranged Spitter ask for movement and a choice of target. |
| `fringe_04` Pulse Chimney | Vent Flyer at the top by the Pulse Bombs (10, 3); Spitter on the lower east ledge (20, 22) | The top and the lower climb were empty (rated boring and too long, no damage). |
| `kiln_02` Furnace Shaft | Vent Flyer mid-shaft (20, 19) | Rows 9 to 25 of the heat shaft were empty between the upper flyer and the antechamber. |

Round 10 (2026-10-06, from the PR 12 Jev review and rounds 5 to 9): the stalactites fell behind
her, so the weaponless rooms still rated 0.65; the 48-room corridors on the lower vaults route and
the hub connector rated 0.61 to 0.66 (too easy, too short). `tools/check_campaign_moves.gd` (`route_threats`) stands on a route cell of each
room and requires a resident enemy to come within 160 px.

| Room | Added | Why |
|---|---|---|
| `fringe_01` Surface Breach | Crawler on the pickup block (38, 8), heading west | It meets her on the block or the lower floor on the way to the shaft; she jumps it. |
| `fringe_02` Drip Shaft | Crawlers on the ledges (13, 16) and (23, 19) | They crawl the shaft walls and ledges she drops past and reach the floor by the Slipstream. |
| `vaults_04` Stalagmite Steps | Hopper on the floor (15, 14); Ceiling Diver over the steps (17, 1) | The drop from vaults_02 landed in an empty hall; only the exit's Armored Guard engaged. |
| `vaults_05` Drip Basin | Hopper on the floor (9, 14); Spitter on the block (23, 12) | The walk from either entrance to the vaults_09 drop held only a Frost Floater. |
| `vaults_09` Plumb Line | Hopper by the landing (10, 14); Spitter on the east block (29, 12); Vent Flyer before the current (36, 8) | The 36-cell floor walk held one Crawler; the refill end stays quiet. |
| `nexus_03` Chime Gallery | Grasshopper on the floor (7, 15); Vent Flyer (15, 8); Spitter on the platform (22, 10) | The connector was empty; the hub stays exempt from the rule. |

Fairness fixes in the same round: a one-tile curb on each side of the vaults_02 floor shaft to
vaults_04 (cols 7 and 11) stops a player walking away from the Bubble Snare from dropping into the
room below by accident; the drop stays a deliberate hop. The upward door lift
(`campaign_root.gd`, `UP_ENTRY_SPEED`) is no longer cut by letting go of jump after the room
change (`Player.apply_door_lift`): in a real nexus_07 probe a held High Jump cleared the nexus_01
floor by 104 px, but a release in the first frames after the door cut the lift to 40 % and dropped
her back.

## Saving, death, resources, and map

- At least one safe save/refill point per area; an accessible save point comes before each boss.
- Save discovered rooms, unique pickups, capacities, abilities, active beam, opened permanent gates,
  boss flags, and safe return point. Never save flying projectiles or ongoing knockback as a permanent
  condition.
- Death waits 0.45 seconds, restores full health at the last checkpoint, and keeps current progress in
  memory. Death does not load the disk save; this is the stipulated exception to the older death-save
  plan. Boss victory provides an atomic safe autosave after updating the arena and return point. This
  behavior is already tested in Phase 1.
- Damaged or unknown save versions must not be silently overwritten. Keep a backup and show an
  understandable menu error; no tutorial box belongs in the game world.
- Common enemies return on room revisits according to a common rule; defeated bosses do not. An occupied
  Heart Pearl never becomes a new tank when changing rooms or recharging.
- Mandatory ammo is available through guaranteed refills, not only random drops. Test every mandatory
  lock and boss route with zero ammo at the previous safe point.
- The map shows discovered rooms, connections, current room, save points, and visited blocked paths
  with icons. No quest arrow or text reveals a puzzle's solution.

## Game done, not just world done

- Start menu with new game, continue, settings, and quit. Overwriting requires confirmation.
- Pause menu, map, unlocked beam selection, and separate main/music/effects volume.
- Keyboard and documented default controls, with rebinding and a way to reset controls. Focus change
  or loss of focus pauses safely.
- Readable HUD icons for health, tanks, harpoon bolts, and selected weapon; color is not the only signal.
  Options reduce flashes and shaking without hiding damage or attack windows.
- Distinct sound identity for areas, materials, pickups, freezing, pulses, spin, and boss phases. Music
  loops and transitions should work across room changes and charging.
- Final boss → short environmental ending → credits → return to the save before the final encounter.
  No long interlude is needed, and the save is not deleted.
- First release platform: Linux desktop as the development environment. Windows export is added only
  with an actual test environment and separately approved test scope; it is not an unsubstantiated promise.

## Phase gate F2

- [ ] All 48 planned rooms have a purpose, correct map connection, and finished visual treatment.
- [x] Main route completed from an empty save profile without developer mode (16-room mini-campaign).
- [ ] Both branch orders completed; no circular ability requirements.
- [ ] At least one playthrough without optional tanks or Focus Lens; required resources secured.
- [ ] Revisiting after each ability gives at least one meaningful shortcut or reward.
- [x] Room graph/IDs validated (campaign graph solver check); duplicate pickups, duplicate boss rewards, and broken respawn tested.
- [ ] Save/load, death, process restart, and damaged save file tried in an exported build.
- [ ] Two new testers try without verbal guidance; time, stops, and misunderstandings are logged.
  The 3–5-hour target is attempted; deviation leads to design decisions, not artificial padding.
- [ ] Image, animation, and sound reviewed in all areas; no visible placeholders.
- [ ] Performance budget established on a documented reference machine; 60 fps target tested in the
  heaviest room and boss fight. Machine, resolution, and frame-time spikes are reported.
- [ ] Release export starts outside the editor and has no accessible dev mode.
- [ ] Provenance/credits complete, known bugs sorted, and no blocking errors open.
- [ ] The dev track's F1 regression also passes with the campaign's final system build.
