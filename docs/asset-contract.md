# Hollowtide — asset contract (normative)

This is the interface between graphics and code.

## Background: why this document was rewritten

The first version forced the graphics into 48px figure height and a bound palette restricted to
thirteen colors. The source images from GPT Image were excellent: consistent player, clean drawing —
but the post-processing ruined them. The limitation came from this document, not from the
tool.

**Hollowtide is not a pixel art game.** Graphics must be rendered at full resolution with
soft edges and free color space. The rule below is therefore as important as the measurements:

> **Post-processing must never be destructive.** No palette quantization. No
> thresholding of the alpha channel. No downscaling below the target measure followed by upscaling.
> Cut out, adjust the foot line, assemble the strip. Nothing more.

## Ownership of directories

| Catalog | Owned by | Others get |
|---|---|---|
| `assets/sprites/` | graphics agent | read only |
| `tools/` | graphics agent | read only |
| everything else (`scenes/`, `scripts/`, `project.godot`) | code agent | read only |

## Image format

PNG, RGBA, true alpha channel with **soft edges** (partially transparent pixels are desirable —
they provide antialiasing). Full color space, no palette limitations.

Frames are **horizontal strips**: frame *n* occupies x from `n*W` to `(n+1)*W`.
The code slices on exact pixel boundaries and breaks silently if a measurement deviates.

## Figures (256 × 256 per frame)

The figure is **192 px high** (3 tiles), horizontally centered, with **feet at pixel row 240**
(16 px air below). It gives the code origin in the feet and leaves space above for hair,
dust and effects. She is always drawn **facing right**; the code reflects.

### Scale each STRIP, never each frame

192 px is the measurement of the HIGHEST pose in the strip. Calculate ONE common scale factor from it,
apply the same factor to all frames and align them to the foot line (line 240).

Scaling each frame to exactly 192 px is a silent but devastating bug. A running cycle varies
naturally just over 10% in height between the crouched and fully extended poses. If you force each
square to the same height, that variation is erased, and the player appears to pump in size 60 times a second
instead of moving. It reads as "broken in motion" without any single frame
looking wrong — which is exactly why it is hard to find.

The same applies to width: no frame may scale horizontally by itself. Common factor, always.

| File | Frames | Dimensions | Contents |
|---|---|---|---|
| `player_idle.png` | 4 | 1024 × 256 | Calm breathing. Subtle. |
| `player_run.png` | 8 | 2048 × 256 | Full running cycle. See the requirement below. |
| `player_jump.png` | 3 | 768 × 256 | 0 rising, 1 apex, 2 falling. |
| `slipstream_body.png` | 4 | 512 × 128 | 128 × 128 cells, water droplet drawn at about 1 tile, centered. The standing → Slipstream transition reuses `player_idle`/`player_crouch` frames and the droplet drawn by `slipstream_visuals.gd`. |

### The treadmill — what went wrong last time

Eight squares must be **eight genuinely different poses**. Generating four and mirroring them gives one
player that reads as broken in motion, which is exactly what happened. Therefore generate all
eight poses in the **same** image, so the image model keeps the figure consistent between them —
it is within a single generation that consistency exists, not between several.

Higher resolution makes inconsistency **more** visible, not less. This requirement is therefore
stricter now than before, not looser.

## Objects and environment

| File | Frames | Dimensions | Contents |
|---|---|---|---|
| `orb.png` | 6 | 768 × 128 | The globe, about 80 px in a 128 × 128 box. Pulsating, loops softly. |
| `tileset_cave.png` | — | 512 × 512 | 8 × 8 grid of 64 × 64 tiles. See below. |

### Tileset layout (column, row — zero-indexed)

```
(0,0) filled stone A        (1,0) upper edge        (2,0) inner corner L    (3,0) inner corner R
(0,1) left edge         (1,1) lower edge       (2,1) right edge      (3,1) solid dark
(0,2) filled stone B        (1,2) filled stone C     (2,2) filled stone D   (3,2) cracks
```

**Filled stone must be in four varieties** (A–D). In the previous version there was only one, and
the walls got a visible grid pattern that drew the eye to the grid instead of to
the room. The variants are randomized by the level code.

The edge pieces must fit together seamlessly when placed next to each other.

## Color palette — indicative, not binding

These values describe the tone and should control the **generation**. They must never be forced into one
finished picture afterwards.

```
#0b0e14  deepest background      #1a2130  background stone
#2d3a4f  mid-tone stone           #46587a  lit stone
#6b8299  wet stone, highlight    #c9d6e3  lightest stone

#e8b894  skin                    #a8623f  skin in shadow
#2b3f6b  dark clothing             #3f5f9e  light clothing
#d94f3d  hair accent

#4fe3c1  orb glow (cool)    #9ffff0  orb core
```

The world is muffled, wet, underground. The green tones of the globe should be the scene's only strongly
saturated color — but that's achieved by drawing the rest low-saturated, not by quantizing.

## Weapon in hand

Before the orb and the weapon are found, she is empty-handed. After the weapon pickup **she keeps the weapon
every square where she is not in Slipstream form**. Shooting without visibly holding anything is immediately read as
a mistake, even by someone who can't put it into words.

The weapon is the Seed Crossbow: a small one-handed wooden hand-crossbow (walnut stock, brass
fittings, short recurved limbs, teal cord grip) with a softly glowing turquoise seed-bolt tip where the
bolt leaves, about 40–55 px long at player scale. It is held in that hand
which is closest to the viewer. She is always drawn **facing right**; the code reflects.

### Armed strips

Same measurements, footprint and scaling rules as the empty hands. Same poses, same number of squares —
the only difference is the weapon in the hand and a slightly tighter shoulder area.

| File | Frames | Dimensions | Contents |
|---|---|---|---|
| `player_idle_armed.png` | 4 | 1024 × 256 | As `player_idle`, the weapon lowered along the thigh. |
| `player_run_armed.png` | 8 | 2048 × 256 | Like `player_run`, weapon in hand, arm pumping less. |
| `player_jump_armed.png` | 3 | 768 × 256 | As `player_jump`, the weapon is held out from the body. |

The empty-handed strips are kept and used before the weapon pickup. Never delete them.

### Aim poses

Four individual poses, one frame each, 256 × 256, same foot line on line 240. She stands steady and
aiming the weapon; the body turns with it, the gaze follows the muzzle.

| File | Dimensions | Direction |
|---|---|---|
| `player_aim_up.png` | 256 × 256 | Straight up. Arm stretched over shoulder, chin lifted. |
| `player_aim_diag_up.png` | 256 × 256 | 45° up-forward. |
| `player_aim_diag_down.png` | 256 × 256 | 45° down-forward. Airborne pose, with legs together. |
| `player_aim_down.png`| 256 × 256 | Straight down. Airborne pose, arm along the body down, gaze down. |

Aiming straight ahead needs no separate pose; `player_idle_armed` is used as usual.

`player_aim_diag_down` and `player_aim_down` only appear in the air, since aiming down on the ground
does not exist (`move_down` on the ground is crouch). Draw them accordingly.


## Phase 1 — enabled extension

`devmode-contract.md` allocates new terrain/graphics files and separates
the image-generation agent from pipeline/integration. 256 px visual terrain modules may be used
over separate 64px collision grid. Existing atlases remain compatible. Spin has fixed
body pivot and scale from standing reference, not a foot-line constraint on rotating feet.
`tools/check_*.py` is owned per file/task according to the code contract, not generally by the graphics role.
