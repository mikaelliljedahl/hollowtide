# Graphics provenance — developer path

This is a work inventory, not a legal certificate. All art shipped in this repository is original to
Hollowtide: raster images were generated with AI image tools (GPT Image via Codex) from the project's
own written prompts and briefs, and the rest is hand-authored SVG or procedural code. No images from
other games, publishers or third-party asset packs are included. Unknown generation IDs remain unknown; a commercial release
still requires a review of the generator's terms.

2026-09 scrub: early item/upgrade studies that leaned too close to genre-classic designs (arm-cannon
guns, red rockets, an armored rolling sphere, energy-tank canisters) and their generation paths were
deleted. Their runtime replacements are the original D19 arsenal art listed below.

## Older sources

- `tools/source_art/tileset_cave_hd.png`: detailed cave original, 1448×1086. Older reports describe
  GPT Image use; full generation ID is missing.
- `tools/source_art/player_*_hd.png`, `crawler_hd.png`, `orb_hd.png`, weapon/projectile sources:
  existing originals from earlier project image work, used for runtime sprites and identity references.
- `tools/source_art/cave_concept.png`: legacy mood/composition reference, not active module source.

## Reported early Codex image rounds

First round reported native `image_gen`, metadata `gpt-image 2.0`, session
`01a0ab50-2c7c-72a1-84e2-12d41356ecab`.

| Source under `tools/source_art/devmode/` | Contents | Reported generation record / status |
|---|---|---|
| `enemy_roster_hd.png` | Seven creatures | `exec-756a4194…`; active source. |
| `boss_roster_hd.png` | Three bosses | `exec-1fe188fe…`; active source. |
| `player_spin_hd_v2.png` | Corrected unarmed spin | Active; full ID not reported. |
| `player_spin_armed_hd_v3.png` | Corrected armed spin | Active edit; full ID not reported. |
| `splash_hd.png` | Start screen, 1672×941 RGB | Runtime `assets/ui/splash.png` 1920×1080; full ID not reported. |
| `player_shoot_right_hd.png` | Horizontal firing pose, 1254×1254 RGB | Runtime 256×256 pose with authored muzzle mapping; full ID not reported. |

Abbreviated IDs are reproduced as reported, never expanded or invented.

## Current Phase 1 source inventory

All paths below exist in repository. They were created as original Hollowtide source images through
Codex image work, but reports do not contain reliable full generation IDs. Rights/generation ID are
therefore recorded as **unknown**, not inferred from filenames or runtime manifests.

| Source | Actual size/format | Processed outputs and status |
|---|---|---|
| `enemies_extra_hd.png` | 1774×887 RGB | 256×256 `shard_turret` and `burrower`; runtime integrated. |
| `f1_new_enemies.svg` | 1536×512 authored SVG | Original vector source for 256×256 `grasshopper`, `shooting_gargoyle`, and `lava_monster`; no external/private-reference assets. |
| `industrial_hazards.svg` | 1024×512 authored SVG | Original coherent four-frame industrial fire-jet and steam-vent strips; supersedes the campfire/forge-like runtime studies without changing damage behavior. |
| `beam_family_vfx_hd.png` | 1536×1024 RGB | Authored beam-family projectiles/impacts, including Burst family; runtime integrated. |
| `wave_core_hd.png` | 1774×887 RGB | Wave core animation source; runtime integrated. |
| `wave_interactions_hd.png` | 1448×1086 RGB | Wave interaction/grate effects; runtime integrated. |
| `player_movement_extra_hd.png` | 1536×1024 RGB | Crouch and earlier sprint/air poses; runtime integrated where selected. |
| `player_sprint_wall_hd.png` | 1402×1122 RGBA | Sprint/armed sprint plus wall-slide/wall-jump pose strips; runtime integrated. Full generation ID unknown. |
| `dev_fixtures_hd.png` | 1774×887 RGBA | Passage arch, missile/bomb/undertow gates, Wave Grate, and checkpoint/refill/Flux shrines; runtime integrated at ten station boundaries and fixtures. Full generation ID unknown. |
| `flux_systems_hd.png` | 1536×1024 RGB | Flux Shield/Burst/Echo pickups/VFX plus shared tank/refill motifs; runtime integrated for four stable Flux Tank IDs. |
| `fire_lava_vfx_hd.png` | 1536×1024 RGBA | Lava remains runtime-integrated; old campfire, fire-vent, and mixed steam cells are retained only as superseded source-sheet studies. |
| `cave_fringe_hd.png` | 1448×1086 RGB | Fringe fill/background/landmark source; runtime S0–S1. |
| `cave_nexus_hd.png` | 1448×1086 RGB | Nexus fill/background/landmark source; runtime S2–S3. |
| `cave_vaults_hd.png` | 1448×1086 RGB | Vaults fill/background/landmark source; runtime S4–S5. |
| `cave_kiln_hd.png` | 1448×1086 RGBA | Basalt/Kiln fill/background/landmark source; runtime S6–S7. |
| `cave_depths_hd.png` | 1448×1086 RGB | Depths fill/background/landmark source; runtime S8–S10. |

Cave, fire/lava, and Flux sources are present; they are not absent placeholders. Five kits produce
256px fill modules, 1920×1080 far/mid layers, 1024×768 room-scale landmarks, manifests, and four
768×256 transition bridges. Environment checks and native captures establish technical wiring only.

## Processing and mapping

- `tools/build_devmode_art.py`: soft-alpha matte helpers and the `shard_turret`/`burrower` extraction.
  Pickup icons under `assets/sprites/devmode/` and `assets/sprites/arsenal/` are delivered as finished
  128×128 originals and are not regenerated.
- `tools/build_flux_art.py`: deterministic Flux pickup/effect extraction with continuous alpha.
- `tools/build_presentation_art.py`: sprint/wall-pose and authored fixture processing with source-
  component/noise checks.
- `tools/build_new_enemy_art.py`: deterministic ImageMagick/Pillow rasterization of the original SVG
  expansion roster, with safe-alpha margins, hashes, and a dark proof sheet.
- Area art is built by `tools/build_area_art.py` into `assets/environment/areas/<area>/` (with `area.json`).
- `tools/build_industrial_hazards.py`: deterministic rasterization of coherent original fire/steam
  strips with exact runtime ownership, hashes, floor anchors, and a dark proof.

## Round 2 art (2026-09, Codex GPT-image)

Generated by a Codex image agent from lane briefs (painterly style locked to the existing player and
dev-mode sprites); generation IDs were not recorded. Runtime locations:

- `assets/sprites/arsenal/`: D19 arsenal — Harpoon, harpoon bolt/peg/socket, Bolt Quiver, Quiver Cache,
  Bubble Snare, bubble floater, Echo Shot, Resonance Pulse, Cracked Crystal, Resonant Membrane,
  Focus Lens, Undertow Dash/Barrier, Heart Pearl.
- Seed Crossbow player poses (replace the pistol), Slipstream body strip and icon, Updraft Cloak and
  Pressure Seal overlays under `assets/sprites/`.
- `assets/sprites/enemies_new/`: surprise enemies (bat swarm, mimic, drop spider, surface eel, stalker,
  chasm sniper).
- `assets/worldfx/`: stalactites, slabs, crushers and switches for the living environment.
- Per-area art under `assets/environment/areas/<area>/`.

## Human-review status

Normal spin is user-approved. No other human visual/audio approval is claimed. The user has played the campaign on this art; there is no formal per-asset sign-off. Rights/provenance uncertainty remains a release concern even if
visual approval passes.
