# Hollowtide — code contract (normative)

Multiple agents build simultaneously. This document is the authoritative record of file ownership
and binding interfaces. **Never write to a file you do not own.** If you need something from another
domain, build against the interface below and assume it exists.

Godot version: **4.7** (`config_version=5`). Language: GDScript.

## File ownership

### Owned by the movement agent
```
scripts/player/player.gd
scripts/player/player_config.gd
scenes/player/player.tscn
```

### Owned by the combat agent
```
scripts/autoload/weapons.gd
scripts/combat/**
scenes/combat/**
scripts/enemies/**
scenes/enemies/**
```

### Owned by the scaffold agent
```
project.godot
scripts/autoload/game_state.gd
scripts/pickups/orb.gd
scenes/pickups/orb.tscn
scenes/levels/level_01.tscn
.gitignore   (add Godot entries; delete nothing existing)
```

### Owned by the graphics agent
```
assets/sprites/**
tools/gen_sprites.py
```

### Verification script in `tools/`
Only `tools/gen_sprites.py` belongs to the graphics agent. However, each agent may create their OWN
verification script under `tools/`, named for the task, such as `tools/check_level.py`.
Whoever creates the script owns it. Never write to another agent's check script, and never put verification logic in `gen_sprites.py`.

No one else touches `docs/` — they are owned by the documentation maintainer.

## Binding interface

### Autoload `GameState`

Expands with weapon and missile status. Same pattern as Slipstream: the owner of an ability
writes, everyone else reads.

```gdscript
signal beam_acquired
signal missiles_acquired

var has_beam: bool = false
var has_missiles: bool = false
var missile_count: int = 0

func acquire_beam() -> void # sets has_beam, sends beam_acquired
func acquire_missiles(n: int) -> void # sets has_missiles, increments missile_count
func spend_missile() -> bool       # false if empty; otherwise decrement and return true
```


Register in `project.godot` as an autoload with the name `GameState`, pointing to
`res://scripts/autoload/game_state.gd`.

```gdscript
extends Node

signal slipstream_acquired

var has_slipstream: bool = false

func acquire_slipstream() -> void:
    if has_slipstream:
        return
    has_slipstream = true
    slipstream_acquired.emit()
```

The motion agent **reads** `GameState.has_slipstream` to determine if transformation is
allowed. It never writes to it.
The pickup agent **calls** `GameState.acquire_slipstream()`. Nothing else.

### Player scene

- Path: `res://scenes/player/player.tscn`
- Root node is named `Player` and is a `CharacterBody2D`, the script declares `class_name Player`
- The origin is at the feet
- Public: `var facing: int` (-1 left, 1 right) — the level gets to read it for the camera

### Collision layers

| Layer | Meaning |
|---|---|
| 1 | World / Terrain |
| 2 | Player |
| 3 | Pickups (`monitoring` Area2D, no physics) |

The player collides with layer 1 and is detected by layer 3.

### The level

- `scenes/levels/level_01.tscn` instantiates the player scene on a `Marker2D` named
`PlayerSpawn`, located in the **right** part of the map.
- The orb is in a niche to the **left**.
- Between the orb and the way back is an opening that is **exactly 1 tile high** (64px) —
passable only in Slipstream form. This is the essence of the scene; build it deliberately.
- The camera is a `Camera2D` child of the player, with `position_smoothing_enabled = true` and `position_smoothing_speed = 8.0`, plus `limit_*` set to map boundaries.

### Project settings that must be set

```
physics/common/physics_ticks_per_second = 60
display/window/size/viewport_width  = 1920
display/window/size/viewport_height = 1080
display/window/stretch/mode   = "canvas_items"
display/window/stretch/aspect = "keep"
rendering/textures/canvas_textures/default_texture_filter = 1 # linear — we're NOT pixel art anymore
```

### Input documents (exact names)

`move_left`, `move_right`, `move_up`, `move_down`, `jump`
— mapping according to `docs/game-feel.md`.

## Graphics availability

Contracted Phase 1 sprites, five environment kits, fixtures, gates, Flux VFX, and presentation poses
are available and integrated. Optional future/campaign assets still use contracted paths and null-safe
loading; never rebuild an interface around a guessed filename. Placeholder textures belong only in
isolated tests, never as claims of delivered runtime art.


## Combat — binding interface

### Autoload `Weapons`

Registers as autoload `Weapons` → `res://scripts/autoload/weapons.gd`.

```gdscript
func fire(kind: StringName, origin: Vector2, direction: Vector2) -> void
```

