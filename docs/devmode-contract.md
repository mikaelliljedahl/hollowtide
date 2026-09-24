# Phase 1 — integration contract (normative supplement)

The user's approval to start the dev track activates this supplement for P0–P7.
It resolves the plan's open API and ownership questions for the implementation below; it does not
replace the tuned base-movement values. Campaign production P8–P11 remains blocked until the user
playtests and accepts the dev track. The live decision below is a normative reconciliation; it does not change physics, damage, or collision constants.

## Orchestration

This deployment round may rerun a maximum of three write Luna tasks simultaneously, provided that file areas remain completely separate and the APIs below are already locked, plus one isolated Codex image agent.
This is a defined exception to the plan's more cautious two-agent standard. The integrator
does not modify an active agent's owned files before the assignment is returned.

## File ownership during this delivery

- System: `scripts/autoload/game_state.gd`, `scripts/progression/**`, `scripts/save/**`,
  `scripts/pickups/**`, `scenes/pickups/**`, `resources/progression/**`.
- Battle: `scripts/autoload/weapons.gd`, `scripts/combat/**`, `scenes/combat/**`,
  `scripts/enemies/**`, `scenes/enemies/**`, `resources/combat/**`.
- Movement: `scripts/player/**`, `scenes/player/**`.
- Graphics: `assets/sprites/**` (incl. `arsenal/`, `enemies_new/`), `assets/environment/**`,
  `assets/worldfx/**`, `tools/build_devmode_art.py`, `tools/build_area_art.py`, `tools/gen_sprites.py`. Image-generating Codex may write image originals only in
  `tools/source_art/devmode/**`; no code or document changes.
- Integrator/scaffold: `scripts/dev/**`, `scripts/world/**`, `scenes/dev/**`,
  `scenes/levels/**`, `project.godot`, `Makefile`, test configuration and documentation.
- HUD: `scripts/ui/**`, `scenes/ui/**` (including dev panel).
- Sound: `scripts/autoload/audio.gd`, `assets/audio/**`, `tools/gen_audio.py`.
- Each agent owns its own new `tools/check_<task>.*` and task report in
  `.agent-reports/`. Existing verification scripts are modified only by the integrator.

## Runtime IDs and shared data

