#!/usr/bin/env python3
"""Small deterministic signal-level proof for Hollowtide audio assets."""

from __future__ import annotations

import math
import re
import subprocess
import wave
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "assets/audio"
MUSIC = AUDIO / "music"
AUDIO_GD = Path(__file__).resolve().parents[1] / "scripts/autoload/audio.gd"
AREA_IDS = ("fringe", "nexus", "vaults", "kiln", "depths")
SFX = AUDIO / "sfx"
SR = 44100
EXPECTED_SFX = {
    "jump",
    "land",
    "step",
    "step_2",
    "step_3",
    "beam_fire",
    "missile_fire",
    "beam_ricochet",
    "missile_hit",
    "enemy_death",
    "orb_pickup",
    "weapon_pickup",
    "slip_in",
    "slip_out",
    "player_hurt",
    "player_death",
    "bomb_place",
    "bomb_explode",
    "freeze",
    "wave_fire",
    "dash_strike",
    "tank_pickup",
    "boss_defeated",
    "weapon_switch",
    "dash_launch",
    "flux_shield",
    "flux_burst",
    "echo_scan",
    "flux_empty",
    "fire_loop",
    "lava_loop",
    "water_loop",
    "cold_ambience",
    "depths_pressure",
    "steam_vent",
}
ENVIRONMENT_LOOPS = {
    "fire_loop",
    "lava_loop",
    "water_loop",
    "cold_ambience",
    "depths_pressure",
}


def rms(signal: list[float]) -> float:
    return math.sqrt(sum(sample * sample for sample in signal) / max(len(signal), 1))


def dbfs(value: float) -> float:
    return -120.0 if value <= 1e-12 else 20.0 * math.log10(value)


def read_wav(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2:
            raise ValueError(f"{path}: expected mono 16-bit PCM")
        sample_rate = source.getframerate()
        samples = array("h")
        samples.frombytes(source.readframes(source.getnframes()))
    if samples.itemsize != 2:
        samples.byteswap()
    return [sample / 32768.0 for sample in samples], sample_rate


def read_ogg(path: Path) -> tuple[list[float], int]:
    decoded = subprocess.run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-i",
            str(path),
            "-f",
            "s16le",
            "-ac",
            "1",
            "-ar",
            str(SR),
            "pipe:1",
        ],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    samples = array("h")
    samples.frombytes(decoded)
    if samples.itemsize != 2:
        samples.byteswap()
    return [sample / 32768.0 for sample in samples], SR


def signal_checks(name: str, signal: list[float]) -> list[str]:
    peak = max(abs(sample) for sample in signal)
    max_step = max(
        (abs(signal[index] - signal[index - 1]) for index in range(1, len(signal))),
        default=0.0,
    )
    if not all(math.isfinite(sample) for sample in signal):
        raise AssertionError(f"{name}: non-finite sample")
    if peak >= 1.0:
        raise AssertionError(f"{name}: clipping peak={peak:.6f}")
    if max_step >= 0.99:
        raise AssertionError(f"{name}: possible glitch max_step={max_step:.6f}")
    return [
        f"{name}: duration={len(signal) / SR:.6f}s",
        f"{name}: rms_dbfs={dbfs(rms(signal)):.3f}",
        f"{name}: peak_dbfs={dbfs(peak):.3f}",
        f"{name}: max_adjacent_step={max_step:.6f}",
    ]


