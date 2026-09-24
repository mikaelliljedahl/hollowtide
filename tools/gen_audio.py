#!/usr/bin/env python3
"""Deterministically synthesize Hollowtide's original music and SFX."""

from __future__ import annotations

import argparse
import math
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy import signal as sps
from scipy.ndimage import minimum_filter1d, uniform_filter1d

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / "assets/audio/music"
SFX = ROOT / "assets/audio/sfx"
SR = 44100
SFX_SEED = 0x484F4C4C  # Preserve established SFX noise character.
DEV_SFX_SEED = 0x44455631  # DEV1
FLUX_SFX_SEED = 0x464C5558  # FLUX
ENVIRONMENT_SFX_SEED = 0x454E5631  # ENV1
FLUX_IDS = ("flux_shield", "flux_burst", "echo_scan", "flux_empty")
ENVIRONMENT_IDS = (
    "fire_loop",
    "lava_loop",
    "water_loop",
    "cold_ambience",
    "depths_pressure",
    "steam_vent",
)
LOOP_DURATIONS = {
    "fire_loop": 3.0,
    "lava_loop": 3.0,
    "water_loop": 4.0,
    "cold_ambience": 4.0,
    "depths_pressure": 4.0,
}


def env(n: int, attack: float, release: float, duration: float) -> np.ndarray:
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    r = np.clip((duration - t) / max(release, 1e-5), 0.0, 1.0)
    return np.minimum(a, r)


def tone(
    freq: float,
    duration: float,
    attack: float = 0.004,
    release: float = 0.08,
    fm: float = 0.0,
    ratio: float = 1.0,
) -> np.ndarray:
    n = round(duration * SR)
    t = np.arange(n) / SR
    phase = 2.0 * np.pi * freq * t + fm * np.sin(2.0 * np.pi * freq * ratio * t)
    return np.sin(phase) * env(n, attack, release, duration)


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    out = np.empty_like(x)
    last = 0.0
    for i, value in enumerate(x):
        last = (1.0 - a) * value + a * last
        out[i] = last
    return out


def lowpass_steep(x: np.ndarray, cutoff: float, stages: int = 4) -> np.ndarray:
    """Cascade one-pole filters when a genuinely steep high-frequency rolloff is needed."""
    for _ in range(stages):
        x = lowpass(x, cutoff)
    return x


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass(x, cutoff)


def delay(x: np.ndarray, seconds: float, gain: float, repeats: int = 1) -> np.ndarray:
    d = round(seconds * SR)
    out = x.copy()
    for repeat in range(1, repeats + 1):
        shift = d * repeat
        if shift < len(x):
            out[shift:] += x[:-shift] * gain**repeat
    return out


def write_wav(path: Path, x: np.ndarray, peak: float = 0.88) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    maximum = float(np.max(np.abs(x)))
    if maximum:
        x *= peak / maximum
    _write_pcm(path, x)


def write_wav_absolute(path: Path, x: np.ndarray) -> None:
    """Write at authored level instead of normalizing its peak."""
    path.parent.mkdir(parents=True, exist_ok=True)
    _write_pcm(path, np.asarray(x, dtype=np.float64))


def _write_pcm(path: Path, x: np.ndarray) -> None:
    channels = 1 if x.ndim == 1 else x.shape[1]
    with wave.open(str(path), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(SR)
        pcm = np.clip(x, -1.0, 1.0)
        output.writeframes((pcm * 32767.0).astype("<i2").tobytes())


def _ogg_crc(page: bytes) -> int:
    """Ogg's CRC-32 (different bit order from zlib.crc32)."""
    value = 0
    for byte in page:
        value ^= byte << 24
        for _ in range(8):
            value = (
                ((value << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
                if value & 0x80000000
                else (value << 1) & 0xFFFFFFFF
            )
    return value


def stabilize_ogg_serial(path: Path, serial: int = 0x484F4C4C) -> None:
    """FFmpeg randomizes Ogg stream serials; replace them and repair page CRCs."""
    data = bytearray(path.read_bytes())
    offset = 0
    while offset < len(data):
        if data[offset : offset + 4] != b"OggS":
            raise ValueError("Invalid Ogg page while stabilizing stream serial")
        segments = data[offset + 26]
        size = 27 + segments + sum(data[offset + 27 : offset + 27 + segments])
        page = bytearray(data[offset : offset + size])
        page[14:18] = serial.to_bytes(4, "little")
        page[22:26] = b"\0\0\0\0"
        page[22:26] = _ogg_crc(page).to_bytes(4, "little")
        data[offset : offset + size] = page
        offset += size
    path.write_bytes(data)


def add_at(track: np.ndarray, x: np.ndarray, start: float, gain: float = 1.0) -> None:
    i = round(start * SR)
    end = min(len(track), i + len(x))
    if i < len(track):
        track[i:end] += x[: end - i] * gain


def mix(*parts: np.ndarray) -> np.ndarray:
    """Mix unequal-length one-shot layers without NumPy broadcasting."""
    result = np.zeros(max(len(part) for part in parts))
    for part in parts:
        result[: len(part)] += part
    return result


def _soft_envelope(t: np.ndarray, duration: float, attack: float, release: float) -> np.ndarray:
    rise = np.clip(t / attack, 0.0, 1.0)
    attack_curve = 0.5 - 0.5 * np.cos(np.pi * rise)
    tail_start = duration - release
    tail_phase = np.clip((t - tail_start) / release, 0.0, 1.0)
    tail = 0.5 + 0.5 * np.cos(np.pi * tail_phase)
    return attack_curve * np.where(t >= tail_start, tail, 1.0)


def _set_rms(x: np.ndarray, dbfs: float) -> np.ndarray:
    target = 10.0 ** (dbfs / 20.0)
    measured = math.sqrt(float(np.mean(x * x)))
    if measured:
        x = x * (target / measured)
    x[-1] = 0.0
    return x


def _finish_one_shot(x: np.ndarray, peak: float) -> np.ndarray:
    """Apply click-free endpoints and a fixed, sub-minus-8 dBFS peak."""
    n = len(x)
    edge = min(round(0.008 * SR), n // 3)
    fade = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, edge, endpoint=True))
    x[:edge] *= fade
    x[-edge:] *= fade[::-1]
    maximum = float(np.max(np.abs(x)))
    if maximum:
        x *= peak / maximum
    x[0] = 0.0
    x[-1] = 0.0
    return x


def _periodic_noise(n: int, rng: np.random.Generator, low: float, high: float) -> np.ndarray:
    """Seeded spectral noise whose DFT basis wraps exactly at loop boundary."""
    frequencies = np.fft.rfftfreq(n, 1.0 / SR)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    high_rolloff = 1.0 / (1.0 + (frequencies / high) ** 6)
    low_rolloff = 1.0 - 1.0 / (1.0 + (frequencies / max(low, 1.0)) ** 4)
    spectrum *= high_rolloff * low_rolloff
    spectrum[0] = 0.0
    return np.fft.irfft(spectrum, n)


def _finish_loop(x: np.ndarray, dbfs: float) -> np.ndarray:
    """Set authored loop loudness and make first/last PCM samples identical."""
    measured = math.sqrt(float(np.mean(x * x)))
    if measured:
        x = np.tanh(x * (0.65 / measured))
    measured = math.sqrt(float(np.mean(x * x)))
    if measured:
        x *= 10.0 ** (dbfs / 20.0) / measured
    peak = float(np.max(np.abs(x)))
    if peak > 0.30:
        x *= 0.30 / peak
    edge = 0.5 * (x[0] + x[-1])
    x[0] = edge
    x[-1] = edge
    return x


def soft_step(variant: int) -> np.ndarray:
    """Short low thud with a smooth onset and zero-valued tail."""
    durations = (0.072, 0.076, 0.081)
    duration = durations[variant % len(durations)]
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x53544550 + variant)
    body_noise = lowpass_steep(rng.standard_normal(n), 620.0 + 30.0 * variant)
    gravel = highpass(lowpass_steep(rng.standard_normal(n), 1600.0, 4), 650.0)
    frequency = 178.0 + 21.0 * variant
    pitch_drop = 34.0 + 4.0 * variant
    body_phase = 2.0 * np.pi * (frequency * t - 0.5 * pitch_drop * t * t / duration)
    body = np.sin(body_phase) * np.exp(-t * 28.0)
    x = 0.86 * body_noise + 0.005 * gravel + 0.68 * body
    x *= _soft_envelope(t, duration, 0.0025, 0.018) * np.exp(-t * 10.0)
    return _set_rms(x, -24.0)


def soft_land() -> np.ndarray:
    """Keep landing event loudness while retaining its dark, soft impact character."""
    duration = 0.16
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x4C414E44)
    impact = lowpass_steep(rng.standard_normal(n), 430.0)
    grit = highpass(lowpass_steep(rng.standard_normal(n), 1500.0, 4), 620.0)
    body = np.sin(2.0 * np.pi * 76.0 * t + 0.25 * np.sin(2.0 * np.pi * 34.0 * t))
    x = 0.82 * impact + 0.005 * grit + 0.58 * body
    x *= _soft_envelope(t, duration, 0.0025, 0.028) * np.exp(-t * 11.0)
    return _set_rms(x, -12.5)


def soft_jump() -> np.ndarray:
    """Short muted cloth, breath and body whoosh; deliberately has no pitch sweep."""
    duration = 0.16
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x4A554D50)  # JUMP
    cloth = highpass(lowpass(rng.standard_normal(n), 2600.0), 420.0)
    breath = lowpass(rng.standard_normal(n), 850.0)
    body = np.sin(2.0 * np.pi * 118.0 * t) * np.exp(-t * 17.0)
    envelope = _soft_envelope(t, duration, 0.006, 0.050) * np.exp(-t * 12.0)
    x = (0.38 * cloth + 0.34 * breath + 0.18 * body) * envelope
    return _set_rms(x, -21.5)


def restrained_player_hurt() -> np.ndarray:
    """A short voiced pained exhalation, synthesized without a recorded sample."""
    duration = 0.34
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x48555254)  # HURT

    # A gently falling female-range fundamental drives a harmonic glottal source. Broad
    # formant weights make an "uh"-like exhalation without turning it into a pitched alarm.
    f0 = 218.0 - 47.0 * np.clip(t / duration, 0.0, 1.0)
    f0 += 2.2 * np.sin(2.0 * np.pi * 5.1 * t) * np.exp(-t * 5.0)
    phase = 2.0 * np.pi * np.cumsum(f0) / SR
    voiced = np.zeros(n)
    for harmonic in range(1, 18):
        frequency = harmonic * f0
        formants = (
            0.20
            + 1.00 * np.exp(-0.5 * ((frequency - 610.0) / 150.0) ** 2)
            + 0.58 * np.exp(-0.5 * ((frequency - 1120.0) / 230.0) ** 2)
            + 0.18 * np.exp(-0.5 * ((frequency - 2480.0) / 360.0) ** 2)
        )
        voiced += formants * np.sin(harmonic * phase + 0.11 * harmonic) / harmonic**1.22

    breath = highpass(lowpass_steep(rng.standard_normal(n), 2850.0, 3), 240.0)
    breath_envelope = np.exp(-t * 7.5) * _soft_envelope(t, duration, 0.012, 0.13)
    voice_envelope = np.exp(-t * 4.4) * _soft_envelope(t, duration, 0.020, 0.12)
    signal = 0.62 * voiced * voice_envelope + 0.10 * breath * breath_envelope
    signal = lowpass_steep(signal, 3600.0, 3)
    return _finish_one_shot(signal, 0.30)


def softened_beam_fire() -> np.ndarray:
    """Compact energy pulse with a rounded onset and controlled upper spectrum."""
    duration = 0.16
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x4245414D)  # BEAM
    frequency = 520.0 - 175.0 * np.clip(t / duration, 0.0, 1.0)
    phase = 2.0 * np.pi * np.cumsum(frequency) / SR
    core = np.sin(phase) + 0.24 * np.sin(2.02 * phase + 0.3)
    body = 0.23 * np.sin(2.0 * np.pi * 164.0 * t + 0.45 * np.sin(phase))
    air = highpass(lowpass_steep(rng.standard_normal(n), 2500.0, 4), 480.0)
    envelope = _soft_envelope(t, duration, 0.006, 0.075) * np.exp(-t * 10.5)
    signal = lowpass_steep((0.72 * core + body + 0.055 * air) * envelope, 3200.0, 3)
    return _finish_one_shot(signal, 0.34)


def softened_missile_fire() -> np.ndarray:
    """Low mechanical launch with breathy thrust instead of a full-scale hard onset."""
    duration = 0.30
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x4D49534C)  # MISL
    low_frequency = 108.0 - 34.0 * np.clip(t / duration, 0.0, 1.0)
    low_phase = 2.0 * np.pi * np.cumsum(low_frequency) / SR
    motor_frequency = 286.0 - 92.0 * np.clip(t / duration, 0.0, 1.0)
    motor_phase = 2.0 * np.pi * np.cumsum(motor_frequency) / SR
    thrust = highpass(lowpass_steep(rng.standard_normal(n), 1850.0, 4), 120.0)
    envelope = _soft_envelope(t, duration, 0.010, 0.105) * np.exp(-t * 5.8)
    signal = (
        0.74 * np.sin(low_phase) + 0.25 * np.sin(motor_phase + 0.25) + 0.075 * thrust
    ) * envelope
    return _finish_one_shot(lowpass_steep(signal, 2400.0, 3), 0.34)


def softened_bomb_place() -> np.ndarray:
    """Muted arming pulse for bomb placement; explosion weight remains separate."""
    duration = 0.11
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x424F4D42)  # BOMB
    frequency = 205.0 - 48.0 * np.clip(t / duration, 0.0, 1.0)
    phase = 2.0 * np.pi * np.cumsum(frequency) / SR
    mechanism = highpass(lowpass_steep(rng.standard_normal(n), 1250.0, 4), 180.0)
    envelope = _soft_envelope(t, duration, 0.006, 0.045) * np.exp(-t * 13.0)
    signal = (0.76 * np.sin(phase) + 0.16 * np.sin(2.0 * phase) + 0.045 * mechanism) * envelope
    return _finish_one_shot(lowpass_steep(signal, 1900.0, 3), 0.28)


def weapon_switch() -> np.ndarray:
    """A soft 68 ms selection tick: mechanical body, muted electronic confirmation."""
    duration = 0.068
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x53574954)  # SWITCH
    click = highpass(lowpass(rng.standard_normal(n), 2400.0), 260.0)
    body = np.sin(2.0 * np.pi * 420.0 * t) + 0.28 * np.sin(2.0 * np.pi * 760.0 * t)
    envelope = _soft_envelope(t, duration, 0.0008, 0.022) * np.exp(-t * 34.0)
    x = (0.18 * click + 0.32 * body) * envelope
    return _set_rms(x, -24.0)


def dash_launch() -> np.ndarray:
    """A compact electrical whoosh for one powered spin activation."""
    duration = 0.22
    n = round(duration * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(0x53435257)  # SCRW
    rising = 170.0 + 390.0 * np.clip(t / duration, 0.0, 1.0)
    phase = 2.0 * np.pi * (170.0 * t + 0.5 * 390.0 / duration * t * t)
    coil = np.sin(phase) + 0.28 * np.sin(phase * 2.03 + 0.5)
    air = highpass(lowpass(rng.standard_normal(n), 3600.0), 700.0)
    envelope = _soft_envelope(t, duration, 0.008, 0.07) * np.exp(-t * 7.5)
    x = (0.24 * coil + 0.08 * air + 0.08 * np.sin(2.0 * np.pi * rising * t)) * envelope
    return _set_rms(x, -25.0)


# =================================================================================
# Music and ambience engine (D18)
# =================================================================================
# Everything below is original procedural composition and sound design. No reference
# audio is read and no existing melody is transcribed; motifs are authored here.
# Scores are stereo, sectioned and rendered with a wrapped tail so reverb/delay tails
# from the end of a loop fold into its start (seamless loops).

AREA_IDS = ("fringe", "nexus", "vaults", "kiln", "depths")
EXTRA_MUSIC_IDS = ("boss", "title", "ending")
MUSIC_IDS = AREA_IDS + EXTRA_MUSIC_IDS
NON_LOOPING_MUSIC = ("ending",)
MUSIC_TARGET_LUFS = -17.0
AMBIENCE_BED_LUFS = -27.0
MUSIC_TAIL = 16.0
MUSIC_OGG_QUALITY = "3"
STATS_HOOK = None  # debugging: callable receiving per-layer RMS (dB) at render time
AMBIENCE = ROOT / "assets/audio/ambience"
FOOTSTEPS = SFX / "footsteps"

MODES = {
    "ionian": (0, 2, 4, 5, 7, 9, 11),
    "dorian": (0, 2, 3, 5, 7, 9, 10),
    "phrygian": (0, 1, 3, 5, 7, 8, 10),
    "lydian": (0, 2, 4, 6, 7, 9, 11),
    "mixolydian": (0, 2, 4, 5, 7, 9, 10),
    "aeolian": (0, 2, 3, 5, 7, 8, 10),
    "harmonic_minor": (0, 2, 3, 5, 7, 8, 11),
    "phrygian_dominant": (0, 1, 4, 5, 7, 8, 10),
}


def midi_hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


class Key:
    """Scale-degree helper: degree 0 is the tonic, 7 the tonic an octave up."""

    def __init__(self, root: int, mode: str) -> None:
        self.root = root
        self.steps = MODES[mode]

    def midi(self, degree: int, octave: int = 0) -> int:
        octaves, index = divmod(degree, len(self.steps))
        return self.root + 12 * (octaves + octave) + self.steps[index]

    def hz(self, degree: int, octave: int = 0) -> float:
        return midi_hz(self.midi(degree, octave))

    def chord(self, degrees: tuple[int, ...], octave: int = 0) -> list[float]:
        return [self.hz(degree, octave) for degree in degrees]


# --- signal primitives ---------------------------------------------------------------


def _time(n: int) -> np.ndarray:
    return np.arange(n) / SR


def envelope(
    n: int,
    attack: float,
    decay: float = 0.3,
    sustain: float = 1.0,
    release: float = 0.1,
    gate: float | None = None,
) -> np.ndarray:
    """ADSR with sine attack, exponential decay and raised-cosine release to exactly zero."""
    t = _time(n)
    length = n / SR
    gate = length - release if gate is None else min(gate, length)
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    body = sustain + (1.0 - sustain) * np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4))
    shape = np.where(t < attack, np.sin(0.5 * np.pi * rise), body)
    fall = np.clip((t - gate) / max(release, 1e-4), 0.0, 1.0)
    shape = shape * (0.5 + 0.5 * np.cos(np.pi * fall))
    if n:
        shape[-1] = 0.0
    return shape


def _phase(freq: float | np.ndarray, n: int, phase0: float = 0.0) -> tuple[np.ndarray, np.ndarray]:
    increment = np.broadcast_to(np.asarray(freq, dtype=np.float64) / SR, (n,)).copy()
    phase = (phase0 + np.cumsum(increment) - increment) % 1.0
    return phase, increment


def sine(freq: float | np.ndarray, n: int, phase0: float = 0.0) -> np.ndarray:
    phase, _ = _phase(freq, n, phase0)
    return np.sin(2.0 * np.pi * phase)


def saw(freq: float | np.ndarray, n: int, phase0: float = 0.0) -> np.ndarray:
    """PolyBLEP band-limited sawtooth."""
    phase, dt = _phase(freq, n, phase0)
    y = 2.0 * phase - 1.0
    low = phase < dt
    x = phase[low] / dt[low]
    y[low] -= x + x - x * x - 1.0
    high = phase > 1.0 - dt
    x = (phase[high] - 1.0) / dt[high]
    y[high] -= x * x + x + x + 1.0
    return y


def square(freq: float | np.ndarray, n: int, duty: float = 0.5, phase0: float = 0.0) -> np.ndarray:
    return 0.5 * (saw(freq, n, phase0) - saw(freq, n, phase0 + duty))


def triangle(freq: float | np.ndarray, n: int, phase0: float = 0.0) -> np.ndarray:
    phase, _ = _phase(freq, n, phase0)
    return 2.0 * np.abs(2.0 * phase - 1.0) - 1.0


def vibrato(
    freq: float, n: int, rate: float, cents: float, delay: float = 0.0, phase0: float = 0.0
) -> np.ndarray:
    t = _time(n)
    depth = np.clip((t - delay) / 0.6, 0.0, 1.0) * cents if delay else cents
    return freq * 2.0 ** (depth * np.sin(2.0 * np.pi * rate * t + phase0) / 1200.0)


def _sos(kind: str, cutoff: float | tuple[float, float], order: int) -> np.ndarray:
    nyquist_safe = 0.45 * SR
    if isinstance(cutoff, tuple):
        cutoff = (max(cutoff[0], 10.0), min(cutoff[1], nyquist_safe))
    else:
        cutoff = min(max(cutoff, 10.0), nyquist_safe)
    return sps.butter(order, cutoff, kind, fs=SR, output="sos")


