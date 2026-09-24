# Feature design: Tide Sockets and Tide Glyphs

Status: implemented on a feature branch; design accepted by the user on 2026-09-24, see
[Accepted Tide Sockets amendment](../implementation-decisions.md#accepted-tide-sockets-amendment). Data lives in
`scripts/progression/tide_catalog.gd`, the loadout model in `scripts/progression/tide_modules.gd`,
the shrine glue in `scripts/campaign/tide_hook.gd` and the screen in `scripts/ui/tide_menu.gd`. The
screen is reached through the save-shrine menu shared with [fast travel](fast-travel.md)
(`scripts/ui/shrine_menu.gd`).

## 1. Goal

Hollowtide should lean toward action depth over puzzles. Tide Glyphs are passive modules the player
finds in the world and sockets at save shrines, so a loadout can be tuned for a boss, an ambush or
an area. Every glyph bends one part of the existing arsenal and pays for it elsewhere; no loadout is
strictly best. Capacity is limited by Tide Sockets, also found in the world.

Out of scope: new weapons, enemy changes, Undertow Dash and Flux glyphs (section 10), an automatic
loadout picker (forbidden, section 8).

## 2. Rules

- **T1 Capacity.** Capacity starts at 2 and each Tide Socket found adds 1, up to 5 (three sockets).
  `TideCatalog.BASE_CAPACITY`, `MAX_SOCKETS_FOUND` (`scripts/progression/tide_catalog.gd:7`).
- **T2 Cost.** Each glyph costs 1 to 3 capacity. The socketed set never exceeds capacity; a glyph
  that does not fit is refused. There is no over-capacity rule of any kind.
- **T3 Shrine only.** The loadout changes only while a save-shrine session is open
  (`TideModules.open_station` / `close_station`, `scripts/progression/tide_modules.gd:68`). Outside
  one, `equip`, `unequip` and `toggle` return false. Restoring a save never leaves a session open.
- **T4 Trade-off.** Every glyph has at least one gain and one downside, both player-visible in the
  menu. Effects are stat multipliers (composed by product) or additive `_add` stats (composed by
  sum), so stacking is predictable and two glyphs can cancel each other.
- **T5 Manual choice.** The player picks every glyph. The game never ranks or auto-selects glyphs.
- **T6 No text in the world.** Pickups, the shrine's up chevron and the menu teach the system. The
  only instruction lives in the pause menu's Controls help (approved text outside the game world).

## 3. Glyph catalogue

Numbers live only in `TideCatalog.GLYPHS` (`scripts/progression/tide_catalog.gd:28`).

| Glyph (id) | Cost | Gain | Downside |
|---|---:|---|---|
| Quickstring (`quickstring`) | 1 | Crossbow bolts fly 35% faster, reload 40% faster | Crossbow bolts deal 30% less damage |
| Farcast (`farcast`) | 1 | Crossbow range +40% | Crossbow reload 60% slower |
| Heavy Barb (`heavy_barb`) | 2 | Harpoon damage +60% | Each harpoon shot spends two bolts |
| Brine Hide (`brine_hide`) | 1 | 25% less damage from hits | Crossbow and Harpoon deal 20% less |
| Ebb Mend (`ebb_mend`) | 2 | Clearing an ambush restores 50 health | 20% more damage from hits |
| Deep Pulse (`deep_pulse`) | 2 | Resonance Pulse damage +75% | Resonance Pulse fuse 50% longer |
| Spring Tide (`spring_tide`) | 3 | Crossbow and Harpoon damage +35% | 35% more damage from hits |

Rounding: scaled integers round to nearest and a positive value never drops to zero
(`TideModules.scale_int`, `scripts/progression/tide_modules.gd:131`). Bubble Snare deals no damage
and stays at zero.

"Damage from hits" means every hit routed through `Player.take_damage`; heat exposure
(`scripts/campaign/heat_zone.gd`) applies damage directly and is not scaled by glyphs, so Pressure
Seal gating is unchanged.

Order with the damage-taken assist option (`scripts/progression/assist.gd`): `Player.take_damage`
applies the Pressure Seal divisor, then the assist multiplier, then `PlayerFluxRuntime.absorb_damage`
applies the glyph multiplier and finally the Flux Shield (`scripts/player/player.gd:182`). The assist
step rounds up and the glyph step rounds to nearest without dropping a positive hit to zero, so an
assist setting of 0 still blocks every hit and any other setting still hurts at least 1.

## 4. Where effects apply

| Stat | Applied at |
|---|---|
| `crossbow_damage`, `crossbow_speed`, `crossbow_range`, `crossbow_reload` | `Weapons._fire_beam`, `scripts/autoload/weapons.gd:86` |
| `harpoon_damage`, `harpoon_bolt_add` | `Weapons._fire_missile`, `scripts/autoload/weapons.gd:113`; a shot needs all its bolts |
| `pulse_damage`, `pulse_fuse` | `Weapons._fire_bomb`, `scripts/autoload/weapons.gd:138`; `Bomb.damage_amount` and `fuse_seconds`, `scripts/combat/bomb.gd:10` |
| `damage_taken` | `PlayerFluxRuntime.absorb_damage`, `scripts/player/player_flux_runtime.gd:70`, before the Flux Shield |
| `ambush_heal_add` | `TideHook._on_ambush_cleared`, connected to every `AmbushArena.cleared` |

`player.gd` is unchanged: every player hit already passes through `absorb_damage`.

## 5. Pickups and placement

Pickup kinds `tide_socket` and `glyph_<id>` are registered in `ContentCatalog.TIDE_PICKUP_KINDS`
(`scripts/progression/content_catalog.gd`) with icons, display names and sounds, and collected
through the generic pickup and `GameState.collect_pickup`. Icons are original procedural art built by
`tools/build_tide_art.py` (Pillow) into `assets/sprites/tide/`: a hexagonal socket frame and slate
tablets with a rune per glyph; rim colour marks the family (amber offence, teal defence, orange
pulse, coral high risk).

Placement is authored as `pickup` legend entries in the layouts and built by
`tools/build_campaign_rooms.py`. All ten are optional (`OPTIONAL_KINDS` in
`tools/check_campaign_graph.py`) and reachable in the graph solver's any-order run. None may depend
on an [intended sequence break](sequence-breaks.md): the solver's `no-breaks` run fails when a Tide
pickup is reached only through a break edge, and none sits on a break route or reward cell.

| Pickup ID | Room | Note |
|---|---|---|
| `fringe_03.quickstring` | Echo Gallery | Upper gallery, right after the Seed Crossbow |
| `fringe_05.farcast` | Long Hollow | Ceiling alcove, pairs with the Focus Lens room |
| `fringe_04.tide_socket` | Pulse Chimney | Left ledge in the chimney climb |
| `fringe_01.deep_pulse` | Surface Breach | Behind the cracked crystal, a Pulse revisit reward |
| `nexus_01.brine_hide` | Resonance Hall | Central platform of the hub shaft |
| `nexus_02.heavy_barb` | Whisper Loft | Behind the resonant membrane, an Echo Shot revisit reward |
| `vaults_01.ebb_mend` | Cold Threshold | East alcove above the save shrine, in the ambush room |
| `vaults_02.tide_socket` | Hanging Vaults | Lower east chamber by the save shrine |
| `kiln_01.tide_socket` | Glow Passage | Upper chamber beside the Heart Pearl |
| `kiln_02.spring_tide` | Furnace Shaft | Bottom floor east of the antechamber ambush trigger |

## 6. Shrine interaction and screen

`CampaignRoot` adds one `TideHook` node (`scripts/campaign/tide_hook.gd`) and the shared shrine
menu. A save shrine offers Tide Sockets while at least one glyph is owned and no room transition,
death or the ending is under way (`shrine_options`, `scripts/campaign/campaign_root.gd:218`);
ambushes and bosses do not remove the option. While the player stands on a save shrine (on the
floor, not in Slipstream form) and the shrine offers anything, the shrine's up chevron shows; it is
the only cue, shared with fast travel. Pressing Up (`move_up`) opens the shrine menu
(`scripts/ui/shrine_menu.gd`): a small centred panel in the `ui_style.gd` look listing "Travel"
(only when fast travel is possible) and "Tide Sockets". When only one option is offered the panel is
skipped and that screen opens directly, so a player with glyphs at a shrine with no travel target
goes straight to the socket screen. Choosing Tide Sockets opens the screen below, which pauses the
tree and opens a shrine session. Closing (Esc or `ui_cancel`) ends the session; a changed loadout is
saved at that shrine through `CampaignRoot.save_at`.

The screen (`scripts/ui/tide_menu.gd`) uses `ui_style.gd`: title and a capacity gauge of slanted
tide-mark segments on top (filled used, outlined free, faint not yet found), then one full-width row
per owned glyph with its icon, name, gain line and downside line inline, a state tag (`SOCKETED`,
`NO ROOM`) and its cost as small slanted segments. There is no side description pane, no grid of
round icons and no circular pips. A refused socket flashes the gauge red and plays the Flux-empty
cue. The HUD indication is a separate bottom-left strip of socketed glyph icons
(`scripts/ui/tide_badge.gd`), hidden when nothing is socketed; `hud.gd` is unchanged.

## 7. Save format

One optional key inside schema version 2, following the map-pins pattern and coexisting with
`map_pins` and `activated_stations`: `tide_modules` with
exactly `sockets_found` (0 to 3), `owned` (unique glyph ids) and `equipped` (a subset of `owned`
whose total cost fits `2 + sockets_found`). It is written only when a socket or glyph has been found
(`GameState.snapshot`, `scripts/autoload/game_state.gd:341`), so older saves and new saves without
finds are byte-compatible. Validation is `TideModules.validated`
(`scripts/progression/tide_modules.gd:161`); any malformed value rejects the whole snapshot, as
every other field does. v1 saves migrate with no finds. Pickup instance IDs are also recorded in
`collected_ids` as for every unique pickup.

## 8. Legal constraints (binding)

From the licence and patent check of 2026-09-24 (`.agent-reports/licence-check.md`, not legal
advice). The mechanic is free to use; only expression and one automation feature are restricted.

- Never use the names charm, notch, overcharmed, badge, BP, shard or chip, nor ring slots. The
  system is "Tide Sockets" and "Tide Glyphs"; `tools/check_tide_modules.gd` rejects glyph names that
  contain the forbidden words.
- No circular notch pips and no charm-screen layout (round icon grid at the bottom, equipped row
  on top, notch row, description pane on the right), and no shard list.
  Section 6 describes the Hollowtide layout.
- Do not port a recognisable set of effects one to one. The catalogue in section 3 bends
  Hollowtide's own arsenal (Seed Crossbow, Harpoon, Resonance Pulse, ambushes) with its own numbers.
- No over-capacity rule copied from another game. Hollowtide has none: capacity is a hard limit.
- No automatic "equip best loadout" feature that ranks glyphs by value per cost (Konami
  JP5437320B2 is active in Japan and China). Any future convenience must stay manual (for example
  saved presets the player builds).
- Before a commercial release a patent attorney should run a proper freedom-to-operate search.

## 9. Verification

Suite `tools/check_tide_modules.tscn` (registered as `tide modules` in `tools/run_godot_check.py`):

| Case | Expectation |
|---|---|
| Catalog | Content catalog kinds match the glyph table; 6 to 8 glyphs; costs 1 to 3; each has a gain, a downside and known stats; names avoid forbidden words; icons load. |
| Capacity | Starts at 2; three sockets reach 5; a fourth is rejected; glyph pickups are unique. |
| Shrine gate | No socketing or removal outside a session; over-capacity and 3-cost-into-2 are refused without change. |
| Crossbow | Quickstring 10 to 7 damage, speed x1.35, reload x0.6; Farcast range x1.4, reload x1.6; Spring Tide 14; Brine Hide 8; stacking by product. |
| Harpoon and Pulse | Heavy Barb 56 damage and two bolts, no shot with one bolt; Spring Tide 47; Brine Hide 28; Deep Pulse 35 damage and fuse x1.5. |
| Damage taken | A 20 hit becomes 15 (Brine Hide), 24 (Ebb Mend), 27 (Spring Tide); never zero. |
| Ebb Mend | A real `AmbushArena.cleared` heals 50 only with the glyph socketed. |
| Save | Key absent without finds; JSON round-trip restores; schema stays 2; eight tampered values rejected atomically; a v2 save without the key and a v1 save load. |
| Campaign | The fringe_03 pickup collects; Up away from a shrine does nothing; the fringe_02 shrine (no travel target) offers only Tide Sockets; Up there opens the socket screen directly, skipping the shrine menu, and pauses; a menu press sockets; the HUD strip shows it; Esc closes, resumes and saves; the slot reloads with the loadout. |
| Shrine menu | In suite `fast travel` (`tools/check_fast_travel.gd`): a travel shrine offers Tide Sockets only once a glyph is owned; with both options Up opens the shrine menu listing both, Tide Sockets opens this screen and Travel the travel map; during an ambush only Tide Sockets is offered. |

`tools/check_pickup_catalog.gd`, `tools/check_phase1_catalog.py` and `tools/check_campaign_graph.py`
cover the registration and placement.

Not verified: hands-on feel and balance of the numbers, and a real-input playthrough with glyphs.

## 10. Follow-ups

- An Undertow Dash glyph (dash recharges on hit, shorter dash) once `scripts/player/undertow_dash.gd`
  is free of concurrent work.
- Flux glyphs once Flux abilities are placed in the campaign.
- Balance pass after playtests; numbers change only in `tide_catalog.gd`.
