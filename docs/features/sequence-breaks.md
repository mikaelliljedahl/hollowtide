# Feature design: intended sequence breaks

Status: implemented on 2026-09-24 as three breaks (four solver routes) in the 16-room mini-campaign.
Design accepted by the user on 2026-09-24; see
[Accepted intended sequence breaks amendment](../implementation-decisions.md#accepted-intended-sequence-breaks-amendment).

## 1. Goal

Hollowtide should reward skill over puzzle solving. An intended sequence break is a hidden, hard but
fair movement route that lets a skilled player reach an ability, an area or an item earlier than the
intended order, and that pays a reward the normal route never gives. The break is optional: the
campaign stays completable, in every branch order, by a player who never finds one.

Out of scope: new movement mechanics, new pickup kinds, boss alternatives, text of any kind.

## 2. Design rules

- **S1 Skill, not knowledge.** A break uses moves the player already owns (single-wall climbs, the
  Undertow Dash). It never needs a glitch, damage boost, pause trick or frame-perfect input.
- **S2 Seen before it is solved.** The reward or the ledge is visible from the normal route: a lit
  niche, a pickup on a ledge, a light through a slot. No text, no map marker.
- **S3 Exclusive reward.** Each break holds a pickup that no intended move reaches in any progression
  stage (proved by the graph solver, section 4). Rewards come from the existing budget: Heart Pearls
  (`energy_tank`) and Bolt Quivers (`missile_tank`).
- **S4 No soft-lock.** Every break ends on a spot from which the normal movement model walks, drops or
  climbs back to a save shrine with the abilities owned at that moment, in every branch order.
- **S5 Intended gates stay honest.** A break never makes an ability gate pass with a plain jump; the
  moves checks that prove the gates (`tools/check_campaign_moves.gd`, `tools/check_campaign_moves_kd.gd`)
  pass unchanged.
- **S6 The glide eases, never gates.** No break needs the Updraft Cloak glide
  ([game-feel.md](../game-feel.md), Updraft Cloak glide).

## 3. The breaks

| Break | Room | Route | Moves | Reward (exclusive) | Gets early |
|---|---|---|---|---|---|
| `breach_ledge` | `fringe_01` Surface Breach | Start floor, up the west wall to a lit niche | Single-wall climb (2 to 3 wall jumps) | Bolt Quiver `fringe_01.missile_ledge` | Harpoon before the Seed Crossbow; the start room's harpoon socket (`fringe_01.missile_03`) at once |
| `pillar_ledge` | `vaults_02` Hanging Vaults | Lower hall, up the west face of the new pillar to its step ledge | Single-wall climb, lean in after the jump clears the overhang | Heart Pearl `vaults_02.energy_pillar` | A Heart Pearl before the Stone Guardian |
| `pillar_band` | `vaults_02` Hanging Vaults | Lower hall, up the east face of the pillar and the chasm edge onto the upper band | Long single-wall climb (17 rows) | Shares `pillar_ledge`'s pillar; its prize is the skip | Updraft Cloak before the Bubble Snare (skips the frozen-floater chasm gate) |
| `undertow_gap` | `depths_01` Pressure Descent | Hole in the upper floor, hidden corridor, 7-tile gap under a low ceiling | Running hop plus an air Undertow Dash | Heart Pearl `depths_01.energy_corridor` | Extra health before the Tidal Heart |

### 3.1 `breach_ledge` (fringe_01)

- Geometry: the niche and its headroom are cut into the top-left corner,
  `scenes/campaign/layouts/fringe_01.txt:18` to `:23`; the Bolt Quiver and a light shaft stand on
  the niche floor (`:23`, legend `:7`). The west wall below the lip is rock rows 7 to 10
  (`:24` to `:27`) above the harpoon socket (`:28` to `:30`).
- Height: the niche floor is 7 rows above the start floor. A plain jump rises 4 rows and the Updraft
  Cloak jump 6 (`scripts/progression/content_catalog.gd:290`), so neither reaches it; a single-wall
  climb does, because a wall jump repeats the full jump impulse
  (`scripts/player/player_config.gd:69`). Six rows of headroom above the lip let the last wall jump
  peak without hitting the ceiling before she drifts back over the lip.
- Hint: the lit niche and the quiver are in frame from the start marker.
- Safe: the niche is a dead end; she drops back to the start floor. Owning the Harpoon early only
  opens more (the solver runs the whole campaign with it, section 4).

### 3.2 `pillar_ledge` and `pillar_band` (vaults_02)

- Geometry: a rock pillar hangs from the upper band floor into the lower hall with a four-row walkway
  under it (`scenes/campaign/layouts/vaults_02.txt:41` to `:50`). Its lower part is one tile wider on
  the west side, forming the step ledge that holds the Heart Pearl (`:44`, legend `:7`); a recess cut
  into the band floor above it (`:39` to `:40`) gives the six rows of headroom a lip climb needs.
- `pillar_ledge`: climb the west face from the hall floor. The Heart Pearl is visible from the Bubble
  Snare's side of the hall.
- `pillar_band`: climb the east face, which continues into the chasm wall, and step west onto the
  upper band. The Updraft Cloak lies in the west hall; the intended route there needs frozen Bubble
  Floaters. With the Cloak she can also take the High Jump crack to the Stone Guardian before the
  Snare; the solver's boss rule for it asks only for the Harpoon
  (`tools/check_campaign_graph.py:55`).
- Safe: from the west hall without the Snare, she drops back through the chasm into the lower hall
  and climbs the existing chimney to the band save. The solver proves this in every order.

### 3.3 `undertow_gap` (depths_01)

- Geometry: a two-wide hole in the upper floor (`scenes/campaign/layouts/depths_01.txt:38` to `:39`)
  drops into a four-row corridor inside the rock between the halls (`:40` to `:43`): a ten-tile
  runway, a seven-tile gap that opens as a slot into the lower chamber (`:44` to `:45`), and a
  four-tile far ledge holding the Heart Pearl under a light shaft (`:43`, legend `:10`).
- Moves: the low ceiling caps a hop at about 80 px. A running hop alone, and a hop with the Cloak
  glide held, fall into the gap; a hop plus an air Undertow Dash (0.18 s at 1500 px/s holding
  altitude, `scripts/progression/content_catalog.gd:286`) lands on the far ledge with about a tile to
  spare. The dash is found in the same room, so the break is the dash's first test of skill.
- Hint: the light over the Heart Pearl shows through the slot in the lower chamber's ceiling.
- Safe: a miss, or leaving the ledge, drops through the slot into the lower chamber by the save
  shrine. The runway is left through the hole (Cloak jump) or the slot.

## 4. Graph solver model

The solver in `tools/check_campaign_graph.py` is deliberately conservative: it climbs only chimneys
and has no dash, so it cannot find any break by itself. Breaks are registered in
`tools/campaign_breaks.py:26` as edges from a standing feet cell to a standing feet cell in the same
room, each with the abilities it needs. The solver adds them to its movement graph
(`tools/check_campaign_graph.py:279`), so every run (any order, vaults first, kiln first, no optional
pickups, permanent crumbles) explores them, collects their rewards and runs its softlock pass over
them. A `no-breaks` run (`tools/check_campaign_graph.py:609`) proves the campaign finishes without
any break.

`break_errors` (`tools/campaign_breaks.py:50`) adds three static rules: each start and end is a real
standing spot; each start is reachable by normal play; and each reward is out of reach of the solver
with every ability, every boss and door flag and no break edges, started from the start marker and
every save shrine. That last rule is the formal meaning of "exclusive" in S3.

## 5. Verification

- `tools/check_sequence_breaks.gd` (suite `sequence breaks`) drives the real player with input
  actions in the generated rooms. Per break it shows the intended moves fall short (plain jumps and
  the Updraft Cloak jump against the wall; a running hop with the glide at the gap), then drives the
  break (a single-wall climb bot, or run, hop and air dash) and asserts the reward is collected and
  where she stands. It also asserts each reward is generated exactly once, in its break room, at its
  break cell. Enemies are removed so the cases measure geometry.
- `tools/check_campaign_graph.py` enforces section 4.
- The moves checks for the three rooms pass unchanged (S5).
- Screenshots of each hint in its room were reviewed during implementation (working files only, D15).

## 6. Open points

- Human feel review: the climbs are tuned against the bot, which leans in 8 frames after a ground
  jump and wall-jumps near the apex; a player may find the 17-row `pillar_band` climb long. The
  frost floaters drifting over the chasm add contact risk near its top.
- The rewards bring the campaign to six Heart Pearls, the `MAX_ENERGY_TANKS` cap
  (`scripts/progression/content_catalog.gd:245`); further Heart Pearls in the 48-room expansion need a
  budget decision.
- A harpoon-peg break is not included: pegs need a side wall, and any wall near an intended ability
  crack would also let a plain wall-jump climb bypass that gate (S5).
