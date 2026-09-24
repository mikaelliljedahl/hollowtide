# Hollowtide — visual plan

**Status (2026-09, env lane): five natural area identities replace the steel-facility layer (D17).**
Every area renders its own rock terrain, painted far/mid parallax, atmosphere, particles and decor.
Steel/industrial pieces are no longer a default tile; they may only appear as a deliberate accent.
Physics values and the 64 px collision grid are unchanged. F1 human visual acceptance remains open.

## Goals and hard limits

- Render 1920×1080 at full resolution. Keep 64 × 64 px physics/logic cells and a 192 px player.
- Visual terrain is separate from the collision grid. Graphics alpha never collides.
- Five areas must read as five different worlds at a glance (material, palette, silhouettes, light),
  not one world with a colour filter.
- Nothing floats unsupported: fixtures and vents stand on real floor, lava/water sit in basins at
  the bottom, stepping stones in fluid are grounded by a rock pillar below the surface.
- Draw order is sane: background < terrain < decor/door frames < player/enemies/pickups < fluids/VFX.
  The player is always in front of arches and passage frames she walks through.
- No tutorial text or text-based teaching in the world.

## Area identities

| Area ID | Terrain material | Background / atmosphere | Decor |
|---|---|---|---|
| `fringe` | Wet blue-grey stone, moss and fern lip, root drips | Surface-lit cavern, daylight shafts, waterfall; drip particles | Root curtains, vines, ferns, old wooden stake |
| `nexus` | Dark slate with teal crystal veins, wet sheen | Huge chasm, water ribbons, ancient resonant ring/crystals; teal mist | Crystal clusters, carved resonant pillar, ring fragment, water ribbon |
| `vaults` | Pale cold limestone, frost crust and icicles | Hanging limestone curtains, frozen terraces, cold fog; snow | Stalactite/icicle clusters, frosted stalagmites, ice crystals |
| `kiln` | Black columnar basalt with glowing cracks | Basalt columns, lava glow from below, steam; rising embers | Basalt drips, column stumps, ember rubble; fumarole/fissure vents |
| `depths` | Near-black abyssal rock, bioluminescent specks | Flooded abyss, dark water, violet/cyan mineral; floating motes | Glowing mineral strands, crystal clusters, orb nodules |

## Pipeline

1. **Sources** (Codex/gpt-image, briefs kept by the lead) live in
   `assets/environment/source/<area>/` (ignored by Godot via `.gdignore`): `fill.png` (seamless rock
   mass), `top.png` / `bottom.png` (horizontal lip / underside bands), `side.png` (vertical wall
   face), `far.png`, `mid.png` (parallax), `props.png` (decor sheet), optional `fluid.png`.
2. **Build:** `uv run --with pillow==12.3.0 --with numpy python tools/build_area_art.py [area…]`
   crops/resamples them into runtime strips under `assets/environment/areas/<area>/` and writes
   `area.json` (strip geometry, parallax, modulation, fog, particles, props, fluid). `fill.png`
   is required; other missing sources are skipped. Props of kind `spare` (glowing orb cluster,
   broken ring) are never auto-placed because they read as pickups/portals. The legacy
   `backgrounds/ decor/ landmarks/ terrain/` art and per-area manifests are gone.
3. **Runtime:** `scripts/world/environment_kit.gd` loads `area.json`. `scripts/world/cave_visuals.gd`
   builds static chunked draw lists once per TileMap change: fill runs, smooth depth shading
   (distance-to-air), bottom/side/top face strips with end caps, clearance-aware crops for
   slipstream tunnels and 1-wide shafts, exterior rock beyond the TileMap edge (openings on the edge are
   extruded as passages), and sparse decor that keeps clear of every gameplay object.
   `cave_background_renderer.gd` draws far/mid parallax, haze, light shafts, mist and particles.
   Vertical parallax is reduced in tall rooms (and the panorama scaled up in zoomed-out views) so
   the painted layers always cover the whole screen; there are no flat colour bands.
4. **Hazards:** `scripts/dev/dev_hazard.gd` draws lava as a textured pool filling its basin and
   vents as painted rock fumaroles (kiln) or rock mounds in the area material.

## Campaign rooms

`CaveVisuals.configure(tiles)` plus `CaveVisuals.set_fixed_area(area_id)` renders any room size
with one area kit and no world-x blending. Dev world (no fixed area) keeps the S0–S10 x-boundaries
5888 / 9984 / 14080 / 18176 and crossfades backgrounds ±384 px around them.

Campaign rooms are dressed automatically from the tile geometry: stand props on floors with
4+ rows of headroom, hang props under ceilings with 5+ rows, roughly one candidate cell in three,
spaced apart, never two identical neighbours, footprint fully on one face, and a 440 px keep-out
around every gameplay object, fluid and room exit. Lava drawn on top of a floor in a layout is sunk
into a one-row basin at parse time (`tools/campaign_layout.py`). The Tidal Heart grate hangs from
the ceiling on a rock column.

## Verification

`tools/check_environment_kits.tscn` (dev world) and `tools/check_area_visuals.tscn` (arbitrary
rooms, all five areas; add `--out=<dir>` when windowed to save screenshots),
`tools/campaign_capture.tscn -- --test-mode --out=<dir> --detail [--rooms=…]` for every campaign
room (overview plus 1:1 tiles), plus
`tools/env_capture.tscn -- --dev-mode --out=<dir> [--stations=0,2] [--at=x:y,…]` for in-game
screenshots. Look at the screenshots; measurements alone are not acceptance.

## Spin and Undertow Dash

`player_spin.png` and `player_spin_armed.png` should be eight genuinely different poses from the same
reference series: huddled body, clear forward fold, readable head/legs through arch. Never rotate
standing sprite in code. Never use `ball_roll` as a spin. Use a common scale from
figure's 192px portrait reference; don't enlarge a shrunken body to 192px height.
This exception to the current maximum height rule must be included in the new spin contract.

All frames have the same 256 × 256 canvas, sprite anchor `(128,240)` at the player's foot origin and
fixed visual center of rotation `(128,144)`. Anchor/pivot does not move between panes;
the feet, on the other hand, rotate with the body and should not be locked to the ground poses in row 240. The Armed series shows weapons in every non-ball pose; weapons must not disappear between poses.

Bas-spin and `Undertow Dash` are separated: bas-spin only changes animation/readability and does not damage;
`assets/sprites/undertow_dash.png` is visual feedback, while actual damage follows attack windows and
state of ability. Effect must not replace hit tests or collision proof.

## Provenance and release gate

Suggested manifest: `docs/art-provenance.md`. One line per source and output must indicate source,
reference, license status, generator/version, actual processing and approval point.

Known entries now include legacy HD terrain, five cave-kit sources, fire/lava VFX, Flux systems,
player sprint/wall poses, dev fixtures, and current sprite/presentation/environment builders. See
`art-provenance.md`; unknown full generation IDs stay unknown.
Origin, license, and rights to the source images are
not established here. Unknown license/provenance prevents release; rights must never be fabricated.
Phase 1 can be test driven with clearly blocked status, but F1's visual final gate requires manifest,
approved by the user level image comparison and no unresolved source/rights issues.