def lp(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return sps.sosfilt(_sos("lowpass", cutoff, order), x, axis=0)


def hp(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return sps.sosfilt(_sos("highpass", cutoff, order), x, axis=0)


def bp(x: np.ndarray, low: float, high: float, order: int = 2) -> np.ndarray:
    return sps.sosfilt(_sos("bandpass", (low, high), order), x, axis=0)


def _rbj(kind: str, cutoff: float, q: float) -> tuple[np.ndarray, np.ndarray]:
    w0 = 2.0 * np.pi * min(max(cutoff, 15.0), 0.45 * SR) / SR
    c = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    if kind == "lp":
        b = [(1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0]
    elif kind == "hp":
        b = [(1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0]
    else:
        b = [alpha, 0.0, -alpha]
    a = [1.0 + alpha, -2.0 * c, 1.0 - alpha]
    return np.array(b) / a[0], np.array(a) / a[0]


def swept(
    x: np.ndarray, cutoff: np.ndarray | float, q: float = 0.707, kind: str = "lp", block: int = 128
) -> np.ndarray:
    """Time-varying resonant biquad; cutoff is per-sample (updated every block)."""
    n = len(x)
    curve = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), (n,))
    out = np.empty_like(x)
    state = np.zeros((2,) + x.shape[1:])
    for start in range(0, n, block):
        stop = min(start + block, n)
        b, a = _rbj(kind, float(curve[(start + stop) // 2]), q)
        out[start:stop], state = sps.lfilter(b, a, x[start:stop], axis=0, zi=state)
    return out


def circular(fn, x: np.ndarray, warm: float = 4.0) -> np.ndarray:
    """Apply a causal process to a loop so its output is (near) periodic."""
    w = min(round(warm * SR), len(x))
    return fn(np.concatenate([x[-w:], x]))[w:]


def pan(x: np.ndarray, position: float) -> np.ndarray:
    """Equal-power pan of mono into stereo; centre keeps unity per channel."""
    angle = (np.clip(position, -1.0, 1.0) + 1.0) * np.pi / 4.0
    return np.stack([x * math.cos(angle), x * math.sin(angle)], axis=1) * math.sqrt(2.0)


def stereo(x: np.ndarray, position: float = 0.0) -> np.ndarray:
    return pan(x, position) if x.ndim == 1 else x


def loop_lfo(n: int, rng: np.random.Generator, cycles: tuple[int, ...]) -> np.ndarray:
    """Smooth pseudo-random curve in [0, 1] that is exactly periodic over n samples."""
    t = np.arange(n) / n
    y = np.zeros(n)
    for count in cycles:
        y += np.sin(2.0 * np.pi * count * t + rng.uniform(0.0, 2.0 * np.pi)) / math.sqrt(count)
    y -= y.min()
    peak = y.max()
    return y / peak if peak else y


def curve(points: list[tuple[float, float]], n: int) -> np.ndarray:
    """Piecewise-linear automation from (seconds, value) points."""
    times = [time for time, _ in points]
    values = [value for _, value in points]
    return np.interp(_time(n), times, values)


# --- spaces --------------------------------------------------------------------------


def reverb_ir(
    seconds: float,
    rt_low: float,
    rt_mid: float,
    rt_high: float,
    seed: int,
    predelay: float = 0.02,
    early: int = 10,
) -> np.ndarray:
    """Synthetic stereo room: early reflections plus band-dependent exponential tail."""
    rng = np.random.default_rng(seed)
    n = round(seconds * SR)
    t = _time(n)
    noise = rng.standard_normal((n, 2))
    low = lp(noise, 320.0)
    high = hp(noise, 3200.0)
    mid = noise - low - high

    def decay(rt: float) -> np.ndarray:
        return 10.0 ** (-3.0 * t / rt)[:, None]

    tail = low * decay(rt_low) + mid * decay(rt_mid) + high * decay(rt_high)
    tail *= (1.0 - np.exp(-t / 0.035))[:, None]
    for _ in range(early):
        index = round(rng.uniform(0.004, 0.09) * SR)
        tail[index, rng.integers(0, 2)] += rng.uniform(0.6, 1.6) * rng.choice((-1.0, 1.0)) * 6.0
    tail /= math.sqrt(float(np.sum(tail * tail)) / 2.0)
    return np.concatenate([np.zeros((round(predelay * SR), 2)), tail])


def convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    return np.stack(
        [sps.oaconvolve(x[:, channel], ir[:, channel])[: len(x)] for channel in range(2)], axis=1
    )


def pingpong(
    x: np.ndarray,
    seconds: float,
    feedback: float,
    repeats: int = 6,
    tone: float = 3500.0,
    low_cut: float = 180.0,
) -> np.ndarray:
    """Ping-pong delay whose repeats darken; returns only the wet signal."""
    d = round(seconds * SR)
    out = np.zeros_like(x)
    tap = x
    for _ in range(repeats):
        shifted = np.zeros_like(x)
        shifted[d:] = tap[:-d]
        tap = lp(hp(shifted, low_cut, 1), tone, 1)[:, ::-1] * feedback
        out += tap
    return out


# --- mastering -----------------------------------------------------------------------


def _k_weight(x: np.ndarray) -> np.ndarray:
    gain_db, q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    a_gain = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * math.pi * fc / SR
    alpha = math.sin(w0) / (2.0 * q)
    c = math.cos(w0)
    root = 2.0 * math.sqrt(a_gain) * alpha
    b = [
        a_gain * ((a_gain + 1) + (a_gain - 1) * c + root),
        -2 * a_gain * ((a_gain - 1) + (a_gain + 1) * c),
        a_gain * ((a_gain + 1) + (a_gain - 1) * c - root),
    ]
    a = [(a_gain + 1) - (a_gain - 1) * c + root, 2 * ((a_gain - 1) - (a_gain + 1) * c)]
    a.append((a_gain + 1) - (a_gain - 1) * c - root)
    y = sps.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)
    fc, q = 38.13547087602444, 0.5003270373238773
    w0 = 2.0 * math.pi * fc / SR
    alpha = math.sin(w0) / (2.0 * q)
    c = math.cos(w0)
    a = np.array([1.0 + alpha, -2.0 * c, 1.0 - alpha])
    return sps.lfilter(np.array([1.0, -2.0, 1.0]) / a[0], a / a[0], y, axis=0)


def loudness(x: np.ndarray) -> float:
    """Integrated loudness (ITU-R BS.1770 gating) in LUFS."""
    y = _k_weight(stereo(x))
    block = round(0.4 * SR)
    hop = round(0.1 * SR)
    if len(y) < block:
        return -70.0
    power = np.cumsum(np.concatenate([np.zeros((1, 2)), y * y]), axis=0)
    starts = np.arange(0, len(y) - block + 1, hop)
    energy = ((power[starts + block] - power[starts]) / block).sum(axis=1)
    levels = -0.691 + 10.0 * np.log10(np.maximum(energy, 1e-12))
    gated = energy[levels > -70.0]
    if not len(gated):
        return -70.0
    relative = -0.691 + 10.0 * math.log10(float(gated.mean())) - 10.0
    gated = energy[(levels > -70.0) & (levels > relative)]
    return -0.691 + 10.0 * math.log10(float(gated.mean()))


def _compress(x: np.ndarray, threshold_db: float, ratio: float) -> np.ndarray:
    """Slow, gentle RMS glue compressor (loop-safe via circular warm-up)."""

    def process(signal: np.ndarray) -> np.ndarray:
        power = np.mean(signal * signal, axis=1)
        coefficient = math.exp(-1.0 / (0.25 * SR))
        smoothed = sps.lfilter([1.0 - coefficient], [1.0, -coefficient], power)
        level = 10.0 * np.log10(np.maximum(smoothed, 1e-12))
        over = np.maximum(level - threshold_db, 0.0)
        gain = 10.0 ** (-over * (1.0 - 1.0 / ratio) / 20.0)
        return signal * gain[:, None]

    return circular(process, x, 3.0)


def limit(x: np.ndarray, ceiling_db: float = -1.5, loop: bool = True) -> np.ndarray:
    """Look-ahead peak limiter with smooth gain; exact ceiling guaranteed."""
    ceiling = 10.0 ** (ceiling_db / 20.0)
    peak = np.max(np.abs(x), axis=1)
    needed = np.minimum(1.0, ceiling / np.maximum(peak, 1e-9))
    mode = "wrap" if loop else "nearest"
    hold = round(0.006 * SR)
    gain = minimum_filter1d(needed, 2 * hold + 1, mode=mode)
    gain = uniform_filter1d(gain, hold, mode=mode)
    gain = np.minimum(gain, minimum_filter1d(needed, 3, mode=mode))
    out = x * gain[:, None]
    return np.clip(out, -ceiling, ceiling)


def master(x: np.ndarray, target_lufs: float, loop: bool = True) -> np.ndarray:
    x = hp(x, 24.0, 2) if not loop else circular(lambda s: hp(s, 24.0, 2), x, 2.0)
    x = x - x.mean(axis=0)
    level = loudness(x)
    x = _compress(x * 10.0 ** ((target_lufs + 3.0 - level) / 20.0), target_lufs + 1.0, 2.0)
    for _ in range(3):
        x = x * 10.0 ** ((target_lufs - loudness(x)) / 20.0)
        x = limit(x, -1.5, loop)
    return x


# --- scores --------------------------------------------------------------------------


class Score:
    """Timeline of named stereo layers with sends; rendered with a wrapped tail."""

    def __init__(self, seconds: float, seed: int, bpm: float = 60.0, beats: int = 4) -> None:
        self.length = round(seconds * SR)
        self.n = self.length + round(MUSIC_TAIL * SR)
        self.rng = np.random.default_rng(seed)
        self.beat = 60.0 / bpm
        self.bar = self.beat * beats
        self.layers: dict[str, np.ndarray] = {}
        self.routes: dict[str, dict] = {}
        self.effects: dict[str, object] = {}
        self.stats: dict[str, float] = {}

    def at(self, bar: float, beat: float = 0.0) -> float:
        return bar * self.bar + beat * self.beat

    def layer(self, name: str) -> np.ndarray:
        if name not in self.layers:
            self.layers[name] = np.zeros((self.n, 2))
        return self.layers[name]

    def place(
        self, name: str, sound: np.ndarray, time: float, gain: float = 1.0, position: float = 0.0
    ) -> None:
        start = round(time * SR)
        if start >= self.length or start < 0:
            return
        buffer = self.layer(name)
        sound = stereo(sound, position)
        stop = min(self.n, start + len(sound))
        buffer[start:stop] += sound[: stop - start] * gain

    def bed(self, name: str, sound: np.ndarray, gain: float = 1.0) -> None:
        """Continuous loop-length layer (already periodic over the loop)."""
        self.layer(name)[: self.length] += stereo(sound)[: self.length] * gain

    def route(
        self, name: str, gain=1.0, sends: dict[str, float] | None = None, fx=None, dry=True
    ) -> None:
        self.routes[name] = {"gain": gain, "sends": sends or {}, "fx": fx, "dry": dry}

    def auto(self, points: list[tuple[float, float]]) -> np.ndarray:
        """Automation over bars: [(bar, value), ...] -> per-sample curve for the full buffer."""
        return curve([(bar * self.bar, value) for bar, value in points], self.n)

    def render(self, target_lufs: float = MUSIC_TARGET_LUFS, loop: bool = True) -> np.ndarray:
        dry = np.zeros((self.n, 2))
        sends: dict[str, np.ndarray] = {}
        for name, buffer in self.layers.items():
            route = self.routes.get(name, {"gain": 1.0, "sends": {}, "fx": None, "dry": True})
            signal = buffer
            if route["fx"] is not None:
                signal = route["fx"](signal)
            gain = route["gain"]
            signal = signal * (gain[:, None] if isinstance(gain, np.ndarray) else gain)
            if route["dry"]:
                dry += signal
            self.stats[name] = 10.0 * math.log10(float(np.mean(signal * signal)) + 1e-12)
            for send, amount in route["sends"].items():
                if send not in sends:
                    sends[send] = np.zeros((self.n, 2))
                sends[send] += signal * amount
        for send, signal in sends.items():
            wet = self.effects[send](signal)
            self.stats[f"fx:{send}"] = 10.0 * math.log10(float(np.mean(wet * wet)) + 1e-12)
            dry += wet
        if STATS_HOOK is not None:
            STATS_HOOK(self.stats)
        if loop:
            out = dry[: self.length].copy()
            tail = dry[self.length :]
            out[: len(tail)] += tail
        else:
            out = dry
        return master(out, target_lufs, loop)


# --- voices --------------------------------------------------------------------------


def v_pad(
    freqs: list[float],
    duration: float,
    rng: np.random.Generator,
    attack: float = 2.0,
    release: float = 3.0,
    detune: float = 9.0,
    voices: int = 3,
    shape: str = "saw",
    width: float = 0.8,
) -> np.ndarray:
    """Detuned multi-voice chord with slow drift; filter it at layer level."""
    n = round((duration + release) * SR)
    t = _time(n)
    out = np.zeros((n, 2))
    for freq in freqs:
        for voice in range(voices):
            spread = (voice - (voices - 1) / 2.0) / max((voices - 1) / 2.0, 1.0)
            drift = 2.5 * np.sin(2.0 * np.pi * rng.uniform(0.05, 0.2) * t + rng.uniform(0, 6.3))
            f = freq * 2.0 ** ((detune * spread + rng.uniform(-1.5, 1.5) + drift) / 1200.0)
            if shape == "saw":
                wave = saw(f, n, rng.random())
            elif shape == "square":
                wave = square(f, n, 0.5, rng.random())
            elif shape == "triangle":
                wave = triangle(f, n, rng.random())
            else:
                wave = sine(f, n, rng.random())
            out += pan(wave, spread * width)
    env = envelope(n, attack, 1.0, 1.0, release, gate=duration)
    return out * env[:, None] / math.sqrt(len(freqs) * voices)


def v_pluck(
    freq: float,
    duration: float,
    brightness: float = 0.55,
    decay: float = 1.4,
    partials: int = 12,
    inharmonic: float = 0.0003,
    phase_seed: int = 0,
) -> np.ndarray:
    """Additive plucked string: upper partials decay faster, exact tuning."""
    n = round(duration * SR)
    t = _time(n)
    rng = np.random.default_rng(phase_seed)
    out = np.zeros(n)
    for k in range(1, partials + 1):
        fk = freq * k * math.sqrt(1.0 + inharmonic * k * k)
        if fk > 15000.0:
            break
        amp = brightness ** (k - 1) / math.sqrt(k)
        out += (
            amp
            * np.sin(2.0 * np.pi * fk * t + rng.uniform(0, 6.3))
            * np.exp(-t / (decay / (1.0 + 0.7 * (k - 1))))
        )
    attack = np.clip(t / 0.003, 0.0, 1.0)
    out *= attack * envelope(n, 0.001, 1.0, 1.0, min(0.08, duration / 3))
    return out / max(float(np.max(np.abs(out))), 1e-9)


def v_bell(
    freq: float,
    duration: float,
    ratio: float = 3.5,
    index: float = 2.2,
    decay: float = 2.2,
    index_decay: float = 0.5,
    partial: float = 2.0,
) -> np.ndarray:
    """Two-operator FM bell with a softer extra partial."""
    n = round(duration * SR)
    t = _time(n)
    modulator = np.sin(2.0 * np.pi * freq * ratio * t) * index * np.exp(-t / index_decay)
    body = np.sin(2.0 * np.pi * freq * t + modulator) * np.exp(-t / decay)
    body += 0.25 * np.sin(2.0 * np.pi * freq * partial * 1.0013 * t) * np.exp(-t / (decay * 0.45))
    return body * envelope(n, 0.002, 1.0, 1.0, min(0.2, duration / 3))


def v_glass(freq: float, duration: float, decay: float = 4.0, shimmer: float = 4.5) -> np.ndarray:
    """Struck/rubbed glass: sparse inharmonic partials with slow beating."""
    n = round(duration * SR)
    t = _time(n)
    out = np.zeros(n)
    for ratio, amp, life in (
        (1.0, 1.0, 1.0),
        (2.32, 0.42, 0.6),
        (4.25, 0.22, 0.35),
        (6.63, 0.1, 0.2),
    ):
        if freq * ratio > 15000.0:
            continue
        beating = 1.0 + 0.25 * np.sin(2.0 * np.pi * shimmer * ratio**0.5 * t)
        out += amp * beating * np.sin(2.0 * np.pi * freq * ratio * t) * np.exp(-t / (decay * life))
    return out * envelope(n, 0.004, 1.0, 1.0, min(0.4, duration / 3))


def v_swell_glass(freq: float, duration: float) -> np.ndarray:
    """Bowed-glass tone: slow attack, pure partials, gentle tremolo."""
    n = round(duration * SR)
    t = _time(n)
    out = np.sin(2.0 * np.pi * freq * t) + 0.3 * np.sin(2.0 * np.pi * freq * 2.0 * t + 0.4)
    out += 0.12 * np.sin(2.0 * np.pi * freq * 3.01 * t + 1.1)
    out *= 1.0 + 0.18 * np.sin(2.0 * np.pi * 3.3 * t)
    return out * envelope(n, duration * 0.4, 1.0, 1.0, duration * 0.45)


def v_sub(freq: float, duration: float, attack: float = 0.4, release: float = 1.0) -> np.ndarray:
    n = round(duration * SR)
    t = _time(n)
    out = np.sin(2.0 * np.pi * freq * t) + 0.12 * np.sin(4.0 * np.pi * freq * t)
    return out * envelope(n, attack, 1.0, 1.0, release)


def v_bass(
    freq: float,
    duration: float,
    drive: float = 2.5,
    cutoff: float = 500.0,
    env_amount: float = 1400.0,
    decay: float = 0.16,
    q: float = 1.4,
) -> np.ndarray:
    """Distorted saw/square bass with a plucky filter envelope."""
    n = round(duration * SR)
    t = _time(n)
    raw = 0.7 * saw(freq * 1.003, n) + 0.5 * square(freq * 0.5, n, 0.5) + 0.4 * saw(freq * 0.997, n)
    shaped = swept(raw, cutoff + env_amount * np.exp(-t / decay), q, "lp", 64)
    shaped = np.tanh(drive * shaped) / math.tanh(drive)
    return shaped * envelope(n, 0.003, 0.3, 0.85, min(0.05, duration / 3))


def v_lead(
    freq: float,
    duration: float,
    brightness: float = 3.0,
    vibrato_cents: float = 14.0,
    attack: float = 0.05,
    release: float = 0.25,
    shape: str = "saw",
) -> np.ndarray:
    """Singing lead with delayed vibrato and envelope-following filter."""
    n = round((duration + release) * SR)
    f = vibrato(freq, n, 5.2, vibrato_cents, delay=0.25)
    if shape == "saw":
        raw = 0.6 * saw(f, n) + 0.6 * saw(f * 1.004, n, 0.3)
    else:
        raw = square(f, n, 0.35) + 0.4 * saw(f * 0.998, n)
    env = envelope(n, attack, 0.6, 0.8, release, gate=duration)
    filtered = swept(raw, freq * (1.0 + brightness * env), 0.9, "lp", 64)
    return filtered * env


def v_whistle(freq: float, duration: float, release: float = 0.6) -> np.ndarray:
    """Airy, distant whistle: sine core plus breath noise tuned around the pitch."""
    n = round((duration + release) * SR)
    f = vibrato(freq, n, 4.6, 9.0, delay=0.3)
    core = sine(f, n) + 0.08 * sine(f * 2.0, n)
    rng = np.random.default_rng(int(freq * 100) + n)
    breath = bp(rng.standard_normal(n), freq * 0.85, freq * 1.2, 1) * 1.6
    env = envelope(n, 0.18, 1.0, 1.0, release, gate=duration)
    return (core + breath) * env


def v_choir(
    freqs: list[float],
    duration: float,
    rng: np.random.Generator,
    vowel: str = "oo",
    attack: float = 2.0,
    release: float = 2.5,
) -> np.ndarray:
    """Wordless formant choir."""
    formants = {
        "oo": ((320.0, 1.0), (800.0, 0.35), (2300.0, 0.08)),
        "ah": ((720.0, 1.0), (1150.0, 0.55), (2500.0, 0.18)),
        "eh": ((500.0, 1.0), (1750.0, 0.4), (2550.0, 0.15)),
    }[vowel]
    n = round((duration + release) * SR)
    out = np.zeros((n, 2))
    for freq in freqs:
        for voice in range(4):
            f = vibrato(
                freq * 2.0 ** (rng.uniform(-9, 9) / 1200.0),
                n,
                rng.uniform(4.5, 5.6),
                12.0,
                0.4,
                rng.uniform(0, 6.3),
            )
            source = saw(f, n, rng.random())
            voiced = sum(
                gain * bp(source, center * 0.88, center * 1.12, 1) for center, gain in formants
            )
            out += pan(voiced, (voice - 1.5) / 1.5 * 0.7)
    breath = hp(rng.standard_normal(n), 3000.0) * 0.02
    out += breath[:, None]
    env = envelope(n, attack, 1.0, 1.0, release, gate=duration)
    return out * env[:, None] / math.sqrt(len(freqs) * 4)


def v_stab(freqs: list[float], duration: float, rng: np.random.Generator, cutoff: float = 2600.0):
    n = round(duration * SR)
    t = _time(n)
    out = np.zeros((n, 2))
    for freq in freqs:
        for voice in range(5):
            spread = (voice - 2) / 2.0
            f = freq * 2.0 ** (spread * 14.0 / 1200.0)
            out += pan(saw(f, n, rng.random()), spread * 0.8)
    out = swept(out, cutoff * (0.25 + 0.75 * np.exp(-t / 0.09)), 1.1, "lp", 64)
    return (
        out
        * envelope(n, 0.004, 0.12, 0.35, min(0.06, duration / 3))[:, None]
        / math.sqrt(5 * len(freqs))
    )


# --- percussion ----------------------------------------------------------------------


def d_kick(high: float = 150.0, low: float = 46.0, decay: float = 0.34, click: float = 0.25):
    n = round((decay * 3.0) * SR)
    t = _time(n)
    f = low + (high - low) * np.exp(-t / 0.028)
    body = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    rng = np.random.default_rng(0x4B49434B)
    snap = hp(rng.standard_normal(n), 1800.0) * np.exp(-t / 0.004) * click
    return np.tanh(1.6 * (body + snap)) * envelope(n, 0.0008, 1.0, 1.0, 0.03)


def d_snare(tone: float = 185.0, decay: float = 0.17, noise: float = 0.9, seed: int = 1):
    n = round(decay * 4.0 * SR)
    t = _time(n)
    rng = np.random.default_rng(0x534E0000 + seed)
    body = np.sin(2.0 * np.pi * tone * t) * np.exp(-t / (decay * 0.5))
    rattle = bp(rng.standard_normal(n), 1500.0, 9000.0, 2) * np.exp(-t / decay) * noise
    return (0.6 * body + rattle) * envelope(n, 0.0008, 1.0, 1.0, 0.02)


def d_hat(decay: float = 0.045, seed: int = 0, tone: float = 7500.0) -> np.ndarray:
    n = round(max(decay * 5.0, 0.03) * SR)
    t = _time(n)
    rng = np.random.default_rng(0x48410000 + seed)
    return (
        hp(rng.standard_normal(n), tone, 2) * np.exp(-t / decay) * envelope(n, 0.0005, 1, 1, 0.01)
    )


def d_metal(freq: float, decay: float = 1.2, index: float = 3.5, seed: int = 0) -> np.ndarray:
    """Inharmonic struck-metal clang (pipe/anvil)."""
    n = round(decay * 3.0 * SR)
    t = _time(n)
    rng = np.random.default_rng(0x4D450000 + seed)
    mod = index * np.exp(-t / (decay * 0.2)) * np.sin(2.0 * np.pi * freq * 1.414 * t)
    out = np.sin(2.0 * np.pi * freq * t + mod) * np.exp(-t / decay)
    for ratio, amp in ((2.76, 0.4), (5.40, 0.25), (8.93, 0.12)):
        out += (
            amp
            * np.sin(2.0 * np.pi * freq * ratio * t + rng.uniform(0, 6.3))
            * np.exp(-t / (decay * 0.4))
        )
    out += bp(rng.standard_normal(n), freq, freq * 4.0, 1) * np.exp(-t / 0.02) * 0.8
    return out * envelope(n, 0.0008, 1.0, 1.0, 0.05)


def d_tom(freq: float = 90.0, decay: float = 0.4) -> np.ndarray:
    n = round(decay * 3.0 * SR)
    t = _time(n)
    f = freq * (1.0 + 0.5 * np.exp(-t / 0.05))
    rng = np.random.default_rng(int(freq))
    body = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    skin = lp(rng.standard_normal(n), 2500.0) * np.exp(-t / 0.03) * 0.3
    return np.tanh(1.3 * (body + skin)) * envelope(n, 0.001, 1.0, 1.0, 0.03)


def d_heart(strength: float = 1.0) -> np.ndarray:
    """Low 'lub-dub' pulse."""
    n = round(0.9 * SR)
    out = np.zeros(n)
    for offset, gain, freq in ((0.0, 1.0, 52.0), (0.24, 0.7, 46.0)):
        start = round(offset * SR)
        m = n - start
        t = _time(m)
        f = freq * (1.0 + 0.6 * np.exp(-t / 0.03))
        thump = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11)
        out[start:] += gain * thump
    return lp(out, 420.0) * strength * envelope(n, 0.002, 1, 1, 0.1)


def d_sonar(freq: float = 1180.0, decay: float = 1.6) -> np.ndarray:
    n = round(decay * 3.2 * SR)
    t = _time(n)
    f = freq * (1.0 - 0.012 * (1.0 - np.exp(-t / 0.5)))
    ping = np.sin(2.0 * np.pi * np.cumsum(f) / SR) + 0.15 * np.sin(
        2.0 * np.pi * np.cumsum(f * 2.01) / SR
    )
    return ping * np.exp(-t / decay) * envelope(n, 0.006, 1, 1, 0.2)


def v_groan(f_start: float, f_end: float, duration: float, seed: int = 0) -> np.ndarray:
    """Deep, whale-like gliding groan through a moving formant."""
    n = round(duration * SR)
    t = _time(n)
    rng = np.random.default_rng(0x47520000 + seed)
    glide = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / duration, 0.0, 1.0))
    f = f_start * (f_end / f_start) ** glide
    f = f * 2.0 ** (18.0 * np.sin(2.0 * np.pi * 0.7 * t + rng.uniform(0, 6)) / 1200.0)
    source = 0.7 * saw(f, n) + 0.5 * square(f, n, 0.3)
    formant = 260.0 + 420.0 * np.sin(np.pi * np.clip(t / duration, 0.0, 1.0)) ** 2
    voiced = swept(source, formant, 3.0, "bp", 128) * 2.0 + lp(source, 180.0) * 0.4
    return voiced * envelope(n, duration * 0.3, 1.0, 1.0, duration * 0.4)


# --- motifs --------------------------------------------------------------------------

# Hollowtide's own motif: a rising fifth, a slow stepwise fall and a stretched seventh
# that refuses to resolve at once. (scale degree, beats); None is a rest.
HOLLOW_MOTIF: list[tuple[int | None, float]] = [
    (0, 0.75),
    (4, 0.75),
    (3, 0.5),
    (1, 2.0),
    (2, 0.5),
    (6, 1.5),
    (4, 2.0),
]


def m_transpose(motif, steps: int):
    return [(None if d is None else d + steps, b) for d, b in motif]


def m_invert(motif):
    pivot = next(d for d, _ in motif if d is not None)
    return [(None if d is None else 2 * pivot - d, b) for d, b in motif]


def m_augment(motif, factor: float):
    return [(d, b * factor) for d, b in motif]


def m_retrograde(motif):
    return list(reversed(motif))


def m_fragment(motif, start: int, stop: int):
    return motif[start:stop]


def play_line(
    score: Score,
    layer: str,
    key: Key,
    motif,
    start: float,
    octave: int,
    voice,
    gain: float = 1.0,
    position: float = 0.0,
    legato: float = 0.95,
) -> float:
    """Place a motif; voice(freq, seconds) -> sound. Returns the end time in seconds."""
    time = start
    for degree, beats in motif:
        seconds = beats * score.beat
        if degree is not None:
            score.place(
                layer, voice(key.hz(degree, octave), seconds * legato), time, gain, position
            )
        time += seconds
    return time


# --- beds ----------------------------------------------------------------------------


def wind_bed(
    n: int,
    rng: np.random.Generator,
    low: float,
    high: float,
    q: float = 1.6,
    cycles: tuple[int, ...] = (3, 5, 8, 13, 21),
    floor: float = 0.25,
    whistle: float = 0.25,
) -> np.ndarray:
    """Loop-periodic stereo wind: band-passed noise with wandering centre and gusts."""
    noise = rng.standard_normal((n, 2))
    centre = low * (high / low) ** loop_lfo(n, rng, cycles)
    gust = floor + (1.0 - floor) * loop_lfo(n, rng, cycles) ** 1.6

    def process(block: np.ndarray) -> np.ndarray:
        body = swept(block[:, :2], block[:, 2], q, "bp", 256)
        tone = swept(block[:, :2], block[:, 2] * 1.9, 9.0, "bp", 256)
        return body + whistle * 3.0 * tone

    stacked = np.concatenate([noise, centre[:, None]], axis=1)
    return circular(process, stacked, 2.0) * gust[:, None]


def _chords(score: Score, layer: str, plan, voice, gain: float = 1.0) -> None:
    """plan: [(bar, bars, midi_notes)] -> voice(freqs, seconds) placed on layer."""
    for bar, bars, notes in plan:
        if notes:
            score.place(
                layer, voice([midi_hz(m) for m in notes], bars * score.bar), score.at(bar), gain
            )


# --- area: fringe --------------------------------------------------------------------
# Lonely outer caves: D dorian, 66 bpm, no percussion. Wind, a soft filtered pad and a
# distant plucked motif that drifts through a long dark cave and a dotted-eighth echo.


def fringe_theme() -> np.ndarray:
    s = Score(44 * 4 * 60.0 / 66.0, 0x46524E31, bpm=66.0)
    rng = s.rng
    key = Key(50, "dorian")  # D3
    dm, c, g_b, am = (50, 57, 64, 65), (48, 55, 62, 64), (47, 55, 59, 64), (45, 52, 55, 60)
    bb, f, asus, dm_hi = (46, 53, 57, 62), (41, 48, 57, 64), (45, 52, 57, 62), (50, 57, 62, 65, 69)
    plan = [
        (0, 4, dm),
        (4, 2, dm), (6, 2, c), (8, 2, g_b), (10, 2, am), (12, 2, dm), (14, 2, c),
        (16, 2, bb), (18, 2, f), (20, 2, c), (22, 2, dm), (24, 1, bb), (25, 1, asus),
        (32, 2, dm_hi), (34, 2, c), (36, 2, g_b), (38, 2, am), (40, 2, bb), (42, 2, asus),
    ]  # fmt: skip
    _chords(s, "pad", plan, lambda fr, sec: v_pad(fr, sec, rng, 1.8, 3.0, 11.0, 3, "saw"))
    cutoff = s.auto([(0, 380), (4, 800), (15, 1100), (16, 1300), (25, 1600), (26, 600),
                     (32, 900), (40, 2000), (42, 900), (44, 380)])  # fmt: skip
    s.route(
        "pad",
        s.auto(
            [(0, 0.55), (4, 0.8), (25, 0.9), (26.5, 0.0), (31.5, 0.0), (32, 0.85), (44, 0.55)]
        ),  # fmt: skip
        {"hall": 0.35},
        lambda x: swept(x, cutoff, 0.9),
    )

    def pluck(freq: float, seconds: float) -> np.ndarray:
        return v_pluck(freq, seconds + 2.5, 0.5, 1.6, phase_seed=int(freq))

    motif = HOLLOW_MOTIF
    for bar, variant, octave, where in (
        (4, motif, 1, -0.2),
        (8, m_transpose(motif, 2), 1, 0.25),
        (12, m_fragment(motif, 0, 4) + [(None, 1.0), (4, 0.5), (3, 0.5), (0, 2.0)], 1, -0.1),
        (32, m_invert(motif), 1, 0.2),
        (36, motif, 2, -0.25),
        (40, m_fragment(m_invert(motif), 0, 5), 1, 0.1),
    ):
        play_line(s, "pluck", key, variant, s.at(bar), octave, pluck, 0.9, where)
    # B-section: broken chord tones, sparse
    for bar in range(16, 26):
        for beat in (0.0, 1.5, 3.0):
            if rng.random() < 0.55:
                degree = int(rng.choice([0, 2, 4, 6, 7]))
                s.place("pluck", pluck(key.hz(degree, 2), 1.0), s.at(bar, beat), 0.45,
                        rng.uniform(-0.7, 0.7))  # fmt: skip
    # breakdown: lonely single notes
    for bar in (26.5, 28.0, 29.25, 30.5):
        degree = int(rng.choice([4, 0, 3, 6]))
        s.place("pluck", pluck(key.hz(degree, 1), 1.0), s.at(bar), 0.6, rng.uniform(-0.8, 0.8))
    s.route("pluck", 1.0, {"hall": 0.5, "echo": 0.6})

    def whistle(freq: float, seconds: float) -> np.ndarray:
        return v_whistle(freq, seconds, 0.9)

    play_line(s, "whistle", key, m_augment(motif, 2.0), s.at(17), 1, whistle, 1.0, 0.15)
    play_line(s, "whistle", key, m_augment(m_fragment(m_invert(motif), 0, 4), 2.0), s.at(21), 1,
              whistle, 0.9, -0.15)  # fmt: skip
    s.route("whistle", 0.4, {"hall": 0.7, "echo": 0.2})

    for bar, bars, note in ((4, 8, 38), (12, 4, 38), (16, 4, 34), (20, 6, 36), (26, 6, 38),
                            (32, 6, 38), (38, 4, 33), (42, 2, 33)):  # fmt: skip
        s.place("sub", v_sub(midi_hz(note), bars * s.bar, 1.5, 2.0), s.at(bar), 1.0)
    s.route("sub", s.auto([(0, 0.0), (4, 0.11), (26, 0.15), (32, 0.13), (44, 0.0)]))

    # A'-section rain of tiny high notes
    for step in range(32 * 8, 42 * 8):
        if rng.random() < 0.18:
            s.place("drops", v_pluck(key.hz(int(rng.choice([0, 2, 4, 7])), 3), 1.2, 0.3, 0.5),
                    s.at(0, step / 2), 0.25, rng.uniform(-0.9, 0.9))  # fmt: skip
    s.route("drops", 2.0, {"hall": 0.8, "echo": 0.5})

    s.bed("wind", wind_bed(s.length, rng, 260.0, 1300.0, 1.4, whistle=0.2))
    s.route("wind", s.auto([(0, 1.4), (4, 0.75), (25, 0.75), (27, 1.5), (31, 1.5), (33, 0.7),
                            (42, 0.9), (44, 1.4)]),  # fmt: skip
            {"hall": 0.25})  # fmt: skip
    s.effects["hall"] = lambda x: convolve(x, reverb_ir(6.0, 3.8, 3.2, 1.5, 0x46520001, 0.03))
    s.effects["echo"] = lambda x: pingpong(x, 0.75 * s.beat, 0.45, 6, 2400.0)
    return s.render()


def _arp(
    score: Score,
    layer: str,
    plan,
    voice,
    step_beats: float,
    pattern: tuple[int, ...],
    gain: float = 1.0,
    skip: float = 0.0,
    spread: float = 0.5,
) -> None:
    """Arpeggiate chords: pattern indexes chord tones (wrapping upward by octaves)."""
    rng = score.rng
    for bar, bars, notes in plan:
        if not notes:
            continue
        steps = round(bars * score.bar / (step_beats * score.beat))
        for step in range(steps):
            if skip and rng.random() < skip:
                continue
            index = pattern[step % len(pattern)]
            octave, tone = divmod(index, len(notes))
            freq = midi_hz(notes[tone] + 12 * octave)
            position = spread * math.sin(step * 0.9)
            accent = 1.0 if step % 4 == 0 else 0.72
            score.place(
                layer, voice(freq), score.at(bar, step * step_beats), gain * accent, position
            )


# --- area: nexus ---------------------------------------------------------------------
# Resonant hub: E lydian, 80 bpm. FM bell arpeggios in a large hall with ping-pong
# echoes, a beating low hum and glassy lead lines.


def nexus_theme() -> np.ndarray:
    s = Score(52 * 3.0, 0x4E455831, bpm=80.0)
    rng = s.rng
    key = Key(52, "lydian")  # E3
    e, csm, a, b = (
        (40, 47, 56, 63, 66),
        (49, 56, 59, 63),
        (45, 52, 56, 61, 63),
        (47, 54, 56, 61, 64),
    )
    fsm, gsm, cmaj = (42, 49, 52, 57, 59), (44, 51, 54, 59), (48, 55, 59, 64)
    plan_a = [(4, 2, e), (6, 2, csm), (8, 2, a), (10, 2, b), (12, 2, e), (14, 2, csm)]
    plan_b = [(16, 2, fsm), (18, 2, gsm), (20, 2, cmaj), (22, 2, b), (24, 2, fsm), (26, 2, b)]
    plan_c = [(36, 2, e), (38, 2, a), (40, 2, e), (42, 2, csm), (44, 2, a), (46, 2, b),
              (48, 2, cmaj), (50, 2, b)]  # fmt: skip

    def bell(freq: float) -> np.ndarray:
        return v_bell(freq, 1.6, 3.5, 1.6, 0.9, 0.25)

    up = (4, 5, 6, 7, 8, 7, 6, 5)
    _arp(s, "arp", plan_a, bell, 0.5, up, 0.8, 0.08)
    _arp(s, "arp", plan_b, bell, 0.5, (5, 7, 6, 8, 7, 9, 8, 6), 0.8, 0.05)
    _arp(s, "arp", plan_c, bell, 0.5, up, 0.8, 0.04)
    # second, triplet arp in B and the last A for density
    tri = [(bar, bars, notes) for bar, bars, notes in plan_b[1:] + plan_c[4:]]
    _arp(s, "arp2", tri, lambda f: v_bell(f * 2.0, 1.0, 2.0, 1.2, 0.6, 0.2), 1.0 / 3.0,
         (0, 2, 1, 3, 2, 4), 0.35, 0.35, 0.9)  # fmt: skip
    arp_cut = s.auto([(0, 3000), (28, 3000), (36, 500), (40, 7000), (52, 3000)])
    s.route(
        "arp",
        s.auto(
            [
                (0, 0.0),
                (3.5, 0.0),
                (4, 1.0),
                (28, 1.0),
                (28.5, 0.0),
                (36, 0.0),
                (36.2, 0.9),
                (52, 0.9),
            ]
        ),  # fmt: skip
        {"hall": 0.45, "echo": 0.5},
        lambda x: swept(x, arp_cut, 0.8),
    )
    s.route("arp2", 1.0, {"hall": 0.6, "echo": 0.3})

    pad_plan = [(0, 4, e), (28, 4, e), (32, 4, a)] + plan_a + plan_b + plan_c
    _chords(s, "pad", pad_plan, lambda fr, sec: v_pad(fr, sec, rng, 1.2, 2.5, 7.0, 3, "triangle"))
    s.route("pad", s.auto([(0, 0.8), (4, 0.45), (28, 0.5), (29, 0.9), (36, 0.5), (52, 0.8)]),
            {"hall": 0.5}, lambda x: lp(x, 2200.0))  # fmt: skip

    for bar, bars, notes in plan_a + plan_b + plan_c:
        for beat in (0.0, 2.5):
            for rep in range(bars):
                s.place("bass", v_pluck(midi_hz(notes[0]), 1.4, 0.35, 0.8, 8), s.at(bar + rep, beat),
                        1.0 if beat == 0 else 0.6)  # fmt: skip
    s.route("bass", 0.55, {"hall": 0.15})

    def glass(freq: float, seconds: float) -> np.ndarray:
        return v_swell_glass(freq, max(seconds, 0.6) + 0.8)

    play_line(s, "lead", key, m_augment(HOLLOW_MOTIF, 1.5), s.at(17), 1, glass, 1.0, 0.1)
    play_line(s, "lead", key, m_augment(m_invert(HOLLOW_MOTIF), 1.5), s.at(21), 1, glass, 0.9, -0.1)
    play_line(s, "lead", key, HOLLOW_MOTIF, s.at(40), 2,
              lambda f, sec: v_bell(f, sec + 2.5, 1.0, 1.1, 2.4, 0.5, 3.0), 1.0, 0.2)  # fmt: skip
    play_line(s, "lead", key, m_transpose(HOLLOW_MOTIF, 3), s.at(44), 2,
              lambda f, sec: v_bell(f, sec + 2.5, 1.0, 1.1, 2.4, 0.5, 3.0), 0.9, -0.2)  # fmt: skip
    s.route("lead", 0.65, {"hall": 0.6, "echo": 0.35})

    # intro / breakdown: scattered bells and tuned droplets
    for bar_start, bar_end, density in ((0, 4, 0.35), (28, 36, 0.3), (50, 52, 0.3)):
        for step in range(bar_start * 4, bar_end * 4):
            if rng.random() < density:
                degree = int(rng.choice([0, 1, 3, 4, 6, 7, 8]))
                freq = key.hz(degree, 2)
                drop = v_bell(freq, 1.5, 1.0, 0.8, 1.0, 0.1) * 0.6
                s.place("sparkle", drop, s.at(0, step + float(rng.choice([0.0, 0.5]))), 0.7,
                        rng.uniform(-0.9, 0.9))  # fmt: skip
    s.route("sparkle", 0.8, {"hall": 0.7, "echo": 0.5})

    n = s.length
    t = np.arange(n) / SR
    swell = 0.55 + 0.45 * loop_lfo(n, rng, (2, 3, 5))
    cycles = round(41.2 * n / SR)
    hum = np.sin(2.0 * np.pi * cycles * np.arange(n) / n)
    hum += 0.6 * np.sin(2.0 * np.pi * (2 * cycles + 1) * np.arange(n) / n)
    hum += 0.25 * np.sin(2.0 * np.pi * (3 * cycles) * np.arange(n) / n + 0.3 * np.sin(0.2 * t))
    s.bed("hum", pan(hum * swell, 0.0))
    s.route("hum", s.auto([(0, 0.3), (4, 0.16), (28, 0.3), (36, 0.16), (52, 0.3)]), {"hall": 0.2})
    s.effects["hall"] = lambda x: convolve(x, reverb_ir(8.0, 5.0, 4.4, 2.6, 0x4E450001, 0.045))
    s.effects["echo"] = lambda x: pingpong(x, 0.75 * s.beat, 0.5, 7, 4200.0, 300.0)
    return s.render()


# --- area: vaults --------------------------------------------------------------------
# Frozen vaults: B aeolian, 50 bpm, no pulse. High crystalline pads with shimmer,
# struck-crystal notes, icy air and a wordless choir.


def vaults_theme() -> np.ndarray:
    s = Score(34 * 4 * 60.0 / 50.0, 0x56415531, bpm=50.0)
    rng = s.rng
    key = Key(59, "aeolian")  # B3
    bm, g, em, fs = (59, 66, 73, 74), (55, 62, 66, 73), (52, 59, 66, 67, 74), (54, 61, 71, 76)
    d, bm_hi = (50, 57, 61, 66, 69), (71, 78, 85, 86)
    plan = [(0, 3, bm), (3, 2, bm), (5, 2, g), (7, 2, em), (9, 2, fs), (11, 1, bm),
            (12, 2, bm), (14, 2, g), (16, 2, em), (18, 2, fs), (20, 3, em), (23, 3, d),
            (26, 2, bm_hi), (28, 2, g), (30, 2, d), (32, 2, fs)]  # fmt: skip

    def glass_pad(freqs: list[float], seconds: float) -> np.ndarray:
        return v_pad(freqs, seconds, rng, 3.0, 4.0, 5.0, 2, "sine", 0.9) + 0.35 * v_pad(
            [f * 2.0 for f in freqs], seconds, rng, 3.5, 4.0, 4.0, 2, "triangle", 1.0
        )

    _chords(s, "glass", plan, glass_pad)
    s.route("glass", s.auto([(0, 0.5), (3, 0.8), (19, 0.8), (20.5, 0.3), (25.5, 0.3), (26.3, 0.9),
                             (34, 0.5)]),  # fmt: skip
            {"hall": 0.6}, lambda x: hp(x, 180.0))  # fmt: skip
    shimmer_plan = [(bar, bars, tuple(m + 12 for m in notes)) for bar, bars, notes in plan]
    _chords(
        s, "shimmer", shimmer_plan, lambda fr, sec: v_pad(fr, sec, rng, 4.0, 4.0, 3.0, 2, "sine")
    )
    s.route("shimmer", s.auto([(0, 0.25), (20, 0.25), (20.5, 0.0), (26, 0.0), (27, 0.3),
                               (34, 0.25)]),  # fmt: skip
            {"hall": 1.0}, None, dry=False)  # fmt: skip

    # struck crystals
    for bar_start, bar_end, density, octave in (
        (3, 12, 0.22, 1),
        (20, 26, 0.12, 1),
        (26, 33, 0.32, 2),
    ):
        for step in range(bar_start * 8, bar_end * 8):
            if rng.random() < density:
                degree = int(rng.choice([0, 2, 4, 7, 8, 9, 11]))
                s.place(
                    "crystal",
                    v_glass(key.hz(degree, octave), 3.5, 1.4, 5.0),
                    s.at(0, step * 0.5),
                    float(rng.uniform(0.35, 0.8)),
                    rng.uniform(-0.8, 0.8),
                )
    play_line(s, "crystal", key, m_fragment(HOLLOW_MOTIF, 0, 5), s.at(29), 2,
              lambda f, sec: v_glass(f, sec + 3.0, 1.8, 4.0), 1.0, 0.0)  # fmt: skip
    s.route("crystal", 0.5, {"hall": 0.7, "echo": 0.45})

    # choir melody in B
    for bar, bars, notes in ((12, 2, bm), (14, 2, g), (16, 2, em), (18, 2, fs)):
        low = [midi_hz(m - 12) for m in notes[:3]]
        s.place("choir", v_choir(low, bars * s.bar, rng, "oo", 2.5, 3.0), s.at(bar), 0.8)

    def choir_voice(freq: float, seconds: float) -> np.ndarray:
        return v_choir([freq], seconds, rng, "oo", 0.8, 1.6)

    play_line(s, "choir", key, m_augment(HOLLOW_MOTIF, 1.0), s.at(12), 1, choir_voice, 1.2, 0.1)
    play_line(s, "choir", key, m_augment(m_invert(HOLLOW_MOTIF), 1.0), s.at(16), 1, choir_voice,
              1.1, -0.1)  # fmt: skip
    s.route("choir", 0.9, {"hall": 0.65})

    for bar, bars in ((0, 20), (20, 6), (26, 8)):
        s.place("sub", v_sub(midi_hz(35), bars * s.bar, 3.0, 3.0), s.at(bar), 1.0)
    s.route("sub", s.auto([(0, 0.0), (2, 0.14), (20, 0.18), (26, 0.12), (33, 0.1), (34, 0.0)]))
    for bar, bars in ((20, 3), (23, 3)):
        s.place(
            "sub", v_sub(midi_hz(40 if bar == 20 else 38), bars * s.bar, 2.0, 2.5), s.at(bar), 0.8
        )
    # breakdown: a single high bowed tone
    s.place("air", v_swell_glass(key.hz(4, 2), 5 * s.bar), s.at(20.5), 0.25, 0.3)
    n = s.length
    hiss = hp(rng.standard_normal((n, 2)), 5200.0, 2) + 0.4 * bp(rng.standard_normal((n, 2)), 2500.0,
                                                                 4800.0)  # fmt: skip
    swell = (0.15 + 0.85 * loop_lfo(n, rng, (2, 5, 9, 14)) ** 2.0)[:, None]
    s.bed("air", circular(lambda x: x, hiss) * swell * 0.25)
    s.route("air", 1.0, {"hall": 0.5})
    s.effects["hall"] = lambda x: convolve(x, reverb_ir(9.0, 5.5, 6.0, 5.0, 0x56410001, 0.06))
    s.effects["echo"] = lambda x: pingpong(x, 1.5 * s.beat, 0.4, 5, 6000.0, 600.0)
    return s.render()


# --- area: kiln ----------------------------------------------------------------------
# Industrial-volcanic forge: C phrygian dominant, 92 bpm. Distorted bass ostinati,
# kick/pipe/anvil percussion, steam ticks, a growling pad and a horn motif.


def kiln_theme() -> np.ndarray:
    s = Score(60 * 4 * 60.0 / 92.0, 0x4B494C31, bpm=92.0)
    rng = s.rng
    key = Key(36, "phrygian_dominant")  # C2
    sixteenth = 0.25
    bass_a = [(0, 2), (None, 1), (0, 1), (None, 2), (0, 1), (1, 1), (0, 2), (None, 2), (3, 1),
              (2, 1), (1, 2)]  # fmt: skip
    bass_b = [(0, 1), (0, 1), (None, 1), (0, 1), (None, 1), (0, 1), (1, 2), (0, 1), (0, 1),
              (None, 1), (-2, 1), (-1, 2), (None, 2)]  # fmt: skip
    bass_cache: dict[tuple[float, float], np.ndarray] = {}

    def bass(freq: float, seconds: float) -> np.ndarray:
        cache_key = (round(freq, 3), round(seconds, 3))
        if cache_key not in bass_cache:
            bass_cache[cache_key] = v_bass(freq, seconds, 2.8, 260.0, 1300.0, 0.12, 1.6)
        return bass_cache[cache_key]

    def bass_bar(bar: int, pattern, shift: int = 0) -> None:
        time = s.at(bar)
        for degree, steps in pattern:
            seconds = steps * sixteenth * s.beat
            if degree is not None:
                s.place("bass", bass(key.hz(degree + shift, 0), seconds * 0.9), time, 1.0)
            time += seconds

    for bar in range(4, 16):
        bass_bar(bar, bass_a)
    for bar in range(16, 28):
        bass_bar(bar, bass_b if bar % 4 != 3 else bass_a)
    for bar in range(40, 56):
        bass_bar(bar, bass_b if bar % 2 else bass_a, 1 if 48 <= bar < 52 else 0)
    s.route("bass", 0.8, {"forge": 0.12})

    kick = d_kick(140.0, 44.0, 0.3, 0.3)
    pipe_hits = [d_metal(f, 1.4, 3.0, i) for i, f in enumerate((310.0, 347.0, 415.0))]
    anvil = d_metal(1250.0, 0.35, 2.0, 7)
    ticks = [d_hat(0.035, i, 6500.0) for i in range(4)]
    tom = [d_tom(f, 0.35) for f in (72.0, 96.0, 128.0)]

    def drums_a(bar: int) -> None:
        for step in (0, 6, 10):
            s.place("kick", kick, s.at(bar, step * sixteenth), 1.0)
        for step in (4, 12):
            s.place("metal", pipe_hits[(bar + step) % 3], s.at(bar, step * sixteenth), 0.5,
                    -0.4 if step == 4 else 0.4)  # fmt: skip
        for step in range(0, 16, 2):
            s.place("ticks", ticks[step % 4], s.at(bar, step * sixteenth),
                    0.5 if step % 4 == 2 else 0.25, 0.5)  # fmt: skip

    def drums_b(bar: int) -> None:
        drums_a(bar)
        for step in (4, 12):
            s.place("metal", anvil, s.at(bar, step * sixteenth), 0.4, 0.2)
        for step in range(1, 16, 2):
            if rng.random() < 0.6:
                s.place("ticks", ticks[step % 4], s.at(bar, step * sixteenth), 0.2, -0.5)
        if bar % 4 == 3:
            for i, step in enumerate((12, 13, 14, 15)):
                s.place("kick", tom[2 - i % 3], s.at(bar, step * sixteenth), 0.7, -0.3 + 0.2 * i)

    for bar in range(4, 16):
        drums_a(bar)
    for bar in range(16, 28):
        drums_b(bar)
    for bar in range(28, 36):
        s.place("kick", kick, s.at(bar), 0.9)
        if bar % 2:
            s.place("kick", kick, s.at(bar, 2.5), 0.6)
    for bar in range(36, 40):
        steps = 8 if bar < 38 else 16
        for step in range(steps):
            level = 0.35 + 0.5 * ((bar - 36) * steps + step) / (4 * steps)
            s.place("kick", tom[step % 3], s.at(bar, step * 4 / steps), level, 0.4 * math.sin(step))
    for bar in range(40, 56):
        drums_b(bar)
    s.route("kick", 1.0, {"forge": 0.1})
    s.route("ticks", 0.55, {"forge": 0.2})
    for bar_start, bar_end, chance in ((0, 4, 0.5), (28, 36, 0.45), (56, 60, 0.5)):
        for beat in range(bar_start * 4, bar_end * 4):
            if rng.random() < chance:
                s.place(
                    "metal",
                    pipe_hits[int(rng.integers(0, 3))],
                    s.at(0, beat + 0.5 * int(rng.integers(0, 2))),
                    float(rng.uniform(0.3, 0.6)),
                    rng.uniform(-0.8, 0.8),
                )
    s.route("metal", 0.7, {"forge": 0.5, "echo": 0.35})

    growl_plan = [(16, 4, (36, 43, 48)), (20, 4, (37, 44, 49)), (24, 4, (36, 43, 48)),
                  (28, 4, (36, 43, 46)), (32, 4, (37, 44, 49)),
                  (48, 4, (37, 44, 49)), (52, 4, (36, 43, 48))]  # fmt: skip
    _chords(s, "growl", growl_plan, lambda fr, sec: v_pad(fr, sec, rng, 0.8, 1.5, 14.0, 3, "saw"))
    wah = s.auto([(0, 300), (16, 400), (28, 700), (36, 300), (48, 500), (56, 900), (60, 300)])
    wah = wah * (1.0 + 0.6 * np.sin(2.0 * np.pi * np.arange(s.n) / SR / (2 * s.bar)))
    s.route("growl", 0.7, {"forge": 0.3},
            lambda x: np.tanh(2.2 * swept(x, wah, 2.2)) * 0.6)  # fmt: skip

    def horn(freq: float, seconds: float) -> np.ndarray:
        return np.tanh(1.8 * v_lead(freq, seconds, 2.2, 10.0, 0.06, 0.3))

    play_line(s, "horn", key, HOLLOW_MOTIF, s.at(18), 1, horn, 1.0, 0.0)
    play_line(s, "horn", key, m_transpose(HOLLOW_MOTIF, -1), s.at(24), 1, horn, 1.0, 0.0)
    play_line(s, "horn", key, m_invert(HOLLOW_MOTIF), s.at(44), 2, horn, 0.9, 0.0)
    play_line(s, "horn", key, m_fragment(HOLLOW_MOTIF, 0, 4) + [(4, 4.0)], s.at(50), 1, horn, 1.0)
    s.route("horn", 0.45, {"forge": 0.4, "echo": 0.2})

    n = s.length
    rumble = lp(rng.standard_normal((n, 2)), 90.0, 4) * 6.0
    rumble *= (0.35 + 0.65 * loop_lfo(n, rng, (3, 7, 11, 19)))[:, None]
    s.bed("rumble", circular(lambda x: x, rumble))
    s.route("rumble", s.auto([(0, 0.6), (4, 0.35), (28, 0.6), (36, 0.35), (56, 0.6), (60, 0.6)]))
    s.effects["forge"] = lambda x: convolve(x, reverb_ir(3.0, 1.8, 1.4, 0.6, 0x4B490001, 0.012, 16))
    s.effects["echo"] = lambda x: pingpong(x, s.beat, 0.35, 4, 2200.0, 250.0)
    return s.render()


# --- area: depths --------------------------------------------------------------------
# Drowned depths: C# phrygian, 56 bpm. Pressure drones, sonar pings, a heartbeat,
# whale-like groans, a low reed motif and a dark cluster choir at the climax.


def depths_theme() -> np.ndarray:
    s = Score(36 * 4 * 60.0 / 56.0, 0x44455031, bpm=56.0)
    rng = s.rng
    key = Key(37, "phrygian")  # C#2
    n = s.length
    t = np.arange(n) / n

    def tone_bed(midi: float, harmonics: float) -> np.ndarray:
        cycles = round(midi_hz(midi) * n / SR)
        wave = np.sin(2.0 * np.pi * cycles * t) + harmonics * np.sin(4.0 * np.pi * cycles * t + 0.4)
        return wave

    drone = tone_bed(37, 0.4) + 0.6 * tone_bed(25, 0.0)
    raw = circular(lambda x: lp(x, 160.0, 2), rng.standard_normal(n)) * 3.0
    drone += raw * (0.4 + 0.6 * loop_lfo(n, rng, (2, 3, 7)))
    s.bed("drone", pan(drone, 0.0))
    s.route("drone", s.auto([(0, 0.35), (4, 0.45), (12, 0.5), (19, 0.55), (21, 0.22), (25, 0.25),
                             (27, 0.6), (32, 0.6), (36, 0.35)]),
            {"hall": 0.3})  # fmt: skip
    tension = tone_bed(38, 0.2) + 0.5 * tone_bed(50, 0.0)
    s.bed("tension", pan(tension, 0.15))
    s.route("tension", s.auto([(0, 0.0), (12, 0.0), (16, 0.12), (20, 0.0), (26, 0.0), (29, 0.18),
                               (32, 0.0), (36, 0.0)]),  # fmt: skip
            {"hall": 0.4})  # fmt: skip

    heart = d_heart(1.0)
    for bar in range(4, 12):
        s.place("heart", heart, s.at(bar), 0.9)
    for bar in range(12, 20):
        s.place("heart", heart, s.at(bar), 0.95)
        s.place("heart", heart, s.at(bar, 2), 0.8)
    for bar in range(26, 32):
        s.place("heart", heart, s.at(bar), 1.0)
        s.place("heart", heart, s.at(bar, 2), 0.85)
    s.route("heart", 1.8, {"hall": 0.15})

    ping_times = [0.5, 2.5, 5.0, 8.2, 11.0, 14.5, 17.2, 20.3, 22.0, 23.6, 25.1, 29.0, 32.4, 34.6]
    for index, bar in enumerate(ping_times):
        freq = key.hz(int(rng.choice([0, 4, 7])), 4 if index % 3 else 3)
        s.place("sonar", d_sonar(freq, 1.3), s.at(bar), 1.0, rng.uniform(-0.6, 0.6))
    s.route("sonar", 0.35, {"hall": 0.6, "echo": 0.7})

    for bar, f0, f1, dur in ((13, 92.0, 64.0, 7.0), (17.5, 70.0, 104.0, 6.0), (21, 82.0, 55.0, 9.0),
                             (24.5, 60.0, 76.0, 7.0), (30, 110.0, 73.0, 8.0)):  # fmt: skip
        s.place("groan", v_groan(f0, f1, dur, int(bar)), s.at(bar), 1.0, rng.uniform(-0.5, 0.5))
    s.route("groan", 0.5, {"hall": 0.7, "echo": 0.2})

    def reed(freq: float, seconds: float) -> np.ndarray:
        return lp(v_lead(freq, seconds, 1.2, 6.0, 0.15, 0.6, "square"), 900.0)

    play_line(s, "reed", key, HOLLOW_MOTIF, s.at(6), 1, reed, 1.0, -0.1)
    play_line(s, "reed", key, m_transpose(m_fragment(HOLLOW_MOTIF, 0, 5), 1), s.at(9), 1, reed, 0.9)
    play_line(
        s, "reed", key, m_augment(m_fragment(HOLLOW_MOTIF, 2, 7), 1.5), s.at(27), 1, reed, 1.0
    )
    s.route("reed", 0.55, {"hall": 0.45, "echo": 0.15})

    cluster = [midi_hz(m) for m in (49, 50, 56, 61)]
    s.place("choir", v_choir(cluster, 6 * s.bar, rng, "ah", 6.0, 5.0), s.at(26), 1.0)
    s.route("choir", 0.45, {"hall": 0.6}, lambda x: lp(x, 1800.0))
    s.effects["hall"] = lambda x: convolve(
        lp(x, 2600.0), reverb_ir(8.0, 6.5, 4.0, 1.1, 0x44450001, 0.08)
    )
    s.effects["echo"] = lambda x: pingpong(x, 0.75 * s.beat, 0.55, 7, 1800.0, 200.0)
    return s.render()


# --- boss ----------------------------------------------------------------------------
# Tense and driving: D harmonic minor, 140 bpm, 16th-note distorted bass, four-on-the-floor
# kick, snare backbeat, supersaw stabs and a brass-like lead built from the motif.


def boss_theme() -> np.ndarray:
    s = Score(56 * 4 * 60.0 / 140.0, 0x424F5331, bpm=140.0)
    rng = s.rng
    key = Key(38, "harmonic_minor")  # D2
    roots = {"i": 0, "VI": 5, "iv": 3, "V": 4}
    progression = ["i", "i", "VI", "V", "i", "i", "iv", "V"]
    riff = (0, 0, 7, 0, 0, 0, 5, 0, 0, 0, 7, 0, 4, 5, 4, 3)
    bass_cache: dict[int, np.ndarray] = {}

    def bass(midi: int, seconds: float) -> np.ndarray:
        if midi not in bass_cache:
            bass_cache[midi] = v_bass(midi_hz(midi), seconds, 3.2, 320.0, 1800.0, 0.07, 1.3)
        return bass_cache[midi]

    step = 0.25 * s.beat
    for bar in list(range(0, 24)) + list(range(32, 56)):
        root = roots[progression[(bar // 2) % len(progression)]]
        for index, degree in enumerate(riff):
            if bar >= 48 and index % 2 and bar % 2 == 0:
                continue
            s.place("bass", bass(key.midi(root + degree, 0), step * 0.85), s.at(bar, index * 0.25),
                    1.0 if index % 4 == 0 else 0.8)  # fmt: skip
    for bar in range(24, 32, 2):
        root = roots[progression[(bar // 2) % len(progression)]]
        s.place("bass", v_bass(key.hz(root, 0), 2 * s.bar * 0.95, 4.0, 200.0, 900.0, 0.5, 1.8),
                s.at(bar), 0.9)  # fmt: skip
    s.route("bass", 0.75, {"room": 0.08})

    kick = d_kick(160.0, 50.0, 0.22, 0.35)
    snare = d_snare(200.0, 0.16, 1.0, 3)
    hats = [d_hat(0.03, i, 8000.0) for i in range(3)]
    toms = [d_tom(f, 0.3) for f in (80.0, 110.0, 150.0)]
    crash = d_metal(420.0, 1.6, 4.0, 11)
    for bar in range(56):
        section_c = 24 <= bar < 32
        if section_c:
            for beat in (0.0, 2.5):
                s.place("drums", kick, s.at(bar, beat), 1.0)
            s.place("drums", snare, s.at(bar, 3.0), 0.9, 0.05)
        else:
            for beat in range(4):
                s.place("drums", kick, s.at(bar, beat), 1.0)
            if bar >= 8:
                for beat in (1, 3):
                    s.place("drums", snare, s.at(bar, beat), 0.85, 0.05)
            for index in range(8 if bar < 32 else 16):
                spacing = 0.5 if bar < 32 else 0.25
                s.place("drums", hats[index % 3], s.at(bar, index * spacing),
                        0.5 if index % 2 else 0.3, 0.35)  # fmt: skip
        if bar % 8 == 7:
            for index in range(8):
                s.place("drums", toms[2 - index // 3], s.at(bar, 2.0 + index * 0.25), 0.8,
                        -0.4 + index * 0.1)  # fmt: skip
        if bar % 8 == 0:
            s.place("drums", crash, s.at(bar), 0.45, -0.2)
    for index in range(32):  # snare build at the end of the loop
        s.place("drums", snare, s.at(52, index * 0.5), 0.25 + 0.6 * index / 32, 0.0)
    s.route("drums", 0.9, {"room": 0.15})

    chords = {
        "i": (50, 53, 57, 62),
        "VI": (46, 50, 53, 58),
        "iv": (43, 50, 55, 58),
        "V": (45, 49, 52, 57),
    }
    for bar in list(range(8, 24)) + list(range(32, 48)):
        notes = chords[progression[(bar // 2) % len(progression)]]
        for beat in (0.5, 1.5, 2.75, 3.5):
            s.place("stabs", v_stab([midi_hz(m + 12) for m in notes], 0.18, rng), s.at(bar, beat),
                    0.8, 0.0)  # fmt: skip
    s.route("stabs", 1.3, {"room": 0.3, "echo": 0.3})

    def brass(freq: float, seconds: float) -> np.ndarray:
        return np.tanh(1.5 * v_lead(freq, seconds, 3.5, 16.0, 0.03, 0.18))

    doubled = m_augment(HOLLOW_MOTIF, 2.0)
    play_line(s, "lead", key, doubled, s.at(8), 2, brass, 1.0, 0.0)
    play_line(s, "lead", key, m_transpose(doubled, 2), s.at(16), 2, brass, 1.0, 0.0)
    play_line(s, "lead", key, m_invert(doubled), s.at(32), 2, brass, 1.0, 0.0)
    play_line(s, "lead", key, m_transpose(doubled, 4), s.at(40), 2, brass, 1.0, 0.0)
    s.route("lead", 0.55, {"room": 0.35, "echo": 0.25})

    for bar in range(24, 32, 2):
        notes = chords[progression[(bar // 2) % len(progression)]]
        s.place("choir", v_choir([midi_hz(m) for m in notes], 2 * s.bar, rng, "ah", 0.3, 0.8),
                s.at(bar), 1.0)  # fmt: skip
    s.route("choir", 1.2, {"room": 0.5})
    _arp(s, "arp", [(bar, 2, chords[progression[(bar // 2) % 8]]) for bar in range(32, 48, 2)],
         lambda f: v_pluck(f, 0.4, 0.7, 0.25, 8), 0.25, (4, 5, 6, 7, 8, 7, 6, 5), 0.5)  # fmt: skip
    s.route("arp", 0.9, {"room": 0.3, "echo": 0.3})
    s.effects["room"] = lambda x: convolve(x, reverb_ir(3.5, 2.2, 1.8, 1.0, 0x424F0001, 0.015))
    s.effects["echo"] = lambda x: pingpong(x, 0.75 * s.beat, 0.35, 4, 3000.0, 300.0)
    return s.render(-16.0)


# --- title ---------------------------------------------------------------------------
# Calm menu theme: E dorian, 60 bpm. Warm pad, a soft electric-bell statement of the
# motif, distant wind and a whistle counter-line.


def title_theme() -> np.ndarray:
    s = Score(30 * 4.0, 0x5449544C, bpm=60.0)
    rng = s.rng
    key = Key(52, "dorian")  # E3
    em9, cmaj7, g_b, d6, am9, bsus = ((40, 52, 55, 59, 66), (36, 52, 55, 59, 64), (47, 50, 55, 62),
                                      (38, 50, 54, 59, 62), (45, 52, 55, 59, 60), (47, 52, 54, 59))  # fmt: skip
    plan = [(0, 4, em9), (4, 2, em9), (6, 2, cmaj7), (8, 2, g_b), (10, 2, d6), (12, 2, am9),
            (14, 2, bsus), (16, 2, em9), (18, 2, cmaj7), (20, 2, g_b), (22, 2, d6), (24, 2, am9),
            (26, 2, cmaj7), (28, 2, bsus)]  # fmt: skip
    _chords(s, "pad", plan, lambda fr, sec: v_pad(fr, sec, rng, 2.5, 3.0, 8.0, 3, "triangle"))
    cut = s.auto([(0, 700), (4, 1500), (12, 1100), (16, 2400), (24, 1200), (30, 700)])
    s.route("pad", s.auto([(0, 0.7), (4, 0.8), (30, 0.7)]), {"hall": 0.45},
            lambda x: swept(x, cut, 0.8))  # fmt: skip

    def keys(freq: float, seconds: float) -> np.ndarray:
        return v_bell(freq, seconds + 3.0, 1.0, 1.4, 2.8, 0.35, 4.0)

    play_line(s, "keys", key, HOLLOW_MOTIF, s.at(4), 1, keys, 1.0, -0.1)
    play_line(s, "keys", key, m_transpose(HOLLOW_MOTIF, 2), s.at(8), 1, keys, 0.9, 0.1)
    play_line(s, "keys", key, HOLLOW_MOTIF, s.at(16), 2, keys, 0.9, -0.1)
    play_line(s, "keys", key, m_invert(HOLLOW_MOTIF), s.at(20), 1, keys, 0.9, 0.1)
    for bar in range(12, 16):
        for beat in (0.0, 1.5, 3.0):
            if rng.random() < 0.6:
                degree = int(rng.choice([0, 2, 4, 6, 7, 9]))
                s.place(
                    "keys",
                    keys(key.hz(degree, 2), 0.5),
                    s.at(bar, beat),
                    0.35,
                    rng.uniform(-0.6, 0.6),
                )
    s.route("keys", 0.8, {"hall": 0.5, "echo": 0.35})
    play_line(s, "whistle", key, m_augment(m_fragment(HOLLOW_MOTIF, 2, 7), 2.0), s.at(16.5), 1,
              lambda f, sec: v_whistle(f, sec, 1.0), 1.0, 0.25)  # fmt: skip
    s.route("whistle", 0.3, {"hall": 0.7, "echo": 0.2})
    for bar, bars, note in (
        (4, 8, 40),
        (12, 2, 45),
        (14, 2, 47),
        (16, 8, 40),
        (24, 4, 45),
        (28, 2, 47),
    ):
        s.place("sub", v_sub(midi_hz(note), bars * s.bar, 1.0, 2.0), s.at(bar), 1.0)
    s.route("sub", 0.12)
    s.bed("wind", wind_bed(s.length, rng, 300.0, 1100.0, 1.2, whistle=0.1))
    s.route("wind", 0.5, {"hall": 0.2})
    s.effects["hall"] = lambda x: convolve(x, reverb_ir(6.0, 3.6, 3.4, 2.0, 0x54490001, 0.03))
    s.effects["echo"] = lambda x: pingpong(x, 0.75 * s.beat, 0.4, 5, 3000.0, 250.0)
    return s.render(-18.0)


# --- ending --------------------------------------------------------------------------
# Credits piece: D major, 72 bpm, plays once. The motif finally resolves in major.


def ending_theme() -> np.ndarray:
    s = Score(26 * 4 * 60.0 / 72.0, 0x454E4431, bpm=72.0)
    rng = s.rng
    key = Key(62, "ionian")  # D4
    d, bm, g, a, em, fsm = ((50, 57, 62, 66, 69), (47, 54, 59, 62, 66), (43, 55, 59, 62, 66),
                            (45, 52, 57, 61, 64), (40, 52, 55, 59, 62), (42, 54, 57, 61))  # fmt: skip
    plan = [(0, 2, d), (2, 2, g), (4, 2, d), (6, 2, bm), (8, 2, g), (10, 2, a), (12, 2, bm),
            (14, 2, fsm), (16, 2, g), (18, 2, a), (20, 2, em), (22, 2, a), (24, 2, d)]  # fmt: skip
    _chords(s, "pad", plan, lambda fr, sec: v_pad(fr, sec, rng, 1.5, 3.0, 8.0, 3, "saw"))
    s.route("pad", s.auto([(0, 0.4), (4, 0.55), (12, 0.75), (24, 0.8), (26, 0.8)]), {"hall": 0.45},
            lambda x: lp(x, 1800.0))  # fmt: skip
    _arp(s, "arp", plan[:-1], lambda f: v_pluck(f, 1.6, 0.5, 0.9, 10), 0.5, (5, 6, 7, 8, 9, 8, 7, 6),
         0.6, 0.05)  # fmt: skip
    s.route("arp", 0.6, {"hall": 0.4, "echo": 0.3})

    def lead(freq: float, seconds: float) -> np.ndarray:
        return v_whistle(freq, seconds, 0.9)

    play_line(s, "lead", key, HOLLOW_MOTIF, s.at(4), 0, lead, 1.0, 0.0)
    play_line(s, "lead", key, m_transpose(HOLLOW_MOTIF, 2), s.at(8), 0, lead, 1.0, 0.0)
    play_line(s, "lead", key, m_augment(HOLLOW_MOTIF[:5] + [(4, 1.0), (7, 3.0)], 1.5), s.at(16), 0,
              lead, 1.0, 0.0)  # fmt: skip
    s.route("lead", 0.5, {"hall": 0.55, "echo": 0.25})
    for bar, bars, notes in plan[6:]:
        s.place("choir", v_choir([midi_hz(m) for m in notes[1:]], bars * s.bar, rng, "ah", 1.5, 2.0),
                s.at(bar), 1.0)  # fmt: skip
    s.route("choir", 0.4, {"hall": 0.6})
    for bar, bars, notes in plan:
        s.place("sub", v_sub(midi_hz(notes[0]), bars * s.bar, 0.6, 1.5), s.at(bar), 1.0)
    s.route("sub", 0.14)
    s.effects["hall"] = lambda x: convolve(x, reverb_ir(7.0, 4.0, 3.8, 2.4, 0x454E0001, 0.03))
    s.effects["echo"] = lambda x: pingpong(x, 0.75 * s.beat, 0.4, 5, 3000.0, 250.0)
    out = s.render(-18.0, loop=False)
    fade = np.ones(len(out))
    tail = round(6.0 * SR)
    fade[-tail:] = np.linspace(1.0, 0.0, tail) ** 2
    return out * fade[:, None]


MUSIC_GENERATORS = {
    "fringe": fringe_theme,
    "nexus": nexus_theme,
    "vaults": vaults_theme,
    "kiln": kiln_theme,
    "depths": depths_theme,
    "boss": boss_theme,
    "title": title_theme,
    "ending": ending_theme,
}


# =================================================================================
# Area ambience: stereo loop beds + randomized one-shot layers (played by Audio)
# =================================================================================

AMBIENCE_BED_SECONDS = 60.0


def _stable_seed(text: str) -> int:
    """Process-independent seed (Python's hash() is salted per run)."""
    value = 2166136261
    for byte in text.encode():
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


def scatter(n: int, rng: np.random.Generator, rate: float, maker, stereo_out: bool = True):
    """Place rate-per-second events at random times, wrapping around the loop."""
    out = np.zeros((n, 2)) if stereo_out else np.zeros(n)
    count = rng.poisson(rate * n / SR)
    for _ in range(count):
        sound = maker(rng)
        sound = stereo(sound, rng.uniform(-0.9, 0.9)) if stereo_out else sound
        start = int(rng.integers(0, n))
        stop = start + len(sound)
        if stop <= n:
            out[start:stop] += sound
        else:
            split = n - start
            out[start:] += sound[:split]
            out[: stop - n] += sound[split:]
    return out


def _bubble(rng: np.random.Generator, low: float = 500.0, high: float = 2200.0) -> np.ndarray:
    duration = rng.uniform(0.012, 0.04)
    n = round(duration * SR)
    t = _time(n)
    f0 = rng.uniform(low, high)
    f = f0 * (1.0 + 1.6 * t / duration)
    return (
        np.sin(2.0 * np.pi * np.cumsum(f) / SR)
        * np.exp(-t / (duration * 0.35))
        * rng.uniform(0.2, 1.0)
    )


def _crackle(rng: np.random.Generator) -> np.ndarray:
    n = round(rng.uniform(0.002, 0.008) * SR)
    t = _time(n)
    return rng.standard_normal(n) * np.exp(-t / 0.0015) * rng.uniform(0.1, 1.0) ** 2


def _noise_loop(n: int, rng: np.random.Generator, low: float, high: float) -> np.ndarray:
    return np.stack([_periodic_noise(n, rng, low, high) for _ in range(2)], axis=1)


def _bed_fringe() -> np.ndarray:
    rng = np.random.default_rng(0x41424631)
    n = round(AMBIENCE_BED_SECONDS * SR)
    wind = wind_bed(n, rng, 180.0, 900.0, 1.3, (2, 3, 5, 8, 13), 0.15, 0.18)
    room = _noise_loop(n, rng, 25.0, 110.0) * 0.5
    air = _noise_loop(n, rng, 2500.0, 7000.0) * 0.05
    return wind + room / np.std(room) * 0.08 + air / np.std(air) * 0.02


def _bed_nexus() -> np.ndarray:
    rng = np.random.default_rng(0x41424E31)
    n = round(AMBIENCE_BED_SECONDS * SR)
    stream = _noise_loop(n, rng, 300.0, 3200.0)
    stream = stream / np.std(stream) * (0.55 + 0.25 * loop_lfo(n, rng, (7, 11, 17)))[:, None]
    babble = scatter(n, rng, 70.0, _bubble)
    t = np.arange(n) / n
    hum = np.zeros(n)
    for ratio, amp in ((1.0, 1.0), (2.0, 0.5), (3.0, 0.3), (4.02, 0.12)):
        hum += amp * np.sin(2.0 * np.pi * round(55.0 * ratio * AMBIENCE_BED_SECONDS) * t)
    hum *= 0.6 + 0.4 * loop_lfo(n, rng, (1, 2, 3))
    return 0.09 * stream + 0.18 * babble + pan(hum * 0.07, 0.0)


def _bed_vaults() -> np.ndarray:
    rng = np.random.default_rng(0x41425631)
    n = round(AMBIENCE_BED_SECONDS * SR)
    wind = wind_bed(n, rng, 700.0, 3200.0, 2.6, (2, 3, 5, 9, 14), 0.2, 0.45)
    hiss = _noise_loop(n, rng, 5000.0, 12000.0)
    return wind + 0.02 * hiss / np.std(hiss) * (0.3 + 0.7 * loop_lfo(n, rng, (3, 5)))[:, None]


def _bed_kiln() -> np.ndarray:
    rng = np.random.default_rng(0x41424B31)
    n = round(AMBIENCE_BED_SECONDS * SR)
    rumble = _noise_loop(n, rng, 20.0, 85.0)
    rumble = rumble / np.std(rumble) * (0.5 + 0.5 * loop_lfo(n, rng, (2, 5, 9)))[:, None]
    roar = _noise_loop(n, rng, 140.0, 650.0)
    roar = roar / np.std(roar) * (0.3 + 0.7 * loop_lfo(n, rng, (3, 7, 12)) ** 2)[:, None]
    crackle = circular(lambda x: bp(x, 900.0, 6500.0, 1), scatter(n, rng, 22.0, _crackle))
    return 0.22 * rumble + 0.06 * roar + 0.5 * crackle


def _bed_depths() -> np.ndarray:
    rng = np.random.default_rng(0x41424431)
    n = round(AMBIENCE_BED_SECONDS * SR)
    pressure = _noise_loop(n, rng, 15.0, 70.0)
    pressure = pressure / np.std(pressure) * (0.6 + 0.4 * loop_lfo(n, rng, (1, 2, 5)))[:, None]
    water = _noise_loop(n, rng, 60.0, 420.0)
    water = water / np.std(water) * (0.2 + 0.8 * loop_lfo(n, rng, (3, 4, 7)) ** 2)[:, None]
    t = np.arange(n) / n
    tone = np.sin(2.0 * np.pi * round(38.0 * AMBIENCE_BED_SECONDS) * t) + 0.3 * np.sin(
        2.0 * np.pi * round(57.3 * AMBIENCE_BED_SECONDS) * t
    )
    return 0.3 * pressure + 0.08 * water + pan(tone * 0.05 * (0.5 + loop_lfo(n, rng, (1, 2))), 0.0)


AMBIENCE_BEDS = {
    "fringe": _bed_fringe,
    "nexus": _bed_nexus,
    "vaults": _bed_vaults,
    "kiln": _bed_kiln,
    "depths": _bed_depths,
}


def ambience_bed(area: str) -> np.ndarray:
    x = AMBIENCE_BEDS[area]()
    x = x - x.mean(axis=0)
    x *= 10.0 ** ((AMBIENCE_BED_LUFS - loudness(x)) / 20.0)
    return limit(x, -6.0, True)


# --- one-shot layers ----------------------------------------------------------------

_SPACE_IRS = {
    "fringe": (1.8, 1.4, 1.2, 0.7),
    "nexus": (3.2, 2.6, 2.4, 1.4),
    "vaults": (3.5, 2.8, 3.0, 2.6),
    "kiln": (1.4, 1.0, 0.8, 0.4),
    "depths": (3.0, 2.8, 1.8, 0.6),
}


def _space(area: str, x: np.ndarray, wet: float) -> np.ndarray:
    """Bake the area's cave into a mono one-shot."""
    seconds, low, mid, high = _SPACE_IRS[area]
    ir = reverb_ir(seconds, low, mid, high, _stable_seed(area), 0.015)[:, 0]
    ir /= math.sqrt(float(np.sum(ir * ir)))
    padded = np.concatenate([x, np.zeros(len(ir))])
    out = padded + wet * sps.oaconvolve(padded, ir)[: len(padded)] * 0.35
    level = np.abs(out)
    above = np.nonzero(level > 10.0 ** (-70.0 / 20.0) * level.max())[0]
    out = out[: int(above[-1]) + 1] if len(above) else out
    return _finish_one_shot(out, 1.0)


def _drip(rng: np.random.Generator) -> np.ndarray:
    n = round(0.09 * SR)
    t = _time(n)
    f0 = rng.uniform(900.0, 1700.0)
    f = f0 * (1.0 + 1.8 * (1.0 - np.exp(-t / 0.012)))
    tone = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.018)
    tick = hp(rng.standard_normal(n), 3000.0) * np.exp(-t / 0.0015) * 0.3
    return tone + tick


def _plop(rng: np.random.Generator) -> np.ndarray:
    n = round(0.25 * SR)
    t = _time(n)
    f0 = rng.uniform(380.0, 620.0)
    f = f0 * (1.0 + 1.2 * (1.0 - np.exp(-t / 0.03)))
    tone = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05)
    splash = bp(rng.standard_normal(n), 1200.0, 6000.0) * np.exp(-t / 0.025) * 0.4
    trail = (
        scatter(n, rng, 40.0, lambda r: _bubble(r, 700.0, 2400.0), False) * np.exp(-t / 0.08) * 0.3
    )
    return tone + splash + trail


def _gust(rng: np.random.Generator, low: float, high: float, q: float) -> np.ndarray:
    duration = rng.uniform(3.0, 5.5)
    n = round(duration * SR)
    t = _time(n)
    centre = low * (high / low) ** (
        0.5 - 0.5 * np.cos(2.0 * np.pi * t / duration * rng.uniform(0.7, 1.3))
    )
    noise = rng.standard_normal(n)
    body = swept(noise, centre, q, "bp", 256) + 0.8 * swept(noise, centre * 1.7, q * 4.0, "bp", 256)
    return body * np.sin(np.pi * t / duration) ** 1.5


def _pebbles(rng: np.random.Generator) -> np.ndarray:
    duration = rng.uniform(0.6, 1.1)
    n = round(duration * SR)
    out = np.zeros(n)
    time = 0.0
    gain = 1.0
    while time < duration - 0.05:
        k = round(rng.uniform(0.01, 0.03) * SR)
        start = round(time * SR)
        click = bp(rng.standard_normal(k), rng.uniform(1200, 2500), rng.uniform(3500, 7000))
        click *= np.exp(-_time(k) / 0.004) * gain
        out[start : start + k] += click[: n - start]
        time += rng.exponential(0.07)
        gain *= rng.uniform(0.75, 0.95)
    return out


def _pipe_hum(rng: np.random.Generator) -> np.ndarray:
    duration = rng.uniform(4.0, 6.0)
    n = round(duration * SR)
    t = _time(n)
    base = rng.choice([110.0, 123.47, 146.83, 164.81])
    out = np.zeros(n)
    for ratio, amp in ((1.0, 1.0), (2.0, 0.6), (3.0, 0.35), (4.1, 0.2), (5.3, 0.1)):
        out += amp * np.sin(
            2.0 * np.pi * base * ratio * t * (1.0 + 0.002 * np.sin(2.0 * np.pi * 0.3 * t))
        )
    return out * np.sin(np.pi * t / duration) ** 2


def _ring(rng: np.random.Generator) -> np.ndarray:
    return (
        d_metal(rng.uniform(280.0, 520.0), rng.uniform(1.2, 2.0), 1.2, int(rng.integers(0, 99)))
        * 0.8
    )


def _creak(rng: np.random.Generator) -> np.ndarray:
    duration = rng.uniform(0.5, 1.3)
    n = round(duration * SR)
    out = np.zeros(n)
    time = 0.0
    rate = rng.uniform(60.0, 160.0)
    while time < duration - 0.01:
        start = round(time * SR)
        out[start] = rng.uniform(0.4, 1.0)
        time += 1.0 / (rate * rng.uniform(0.7, 1.4))
        rate *= rng.uniform(0.97, 1.03)
    centre = rng.uniform(900.0, 2200.0)
    body = swept(out, centre * (1.0 + 0.3 * np.sin(np.pi * _time(n) / duration)), 6.0, "bp", 128)
    return body * np.sin(np.pi * _time(n) / duration) ** 0.7


def _tinkle(rng: np.random.Generator) -> np.ndarray:
    n = round(1.4 * SR)
    out = np.zeros(n)
    for _ in range(int(rng.integers(3, 7))):
        start = round(rng.uniform(0.0, 0.6) * SR)
        ping = v_glass(rng.uniform(2600.0, 5200.0), 0.8, 0.25, 7.0) * rng.uniform(0.3, 1.0)
        out[start : start + len(ping)] += ping[: n - start]
    return out


def _crack(rng: np.random.Generator) -> np.ndarray:
    n = round(2.5 * SR)
    t = _time(n)
    snap = hp(rng.standard_normal(n), 1500.0) * np.exp(-t / 0.012)
    boom = lp(rng.standard_normal(n), 140.0, 4) * np.exp(-t / 0.5) * 6.0
    return snap + boom


def _lava_bubble(rng: np.random.Generator) -> np.ndarray:
    duration = rng.uniform(0.25, 0.5)
    n = round(duration * SR)
    t = _time(n)
    f = rng.uniform(55.0, 110.0) * (1.0 + 0.8 * t / duration)
    body = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / duration) ** 0.5
    pop = lp(rng.standard_normal(n), 900.0) * np.exp(-np.maximum(t - duration * 0.8, 0) / 0.02)
    pop *= t > duration * 0.8
    return body + 0.6 * pop


def _steam(rng: np.random.Generator) -> np.ndarray:
    duration = rng.uniform(1.0, 2.4)
    n = round(duration * SR)
    t = _time(n)
    hiss = hp(lp(rng.standard_normal(n), 9000.0), rng.uniform(1500.0, 3000.0))
    return hiss * (1.0 - np.exp(-t / 0.03)) * np.exp(-t / (duration * 0.4))


def _boom(rng: np.random.Generator) -> np.ndarray:
    n = round(3.2 * SR)
    t = _time(n)
    return lp(rng.standard_normal(n), 110.0, 4) * (1.0 - np.exp(-t / 0.08)) * np.exp(-t / 0.8) * 5.0


def _clank(rng: np.random.Generator) -> np.ndarray:
    return d_metal(rng.uniform(600.0, 1100.0), rng.uniform(0.4, 0.8), 2.0, int(rng.integers(0, 99)))


def _whale(rng: np.random.Generator) -> np.ndarray:
    duration = rng.uniform(4.0, 7.0)
    f0 = rng.uniform(70.0, 120.0)
    return v_groan(f0, f0 * rng.uniform(0.6, 1.4), duration, int(rng.integers(0, 999)))


def _knock(rng: np.random.Generator) -> np.ndarray:
    n = round(0.8 * SR)
    t = _time(n)
    f = rng.uniform(60.0, 95.0)
    thud = np.sin(2.0 * np.pi * f * t) * np.exp(-t / 0.12)
    resonance = np.sin(2.0 * np.pi * f * 3.7 * t) * np.exp(-t / 0.3) * 0.2
    return lp(thud + resonance + lp(rng.standard_normal(n), 400.0) * np.exp(-t / 0.01), 600.0)


def _rising_bubbles(rng: np.random.Generator) -> np.ndarray:
    duration = rng.uniform(0.9, 1.6)
    n = round(duration * SR)
    out = np.zeros(n)
    time = 0.0
    low = 250.0
    while time < duration - 0.05:
        b = _bubble(rng, low, low * 1.6)
        start = round(time * SR)
        out[start : start + len(b)] += b[: n - start]
        time += rng.exponential(0.06)
        low *= 1.04
    return lp(out, 1800.0)


# (area, kind): (maker, variants, wet)
AMBIENCE_ONE_SHOTS = {
    ("fringe", "drip"): (_drip, 4, 1.0),
    ("fringe", "gust"): (lambda r: _gust(r, 250.0, 1100.0, 2.0), 3, 0.4),
    ("fringe", "pebbles"): (_pebbles, 3, 0.8),
    ("nexus", "plop"): (_plop, 4, 1.0),
    ("nexus", "hum"): (_pipe_hum, 3, 0.8),
    ("nexus", "ring"): (_ring, 3, 1.0),
    ("vaults", "creak"): (_creak, 4, 0.7),
    ("vaults", "tinkle"): (_tinkle, 3, 1.0),
    ("vaults", "crack"): (_crack, 2, 1.0),
    ("kiln", "bubble"): (_lava_bubble, 4, 0.5),
    ("kiln", "steam"): (_steam, 3, 0.5),
    ("kiln", "boom"): (_boom, 2, 0.6),
    ("kiln", "clank"): (_clank, 3, 0.8),
    ("depths", "groan"): (_whale, 3, 0.9),
    ("depths", "knock"): (_knock, 3, 0.9),
    ("depths", "bubbles"): (_rising_bubbles, 3, 0.7),
}


def ambience_one_shots() -> dict[str, np.ndarray]:
    out: dict[str, np.ndarray] = {}
    for (area, kind), (maker, count, wet) in AMBIENCE_ONE_SHOTS.items():
        rng = np.random.default_rng(_stable_seed(f"{area}:{kind}"))
        for index in range(1, count + 1):
            out[f"{area}_{kind}_{index}"] = _space(area, maker(rng), wet) * 0.6
    return out


# --- per-area footsteps --------------------------------------------------------------


def _level(x: np.ndarray, rms_db: float, peak_db: float = -3.0) -> np.ndarray:
    """Authored RMS with a hard peak cap (never clips)."""
    x = _set_rms(x, rms_db)
    peak = float(np.max(np.abs(x)))
    ceiling = 10.0 ** (peak_db / 20.0)
    return x * (ceiling / peak) if peak > ceiling else x


def _thud(rng: np.random.Generator, n: int, freq: float, decay: float, cutoff: float) -> np.ndarray:
    t = _time(n)
    body = np.sin(2.0 * np.pi * freq * (1.0 + 0.4 * np.exp(-t / 0.01)) * t) * np.exp(-t / decay)
    return lp(body + 0.5 * rng.standard_normal(n) * np.exp(-t / (decay * 0.5)), cutoff)


def _grit(rng: np.random.Generator, n: int, low: float, high: float, grains: int) -> np.ndarray:
    out = np.zeros(n)
    for _ in range(grains):
        start = int(rng.integers(0, max(n // 2, 1)))
        k = round(rng.uniform(0.002, 0.008) * SR)
        grain = rng.standard_normal(k) * np.exp(-_time(k) / 0.0015) * rng.uniform(0.3, 1.0)
        stop = min(n, start + k)
        out[start:stop] += grain[: stop - start]
    return bp(out, low, high)


def footstep(area: str, variant: int, landing: bool = False) -> np.ndarray:
    rng = np.random.default_rng(_stable_seed(f"step:{area}:{variant}:{landing}"))
    duration = 0.2 if landing else 0.11
    n = round(duration * SR)
    t = _time(n)
    weight = 1.6 if landing else 1.0
    if area == "fringe":  # packed dirt and gravel
        x = _thud(rng, n, 90.0, 0.025 * weight, 700.0) + 0.7 * _grit(
            rng, n, 1800, 6000, 9 + 6 * landing
        )
    elif area == "nexus":  # wet stone
        splash = bp(rng.standard_normal(n), 1500.0, 7000.0) * np.exp(-t / (0.02 * weight)) * 0.45
        drop = _bubble(rng, 900.0, 1600.0)
        x = _thud(rng, n, 110.0, 0.02 * weight, 900.0) + splash
        x[: len(drop)] += 0.3 * drop
    elif area == "vaults":  # ice and frost crunch
        click = hp(rng.standard_normal(n), 3500.0) * np.exp(-t / 0.003) * 0.6
        ping = np.sin(2.0 * np.pi * rng.uniform(3200, 4600) * t) * np.exp(-t / 0.03) * 0.12
        x = _thud(rng, n, 130.0, 0.015 * weight, 1200.0) * 0.7 + click + ping
        x += 0.9 * _grit(rng, n, 2500, 9000, 14 + 8 * landing)
    elif area == "kiln":  # metal grating over ash
        ring = d_metal(rng.uniform(900.0, 1300.0), 0.09 * weight, 1.2, variant)[:n] * 0.18
        x = _thud(rng, n, 95.0, 0.03 * weight, 800.0)
        x[: len(ring)] += ring
        x += 0.35 * _grit(rng, n, 600, 3000, 6)
    else:  # depths: soft wet silt
        squelch = bp(rng.standard_normal(n), 250.0, 900.0) * np.sin(np.pi * np.clip(t / 0.06, 0, 1))
        x = _thud(rng, n, 70.0, 0.04 * weight, 500.0) + 0.5 * squelch * np.exp(-t / 0.04)
    x = _finish_one_shot(x, 1.0)
    return _level(x, -13.0 if landing else -24.0)


def footsteps() -> dict[str, np.ndarray]:
    out: dict[str, np.ndarray] = {}
    for area in AREA_IDS:
        for variant in (1, 2, 3):
            out[f"{area}_step_{variant}"] = footstep(area, variant)
        out[f"{area}_land"] = footstep(area, 0, True)
    return out


# --- combat feedback cues (requested by the combat lane) -----------------------------


def combat_cues() -> dict[str, np.ndarray]:
    rng = np.random.default_rng(0x434F4D42)  # COMB
    out: dict[str, np.ndarray] = {}

    n = round(0.11 * SR)
    t = _time(n)
    f = 170.0 * (1.0 + 0.8 * np.exp(-t / 0.012))
    body = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.035)
    crunch = bp(rng.standard_normal(n), 500.0, 3200.0) * np.exp(-t / 0.018) * 0.7
    out["enemy_hit"] = _level(_finish_one_shot(np.tanh(1.5 * (body + crunch)), 1.0), -19.0)

    n = round(0.22 * SR)
    t = _time(n)
    clink = sum(
        amp * np.sin(2.0 * np.pi * freq * t) * np.exp(-t / life)
        for freq, amp, life in ((2350.0, 1.0, 0.06), (3710.0, 0.6, 0.04), (5230.0, 0.35, 0.025))
    )
    tick = hp(rng.standard_normal(n), 4000.0) * np.exp(-t / 0.002) * 0.5
    out["armor_clink"] = _level(_finish_one_shot(clink + tick, 1.0), -22.0)

    n = round(0.45 * SR)
    t = _time(n)
    rise = 440.0 * 2.0 ** (t / 0.45 * 1.0)
    chime = np.sin(2.0 * np.pi * np.cumsum(rise) / SR) + 0.4 * np.sin(
        2.0 * np.pi * np.cumsum(rise * 2.5) / SR
    )
    crack = hp(rng.standard_normal(n), 2000.0) * np.exp(-t / 0.01) * 0.6
    out["boss_open"] = _level(
        _finish_one_shot(chime * np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 0.5 + crack, 1.0), -18.0
    )

    n = round(0.26 * SR)
    t = _time(n)
    slam = np.sin(2.0 * np.pi * 70.0 * (1.0 + 0.6 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.07)
    slam += lp(rng.standard_normal(n), 900.0) * np.exp(-t / 0.015)
    out["boss_close"] = _level(_finish_one_shot(np.tanh(2.0 * slam), 1.0), -17.0)

    n = round(0.85 * SR)
    t = _time(n)
    roar = swept(saw(55.0 * (1.0 + 0.3 * np.sin(2 * np.pi * 6 * t)), n) + 0.8 * rng.standard_normal(n),
                 300.0 + 1500.0 * np.exp(-t / 0.25), 2.0, "lp", 128)  # fmt: skip
    impact = d_kick(120.0, 40.0, 0.35, 0.5)
    roar[: len(impact)] += 1.5 * impact[:n]
    out["boss_phase"] = _level(
        _finish_one_shot(np.tanh(1.4 * roar) * np.exp(-t / 0.45), 1.0), -15.0
    )

    n = round(0.32 * SR)
    t = _time(n)
    whoosh = swept(rng.standard_normal(n), 400.0 * 2.0 ** (t / 0.32 * 3.0), 3.0, "bp", 64)
    whine = np.sin(2.0 * np.pi * np.cumsum(300.0 * 2.0 ** (t / 0.32 * 2.0)) / SR) * 0.25
    out["boss_telegraph"] = _level(
        _finish_one_shot((whoosh + whine) * (t / 0.32) ** 1.5, 1.0), -21.0
    )

    n = round(0.6 * SR)
    shatter = np.zeros(n)
    for _ in range(14):
        start = round(rng.uniform(0.0, 0.12) * SR)
        shard = v_glass(rng.uniform(1800.0, 6000.0), 0.4, 0.12, 9.0) * rng.uniform(0.3, 1.0)
        shatter[start : start + len(shard)] += shard[: n - start]
    shatter += hp(rng.standard_normal(n), 2500.0) * np.exp(-_time(n) / 0.02) * 0.8
    out["ice_shatter"] = _level(_finish_one_shot(shatter, 1.0), -18.0)

    n = round(0.9 * SR)
    t = _time(n)
    blast = lp(rng.standard_normal(n), 1800.0) * np.exp(-t / 0.18)
    blast += lp(rng.standard_normal(n), 160.0, 4) * np.exp(-t / 0.35) * 4.0
    kick = d_kick(90.0, 38.0, 0.3, 0.2)[:n]
    blast[: len(kick)] += kick
    out["boss_explosion"] = _level(_finish_one_shot(np.tanh(1.6 * blast), 1.0), -15.0)
    return out


# --- positional environment loops (hazards, water) -----------------------------------

POSITIONAL_LOOP_SECONDS = {
    "fire_loop": 6.0,
    "lava_loop": 8.0,
    "water_loop": 8.0,
    "cold_ambience": 8.0,
    "depths_pressure": 8.0,
}


def positional_loops() -> dict[str, np.ndarray]:
    """Mono loops for AudioStreamPlayer2D emitters; exactly periodic, no seam."""
    out: dict[str, np.ndarray] = {}
    rng = np.random.default_rng(0x504F5331)

    def mono_scatter(n: int, rate: float, maker) -> np.ndarray:
        return scatter(n, rng, rate, maker, False)

    n = round(POSITIONAL_LOOP_SECONDS["fire_loop"] * SR)
    body = _periodic_noise(n, rng, 150.0, 3500.0)
    body *= 0.6 + 0.4 * loop_lfo(n, rng, (5, 9, 14, 23))
    crackle = circular(lambda x: bp(x, 1200.0, 7000.0, 1), mono_scatter(n, 30.0, _crackle))
    out["fire_loop"] = _finish_loop(
        body / np.std(body) + 3.0 * crackle / max(np.std(crackle), 1e-9) * 0.3, -27.0
    )

    n = round(POSITIONAL_LOOP_SECONDS["lava_loop"] * SR)
    glow = _periodic_noise(n, rng, 20.0, 380.0)
    blorps = mono_scatter(n, 1.6, _lava_bubble)
    out["lava_loop"] = _finish_loop(
        glow / np.std(glow) * 0.5 + blorps / max(np.std(blorps), 1e-9) * 0.6, -26.5
    )

    n = round(POSITIONAL_LOOP_SECONDS["water_loop"] * SR)
    stream = _periodic_noise(n, rng, 250.0, 3000.0)
    stream *= 0.7 + 0.3 * loop_lfo(n, rng, (6, 11, 19))
    babble = mono_scatter(n, 90.0, _bubble)
    out["water_loop"] = _finish_loop(
        stream / np.std(stream) + 0.8 * babble / max(np.std(babble), 1e-9), -28.0
    )

    n = round(POSITIONAL_LOOP_SECONDS["cold_ambience"] * SR)
    breath = _periodic_noise(n, rng, 500.0, 6000.0) * (0.2 + 0.8 * loop_lfo(n, rng, (2, 3, 5)) ** 2)
    tinkles = mono_scatter(n, 0.5, lambda r: v_glass(r.uniform(2500, 5000), 0.8, 0.2, 7.0))
    out["cold_ambience"] = _finish_loop(
        breath / np.std(breath) + 0.5 * tinkles / max(np.std(tinkles), 1e-9), -29.0
    )

    n = round(POSITIONAL_LOOP_SECONDS["depths_pressure"] * SR)
    pressure = _periodic_noise(n, rng, 12.0, 160.0) * (0.6 + 0.4 * loop_lfo(n, rng, (1, 2, 3)))
    t = np.arange(n) / n
    pressure = pressure / np.std(pressure) + 0.6 * np.sin(2.0 * np.pi * round(31.0 * n / SR) * t)
    out["depths_pressure"] = _finish_loop(pressure, -25.5)
    return out


def sfx() -> dict[str, np.ndarray]:
    """Generate movement, combat and pickup SFX from an independent seed."""
    rng = np.random.default_rng(SFX_SEED)
    out: dict[str, np.ndarray] = {}
    out["jump"] = soft_jump()
    # Keep stream position stable for existing non-jump SFX while jump owns its noise seed.
    rng.standard_normal(round(0.16 * SR))
    out["land"] = soft_land()
    rng.standard_normal(round(0.075 * SR))
    out["step"] = soft_step(0)
    out["step_2"] = soft_step(1)
    out["step_3"] = soft_step(2)
    out["beam_fire"] = softened_beam_fire()
    # Preserve the established shared RNG position so unrelated SFX stay byte-identical.
    rng.standard_normal(round(0.25 * SR))
    out["missile_fire"] = softened_missile_fire()
    rng.standard_normal(round(0.42 * SR))
    # Immune-beam pip: short, dry, and quiet, with one weak inharmonic partial.
    rng.standard_normal(round(0.48 * SR))
    p = np.arange(round(0.09 * SR)) / SR
    attack = 1.0 - np.exp(-p / 0.00065)
    decay = np.exp(-p * 48.0)
    tail = np.ones_like(p)
    tail_start = 0.078
    fading = p >= tail_start
    tail[fading] = 0.5 * (1.0 + np.cos(np.pi * (p[fading] - tail_start) / (0.09 - tail_start)))
    out["beam_ricochet"] = (
        (np.sin(2 * np.pi * 1510 * p) + 0.10 * np.sin(2 * np.pi * 2825 * p)) * attack * decay * tail
    )
    p = np.arange(round(0.34 * SR)) / SR
    out["missile_hit"] = (
        0.7 * lowpass(rng.standard_normal(p.size), 1350)
        + 0.45 * np.sin(2 * np.pi * (92 + 30 * p) * p)
    ) * np.exp(-p * 8.5)
    p = np.arange(round(0.52 * SR)) / SR
    out["enemy_death"] = (
        lowpass(rng.standard_normal(p.size), 2100) + 0.35 * np.sin(2 * np.pi * (340 - 260 * p) * p)
    ) * np.exp(-p * 5.4)

    def pickup(freqs: list[float], colour: float) -> np.ndarray:
        track = np.zeros(round(0.78 * SR))
        for j, frequency in enumerate(freqs):
            q = np.arange(round(0.32 * SR)) / SR
            x = (
                np.sin(2 * np.pi * frequency * q + colour * np.sin(2 * np.pi * frequency * 2 * q))
                + 0.22 * np.sin(2 * np.pi * frequency * 3.03 * q)
            ) * np.exp(-q * 5.8)
            add_at(track, x, j * 0.14)
        return delay(track, 0.11, 0.28, 2)

    out["orb_pickup"] = pickup([392.00, 523.25, 698.46, 932.33], 1.4)
    out["weapon_pickup"] = pickup([329.63, 493.88, 739.99, 987.77], 2.4)
    p = np.arange(round(0.30 * SR)) / SR
    out["slip_in"] = np.sin(
        2 * np.pi * (310 - 210 * p) * p + 1.8 * np.sin(2 * np.pi * 110 * p)
    ) * np.exp(-p * 8) + 0.17 * lowpass(rng.standard_normal(p.size), 900) * np.exp(-p * 10)
    out["slip_out"] = np.sin(
        2 * np.pi * (105 + 420 * p) * p + 1.2 * np.sin(2 * np.pi * 180 * p)
    ) * np.exp(-p * 7) + 0.12 * highpass(rng.standard_normal(p.size), 1800) * np.exp(-p * 11)
    out["player_hurt"] = restrained_player_hurt()
    rng.standard_normal(round(0.36 * SR))
    p = np.arange(round(0.88 * SR)) / SR
    collapse = np.sin(2 * np.pi * (196 - 112 * p) * p + 0.7 * np.sin(2 * np.pi * 23 * p))
    pulse = 0.42 * np.sin(2 * np.pi * 49 * p) * (1.0 - np.exp(-p * 16.0))
    debris = 0.22 * lowpass(rng.standard_normal(p.size), 1250.0)
    out["player_death"] = (
        (collapse + pulse + debris) * _soft_envelope(p, 0.88, 0.006, 0.16) * np.exp(-p * 3.6)
    )
    return out


def dev_sfx() -> dict[str, np.ndarray]:
    """Independent seed: adding dev sounds never changes existing movement audio."""
    rng = np.random.default_rng(DEV_SFX_SEED)
    output: dict[str, np.ndarray] = {}
    for name, duration, frequency, colour in [
        ("bomb_place", 0.12, 210, 0.15),
        ("bomb_explode", 0.48, 72, 0.75),
        ("freeze", 0.42, 1450, 0.12),
        ("wave_fire", 0.27, 420, 0.08),
        ("dash_strike", 0.24, 620, 0.24),
        ("tank_pickup", 0.70, 330, 0.02),
        ("boss_defeated", 1.2, 110, 0.32),
    ]:
        t = np.arange(round(duration * SR)) / SR
        attack = np.minimum(t / 0.008, 1)
        release = np.minimum((duration - t) / 0.06, 1)
        envelope = attack * release * np.exp(-t * (3 / duration))
        pitched = np.sin(2 * np.pi * frequency * t + 1.4 * np.sin(2 * np.pi * 7 * t))
        texture = lowpass(rng.standard_normal(t.size), 1900 if name == "freeze" else 650)
        output[name] = (pitched + colour * texture) * envelope
    output["bomb_place"] = softened_bomb_place()
    return output


def flux_sfx() -> dict[str, np.ndarray]:
    """Original Flux cues: mineral/electrical family with restrained transients."""
    rng = np.random.default_rng(FLUX_SFX_SEED)
    output: dict[str, np.ndarray] = {}

    duration = 0.25
    t = np.arange(round(duration * SR)) / SR
    glass = sum(
        gain * np.sin(2.0 * np.pi * frequency * t + phase)
        for frequency, gain, phase in (
            (934.0, 0.58, 0.0),
            (1477.0, 0.31, 0.7),
            (2213.0, 0.16, 1.4),
        )
    )
    mint_air = highpass(lowpass(rng.standard_normal(t.size), 5100.0), 1500.0)
    output["flux_shield"] = _finish_one_shot(
        (glass * np.exp(-t * 12.0) + 0.11 * mint_air * np.exp(-t * 19.0)), 0.34
    )

    duration = 0.10
    t = np.arange(round(duration * SR)) / SR
    impulse = np.sin(2.0 * np.pi * (285.0 * t + 1650.0 * t * t))
    amber_grit = highpass(lowpass(rng.standard_normal(t.size), 4400.0), 650.0)
    output["flux_burst"] = _finish_one_shot(
        (0.82 * impulse + 0.12 * amber_grit) * np.exp(-t * 34.0), 0.32
    )

    duration = 0.75
    t = np.arange(round(duration * SR)) / SR
    outbound_frequency = 1280.0 - 780.0 * np.clip(t / 0.43, 0.0, 1.0)
    outbound_phase = 2.0 * np.pi * np.cumsum(outbound_frequency) / SR
    returning_t = np.clip(t - 0.43, 0.0, None)
    return_frequency = 520.0 + 610.0 * np.clip(returning_t / 0.24, 0.0, 1.0)
    return_phase = 2.0 * np.pi * np.cumsum(return_frequency) / SR
    outbound = np.sin(outbound_phase) * np.exp(-t * 5.4)
    returning = np.sin(return_phase + 0.6) * np.exp(-returning_t * 8.0) * (t >= 0.43)
    mineral = 0.18 * np.sin(outbound_phase * 2.41 + 0.3) * np.exp(-t * 7.0)
    output["echo_scan"] = _finish_one_shot(outbound + 0.55 * returning + mineral, 0.33)

    duration = 0.28
    t = np.arange(round(duration * SR)) / SR
    frequency = 118.0 - 74.0 * np.clip(t / duration, 0.0, 1.0)
    phase = 2.0 * np.pi * np.cumsum(frequency) / SR
    dry_noise = lowpass(rng.standard_normal(t.size), 520.0)
    collapse = (np.sin(phase) + 0.16 * dry_noise) * np.exp(-t * 13.0)
    output["flux_empty"] = _finish_one_shot(collapse, 0.30)
    return output


def environment_sfx() -> dict[str, np.ndarray]:
    """Original mono positional ambience; loops use periodic components only."""
    rng = np.random.default_rng(ENVIRONMENT_SFX_SEED)
    output: dict[str, np.ndarray] = {}

    n = round(LOOP_DURATIONS["fire_loop"] * SR)
    t = np.arange(n) / SR
    fire = 0.65 * _periodic_noise(n, rng, 180.0, 4200.0)
    for center, width, gain in ((0.37, 0.018, 1.4), (1.12, 0.012, 1.1), (2.31, 0.021, 1.5)):
        fire += gain * np.exp(-(((t - center) / width) ** 2)) * rng.standard_normal(n)
    output["fire_loop"] = _finish_loop(lowpass(highpass(fire, 120.0), 5200.0), -27.0)

    n = round(LOOP_DURATIONS["lava_loop"] * SR)
    t = np.arange(n) / SR
    lava = 0.5 * _periodic_noise(n, rng, 18.0, 430.0)
    for center, frequency in ((0.44, 73.0), (1.36, 58.0), (2.42, 82.0)):
        local = t - center
        bubble = np.sin(2.0 * np.pi * frequency * local) * np.exp(-(((local) / 0.13) ** 2))
        lava += bubble
    output["lava_loop"] = _finish_loop(lowpass(lava, 620.0), -26.5)

    n = round(LOOP_DURATIONS["water_loop"] * SR)
    t = np.arange(n) / SR
    water = _periodic_noise(n, rng, 90.0, 2600.0)
    water *= (
        0.78 + 0.17 * np.sin(2.0 * np.pi * t / 4.0) + 0.05 * np.sin(2.0 * np.pi * 3.0 * t / 4.0)
    )
    output["water_loop"] = _finish_loop(water, -28.0)

    n = round(LOOP_DURATIONS["cold_ambience"] * SR)
    t = np.arange(n) / SR
    breath = _periodic_noise(n, rng, 350.0, 5100.0)
    sparse = 0.22 + 0.78 * (
        np.exp(-(((t - 0.92) / 0.34) ** 2)) + np.exp(-(((t - 2.83) / 0.43) ** 2))
    )
    ice = breath * sparse + 0.08 * np.sin(2.0 * np.pi * 1733.0 * t) * np.exp(
        -(((t - 2.1) / 0.16) ** 2)
    )
    output["cold_ambience"] = _finish_loop(ice, -29.0)

    n = round(LOOP_DURATIONS["depths_pressure"] * SR)
    t = np.arange(n) / SR
    pressure = _periodic_noise(n, rng, 12.0, 180.0)
    pressure += (
        0.48 * np.sin(2.0 * np.pi * 31.0 * t) * (0.72 + 0.18 * np.sin(2.0 * np.pi * t / 4.0))
    )
    output["depths_pressure"] = _finish_loop(lowpass(pressure, 230.0), -25.5)

    duration = 1.0
    t = np.arange(round(duration * SR)) / SR
    steam = highpass(lowpass_steep(rng.standard_normal(t.size), 5200.0, 2), 480.0)
    release = (1.0 - np.exp(-t * 55.0)) * np.exp(-t * 4.7)
    output["steam_vent"] = _finish_one_shot(steam * release, 0.31)
    return output


def write_flux_sfx() -> None:
    for name, audio in flux_sfx().items():
        write_wav_absolute(SFX / f"{name}.wav", audio)


def write_environment_sfx() -> None:
    """Positional hazard/water loops plus the established steam burst."""
    for name, audio in positional_loops().items():
        write_wav_absolute(SFX / f"{name}.wav", audio)
    write_wav_absolute(SFX / "steam_vent.wav", environment_sfx()["steam_vent"])


def write_dev_sfx() -> None:
    for name, audio in dev_sfx().items():
        if name == "bomb_place":
            write_wav_absolute(SFX / f"{name}.wav", audio)
        else:
            write_wav(SFX / f"{name}.wav", audio, 0.52)


def write_ogg(path: Path, x: np.ndarray, quality: str, tags: dict[str, str]) -> None:
    """Encode with FFmpeg's libvorbis and pin the stream serial for reproducible bytes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.stem}.wav")
    write_wav_absolute(temp, x)
    command = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(temp), "-c:a", "libvorbis"]
    command += ["-q:a", quality]
    for key, value in tags.items():
        command += ["-metadata", f"{key}={value}"]
    subprocess.run([*command, str(path)], check=True)
    stabilize_ogg_serial(path, _stable_seed(path.name))
    temp.unlink()


def write_music(ids: list[str] | None = None) -> None:
    for music_id in ids or MUSIC_IDS:
        audio = MUSIC_GENERATORS[music_id]()
        tags = {"MUSIC_ID": music_id}
        if music_id not in NON_LOOPING_MUSIC:
            tags |= {"LOOPSTART": "0", "LOOPLENGTH": str(len(audio))}
        write_ogg(MUSIC / f"{music_id}.ogg", audio, MUSIC_OGG_QUALITY, tags)
        print(f"music/{music_id}.ogg: {len(audio) / SR:.1f}s")


def write_ambience() -> None:
    for area in AREA_IDS:
        bed = ambience_bed(area)
        tags = {"LOOPSTART": "0", "LOOPLENGTH": str(len(bed))}
        write_ogg(AMBIENCE / f"{area}_bed.ogg", bed, "2", tags)
    for name, audio in ambience_one_shots().items():
        write_ogg(AMBIENCE / f"{name}.ogg", audio, "3", {})
    print(f"ambience: {len(AREA_IDS)} beds and one-shot layers")


# --- D20 surprise enemy cues (enemies lane; played positionally by SurpriseSfx) -------

ENEMY_SFX = SFX / "enemies"


def _chirp(n: int, f0: float, f1: float, tau: float) -> np.ndarray:
    t = _time(n)
    f = f1 + (f0 - f1) * np.exp(-t / tau)
    return np.sin(2.0 * np.pi * np.cumsum(f) / SR)


def _screech(rng: np.random.Generator, duration: float, f0: float, f1: float) -> np.ndarray:
    n = round(duration * SR)
    t = _time(n)
    f = f0 + (f1 - f0) * t / duration + 180.0 * np.sin(2.0 * np.pi * 38.0 * t)
    tone = np.sin(2.0 * np.pi * np.cumsum(f) / SR) + 0.35 * np.sin(4.0 * np.pi * np.cumsum(f) / SR)
    air = bp(rng.standard_normal(n), 2500.0, 9000.0) * 0.25
    return (tone + air) * np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 0.6


def _flutter(rng: np.random.Generator, duration: float, rate: float, gain: float) -> np.ndarray:
    n = round(duration * SR)
    t = _time(n)
    beats = 0.5 + 0.5 * np.sign(np.sin(2.0 * np.pi * rate * t))
    leather = bp(rng.standard_normal(n), 350.0, 2400.0) * lp(beats, 60.0)
    return leather * gain


def _growl(rng: np.random.Generator, duration: float, pitch: float, rough: float) -> np.ndarray:
    n = round(duration * SR)
    t = _time(n)
    f = (
        pitch
        * (1.0 + 0.08 * np.sin(2.0 * np.pi * 5.0 * t))
        * (1.0 + rough * rng.standard_normal(n) * 0.02)
    )
    voice = saw(f, n) * (0.6 + 0.4 * np.sin(2.0 * np.pi * 23.0 * t) ** 2)
    voice = swept(voice + 0.4 * rng.standard_normal(n), 380.0 + 900.0 * t / duration, 3.0, "lp", 64)
    return voice * np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 0.5


def enemy_cues() -> dict[str, np.ndarray]:
    rng = np.random.default_rng(_stable_seed("enemies:d20"))
    out: dict[str, np.ndarray] = {}

    # Bat swarm: leathery rustle, a burst of wings with overlapping squeaks, dive whoosh.
    rustle = _flutter(rng, 0.45, 19.0, 1.0) * np.linspace(0.3, 1.0, round(0.45 * SR))
    out["bat_rustle"] = _level(_finish_one_shot(rustle, 1.0), -26.0)
    burst = _flutter(rng, 0.9, 27.0, 1.0) * np.exp(-_time(round(0.9 * SR)) / 0.4)
    for _ in range(6):
        squeak = _screech(
            rng, rng.uniform(0.05, 0.1), rng.uniform(3800, 5200), rng.uniform(2600, 3600)
        )
        start = round(rng.uniform(0.0, 0.45) * SR)
        burst[start : start + len(squeak)] += 0.35 * squeak[: len(burst) - start]
    out["bat_burst"] = _level(_finish_one_shot(burst, 1.0), -19.0)
    out["bat_screech"] = _level(_finish_one_shot(_screech(rng, 0.12, 4600.0, 3100.0), 1.0), -25.0)
    n = round(0.3 * SR)
    whoosh = swept(rng.standard_normal(n), 700.0 + 2600.0 * _time(n) / 0.3, 2.0, "bp", 64)
    out["bat_swoop"] = _level(_finish_one_shot(whoosh * np.sin(np.pi * _time(n) / 0.3), 1.0), -27.0)

    # Mimic: stony rattle, snapping lunge, clicky skitter.
    n = round(0.34 * SR)
    rattle = np.zeros(n)
    for start in range(0, n - round(0.05 * SR), round(0.045 * SR)):
        knock = _thud(rng, round(0.05 * SR), rng.uniform(140, 260), 0.02, 2200.0)
        rattle[start : start + len(knock)] += knock
    out["mimic_rattle"] = _level(
        _finish_one_shot(rattle + 0.6 * _grit(rng, n, 1500, 6000, 18), 1.0), -21.0
    )
    n = round(0.3 * SR)
    snap = _thud(rng, n, 90.0, 0.06, 900.0) + hp(rng.standard_normal(n), 2500.0) * np.exp(
        -_time(n) / 0.008
    )
    out["mimic_lunge"] = _level(_finish_one_shot(np.tanh(2.0 * snap), 1.0), -17.0)
    out["mimic_skitter"] = _level(
        _finish_one_shot(_grit(rng, round(0.18 * SR), 2000, 8000, 12), 1.0), -27.0
    )

    # Drop spider: creaking silk, a fast zip down, a ratcheting climb.
    n = round(0.32 * SR)
    creak = sum(
        np.sin(
            2.0 * np.pi * np.cumsum(np.full(n, f) + 40.0 * np.sin(2 * np.pi * 7 * _time(n))) / SR
        )
        * np.exp(-_time(n) / 0.12)
        for f in (620.0, 910.0)
    )
    creak *= 0.6 + 0.4 * np.sign(np.sin(2.0 * np.pi * 31.0 * _time(n)))
    out["spider_creak"] = _level(_finish_one_shot(bp(creak, 400.0, 3000.0), 1.0), -25.0)
    n = round(0.4 * SR)
    zip_ = swept(rng.standard_normal(n), 4500.0 - 3500.0 * _time(n) / 0.4, 4.0, "bp", 64)
    out["spider_drop"] = _level(_finish_one_shot(zip_ * np.exp(-_time(n) / 0.25), 1.0), -21.0)
    out["spider_climb"] = _level(
        _finish_one_shot(_grit(rng, round(0.6 * SR), 1200, 5000, 26) * 0.8, 1.0), -29.0
    )

    # Surface eel: rising bubbles, an eruptive strike, a sinking splash.
    n = round(0.7 * SR)
    bubbles = np.zeros(n)
    for _ in range(26):
        b = _bubble(rng, 300.0, 1400.0)
        start = round(rng.uniform(0.0, 0.62) * SR)
        bubbles[start : start + len(b)] += b[: n - start] * rng.uniform(0.3, 1.0)
    bubbles += lp(rng.standard_normal(n), 300.0) * np.linspace(0.1, 0.6, n)
    out["eel_bubble"] = _level(_finish_one_shot(bubbles, 1.0), -21.0)
    n = round(0.55 * SR)
    burst = lp(rng.standard_normal(n), 2600.0) * np.exp(-_time(n) / 0.12)
    burst += d_kick(110.0, 45.0, 0.2, 0.3)[:n] * 1.4
    hiss = 0.5 * _screech(rng, 0.25, 900.0, 520.0)
    burst[: len(hiss)] += hiss
    out["eel_strike"] = _level(_finish_one_shot(np.tanh(1.6 * burst), 1.0), -16.0)
    n = round(0.45 * SR)
    splash = bp(rng.standard_normal(n), 400.0, 5000.0) * np.exp(-_time(n) / 0.09)
    out["eel_splash"] = _level(_finish_one_shot(splash, 1.0), -22.0)

    # Stalker: low growl, pounce snarl, hiss, death wail.
    out["stalker_growl"] = _level(_finish_one_shot(_growl(rng, 0.55, 62.0, 1.0), 1.0), -18.0)
    n = round(0.35 * SR)
    snarl = _growl(rng, 0.35, 95.0, 2.0) + swept(rng.standard_normal(n), 900.0, 2.0, "bp", 64) * 0.4
    out["stalker_pounce"] = _level(_finish_one_shot(np.tanh(1.5 * snarl), 1.0), -17.0)
    n = round(0.4 * SR)
    hiss = hp(rng.standard_normal(n), 3000.0) * np.sin(np.pi * _time(n) / 0.4) ** 0.4
    out["stalker_hiss"] = _level(_finish_one_shot(hiss, 1.0), -24.0)
    n = round(1.1 * SR)
    wail = _growl(rng, 1.1, 120.0, 1.5) * np.exp(-_time(n) / 0.6)
    wail += 0.4 * _chirp(n, 420.0, 90.0, 0.35) * np.exp(-_time(n) / 0.5)
    out["stalker_death"] = _level(_finish_one_shot(wail, 1.0), -17.0)

    # Chasm sniper: shell slide, rising charge whine, lock beeps, sharp crack.
    n = round(0.3 * SR)
    slide = _grit(rng, n, 800, 3000, 14) + _thud(rng, n, 120.0, 0.05, 700.0) * 0.6
    out["sniper_rise"] = _level(_finish_one_shot(slide, 1.0), -25.0)
    n = round(0.8 * SR)
    t = _time(n)
    whine = np.sin(2.0 * np.pi * np.cumsum(500.0 * 2.0 ** (t / 0.8 * 1.5)) / SR) * (t / 0.8) ** 1.2
    out["sniper_charge"] = _level(_finish_one_shot(whine * 0.8, 1.0), -27.0)
    n = round(0.34 * SR)
    t = _time(n)
    beeps = np.sin(2.0 * np.pi * 2100.0 * t) * (np.sin(2.0 * np.pi * 18.0 * t) > 0.2)
    out["sniper_lock"] = _level(_finish_one_shot(beeps, 1.0), -24.0)
    n = round(0.35 * SR)
    t = _time(n)
    crack = hp(rng.standard_normal(n), 1500.0) * np.exp(-t / 0.012) * 1.5
    crack += _chirp(n, 3200.0, 600.0, 0.03) * np.exp(-t / 0.08)
    out["sniper_fire"] = _level(_finish_one_shot(np.tanh(1.8 * crack), 1.0), -17.0)

    # Aggression-pass wind-ups for existing enemies.
    n = round(0.42 * SR)
    t = _time(n)
    scrape = _thud(rng, n, 70.0, 0.2, 500.0) + 0.5 * _grit(rng, n, 400, 2500, 10)
    scrape += 0.3 * np.sin(2.0 * np.pi * np.cumsum(90.0 + 60.0 * t / 0.42) / SR)
    out["guard_charge"] = _level(_finish_one_shot(scrape, 1.0), -20.0)
    out["parasite_lunge"] = _level(_finish_one_shot(_screech(rng, 0.2, 1800.0, 3400.0), 1.0), -27.0)
    out["diver_screech"] = _level(_finish_one_shot(_screech(rng, 0.22, 2600.0, 1500.0), 1.0), -25.0)
    return out


def write_enemy_sfx() -> None:
    ENEMY_SFX.mkdir(parents=True, exist_ok=True)
    for name, audio in enemy_cues().items():
        write_wav_absolute(ENEMY_SFX / f"{name}.wav", audio)


# --- Living environment (D21, worldfx lane) --------------------------------------------------

WORLD_SFX_SEED = 0x574F524C  # WORL
WORLD_LOOP_SECONDS = 4.0


def _world_rng(salt: int) -> np.random.Generator:
    return np.random.default_rng(WORLD_SFX_SEED + salt)


def _decay(n: int, seconds: float) -> np.ndarray:
    return np.exp(-np.arange(n) / SR / max(seconds, 1e-4))


def world_slam() -> np.ndarray:
    """Heavy stone slab hitting stone: sub thump, gritty crunch, short rubble tail."""
    rng = _world_rng(1)
    n = round(0.9 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (46 + 60 * np.exp(-t * 30)) * t) * _decay(n, 0.16)
    crunch = lp(hp(rng.standard_normal(n), 180), 2400) * _decay(n, 0.07)
    rubble = np.zeros(n)
    for _ in range(18):
        start = int(rng.uniform(0.03, 0.55) * SR)
        length = int(rng.uniform(0.01, 0.035) * SR)
        grain = bp(rng.standard_normal(length), 600, 3200) * _decay(length, 0.008)
        rubble[start : start + length] += grain[: n - start] * rng.uniform(0.1, 0.3)
    return _finish_one_shot(1.0 * thump + 0.55 * crunch + rubble, 0.8)


def world_rumble() -> np.ndarray:
    """Low grinding rumble used for telegraphs, sealing and floods."""
    rng = _world_rng(2)
    n = round(1.3 * SR)
    t = np.arange(n) / SR
    body = lp(rng.standard_normal(n), 140, 4) * 3.0
    grind = bp(rng.standard_normal(n), 250, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t))
    shape = _soft_envelope(t, 1.3, 0.25, 0.5)
    return _finish_one_shot((body + 0.25 * grind) * shape, 0.62)


def world_crack() -> np.ndarray:
    """Dry stone crack: a few sharp ticks with a brittle high tail."""
    rng = _world_rng(3)
    n = round(0.32 * SR)
    x = np.zeros(n)
    for index, offset in enumerate((0.0, 0.035, 0.06, 0.11)):
        start = int(offset * SR)
        length = int(0.03 * SR)
        grain = hp(rng.standard_normal(length), 1400) * _decay(length, 0.006)
        x[start : start + length] += grain * (1.0 - 0.18 * index)
    x += bp(rng.standard_normal(n), 900, 5000) * _decay(n, 0.05) * 0.2
    return _finish_one_shot(x, 0.55)


def world_crumble() -> np.ndarray:
    """Tile breaking apart: crunch plus falling pebbles."""
    rng = _world_rng(4)
    n = round(0.85 * SR)
    t = np.arange(n) / SR
    crunch = lp(hp(rng.standard_normal(n), 120), 1800) * _decay(n, 0.09)
    thud = np.sin(2 * np.pi * (70 + 40 * np.exp(-t * 25)) * t) * _decay(n, 0.1)
    pebbles = np.zeros(n)
    for _ in range(26):
        start = int(rng.uniform(0.05, 0.75) * SR)
        length = int(rng.uniform(0.006, 0.02) * SR)
        grain = bp(rng.standard_normal(length), 1200, 5200) * _decay(length, 0.004)
        pebbles[start : start + length] += grain[: n - start] * rng.uniform(0.08, 0.25)
    return _finish_one_shot(0.8 * crunch + 0.6 * thud + pebbles, 0.66)


def world_shatter(ice: bool) -> np.ndarray:
    """Spike shattering on the floor; crystalline ring for ice/crystal areas."""
    rng = _world_rng(5 if not ice else 6)
    n = round(0.8 * SR)
    t = np.arange(n) / SR
    burst = hp(rng.standard_normal(n), 700 if not ice else 2000) * _decay(n, 0.05)
    thud = np.sin(2 * np.pi * (90 + 50 * np.exp(-t * 30)) * t) * _decay(n, 0.08)
    ring = np.zeros(n)
    if ice:
        for freq in (2350.0, 3120.0, 4480.0, 5230.0):
            ring += np.sin(2 * np.pi * freq * t + rng.uniform(0, 6.28)) * _decay(n, 0.22)
    shards = np.zeros(n)
    for _ in range(20):
        start = int(rng.uniform(0.02, 0.6) * SR)
        length = int(rng.uniform(0.004, 0.015) * SR)
        grain = hp(rng.standard_normal(length), 2500) * _decay(length, 0.003)
        shards[start : start + length] += grain[: n - start] * rng.uniform(0.1, 0.3)
    return _finish_one_shot(0.7 * burst + 0.5 * thud + 0.12 * ring + shards, 0.7)


def world_tick() -> np.ndarray:
    """Countdown tick: short resonant stone-and-crystal click."""
    n = round(0.16 * SR)
    t = np.arange(n) / SR
    click = np.sin(2 * np.pi * 1760 * t) * _decay(n, 0.018)
    body = np.sin(2 * np.pi * 440 * t) * _decay(n, 0.04)
    return _finish_one_shot(0.7 * click + 0.5 * body, 0.5)


def world_door_open() -> np.ndarray:
    """Slab sliding up fast into the rock: rising grind with a clunk."""
    rng = _world_rng(7)
    n = round(0.5 * SR)
    t = np.arange(n) / SR
    grind = bp(rng.standard_normal(n), 200, 1400) * _soft_envelope(t, 0.5, 0.02, 0.2)
    sweep = np.sin(2 * np.pi * np.cumsum(90 + 140 * t / 0.5) / SR) * _soft_envelope(
        t, 0.5, 0.02, 0.25
    )
    clunk = np.sin(2 * np.pi * 120 * t) * _decay(n, 0.05)
    return _finish_one_shot(0.6 * grind + 0.5 * sweep + 0.4 * clunk, 0.6)


def world_unlock() -> np.ndarray:
    """Calm resolving chime when an arena clears or a timed door latches."""
    n = round(1.4 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for index, freq in enumerate((392.0, 587.33, 783.99)):
        start = int(index * 0.09 * SR)
        partial = np.sin(2 * np.pi * freq * t[: n - start]) + 0.25 * np.sin(
            2 * np.pi * freq * 2.01 * t[: n - start]
        )
        x[start:] += partial * _decay(n - start, 0.5) * (1.0 - 0.15 * index)
    return _finish_one_shot(x, 0.5)


def world_emerge() -> np.ndarray:
    """Enemy bursting out of rock: muffled whoomp with scattering grit."""
    rng = _world_rng(8)
    n = round(0.6 * SR)
    t = np.arange(n) / SR
    whoomp = np.sin(2 * np.pi * (60 + 110 * np.exp(-t * 18)) * t) * _decay(n, 0.12)
    air = lp(rng.standard_normal(n), 900) * _soft_envelope(t, 0.6, 0.05, 0.4)
    grit = bp(rng.standard_normal(n), 1500, 4500) * _decay(n, 0.08)
    return _finish_one_shot(whoomp + 0.5 * air + 0.3 * grit, 0.66)


def world_loop(kind: str) -> np.ndarray:
    """Seamless positional loop: `wind` (hollow gusting air) or `steam` (hissing column)."""
    rng = _world_rng(20 if kind == "wind" else 21)
    n = round(WORLD_LOOP_SECONDS * SR)
    t = np.arange(n) / SR
    if kind == "wind":
        noise = _periodic_noise(n, rng, 120.0, 1400.0)
        gust = 0.65 + 0.35 * np.sin(2 * np.pi * t / WORLD_LOOP_SECONDS * 2)
        whistle = np.sin(2 * np.pi * 620 * t + 2.0 * np.sin(2 * np.pi * t / WORLD_LOOP_SECONDS))
        x = noise * gust + 0.015 * whistle * gust
    else:
        noise = _periodic_noise(n, rng, 1800.0, 9000.0)
        low = _periodic_noise(n, rng, 60.0, 400.0)
        flutter = 0.8 + 0.2 * np.sin(2 * np.pi * t / WORLD_LOOP_SECONDS * 8)
        x = noise * flutter + 0.6 * low
    return _finish_loop(x, -24.0)


def world_sfx() -> dict[str, np.ndarray]:
    return {
        "world_slam": world_slam(),
        "world_rumble": world_rumble(),
        "world_crack": world_crack(),
        "world_crumble": world_crumble(),
        "world_shatter": world_shatter(False),
        "world_shatter_ice": world_shatter(True),
        "world_tick": world_tick(),
        "world_door_open": world_door_open(),
        "world_unlock": world_unlock(),
        "world_emerge": world_emerge(),
        "world_wind": world_loop("wind"),
        "world_steam": world_loop("steam"),
    }


def write_world_sfx() -> None:
    for name, audio in world_sfx().items():
        write_wav_absolute(SFX / f"{name}.wav", audio)


def slipstream_trickle() -> np.ndarray:
    """Seamless 2 s loop of small bubbling water for the Slipstream form."""
    rng = np.random.default_rng(0x534C4950)
    n = round(2.0 * SR)
    track = np.zeros(n)
    for _ in range(46):
        start = int(rng.integers(0, n))
        length = round(rng.uniform(0.018, 0.05) * SR)
        q = np.arange(length) / SR
        base = rng.uniform(700.0, 1900.0)
        bubble = np.sin(2 * np.pi * (base + base * 1.6 * q / q[-1]) * q) * np.exp(-q * 70.0)
        index = (start + np.arange(length)) % n
        track[index] += bubble * rng.uniform(0.25, 1.0)
    wash = _periodic_noise(n, rng, 220.0, 2400.0)
    return _finish_loop(track + 0.35 * wash, -30.0)


def write_sfx() -> None:
    SFX.mkdir(parents=True, exist_ok=True)
    for name, audio in sfx().items():
        if name in {
            "land",
            "step",
            "step_2",
            "step_3",
            "jump",
            "player_hurt",
            "beam_fire",
            "missile_fire",
        }:
            write_wav_absolute(SFX / f"{name}.wav", audio)
        else:
            write_wav(SFX / f"{name}.wav", audio, 0.44 if name == "beam_ricochet" else 0.88)
    write_dev_sfx()
    write_flux_sfx()
    write_environment_sfx()
    write_world_sfx()
    write_wav(SFX / "weapon_switch.wav", weapon_switch(), 0.5)
    write_wav(SFX / "dash_launch.wav", dash_launch(), 0.5)
    write_wav_absolute(SFX / "slipstream_trickle.wav", slipstream_trickle())
    for name, audio in combat_cues().items():
        write_wav_absolute(SFX / f"{name}.wav", audio)
    write_enemy_sfx()
    FOOTSTEPS.mkdir(parents=True, exist_ok=True)
    for name, audio in footsteps().items():
        write_wav_absolute(FOOTSTEPS / f"{name}.wav", audio)


# =================================================================================
# Arsenal SFX (D19): harpoon, bubble snare, echo shot, resonance pulse, undertow dash
# =================================================================================
ARSENAL_SFX_SEED = 0x4152534E  # ARSN


def _sweep_phase(start: float, end: float, n: int, shape: float = 1.0) -> np.ndarray:
    progress = np.linspace(0.0, 1.0, n) ** shape
    frequency = start + (end - start) * progress
    return 2.0 * np.pi * np.cumsum(frequency) / SR


def _bloop(start: float, end: float, duration: float, decay: float) -> np.ndarray:
    n = round(duration * SR)
    t = np.arange(n) / SR
    body = np.sin(_sweep_phase(start, end, n, 0.6))
    return body * _soft_envelope(t, duration, 0.002, duration * 0.4) * np.exp(-t * decay)


def arsenal_sfx() -> dict[str, np.ndarray]:
    rng = np.random.default_rng(ARSENAL_SFX_SEED)
    out: dict[str, np.ndarray] = {}

    # Harpoon: taut string twang, a wooden knock and a short air rush.
    d = 0.34
    n = round(d * SR)
    t = np.arange(n) / SR
    string = np.sin(_sweep_phase(196.0, 150.0, n)) + 0.4 * np.sin(_sweep_phase(392.0, 300.0, n))
    string *= np.exp(-t * 9.0) * (1.0 + 0.35 * np.sin(2.0 * np.pi * 26.0 * t))
    knock = np.sin(2.0 * np.pi * 95.0 * t) * np.exp(-t * 40.0)
    rush = bp(rng.standard_normal(n), 500.0, 2600.0) * np.exp(-((t - 0.05) ** 2) / 0.002)
    out["harpoon_fire"] = _finish_one_shot(0.6 * string + 0.8 * knock + 0.25 * rush, 0.36)

    # Harpoon hit: dull thud with a brief metallic ring.
    d = 0.3
    n = round(d * SR)
    t = np.arange(n) / SR
    thud = np.sin(_sweep_phase(140.0, 70.0, n)) * np.exp(-t * 22.0)
    ring = (np.sin(2.0 * np.pi * 910.0 * t) + 0.6 * np.sin(2.0 * np.pi * 1370.0 * t)) * np.exp(
        -t * 18.0
    )
    grit = lp(rng.standard_normal(n), 1800.0) * np.exp(-t * 30.0)
    out["harpoon_hit"] = _finish_one_shot(thud + 0.18 * ring + 0.3 * grit, 0.34)

    # Harpoon embed: thunk into rock and the quivering shaft.
    d = 0.5
    n = round(d * SR)
    t = np.arange(n) / SR
    thunk = np.sin(_sweep_phase(120.0, 60.0, n)) * np.exp(-t * 26.0)
    quiver = np.sin(2.0 * np.pi * 185.0 * t) * np.abs(np.sin(2.0 * np.pi * 21.0 * t))
    quiver *= np.exp(-t * 7.0) * np.clip(t / 0.02, 0.0, 1.0)
    grit = bp(rng.standard_normal(n), 800.0, 3500.0) * np.exp(-t * 35.0)
    out["harpoon_embed"] = _finish_one_shot(thunk + 0.35 * quiver + 0.25 * grit, 0.36)

    # Bubble snare fire: a rising bloop with a small echo bloop.
    first = _bloop(320.0, 900.0, 0.14, 16.0)
    second = _bloop(520.0, 1300.0, 0.09, 24.0)
    track = np.zeros(round(0.22 * SR))
    add_at(track, first, 0.0)
    add_at(track, second, 0.07, 0.45)
    out["bubble_fire"] = _finish_one_shot(track, 0.30)

    # Bubble trap: a soft enveloping whoomp plus a cluster of bubbles.
    d = 0.6
    track = np.zeros(round(d * SR))
    t = np.arange(len(track)) / SR
    track += np.sin(_sweep_phase(140.0, 260.0, len(track), 0.5)) * np.exp(-t * 6.0)
    for index in range(7):
        start = 0.04 + 0.06 * index + rng.uniform(0.0, 0.03)
        base = rng.uniform(420.0, 900.0)
        add_at(track, _bloop(base, base * 1.8, 0.08, 30.0), start, 0.35)
    out["bubble_trap"] = _finish_one_shot(lp(track, 3500.0), 0.32)

    # Bubble pop: a wet pop and a few droplets.
    d = 0.35
    track = np.zeros(round(d * SR))
    click_n = round(0.012 * SR)
    click = hp(rng.standard_normal(click_n), 1200.0) * np.linspace(1.0, 0.0, click_n)
    add_at(track, click, 0.0, 0.6)
    add_at(track, _bloop(900.0, 1900.0, 0.05, 50.0), 0.0, 0.8)
    for index in range(4):
        base = rng.uniform(1300.0, 2300.0)
        add_at(track, _bloop(base, base * 1.4, 0.04, 70.0), 0.06 + 0.05 * index, 0.3)
    out["bubble_pop"] = _finish_one_shot(track, 0.30)

    # Echo shot: a sonar ping with two quiet echoes.
    d = 0.5
    n = round(d * SR)
    t = np.arange(n) / SR
    ping = (np.sin(2.0 * np.pi * 1180.0 * t) + 0.3 * np.sin(2.0 * np.pi * 2360.0 * t)) * np.exp(
        -t * 14.0
    )
    ping *= np.clip(t / 0.003, 0.0, 1.0)
    out["echo_fire"] = _finish_one_shot(delay(ping, 0.11, 0.35, 2), 0.28)

    # Echo bounce: a shorter, brighter ping.
    d = 0.2
    n = round(d * SR)
    t = np.arange(n) / SR
    ping = np.sin(2.0 * np.pi * 1560.0 * t) * np.exp(-t * 26.0) * np.clip(t / 0.002, 0.0, 1.0)
    out["echo_bounce"] = _finish_one_shot(ping, 0.2)

    # Resonance pulse: a glassy charge shimmer, then a resonant burst.
    d = 0.24
    n = round(d * SR)
    t = np.arange(n) / SR
    shimmer = sum(
        np.sin(2.0 * np.pi * f * t) * (0.6**k) for k, f in enumerate((660.0, 990.0, 1485.0))
    )
    shimmer *= np.clip(t / 0.05, 0.0, 1.0) * np.exp(-t * 9.0)
    out["pulse_charge"] = _finish_one_shot(shimmer, 0.24)

    d = 0.9
    n = round(d * SR)
    t = np.arange(n) / SR
    boom = np.sin(_sweep_phase(110.0, 55.0, n)) * np.exp(-t * 6.0)
    glass = sum(
        np.sin(2.0 * np.pi * f * t) * (0.55**k) * np.exp(-t * (4.0 + k))
        for k, f in enumerate((440.0, 660.0, 1320.0, 1980.0))
    )
    whoosh = bp(rng.standard_normal(n), 300.0, 2400.0) * np.exp(-t * 12.0)
    out["pulse_burst"] = _finish_one_shot(boom + 0.35 * glass + 0.25 * whoosh, 0.42)

    # Undertow dash: a surging water rush.
    d = 0.3
    n = round(d * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    rush = bp(noise, 350.0, 1500.0) * np.sin(np.pi * np.clip(t / d, 0.0, 1.0)) ** 0.6
    swell = np.sin(_sweep_phase(90.0, 170.0, n)) * np.exp(-t * 5.0)
    gurgle = sum(
        _pad_to(_bloop(rng.uniform(250.0, 500.0), rng.uniform(600.0, 900.0), 0.05, 40.0), n, s)
        for s in (0.03, 0.09, 0.15)
    )
    out["dash"] = _finish_one_shot(rush + 0.5 * swell + 0.25 * gurgle, 0.32)

    # Dash hit: a splashy body blow.
    d = 0.28
    n = round(d * SR)
    t = np.arange(n) / SR
    splash = lp(rng.standard_normal(n), 2400.0) * np.exp(-t * 18.0)
    body = np.sin(_sweep_phase(150.0, 80.0, n)) * np.exp(-t * 20.0)
    out["dash_hit"] = _finish_one_shot(body + 0.45 * splash, 0.36)

    # Barrier break: splintering driftwood and a wash of water.
    d = 0.8
    n = round(d * SR)
    t = np.arange(n) / SR
    track = np.zeros(n)
    for index in range(9):
        start = 0.01 + index * 0.035 + rng.uniform(0.0, 0.02)
        crack_n = round(0.03 * SR)
        crack = bp(rng.standard_normal(crack_n), 600.0, 3200.0) * np.exp(
            -np.arange(crack_n) / SR * 90.0
        )
        add_at(track, crack, start, rng.uniform(0.4, 0.9))
    wash = bp(rng.standard_normal(n), 200.0, 1600.0) * np.sin(np.pi * np.clip(t / d, 0.0, 1.0))
    thump = np.sin(_sweep_phase(100.0, 50.0, n)) * np.exp(-t * 14.0)
    out["barrier_break"] = _finish_one_shot(track + 0.4 * wash + 0.7 * thump, 0.42)
    return out


def _pad_to(x: np.ndarray, n: int, start: float) -> np.ndarray:
    out = np.zeros(n)
    add_at(out, x, start)
    return out


def write_arsenal_sfx() -> None:
    SFX.mkdir(parents=True, exist_ok=True)
    for name, audio in arsenal_sfx().items():
        write_wav_absolute(SFX / f"{name}.wav", audio)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only",
        action="append",
        choices=("music", "ambience", "sfx", "arsenal"),
        help="render only these groups (repeatable); default renders everything",
    )
    parser.add_argument(
        "--track", action="append", choices=MUSIC_IDS, help="render only these music tracks"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    groups = set(args.only or ())
    if args.track:
        groups.add("music")
    if not groups:
        groups = {"music", "ambience", "sfx"}
    if "sfx" in groups:
        write_sfx()
    if "sfx" in groups or "arsenal" in groups:
        write_arsenal_sfx()
    if "ambience" in groups:
        write_ambience()
    if "music" in groups:
        write_music(args.track)


if __name__ == "__main__":
    main()