def main() -> None:
    missing = sorted(name for name in EXPECTED_SFX if not (SFX / f"{name}.wav").exists())
    if missing:
        raise AssertionError(f"missing SFX: {', '.join(missing)}")

    # Music is judged at in-game level: file level plus the per-track trim in audio.gd.
    trims = {
        name: float(value)
        for name, value in re.findall(
            r'&"([a-z_]+)":\s*(-?[\d.]+),', AUDIO_GD.read_text().split("MUSIC_VOLUME_DB")[1]
        )
    }
    music_signals: dict[str, list[float]] = {}
    for area in AREA_IDS + ("boss",):
        music, music_rate = read_ogg(MUSIC / f"{area}.ogg")
        if music_rate != SR:
            raise AssertionError(f"{area}: expected {SR} Hz, got {music_rate} Hz")
        edge_jump = abs(music[0] - music[-1])
        if edge_jump >= 0.08:
            raise AssertionError(f"{area}: loop edge jump too large: {edge_jump:.6f}")
        gain = 10.0 ** (trims.get(area, 0.0) / 20.0)
        music_signals[area] = [sample * gain for sample in music[::4]]
        print(
            f"{area}: duration={len(music) / SR:.1f}s in-game "
            f"rms={dbfs(rms(music_signals[area])):.2f}dBFS edge={edge_jump:.6f}"
        )

    print("audio-feedback: PASS")
    sfx_signals: dict[str, list[float]] = {}
    for name in sorted(EXPECTED_SFX):
        signal, sample_rate = read_wav(SFX / f"{name}.wav")
        if sample_rate != SR:
            raise AssertionError(f"{name}: expected {SR} Hz, got {sample_rate} Hz")
        sfx_signals[name] = signal
        for line in signal_checks(name, signal):
            if name in {"jump", "land"}:
                print(line)

    jump_rms = rms(sfx_signals["jump"])
    land_rms = rms(sfx_signals["land"])
    sequence = sfx_signals["jump"] + [0.0] * round(0.25 * SR) + sfx_signals["land"]
    print(f"jump: rms_dbfs={dbfs(jump_rms):.3f}")
    print(f"land: rms_dbfs={dbfs(land_rms):.3f}")
    print(f"jump_land_sequence: duration={len(sequence) / SR:.6f}s")
    print(f"jump_land_sequence: rms_dbfs={dbfs(rms(sequence)):.3f}")
    print(f"jump_land_sequence: peak_dbfs={dbfs(max(map(abs, sequence))):.3f}")
    loudest_music_rms = max(rms(signal) for signal in music_signals.values())
    print(f"mix_margin: land_minus_music_db={dbfs(land_rms) - dbfs(loudest_music_rms):.3f}")

    loop_levels = {name: rms(sfx_signals[name]) for name in ENVIRONMENT_LOOPS}
    loudest_loop_name = max(loop_levels, key=loop_levels.get)
    loudest_loop_rms = loop_levels[loudest_loop_name]
    loop_music_margin = dbfs(loudest_music_rms) - dbfs(loudest_loop_rms)
    loop_jump_margin = dbfs(jump_rms) - dbfs(loudest_loop_rms)
    loop_land_margin = dbfs(land_rms) - dbfs(loudest_loop_rms)
    combined_bed_rms = math.sqrt(loudest_music_rms**2 + loudest_loop_rms**2)
    print(
        f"environment_mix_margin: loudest={loudest_loop_name} "
        f"loop={dbfs(loudest_loop_rms):.3f}dBFS music={loop_music_margin:.3f}dB "
        f"jump={loop_jump_margin:.3f}dB land={loop_land_margin:.3f}dB "
        f"combined_bed={dbfs(combined_bed_rms):.3f}dBFS"
    )

    if dbfs(jump_rms) > -18.0:
        raise AssertionError("jump: RMS is not clearly below comfort target")
    if dbfs(loudest_music_rms) >= dbfs(land_rms) - 3.0:
        raise AssertionError("music: RMS is not below SFX mix target")
    if loop_music_margin < 2.0 or loop_jump_margin < 3.0 or loop_land_margin < 10.0:
        raise AssertionError("environment loops: insufficient music/player-cue mix margin")
    if dbfs(combined_bed_rms) > -18.0:
        raise AssertionError("environment loops: combined bed exceeds mix headroom target")


if __name__ == "__main__":
    main()