`ContentCatalog` (`scripts/progression/content_catalog.gd`, `class_name ContentCatalog`)
is the single source of truth for new balance values, ability lists, enemy IDs, and pickup mappings.
Runtime ability IDs: `beam`, `slipstream`, `missiles`, `long_beam`, `ice_beam`,
`wave_beam`, `bombs`, `high_jump`, `pressure_seal`, `undertow_dash`, `flux_shield`, `burst_beam`,
`echo_scan`. Visible names differ (D19): see `DISPLAY_NAMES` and
[content-catalog.md](content-catalog.md#names-and-internal-ids-d19).
Active beam: `base`, `ice`, `wave`. Long is separate passive modifier.

Constants: beam 10, wave 12, missile 35, bomb 20, undertow 24; beam range 640 px,
Long ×1.75; bomb fuse 0.75 s, radius 72 px, lift 720 px/s, max three active bombs;
freeze 4 s. High Jump ground impulse 1568 px/s as initial calibration, about 1.5 × measured
base height. Wall-jump impulse, gravity, cutoff, apex behavior, and all other base values remain unchanged.
Pressure Seal halves valid positive damage, rounded up, before `GameState.apply_damage`.

## GameState — data, not file I/O

Existing signals/properties/methods are kept compatible. Add:

```gdscript
signal state_changed
signal ammo_changed(current: int, maximum: int)
var max_missiles: int = 0
var active_beam: StringName = &"base"
func has_ability(id: StringName) -> bool
func unlock_ability(id: StringName) -> bool
func collect_pickup(instance_id: String, kind: StringName) -> bool
func set_active_beam(kind: StringName) -> bool
func set_active_flux_module(module: StringName) -> bool
func set_flux_enabled(enabled: bool) -> bool
func spend_flux(amount: int) -> bool
func refill() -> void
func refill_missiles(amount: int) -> void
func refill_flux(amount: int = 10) -> void
func reset_progress() -> void
func snapshot() -> Dictionary
func restore_snapshot(data: Dictionary) -> bool
func set_world_flag(id: String, value: bool = true) -> void
func has_world_flag(id: String) -> bool
```

Pickup `kind`: ability-ID, `energy_tank`, `missile_tank`, `flux_tank`, `energy_refill`,
`missile_refill`, or `flux_refill`.
Unique instance IDs are recorded atomically; duplicate collection returns false without mutation. Refill is consumption
without permanent ID record keeping; spawn/reset owns its life cycle. Bolt Quiver unlocks missiles
at first container and raises max/current ammo +5 (max 12 tanks). Heart Pearl gives +100 max
(maximum 6), fills completely. `unlock_ability(missiles)` for dev gives first container capacity
if missing, not free +5 on each call. Bomb requires Slipstream; beam variants require beam.
Invalid snapshot/pickup is rejected in full, not in part. Active beam must be owned.
Legacy `acquire_missiles(n)` provides first unlock when needed and fills n within capacity;
legacy `acquire_beam`/`acquire_slipstream` call the same state path.

Snapshot schema v2 contains version, abilities, active beam, energy/missile/Flux tank counts,
current resources, active Flux module/enabled state, collected IDs, world flags, discovered rooms,
and checkpoints. Valid v1 snapshots migrate with zero Flux state; unknown/future versions reject.
Checkpoint standard:
`{room: "prototype", x: 3360.0, y: 448.0}`. New coordinates must be finite and secure;
scaffold is responsible for actual spawn validation. `set_checkpoint(room: String, position: Vector2)`
and `discover_room(room: String)` are common mutators; property `checkpoint: Dictionary`
and `discovered_rooms: Array[String]` may be read, not manipulated by the UI.

## SaveStore — autoload

`res://scripts/save/save_store.gd`, autoload `SaveStore`. Domain is selected at startup, `dev` only
with `OS.is_debug_build()` and `--dev-mode` in user arguments, otherwise `campaign`.

```gdscript
var domain: StringName
func save_game() -> Error
func load_game() -> Error
func has_save() -> bool
```

Domain is not changed at runtime. Paths `user://saves/<domain>/slot_01.json`, `.bak`, `.tmp`.
Snapshot is encapsulated by schema version and domain. Validation before state change; atomic file replacement,
valid backup is preserved, corrupt/unknown version is not automatically overwritten. Never fall back again in
the other domain. Tests must use isolated temporary path or own test project/user directory;
tests must never write real user save files.

## Player — new public interfaces

```gdscript
var is_spinning: bool
var undertow_active: bool
var dev_invulnerable: bool = false
func apply_bomb_impulse(origin: Vector2, radius: float) -> void
func reset_for_spawn(position: Vector2) -> void
```

The player belongs to group `player`. `apply_bomb_impulse` provides lift only in ball and within radius;
no player injury. `reset_for_spawn` restores shape, velocity, timers, spin, blink and
camera smoothing. Death stops control/shot to respawn; scaffold handles the respawn itself.

Spin starts on a horizontal ground jump or wall jump and is interrupted by landing, shooting, vertical aim,
slipping, actual damage, death, or reset. Jumps from a standstill and ball lifts are not spins.
Undertow hits once per continuous overlap for enemies in group `damageable`, within an 82 px radius
around the body (global position + Vector2(0,-88)). Call `take_damage(24, &"undertow")`.
Immune crawler or boss phase may still damage the player; no general invulnerability.
`is_vulnerable_to(kind: StringName) -> bool` on enemies determines contact priority.

In ball form, X/J (`fire_beam`) places a bomb via `Weapons.fire(&"bomb", ball_center, Vector2.UP)`;
beam/missiles remain prohibited. A/Space performs a regular grounded/coyote jump (A primary, Space
alternate) with unchanged base
`JUMP_VELOCITY` while Ball form/collider remain active. High Jump, wall jump, humanoid spin/Undertow,
and midair double jump do not apply. Bomb lift remains separate and unchanged.

## Weapons and enemies

Existing `Weapons.fire(kind, origin, direction)` is retained; `bomb` is new case.
Weapons reads `GameState.active_beam` for `beam`, creates the correct variant and handles cost,
cooldown and a maximum of three bombs. Physics time, not wall-clock time, controls cooldown so pause behavior remains a real pause.
`Weapons.reset_runtime()` clears cooldown. Group `transient` for projectiles/bombs/effects.

Enemy types: `crawler`, `ceiling_diver`, `vent_flyer`, `hopper`, `spitter`, `armored_guard`,
`frost_floater`, `energy_parasite`, `shard_turret`, `burrower`, `grasshopper`,
`shooting_gargoyle`, `lava_monster`. The final five are additive Phase 1 expansions of the
original eight; no existing ID is renamed or replaced. Boss ID: `stone_guardian`,
`furnace_mother`, `tidal_heart`.
Factory `EnemyFactory.create(id: StringName) -> Node2D` in `scripts/enemies/enemy_factory.gd`
returns a configured, unparented enemy or null for unknown ID.
All enemies expose `take_damage(amount, kind)` and `is_vulnerable_to(kind)` and belong to the
`damageable` and `enemies` groups; bosses also belong to `bosses`. Boss exposes `signal defeated(id: StringName)` and
`set_test_phase(phase: int)`. Type ID and current/max HP are readable via `enemy_id`, `health`,
`max_health`. The death flag is always saved by the scaffold, never by the enemy script.

Freezable enemies become platforms at **layer 6, bit value 32**; player mask `1 | 32 = 33`.
Layers 1 Terrain, 2 Player, 3 Pickup, 4 Enemy, 5 Player Projectile are retained. Enemy projectiles
are Area2D with mask 2, no new layer conflict. Frozen enemy stops AI and contact damage,
can be damaged according to reaction matrix, thaws without HP reset. Bomb area also hits air targets in radius.
The crawler remains vulnerable ONLY to missiles. Reaction matrix from content-catalog applies.
The boss arena's resource source is scaffold responsibility; boss may not require more max capacity than five missiles.

## Graphics and terrain

Allowed addition: 256 px visual modules in `assets/environment/**`, separate 64 px
TileMap collision, common manifest layout. Original `tileset_cave.png` is kept compatible.
Full Phase 1 environmental production and technical captures are integrated; user's trial run remains
final visual gate and no technical capture asserts approved graphics.
Spin strips: `assets/sprites/player_spin.png` and `player_spin_armed.png`, eight 256 px squares,
anchor (128,240), body pivot (128,144). Body is scaled from the 192 px portrait reference, so each collapsed box does not fill the same height. Various drawn poses are required; never use a spun upright sprite.
Enemy/boss graphics are delivered under `assets/sprites/devmode/<runtime_id>.png`;
each file a 256 px square for normal enemies, 512 px square for bosses. Animation can combine
sprite deformation/pose and separate effects but should show attack signals; new extra poses
may be added if there is a documented need. Icons: `assets/sprites/devmode/<ability_id>.png`,
`<pickup_kind>.png` and explicit feedback motifs in 128 px. Every arsenal/pickup motif should be mapped by stable runtime ID; generated image without runtime connection does not count as delivery.

## Normative live reconciliation

- Visible runtime strings are English. The documentation is in English. Start menu, pause/help and
  devpanel may display controls and technical labels; the game world gets no tutorial text.
- Runtime bindings are Down crouch, Z Slipstream, Left Shift held for run, A jump (Space alternate),
  X beam/bomb or crouched low shot, C missiles, V owned-beam cycle, Q owned-Flux-module cycle,
  F Flux activate/toggle, Esc pause/help, and F1 dev panel. J/K are alternate beam/missile bindings.
- Death waits 0.45s, restores full health at current session checkpoint and keeps
  progress in memory. The disk save does not load during death respawn.
- Enemy drops are temporary: energy +25, missile +2, or owned-system Flux +10, clamped to capacity,
  without permanent pickup ID or progression lock. Reset and death clear loot.
- Actual events require matching feedback: splash/start presentation, HUD state, distinct Ice/Wave
  effects, Undertow Dash aura, a compact bomb explosion, and enemy/boss death effects with relevant sounds.
  Feedback may not replace hit logic, create tutorial text, or grant immortality.

## Integration and limit for this session

Scaffold builds on `level_01`, keeping the original flow and adding hubs/sample rooms.
F1 switches devpanel; only debug + explicit dev mode enables it. No tutorial text in
the game world. The UI can display technical labels in the panel and help in the dev menu.
Dev isolation/reset/flag saving test follows implementation-decisions and phase-1-devmode.
The developer track is handed over for user testing; campaign production does not start automatically.

## Fixed integration decisions

- Runtime UI and visible game strings are in English. The project's documentation is in English.
  Help in start menu and pause panel is explicitly approved text outside the game world; no
  tutorial text is added to the game world.
- Runtime controls are Down crouch, Z Slipstream, Left Shift held for run, A jump (Space alternate),
  X beam/bomb or crouched low shot, C missiles, V beam cycle, Q owned-Flux-module cycle,
  F Flux activate/toggle, Esc pause/help, and F1 dev panel. J/K remain alternate beam/missile bindings.
- Normal boot uses `make run`; dev boot uses `make dev`, which starts the normal boot menu
  with explicit dev flag. The dev panel and dev profile remain isolated.
- Death waits 0.45s, restores full health at last checkpoint and keeps current
  progress in memory. Death does not load the disk save; this supersedes the earlier death-reload plan.
- Phase 1 integration is implemented but F1 is awaiting playtests and ongoing integration.
  Phase 2 has not started.
- Image-agent rule remains: Sol may take code work through approved Pi escalation. Codex CLI agents
  may write only still-image originals under `tools/source_art/devmode/**`. The limit remains three
  concurrent code-writing assignments plus one isolated image agent.
- Normal spin is user-approved ("the spin looks good"). No other visual/audio acceptance is claimed.
- Crouch/Z-Slipstream/Shift-run/low-shot controls, authored sprint and wall poses, muzzle mapping, pickup
  icons, thirteen-enemy panel, authored beam families, gates, Wave Grate, shrines, and ten station-boundary
  passages are implemented. They remain subject to F1 hands-on review.
- S0–S10 presentation uses fringe S0–S1, nexus S2–S3, vaults S4–S5, kiln S6–S7, and depths S8–S10.
  Kiln includes visible basalt/lava/fire/steam hazards and ambience. Five-area presentation is Phase 1
  review scope, not evidence that campaign P9 started.

## Accepted Slipstream jump replacement

User-approved replacement D04-R1 is implemented: Slipstream can perform regular grounded/coyote
Jump on A (Space as alternate) with unchanged base `JUMP_VELOCITY`, retaining Ball form and collider. No High Jump
multiplier, wall jump, spin/Undertow, or midair double jump applies. Bomb lift remains separate and
unchanged. This supersedes every older no-ball-jump statement.

## Implemented Flux package and save v2

Flux Shield, Burst Beam, Echo Scan, four Flux Tanks, refills/drops, HUD/dev controls, VFX/audio, and
save/load are implemented. One module is selected at a time: Q cycles owned modules; F toggles
Shield/Burst or pulses Echo. First ownership supplies 100 capacity; four tanks add 50 each to maximum
300. Echo costs 20, temporary refill gives 10, Burst drains 8/s, and Shield costs one Flux per damage
absorbed. Schema v2 persists fields and explicitly migrates valid v1 saves without latent Flux state.
No world tutorial text is allowed.

## Current integration gate

All twelve dev-track Bolt Quivers keep stable IDs/count and have audited standing-safe collection and
retreat. Five original 48-second area melodies are integrated. The three additive enemy IDs, natural
S5/S7/S8 boss encounters, and grounded Kiln lava basins are part of the active F1 integration and must
pass the full gate before evidence is refreshed. F1 still requires user hands-on approval.
