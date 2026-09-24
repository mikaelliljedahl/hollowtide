# Feature design: player map pins

Status: implemented on the campaign map. Pure rules in `scripts/campaign/campaign_map_pins.gd`,
map screen controls in `scripts/campaign/campaign_map.gd`, drawing in
`scripts/campaign/campaign_map_painter.gd` (shared by the minimap), persistence in
`scripts/autoload/game_state.gd`. Design accepted by the user on 2026-09-24; see
[Accepted map pins amendment](../implementation-decisions.md#accepted-map-pins-amendment).

## 1. Goal

Players navigate a metroidvania by "map poking": they open the map, scan it for exits they have not
taken, and plan the next route. The campaign map already marks unexplored exits and visited blocked
paths (see [phase-2-campaign.md](../phase-2-campaign.md), "Saving, death, resources, and map").
What it cannot show is the player's own intent: "I saw something up there", "that room hurt",
"a ledge I could not reach yet". Map pins let the player record that intent in a few keystrokes, on
the map screen, without any text in the game world.

Out of scope: free-text notes, automatic pins, pins in the dev world map, a quest marker or any
hint the game places itself (the map must never reveal a solution).

## 2. Rules

- **P1 Where.** A pin sits on one cell of a room the player has entered (`GameState.discovered_rooms`).
  Any cell inside the room's rectangle counts, rock included, so a pin can mark a cracked wall or a
  ledge edge. Ghost rooms (seen through a door, never entered) and empty space take no pins.
- **P2 How many.** At most 12 pins (`MAX_PINS`, `scripts/campaign/campaign_map_pins.gd:8`). A full
  set refuses new pins silently; existing pins can still be cycled or removed. The hint line shows
  the count, so the refusal is readable.
- **P3 Kinds.** Three kinds, cycled in order `return` → `danger` → `item` → `return`
  (`KINDS`, `scripts/campaign/campaign_map_pins.gd:10`). One pin per cell.
- **P4 No text in the world.** Pins have no labels. The only words are the map legend and the
  control hint, both on the map screen, which is a menu (the map already had both).
- **P5 Deterministic rules.** Every rule function returns a new list and never touches global
  state (`activated`, `removed`, `can_place`, `validated`); the map screen hands the result to
  `GameState.set_map_pins`, which validates again before storing.

## 3. Controls

The map pauses the game, so the combat actions are free while it is open and are reused; no new
input actions were added and `REBINDABLE_ACTIONS` is unchanged.

| Input (default keys) | Effect on the map screen |
|---|---|
| Arrows / mouse drag | Pan, as before. The frame centre is the cursor; it snaps to the cell under it. |
| Wheel, `+` / `-` | Zoom, as before; zooming in makes single cells easy to hit. |
| `fire_beam` (X / J) | Place a `return` pin on the cursor cell, or advance the kind of the pin there. |
| `fire_missile` (C / K) | Remove the pin on the cursor cell. |
| R, M / Tab / Esc | Recentre, close, as before. |

Handling is in `_unhandled_input` (`scripts/campaign/campaign_map.gd:182`); the action checks come
before the physical-key table, so a rebound fire key keeps working on the map. The cursor lookup is
`Model.cell_at` (`scripts/campaign/campaign_map_model.gd:174`). The hint line
(`_refresh_hint`, `scripts/campaign/campaign_map.gd:445`) reads the first bound key of each action
from `scripts/ui/game_settings.gd`, so it follows rebinding, and shows `PIN n/12`.

## 4. Visuals

- A pin is a needle whose point sits on the cell centre with a head above it
  (`draw_pin`, `scripts/campaign/campaign_map_painter.gd:265`). Shape carries the kind, colour
  repeats it: ring (pink) for `return`, warning triangle (orange-red) for `danger`, star (lime) for
  `item` (`PIN_COLORS`, `scripts/campaign/campaign_map_painter.gd:37`). Colour is never the only signal.
- Pins are painted after gates and items and before the player marker
  (`scripts/campaign/campaign_map_painter.gd:88`), so they are never hidden by room art.
- The painter is shared, so the HUD minimap shows the same pins at its smaller icon scale (with a
  floor on the size so they stay readable).
- The cursor (`_draw_cursor`, `scripts/campaign/campaign_map.gd:296`) is four short crosshair ticks
  at the frame centre plus an outlined cell when the cell can take a pin. It does not animate, so
  the reduce-flashes setting needs no special case.
- The legend lists a pin kind only while at least one pin of that kind exists
  (`PIN_NAMES`, `scripts/campaign/campaign_map.gd:39`): COME BACK, DANGER, ITEM MARK.

## 5. Persistence

Pins are part of the progress snapshot, so they follow the active save domain (campaign or dev)
like discovered rooms. The save schema version stays 2.

- `GameState.map_pins` holds a list of `{"room": String, "x": int, "y": int, "kind": String}` with
  x/y as the local cell of the room (`scripts/autoload/game_state.gd:37`). Local cells keep a pin
  on its room if room origins are regenerated.
- `snapshot()` writes the optional key `map_pins` only when at least one pin exists
  (`scripts/autoload/game_state.gd:338`). A save without pins is byte-for-byte the format that
  existed before this feature, so older builds can still read it.
- Validation (`scripts/autoload/game_state.gd:631`, `:682`) accepts a v2 snapshot with or without
  `map_pins`. When present it must be a list of at most 12 entries, each with exactly the four keys,
  a room in the same snapshot's `discovered_rooms`, a kind from `KINDS`, whole-number cells in
  `0..1023` (JSON floats such as `2.0` are accepted and restored as integers), and no two pins on one
  cell. Anything else rejects the whole snapshot, like every other field.
- A v1 (legacy) snapshot never carries `map_pins` and migrates with no pins.
- `reset_progress()` clears the pins; death and respawn do not touch them (they are kept in memory
  with the rest of the progress and saved at the next shrine or boss autosave).

## 6. Tests

Suite `map pins` (`tools/check_map_pins.gd`, registered in `tools/run_godot_check.py`):

| Area | What is checked |
|---|---|
| Rules | Place, cycle through all three kinds with wrap-around, remove, input list not mutated. |
| Limit | Twelve pins fit, a thirteenth is refused, a full set still cycles, removing frees a slot. |
| Explored only | Undiscovered rooms, cells outside the room, negative cells and ghost rooms are refused; `cell_at` maps world tiles to local cells. |
| GameState | Valid pins stored, a pin in an undiscovered room refused without change, reset clears. |
| Save | Round-trip through `SaveStore` restores pins exactly with integer cells; the file keeps `schema_version` 2; a v2 save without the key and a v1 save both load with no pins; a snapshot without pins omits the key; eight kinds of tampered pin data are rejected. |
| Screen | The cursor snaps to the cell under the frame centre; real X and C key events place, cycle and remove a pin; nothing is placed over an unexplored room; the minimap returns after closing. |

Visual check: the map and minimap were captured with pins of all three kinds (full map, zoomed map
with the cursor on a pin, and gameplay with the minimap), following the capture pattern of
`tools/capture_campaign_map.gd`. Screenshots are working files and are not committed (D15).
