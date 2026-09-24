# Feature design: fast travel and boss shortcuts

Status: implemented in the campaign. Pure rules in `scripts/campaign/fast_travel.gd`, the trip and
its refusal rules in `scripts/campaign/campaign_root.gd`, the shrine prompt in
`scripts/campaign/station.gd`, the shared shrine menu in `scripts/ui/shrine_menu.gd` (also used by
[Tide Sockets](tide-modules.md)), the map's travel mode in `scripts/campaign/campaign_map.gd` with
its state in `scripts/campaign/campaign_map_travel.gd`, persistence in
`scripts/autoload/game_state.gd`. Boss shortcuts were already in the layouts; this feature adds a
graph check that keeps them there. Design accepted by the user on 2026-09-24; see
[Accepted fast travel and boss shortcut amendment](../implementation-decisions.md#accepted-fast-travel-and-boss-shortcut-amendment).

## 1. Goal

The campaign grows toward 48 rooms ([phase-2-campaign.md](../phase-2-campaign.md), content
budget). Backtracking is part of the genre, but players accept it when the world offers shortcuts
and a way to cross known ground quickly (the genre's usual lifts and travel stations). Two tools
cover that:

- **Fast travel:** every save shrine the player has used becomes a station. At a station the player
  can open the map and pick any other activated station; the trip is a fade, not a cutscene.
- **Boss shortcuts:** after each branch boss a sealed gate opens from the boss room straight into
  the hub, as phase-2-campaign.md requires ("Each branch has a shortcut back to the hub after its
  boss").

Out of scope: travel from anywhere, travel to shrines never touched, a travel item or cost,
elevators between areas, new rooms.

## 2. Rules

- **T1 Activation.** Touching a save shrine (the existing save on contact) activates it
  (`save_at`, `scripts/campaign/campaign_root.gd:152`). Refill and ammo shrines are not stations.
  A slot written before this feature activates the shrine it resumes at
  (`scripts/campaign/campaign_root.gd:97`), so an old save has a first station at once.
- **T2 Identity.** A station id is `<room_id>.save.<cell_x>_<cell_y>`, the shrine's layout cell
  (`station_id`, `scripts/campaign/fast_travel.gd:18`). It is derived from the generated room index,
  so no new data is written into `campaign_rooms.gd`. Moving a shrine in a layout forgets only that
  one activation; the save still loads (T8).
- **T3 Where from.** Travel starts only while standing on an activated save shrine, on the floor
  and not in Slipstream form (`_shrine_ready`, `scripts/campaign/station.gd:99`).
- **T4 Where to.** Targets are the other activated stations in discovered rooms, ordered west to
  east so stepping moves across the map (`stations`, `targets`,
  `scripts/campaign/fast_travel.gd:24`, `:68`; `travel_targets`,
  `scripts/campaign/campaign_root.gd:194`). With no target the shrine offers no Travel option.
- **T5 Never mid-danger.** Travel is refused while an ambush arena is sealing, fighting or between
  waves, while a living boss has the player inside its arena, while a rising flood is not at rest,
  and during a room transition, death or the ending (`travel_blocker`,
  `scripts/campaign/campaign_root.gd:167`). The same check runs when the shrine menu is built, when
  the map opens and again when the trip is confirmed (`travel_to`,
  `scripts/campaign/campaign_root.gd:255`).
- **T6 Arrival is resting.** The trip fades out (0.4 s), loads the target room, stands the player
  on the shrine, refills, moves the checkpoint there and saves, then fades in (`_travel`,
  `scripts/campaign/campaign_root.gd:264`). Death after a trip therefore returns to the arrival
  shrine. Travel grants nothing a player could not get by stepping off and on the shrine.
- **T7 No text in the world.** The shrine shows a bobbing up chevron, no words
  (`_draw_prompt`, `scripts/campaign/station.gd:108`). The only words are the shrine menu's, the
  map's title and its key hint line, and both are menus.
- **T8 Save compatibility.** See section 5.
- **T9 One shrine gesture.** `move_up` on a save shrine opens the shrine menu
  (`open_shrine`, `scripts/campaign/campaign_root.gd:231`), which lists Travel while T3 to T5 allow
  a trip and Tide Sockets while at least one Tide Glyph is owned (`shrine_options`,
  `scripts/campaign/campaign_root.gd:218`). With one option the menu is skipped and that screen
  opens directly, so a player without glyphs sees exactly the travel flow described here.

## 3. Controls

No input action was added; `REBINDABLE_ACTIONS` is unchanged.

| Where | Input (default keys) | Effect |
|---|---|---|
| Standing on an activated shrine | `move_up` (Up / W) | Opens the map in travel mode, or the shrine menu when Tide Sockets are also offered (`_update_prompt`, `scripts/campaign/station.gd:88`). |
| Shrine menu | Up / Down | Move between Travel and Tide Sockets. |
| Shrine menu | `jump` or Enter | Open the focused screen; Travel opens the map in travel mode. |
| Shrine menu | Esc | Leave; the game resumes. |
| Travel map | `move_left` / `move_up` | Previous target. |
| Travel map | `move_right` / `move_down` | Next target (wraps). |
| Travel map | `jump` (Space / A) or `ui_accept` | Travel to the selected target (`_confirm_travel`, `scripts/campaign/campaign_map.gd:163`). |
| Travel map | Esc / M / Tab | Cancel; the game resumes where it was. |
| Travel map | Mouse wheel | Zoom. |

Travel mode input is `_travel_input` (`scripts/campaign/campaign_map.gd:172`). Map pin keys
(`fire_beam`, `fire_missile`) do nothing in travel mode, so a trip never edits pins by accident;
pins stay visible. Pin editing on the normal map (M / Tab) is unchanged. The hint line reads the
first bound key of each action (`_refresh_hint`, `scripts/campaign/campaign_map.gd:527`).

## 4. Visuals

- In travel mode the title reads TRAVEL and the subtitle names the selected target's area and
  room. The view glides to the selection (`TRAVEL_FOCUS_SPEED`,
  `scripts/campaign/campaign_map.gd:43`).
- Every target's save icon gets a ring; the selected one a larger pulsing double ring with four
  corner ticks (`draw_travel_target`, `scripts/campaign/campaign_map_painter.gd:242`). A dashed line
  joins the player's shrine and the selection (`draw`, `scripts/campaign/campaign_map_travel.gd:49`).
  Shrines never activated keep the plain save diamond, so the map shows which are stations. Size
  and shape carry the selection, not colour alone; the pulse stops under reduce flashes.
- The shrine chevron fades in only when the shrine offers something right now (a trip is possible,
  or a glyph is owned), so the prompt is also the answer to "can I use this shrine". It is the only
  shrine cue; Tide Sockets add no mark of their own.
- The shrine menu (`scripts/ui/shrine_menu.gd`) is a small centred panel in the shared menu style
  (`scripts/ui/ui_style.gd`): the "Save shrine" caption, a rule, one row per offered option and a
  key hint line. It pauses the game while open.

## 5. Persistence

The save schema version stays 2.

- `GameState.activated_stations` is a list of station ids in activation order
  (`scripts/autoload/game_state.gd:38`), added by `activate_station`
  (`scripts/autoload/game_state.gd:428`) and cleared by `reset_progress`.
- `snapshot()` writes the optional key `activated_stations` only when the list is not empty
  (`scripts/autoload/game_state.gd:339`), the same pattern as `map_pins` and `tide_modules`. A
  save with none of them is the format that existed before those features.
- Validation (`scripts/autoload/game_state.gd:631`, `:685`; `validated`,
  `scripts/campaign/fast_travel.gd:87`) accepts a v2 snapshot with or without the key. When present
  it must be a list of at most 64 unique strings of the station id format. An id the room index no
  longer knows is kept and simply never offered as a target, so a layout edit never rejects a save.
  A v1 (legacy) snapshot never carries the key and migrates with no stations.

## 6. Boss shortcuts

Both branch bosses already had one, built from `flaggate` legend marks and
`scripts/campaign/flag_gate.gd`:

| Boss | Boss room | Gate | Leads to |
|---|---|---|---|
| Stone Guardian | `vaults_03` | `G flaggate boss:stone_guardian`, east wall (`scenes/campaign/layouts/vaults_03.txt:8`) | `nexus_01`, lower west door |
| Cinder Warden | `kiln_03` | `G flaggate boss:furnace_mother`, west wall (`scenes/campaign/layouts/kiln_03.txt:9`) | `nexus_01`, lower east door |

The gate stands inside the boss room, so from the hub the player sees a sealed iris in a small
pocket (one-way until the boss falls); victory sets the boss flag and the gate opens for good.
The Tidal Heart is the final boss; its gate leads to the ending, not back to the hub. No layout
changed and no room was regenerated.

What was missing was a guard for the 48-room expansion: `shortcut_errors`
(`tools/campaign_shortcuts.py:17`, called from `tools/check_campaign_graph.py`) now fails the
campaign graph check unless each branch boss room has a flag gate on that boss's flag within four
cells of a door into a hub (`nexus`) room, the solver cannot pass it before the boss flag, and it
can walk through it once the flag is set.

## 7. Tests

Suite `fast travel` (`tools/check_fast_travel.gd`, registered in `tools/run_godot_check.py:73`):

| Area | What is checked |
|---|---|
| Index | Every save shrine is a station, ids unique and valid, ordered west to east, id is the layout cell, lookup by id and by feet position. |
| Rules | No targets without activation, from a shrine never activated, to itself or to a shrine never activated; unknown ids never become targets; seven kinds of bad station lists are rejected. |
| GameState | Activation, no double activation, malformed id refused, key omitted when empty, reset clears. |
| Save | Round-trip through `SaveStore` with pins alongside; the file keeps `schema_version` 2; a v2 save without the key and a v1 save both load with no stations; v1 with the key and three kinds of tampered lists are rejected. |
| Runtime | Walking onto a shrine activates and saves; no prompt, no options and no map with a single station and no glyph; the chevron shows with two; real `move_up` opens travel mode directly and pauses; X places no pin; Esc cancels; `jump` travels, the player stands on the target shrine with full health, checkpoint and save on disk moved there. |
| Shrine menu | Without a glyph a travel shrine offers only Travel; owning one adds Tide Sockets; `move_up` then opens the shrine menu listing both, paused and with no map; an option not offered is refused; Esc resumes; Tide Sockets opens the socket screen and Esc resumes; `jump` on the focused Travel entry opens travel mode. During an ambush the shrine offers only Tide Sockets. |
| Blocked | Ambush sealing and fighting block `travel_targets`, `open_travel` and `travel_to`; a cleared ambush does not; a live boss with the player in its arena blocks; a rising flood blocks, a resting one does not. |
| Shortcuts | Both branch gates are sealed before their boss, stay sealed when only the other boss is down, open on their own boss flag and stay open on re-entry. |
| Old save | A slot written at a shrine with no `activated_stations` resumes there with that shrine activated. |

The refusal path was exercised by mutation: with `travel_blocker` forced to allow, the suite fails
seven checks; with a shortcut gate's flag renamed, the graph check reports the missing shortcut.

Visual check: the shrine chevron in `fringe_02`, the travel map before and after stepping, and both
shortcut gates before and after their boss were captured in a windowed run. Screenshots are working
files and are not committed (D15).

## 8. Follow-ups

- The 48-room expansion should place a save shrine within a room of every branch boss's shortcut
  so the hub, the shortcut and travel reinforce each other.
- If more hubs appear, `HUB_AREA` in `tools/campaign_shortcuts.py` becomes a set.