`kind` is `&"beam"` or `&"missile"`. `Weapons` owns all ammunition logic: it checks
`GameState.has_beam` and calls `GameState.spend_missile()` as appropriate. If the ability is lacking,
it does nothing silently. **Player never checks ammo itself** — it just calls `fire`.

### Player responsibilities

The player has a `Marker2D` named `Muzzle`, placed at hip height in front of the player and
mirrored with `facing`. When `fire_beam` or `fire_missile` is called:

```gdscript
Weapons.fire(&"beam", $Muzzle.global_position, Vector2(facing, 0))
```

No beam or missile firing in Slipstream form. Phase 1 addendum permits X/J bomb placement after
bomb unlock; A/Space Ball jump remains movement, not firing. Shots must not lock movement.

### Enemies

Each enemy exposes:

```gdscript
func take_damage(amount: int, kind: StringName) -> void
```

**The creep enemy (`scenes/enemies/crawler.tscn`) is immune to `&"beam"`** and is damaged only by
missiles. That is intentional gating, not a bug: it teaches the player that the base beam is not
enough, long before the missiles are found. It should never be able to be killed with the ray, and
hits with the beam should give a clear bounce/clunk feedback so the immunity reads as
intentional and not like the game is unresponsive.

The crawler moves along surfaces and follows the contour around corners — floor, wall, ceiling, underside.
It does not chase the player and never changes direction by itself. Contact damages the player.

### Collision layers

**Godot's `collision_layer` and `collision_mask` are bitmasks, not editor layer numbers.**
Layer *n* in the editor interface has the value `1 << (n - 1)`. Use the value column below
directly; never write the editor layer number as the value.

| Layer | Meaning | Value |
|---|---|---|
| 1 | World / Terrain | `1` |
| 2 | Player | `2` |
| 3 | Pickups | `4` |
| 4 | Enemies | `8` |
| 5 | Player projectiles | `16` |

Concrete: projectiles have `collision_layer = 16` and `collision_mask = 9` (world + enemies).
Enemies have `collision_layer = 8` and detect the player via mask bit `2`.

### Input documents (additions)

| Handling | Controls |
|---|---|
| `fire_beam` | X (J alternate) |
| `fire_missile` | C (K alternate) |

The missile button is there from the start but does nothing until missiles are found. The button is
prepared, the ability is not.

## Health and damage — binding interface

### `GameState` is extended

```gdscript
signal health_changed(current: int, maximum: int)
signal player_died

var max_health: int = 100
var health: int = 100

func reset_health() -> void          # health = max_health, emits health_changed
func apply_damage(amount: int) -> void   # decreases and clamps to 0, emits health_changed
                                          # and emits player_died when it reaches 0
func heal(amount: int) -> void       # increases and clamps to max_health, emits health_changed
```

`GameState` records health. It knows nothing about invulnerability, knockback, or blinking — those are the
player's responsibility. `apply_damage` shall always apply what it receives; the caller has already
determined that the damage is valid.

### Player

```gdscript
func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void
```

The player owns the invulnerability window, knockback, input lock, and blinking defined by
`take_damage`. If invulnerability is active, `take_damage` returns without doing anything —
no sound, no push, and no call chain to `GameState`. `source_position` gives the push
direction; if it is `Vector2.ZERO`, the player is pushed back relative to `facing`.

The player plays `Audio.play_sfx(&"player_hurt")` on an actual hit, never on a parry.

### Enemies calls

```gdscript
player.take_damage(CONTACT_DAMAGE, global_position)
```

The creep `CONTACT_DAMAGE` is changed from `1` to `12`, according to `docs/game-feel.md`. The enemy
sends its own position so that knockback points correctly. The enemy does not know the player's health
and must never read `GameState.health`.

### HUD

```
scenes/ui/hud.tscn
scripts/ui/hud.gd
```

`scenes/ui/hud.tscn` is instantiated by the level scene. It listens to `GameState.health_changed` and displays
the health. **No tutorial text, no instructions** — just the meter. It should be readable in half a
second in the corner of your eye: a bar or segment, not a number you have to focus on. A small one
number label next to the bar is allowed, but the bar is what carries the information.

Owned by the HUD agent. No one else writes in `scenes/ui/**` or `scripts/ui/**`.

## Scope — binding interface

The player calculates the aiming direction according to the table in `docs/game-feel.md` and passes it on:

```gdscript
Weapons.fire(&"beam", $Muzzle.global_position, aim_direction)
```

