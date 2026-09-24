#!/usr/bin/env python3
"""Validate the complete Phase 1 runtime catalog without launching Godot."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

AREAS = ("fringe", "nexus", "vaults", "kiln", "depths")
AREA_BY_ROOM = {
    "S0": "fringe",
    "S1": "fringe",
    "S2": "nexus",
    "S3": "nexus",
    "S4": "vaults",
    "S5": "vaults",
    "S6": "kiln",
    "S7": "kiln",
    "S8": "depths",
    "S9": "depths",
    "S10": "depths",
}
ABILITIES = (
    "beam",
    "slipstream",
    "missiles",
    "long_beam",
    "ice_beam",
    "wave_beam",
    "bombs",
    "high_jump",
    "pressure_seal",
    "undertow_dash",
    "flux_shield",
    "burst_beam",
    "echo_scan",
)
FLUX_ABILITIES = ("flux_shield", "burst_beam", "echo_scan")
ENEMIES = (
    "crawler",
    "ceiling_diver",
    "vent_flyer",
    "hopper",
    "spitter",
    "armored_guard",
    "frost_floater",
    "energy_parasite",
    "shard_turret",
    "burrower",
    "grasshopper",
    "shooting_gargoyle",
    "lava_monster",
)
BOSSES = ("stone_guardian", "furnace_mother", "tidal_heart")
REFILLS = ("energy_refill", "missile_refill", "flux_refill")
PHYSICAL_ABILITY_KINDS = (
    "beam",
    "slipstream",
    "long_beam",
    "ice_beam",
    "wave_beam",
    "bombs",
    "high_jump",
    "pressure_seal",
    "undertow_dash",
    *FLUX_ABILITIES,
)
BASE_PICKUP_KINDS = (
    "beam",
    "slipstream",
    "missiles",
    "long_beam",
    "ice_beam",
    "wave_beam",
    "bombs",
    "high_jump",
    "pressure_seal",
    "undertow_dash",
    "energy_tank",
    "missile_tank",
    "energy_refill",
    "missile_refill",
)
PICKUP_KINDS = (*BASE_PICKUP_KINDS, *FLUX_ABILITIES, "flux_tank", "flux_refill")
FORBIDDEN_ASSET_WORDS = ("placeholder", "fallback", "pending", "temporary", "temp_")


class CatalogError(Exception):
    """Raised when a required source construct cannot be parsed safely."""


def _read(relative: str):
    path = ROOT / relative
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise CatalogError(f"{relative}: cannot read: {error}") from error


def _balanced_block(source: str, constant: str, opener: str, closer: str):
    match = re.search(rf"(?m)^const\s+{re.escape(constant)}\b[^=]*=", source)
    if match is None:
        raise CatalogError(f"missing constant {constant}")
    start = source.find(opener, match.end())
    if start < 0:
        raise CatalogError(f"{constant}: missing {opener}")
    depth = 0
    quote = ""
    escaped = False
    for index in range(start, len(source)):
        char = source[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in ('"', "'"):
            quote = char
        elif char == opener:
            depth += 1
        elif char == closer:
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    raise CatalogError(f"{constant}: unterminated {opener}{closer} block")


def _array_names(source: str, constant: str):
    return re.findall(r'&"([^"]+)"', _balanced_block(source, constant, "[", "]"))


def _array_strings(source: str, constant: str):
    return re.findall(r'(?<!&)"([^"]+)"', _balanced_block(source, constant, "[", "]"))


def _dict_pairs(source: str, constant: str, value_string_name: bool = False):
    block = _balanced_block(source, constant, "{", "}")
    value_prefix = r'&"' if value_string_name else '"'
    pattern = rf'&"([^"]+)"\s*:\s*{value_prefix}([^"]+)"'
    return re.findall(pattern, block)


def _dict_name_keys(source: str, constant: str):
    block = _balanced_block(source, constant, "{", "}")
    return re.findall(r'&"([^"]+)"\s*:', block)


def _sha256(path: Path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _resolve_resource(path_text: str):
    if not path_text.startswith("res://"):
        raise CatalogError(f"non-resource asset path: {path_text}")
    path = (ROOT / path_text.removeprefix("res://")).resolve()
    try:
        path.relative_to(ROOT.resolve())
    except ValueError as error:
        raise CatalogError(f"resource path escapes repository: {path_text}") from error
    return path


def _duplicates(values):
    return sorted(value for value, count in Counter(values).items() if count > 1)


def _expect_equal(errors: list[str], label: str, actual, expected):
    if tuple(actual) != tuple(expected):
        errors.append(f"{label}: expected {list(expected)}, found {list(actual)}")


def _expect_set(errors: list[str], label: str, actual, expected):
    actual_values = list(actual)
    actual_set = set(actual_values)
    expected_set = set(expected)
    if actual_set != expected_set:
        errors.append(
            f"{label}: missing={sorted(expected_set - actual_set)} extra={sorted(actual_set - expected_set)}"
        )
    duplicates = _duplicates(actual_values)
    if duplicates:
        errors.append(f"{label}: duplicate entries={duplicates}")


def _check_catalog(errors: list[str]):
    source = _read("scripts/progression/content_catalog.gd")
    _expect_equal(errors, "ability IDs", _array_names(source, "ABILITY_IDS"), ABILITIES)
    _expect_equal(
        errors, "Flux ability IDs", _array_names(source, "FLUX_ABILITY_IDS"), FLUX_ABILITIES
    )
    _expect_equal(errors, "enemy IDs", _array_names(source, "ENEMY_IDS"), ENEMIES)
    _expect_equal(errors, "boss IDs", _array_names(source, "BOSS_IDS"), BOSSES)
    base_pickup_kinds = _array_names(source, "PICKUP_KINDS")
    _expect_equal(errors, "base pickup kinds", base_pickup_kinds, BASE_PICKUP_KINDS)
    flux_pickup_kinds = [*FLUX_ABILITIES, *_array_names(source, "FLUX_PICKUP_KINDS")]
    overlap = sorted(set(base_pickup_kinds) & set(flux_pickup_kinds))
    if overlap:
        errors.append(f"base/Flux pickup kinds overlap: {overlap}")
    _expect_set(
        errors,
        "combined pickup kind partition",
        [*base_pickup_kinds, *flux_pickup_kinds],
        PICKUP_KINDS,
    )

    energy_ids = _array_strings(source, "ENERGY_CONTENT_IDS")
    missile_ids = _array_strings(source, "MISSILE_CONTENT_IDS")
    flux_tank_ids = _array_strings(source, "FLUX_TANK_CONTENT_IDS")
    if energy_ids != [f"UPG-ENERGY-{index:02d}" for index in range(1, 7)]:
        errors.append(f"energy content IDs: expected 01-06, found {energy_ids}")
    if missile_ids != [f"UPG-MISSILE-{index:02d}" for index in range(1, 13)]:
        errors.append(f"missile content IDs: expected 01-12, found {missile_ids}")
    if flux_tank_ids != [f"UPG-FLUX-TANK-{index:02d}" for index in range(1, 5)]:
        errors.append(f"Flux Tank content IDs: expected 01-04, found {flux_tank_ids}")
    all_capacity_ids = [*energy_ids, *missile_ids, *flux_tank_ids]
    if _duplicates(all_capacity_ids):
        errors.append(f"capacity content IDs are duplicated: {_duplicates(all_capacity_ids)}")

    _expect_set(errors, "enemy data", _dict_name_keys(source, "ENEMY_DATA"), ENEMIES)
    _expect_set(errors, "boss data", _dict_name_keys(source, "BOSS_DATA"), BOSSES)
    _expect_set(
        errors, "pickup icon mapping", dict(_dict_pairs(source, "PICKUP_ICON_PATHS")), PICKUP_KINDS
    )
    _expect_set(
        errors,
        "pickup sound mapping",
        dict(_dict_pairs(source, "PICKUP_SOUND_CATEGORIES", value_string_name=True)),
        PICKUP_KINDS,
    )
    for constant, expected in (
        ("MAX_ENERGY_TANKS", 6),
        ("MAX_MISSILE_TANKS", 12),
        ("MAX_FLUX_TANKS", 4),
    ):
        match = re.search(rf"(?m)^const\s+{constant}\s*:=\s*(\d+)\s*$", source)
        if match is None or int(match.group(1)) != expected:
            errors.append(f"{constant}: expected {expected}")

    return source


def _check_assets(errors: list[str], catalog_source: str):
    audio_source = _read("scripts/autoload/audio.gd")
    icon_pairs = _dict_pairs(catalog_source, "PICKUP_ICON_PATHS")
    sound_pairs = _dict_pairs(catalog_source, "PICKUP_SOUND_CATEGORIES", value_string_name=True)
    sfx_keys = set(_dict_name_keys(audio_source, "SFX_PATHS"))
    icon_hashes: dict[str, str] = {}
    for kind, resource in icon_pairs:
        try:
            path = _resolve_resource(resource)
        except CatalogError as error:
            errors.append(f"icon {kind}: {error}")
            continue
        if path.name != f"{kind}.png":
            errors.append(f"icon {kind}: expected dedicated {kind}.png, found {resource}")
        if any(word in resource.lower() for word in FORBIDDEN_ASSET_WORDS):
            errors.append(f"icon {kind}: forbidden placeholder/fallback path {resource}")
        if not path.is_file() or path.stat().st_size == 0:
            errors.append(f"icon {kind}: missing or empty {resource}")
            continue
        icon_hashes[kind] = _sha256(path)
    duplicates = _duplicates(icon_hashes.values())
    if duplicates:
        duplicate_kinds = [kind for kind, digest in icon_hashes.items() if digest in duplicates]
        errors.append(f"pickup icons reuse identical placeholder bytes: {duplicate_kinds}")
    for kind, sound in sound_pairs:
        if sound not in sfx_keys:
            errors.append(f"pickup sound {kind}: Audio.SFX_PATHS lacks {sound}")

    for runtime_id in (*ENEMIES, *BOSSES):
        relative = (
            Path("assets/sprites/crawler.png")
            if runtime_id == "crawler"
            else Path("assets/sprites/devmode") / f"{runtime_id}.png"
        )
        path = ROOT / relative
        if not path.is_file() or path.stat().st_size == 0:
            errors.append(f"runtime art missing for {runtime_id}: {relative}")


def _placement_rows(source: str):
    rows = re.findall(r'\["(S\d+)",\s*"([^"]+)",\s*&"([^"]+)"\s*,\s*Vector2\(', source)
    calls = re.findall(
        r'(?:_spawn_pickup\(|\.call\(\s*"_spawn_pickup"\s*,)'
        r'\s*"([^"]+)"\s*,\s*&"([^"]+)"\s*,',
        source,
    )
    return [(instance_id, kind, room) for room, instance_id, kind in rows] + [
        (instance_id, kind, "S8") for instance_id, kind in calls
    ]


def _check_physical_catalog(errors: list[str]):
    station = _read("scripts/dev/dev_station_layout.gd")
    arena = _read("scripts/dev/dev_runtime_arena.gd")
    placements = _placement_rows(station) + _placement_rows(arena)
    instance_ids = [instance_id for instance_id, _, _ in placements]
    if _duplicates(instance_ids):
        errors.append(f"physical pickup instance IDs duplicated: {_duplicates(instance_ids)}")
    counts = Counter(kind for _, kind, _ in placements)
    for kind, expected in (("energy_tank", 6), ("missile_tank", 12), ("flux_tank", 4)):
        if counts[kind] != expected:
            errors.append(f"physical {kind}: expected {expected}, found {counts[kind]}")
    for kind in PHYSICAL_ABILITY_KINDS:
        if counts[kind] != 1:
            errors.append(f"physical ability {kind}: expected one pickup, found {counts[kind]}")
    if counts["missiles"] != 0:
        errors.append(
            "missiles must unlock through first Missile Tank, not a separate physical pickup"
        )

    # Two legacy prototype fixtures exercise the original cave but are outside the S0-S10 dev catalog.
    level = _read("scenes/levels/level_01.tscn")
    prototype_ids = re.findall(r'instance_id\s*=\s*"(prototype\.missile_tank\.\d+)"', level)
    if prototype_ids != ["prototype.missile_tank.01", "prototype.missile_tank.02"]:
        errors.append(f"legacy prototype Missile fixtures changed unexpectedly: {prototype_ids}")
    if set(prototype_ids) & set(instance_ids):
        errors.append("legacy prototype and S0-S10 pickup IDs overlap")


def _check_environment_and_music(errors: list[str]):
    cave = _read("scripts/world/cave_visuals.gd")
    runtime_room = _read("scripts/dev/dev_runtime_room.gd")
    audio = _read("scripts/autoload/audio.gd")
    _expect_equal(errors, "environment kit IDs", _array_names(cave, "KIT_IDS"), AREAS)

    route_pairs = _dict_pairs(runtime_room, "AREA_BY_ROOM", value_string_name=True)
    route = dict(route_pairs)
    if route != AREA_BY_ROOM or len(route_pairs) != len(AREA_BY_ROOM):
        errors.append(f"station area routing: expected {AREA_BY_ROOM}, found {route}")

    for area in AREAS:
        path = ROOT / "assets/environment/areas" / area / "area.json"
        try:
            manifest = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"environment kit {area}: {error}")
            continue
        if manifest.get("area_id") != area:
            errors.append(f"environment kit {area}: mismatched area_id")
        layers = {**manifest.get("background", {}), **manifest.get("material", {})}
        for role in ("far", "mid", "fill", "top"):
            entry = layers.get(role)
            resource = entry.get("path", "") if isinstance(entry, dict) else entry
            if not resource:
                errors.append(f"environment kit {area}: missing {role} art")
                continue
            try:
                if not _resolve_resource(resource).is_file():
                    errors.append(f"environment kit {area}: {role} art file missing")
            except CatalogError as error:
                errors.append(f"environment kit {area}: {error}")

    music_pairs = _dict_pairs(audio, "MUSIC_PATHS")
    routed_music = {key: value for key, value in music_pairs if key in AREAS}
    if set(routed_music) != set(AREAS):
        errors.append(f"routed area music: expected {list(AREAS)}, found {sorted(routed_music)}")
    paths = list(routed_music.values())
    if _duplicates(paths):
        errors.append(f"routed area music reuses paths: {_duplicates(paths)}")
    hashes = []
    for area in AREAS:
        resource = routed_music.get(area, "")
        try:
            path = _resolve_resource(resource)
        except CatalogError as error:
            errors.append(f"music {area}: {error}")
            continue
        if path.name != f"{area}.ogg" or not path.is_file() or path.stat().st_size == 0:
            errors.append(f"music {area}: missing dedicated non-empty {area}.ogg")
            continue
        hashes.append(_sha256(path))
    if _duplicates(hashes):
        errors.append("routed area melodies are not byte-distinct")


def _check_panel_and_drops(errors: list[str]):
    panel = _read("scripts/ui/dev_panel.gd")
    _expect_set(errors, "dev-panel enemy labels", _dict_name_keys(panel, "ENEMY_LABELS"), ENEMIES)
    _expect_equal(errors, "dev-panel boss IDs", _array_names(panel, "BOSS_IDS"), BOSSES)
    if "const ENEMY_IDS: Array[StringName] = Catalog.ENEMY_IDS" not in panel:
        errors.append("dev panel does not source selectable enemy order from Catalog.ENEMY_IDS")

    rewards = _read("scripts/enemies/defeat_rewards.gd")
    loot = _read("scripts/pickups/combat_loot.gd")
    for kind in REFILLS:
        token = f'&"{kind}"'
        if token not in rewards:
            errors.append(f"defeat rewards cannot produce temporary {kind}")
        if token not in loot:
            errors.append(f"CombatLoot does not accept temporary {kind}")
    if 'GameState.collect_pickup("", kind)' not in loot:
        errors.append("temporary loot does not use the non-persistent empty instance ID")


def main():
    errors: list[str] = []
    try:
        catalog = _check_catalog(errors)
        _check_assets(errors, catalog)
        _check_physical_catalog(errors)
        _check_environment_and_music(errors)
        _check_panel_and_drops(errors)
    except CatalogError as error:
        print(f"phase1-catalog: PARSE ERROR\n- {error}")
        return 2

    if errors:
        print("phase1-catalog: FAIL")
        for error in sorted(errors):
            print(f"- {error}")
        return 1

    print(
        "phase1-catalog: PASS "
        "(5 areas, 13 abilities, 6 Energy Tanks, 12 Missile Tanks, 4 Flux Tanks, "
        "13 enemies, 3 bosses, 19 pickup mappings, 3 temporary drops, 5 melodies)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