`Weapons` normalizes the direction and sends it to the projectile. The projectile should **rotate**
according to its direction of travel (`rotation = direction.angle()`), otherwise an upward shot looks like one
horizontal shot sliding upwards.

The player's sprite chooses a pose based on the aim according to `docs/asset-contract.md`. `facing` is controlled by
movement and never by aiming.


## Phase 1 — enabled extension

For the developer track, new APIs, file areas, frozen platforms, and coordination are defined in
`devmode-contract.md`. The addendum specifies the above interface;
existing basic movement and the crawler's missile exclusivity are retained.

## Parallel lanes 2026-09 (D14)

Each lane runs in its own worktree/branch `lane/<id>` and writes only its files. `docs/` stays with the
integrator except where a lane is named below. Nobody except the owning lane edits `Makefile`,
`project.godot` or `scripts/autoload/game_state.gd`; ask the integrator for new test targets.

| Lane | Owns (write) |
|---|---|
| `env` — area identity/graphics | `scripts/world/**` except `environment_ambience.gd`; `assets/environment/**`; `tools/build_environment_kits.py`, `tools/build_facility_art.py`, `tools/build_industrial_hazards.py`, `tools/gen_terrain.py`; `scripts/dev/dev_station_layout.gd`, `scripts/dev/dev_hazard.gd`, `scripts/dev/dev_passage.gd` (visual placement only, no route/pickup/ID changes); env check scripts it creates; `docs/visual-plan.md`. |
| `audio` — music/ambience/mix | `scripts/autoload/audio.gd`, `scripts/world/environment_ambience.gd`, `assets/audio/**`, `tools/gen_audio.py`, audio check scripts. Owns bus layout; buses `Master`, `Music`, `SFX`, `Ambience` must exist. |
| `combat` — combat/enemy/boss/player juice | `assets/sprites/combat/**`, `assets/sprites/enemies_new/**`, `assets/worldfx/**` (worldfx), `scripts/world/dynamic/**`, `scenes/world/dynamic/**`, `assets/audio/sfx/enemies/**`, `scripts/combat/**`, `scenes/combat/**`, `scripts/enemies/**`, `scenes/enemies/**`, `scripts/effects/**`, `scenes/effects/**`, `resources/combat/**`, `scripts/player/**`, `scenes/player/**`, `scripts/autoload/weapons.gd`, related check scripts. Tuned values in `game-feel.md` stay unchanged. |
| `ui` — menus/settings/HUD | `scripts/ui/**`, `scenes/ui/**`, `assets/ui/**`, `user://settings.cfg` format. |
| `campaign` — Phase 2 mini-campaign | `project.godot`, `scripts/autoload/game_state.gd`, `scripts/save/**`, `scripts/progression/**`, `scripts/pickups/**`, `scenes/pickups/**`, `scripts/campaign/**`, `scenes/campaign/**`, campaign check scripts. |
| `process` — tooling slim-down | `Makefile`, `.gitignore`, `proofs/**`, `.agent-reports/**`, `tools/run_godot_check.py`, `tools/check_f1_evidence.py`, `tools/check_motion_evidence.py`, `tools/check_docs.py`, `scripts/dev/evidence_runner.gd`, `docs/workflow.md`, `docs/pitfalls.md`. |

### Cross-lane interfaces (build against these; use `has_method` / null-safe `load()` until merged)

- **Area per room (env provides, campaign calls):** `CaveVisuals.configure(tiles: TileMapLayer)` stays.
  New: `CaveVisuals.set_fixed_area(area_id: StringName) -> void` forces one kit (`fringe`, `nexus`,
  `vaults`, `kiln`, `depths`) for the whole TileMap, disabling world-x boundary blending. Dev world
  keeps x-boundary behaviour when it is never called.
- **Area music/ambience (audio provides):** `Audio.play_area(area_id: StringName)` switches music and
  ambience with a crossfade; calling it with the current area is a no-op.
- **Campaign entry (campaign provides, ui calls):** `res://scripts/campaign/campaign_entry.gd`,
  `class_name CampaignEntry`, static `has_save() -> bool`, `new_game() -> void`,
  `continue_game() -> void`. Both change scene themselves.
- **Settings (ui owns):** volume sliders drive `AudioServer` buses `Music`, `SFX`, `Ambience`, `Master`.
  Rebinding edits `InputMap` at runtime and persists in `user://settings.cfg`; action names are unchanged.
- **Pause (ui owns):** pause menu is a `CanvasLayer` usable from both dev level and campaign rooms. The
  campaign map screen belongs to `campaign`.
