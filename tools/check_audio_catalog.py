#!/usr/bin/env python3
"""Audio catalog and runtime check: files, formats, loudness, loops and Audio API behaviour."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import wave
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "assets/audio"
AUDIO_GD = ROOT / "scripts/autoload/audio.gd"
SR = 44100
AREA_IDS = ("fringe", "nexus", "vaults", "kiln", "depths")
# id: (target LUFS, minimum loudness range LU, min seconds, max seconds, loops)
MUSIC = {
    "fringe": (-17.0, 3.0, 120.0, 200.0, True),
    "nexus": (-17.0, 3.0, 120.0, 200.0, True),
    "vaults": (-17.0, 3.0, 120.0, 200.0, True),
    "kiln": (-17.0, 3.0, 120.0, 200.0, True),
    "depths": (-17.0, 3.0, 120.0, 200.0, True),
    "boss": (-16.0, 1.5, 60.0, 150.0, True),
    "title": (-18.0, 2.0, 90.0, 180.0, True),
    "ending": (-18.0, 2.0, 60.0, 150.0, False),
}
BED_LUFS = -27.0
NEW_ONE_SHOTS = {
    "enemy_hit",
    "armor_clink",
    "boss_open",
    "boss_close",
    "boss_phase",
    "boss_telegraph",
    "ice_shatter",
    "boss_explosion",
}
FORBIDDEN_NAME_PARTS = ("metroid", "brinstar", "nintendo", "samus", "prime")


def fail(message: str) -> None:
    raise AssertionError(message)


def dict_block(source: str, constant: str) -> str:
    match = re.search(rf"const {constant}[^=]*= \{{(?P<body>.*?)\n\}}", source, re.DOTALL)
    if match is None:
        fail(f"audio.gd: {constant} missing or unparsable")
    return match.group("body")


def ebur128(path: Path) -> tuple[float, float, float]:
    output = subprocess.run(
        ["ffmpeg", "-nostdin", "-i", str(path), "-af", "ebur128=peak=sample", "-f", "null", "-"],
        check=True,
        stderr=subprocess.PIPE,
        text=True,
    ).stderr
    summary = output[output.rindex("Summary:") :]

    def value(label: str) -> float:
        match = re.search(rf"{label}:\s+(-?[\d.]+|-inf)", summary)
        if match is None:
            fail(f"{path.name}: no {label} in ebur128 summary")
        return float(match.group(1))

    return value("I"), value("LRA"), value("Peak")


def probe(path: Path) -> dict:
    output = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels"]
        + ["-show_entries", "stream_tags:format=duration", "-of", "json", str(path)],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout
    data = json.loads(output)
    stream = data["streams"][0]
    stream["duration"] = float(data["format"]["duration"])
    stream["tags"] = {str(k).upper(): str(v) for k, v in stream.get("tags", {}).items()}
    return stream


def wav_info(path: Path) -> tuple[int, int, float, float, float]:
    with wave.open(str(path), "rb") as source:
        channels, frames = source.getnchannels(), source.getnframes()
        samples = array("h")
        samples.frombytes(source.readframes(frames))
    peak = max((abs(s) for s in samples), default=0) / 32768.0
    first = samples[0] / 32768.0 if samples else 0.0
    last = samples[-1] / 32768.0 if samples else 0.0
    return channels, frames, peak, first, last


def verify_files(source: str) -> None:
    for path in AUDIO.rglob("*"):
        if path.is_symlink():
            fail(f"symlink in audio catalog: {path}")
        lowered = path.name.lower()
        if any(part in lowered for part in FORBIDDEN_NAME_PARTS):
            fail(f"forbidden reference name: {path}")
        if path.is_file() and path.suffix not in {".ogg", ".wav", ".import", ".tres"}:
            fail(f"unexpected file in audio catalog: {path}")
        if path.suffix in {".ogg", ".wav"} and not path.with_name(path.name + ".import").exists():
            fail(f"missing Godot import metadata: {path}")
    referenced = set(re.findall(r'"res://(assets/audio/[a-z0-9_/]+\.(?:wav|ogg))"', source))
    for relative in sorted(referenced):
        if not (ROOT / relative).exists():
            fail(f"audio.gd references missing file {relative}")
    layout = (AUDIO / "default_bus_layout.tres").read_text()
    for bus in ("Music", "SFX", "Ambience"):
        if f'name = &"{bus}"' not in layout:
            fail(f"bus {bus} missing from default_bus_layout.tres")
    print(f"catalog: PASS ({len(referenced)} referenced files, buses Master/Music/SFX/Ambience)")


def verify_music(source: str) -> None:
    registered = set(re.findall(r'&"([a-z_]+)":\s*"res://assets/audio/music/', source))
    if registered != set(MUSIC):
        fail(f"MUSIC_PATHS ids {sorted(registered)} != {sorted(MUSIC)}")
    for music_id, (target, min_lra, low, high, loops) in MUSIC.items():
        path = AUDIO / "music" / f"{music_id}.ogg"
        stream = probe(path)
        if stream["codec_name"] != "vorbis" or int(stream["sample_rate"]) != SR:
            fail(f"{music_id}: expected 44.1 kHz Vorbis")
        if int(stream["channels"]) != 2:
            fail(f"{music_id}: music must be stereo")
        if not low <= stream["duration"] <= high:
            fail(f"{music_id}: duration {stream['duration']:.1f}s outside {low}-{high}s")
        if loops and stream["tags"].get("LOOPSTART") != "0":
            fail(f"{music_id}: missing loop tags {stream['tags']}")
        import_text = path.with_name(path.name + ".import").read_text()
        if f"loop={'true' if loops else 'false'}" not in import_text:
            fail(f"{music_id}: import loop flag should be {loops}")
        lufs, lra, peak = ebur128(path)
        if abs(lufs - target) > 1.0 or peak > -0.5 or lra < min_lra:
            fail(f"{music_id}: I={lufs} LUFS (target {target}), LRA={lra}, peak={peak} dBFS")
        print(f"{music_id}: {stream['duration']:.1f}s I={lufs} LUFS LRA={lra} LU peak={peak} dBFS")
    print("music: PASS")


def verify_ambience(source: str) -> None:
    layers = dict_block(source, "AMBIENCE_LAYERS")
    total = 0
    for area in AREA_IDS:
        bed = AUDIO / "ambience" / f"{area}_bed.ogg"
        stream = probe(bed)
        if int(stream["channels"]) != 2 or not 45.0 <= stream["duration"] <= 120.0:
            fail(f"{area}: ambience bed must be a stereo 45-120 s loop")
        lufs, _, peak = ebur128(bed)
        if abs(lufs - BED_LUFS) > 1.5 or peak > -3.0:
            fail(f"{area}: bed I={lufs} LUFS peak={peak}")
        area_block = re.search(rf'&"{area}":\s*\[(.*?)\]', layers, re.DOTALL)
        if area_block is None:
            fail(f"AMBIENCE_LAYERS has no {area}")
        entries = re.findall(r'"kind": "([a-z_]+)", "count": (\d+)', area_block.group(1))
        if len(entries) < 3:
            fail(f"{area}: needs at least three one-shot layers, has {entries}")
        for kind, count in entries:
            for index in range(1, int(count) + 1):
                path = AUDIO / "ambience" / f"{area}_{kind}_{index}.ogg"
                if not path.exists():
                    fail(f"missing ambience one-shot {path.name}")
                total += 1
        print(f"{area}: bed I={lufs} LUFS, layers {[kind for kind, _ in entries]}")
    print(f"ambience: PASS ({len(AREA_IDS)} beds, {total} one-shots)")


def verify_wavs(source: str) -> None:
    loop_ends = {
        name: int(value)
        for name, value in re.findall(
            r'&"([a-z_]+)":\s*(\d+)', dict_block(source, "AMBIENT_LOOP_ENDS")
        )
    }
    wavs = sorted((AUDIO / "sfx").rglob("*.wav"))
    for path in wavs:
        channels, frames, peak, first, last = wav_info(path)
        if peak >= 1.0:
            fail(f"{path.name}: clipping")
        name = path.stem
        if name in loop_ends:
            if channels != 1 or frames != loop_ends[name]:
                fail(f"{name}: positional loop must be mono with {loop_ends[name]} frames")
            text = path.with_name(path.name + ".import").read_text()
            if f"edit/loop_end={frames}" not in text:
                fail(f"{name}: import loop_end does not match {frames}")
            if abs(first - last) > 0.01:
                fail(f"{name}: loop seam {first:.4f} vs {last:.4f}")
        elif name in NEW_ONE_SHOTS or "footsteps" in path.parts:
            if abs(first) > 0.002 or abs(last) > 0.002:
                fail(f"{name}: one-shot must start and end at silence")
    for area in AREA_IDS:
        for suffix in ("step_1", "step_2", "step_3", "land"):
            if not (AUDIO / "sfx/footsteps" / f"{area}_{suffix}.wav").exists():
                fail(f"missing footstep {area}_{suffix}")
    print(f"sfx: PASS ({len(wavs)} WAV files, loop ends match, per-area footsteps)")


FIXTURE = """extends Node

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func count_playing(players: Array) -> int:
	var count := 0
	for player in players:
		if player.playing:
			count += 1
	return count


func _ready() -> void:
	for bus in ["Music", "SFX", "Ambience"]:
		check(AudioServer.get_bus_index(bus) >= 0, "bus %s missing" % bus)
	Audio.play_music(&"cave_theme")
	check(Audio.music_is_playing(&"title"), "cave_theme alias did not play title")
	check(Audio.current_area() == &"", "menu music kept an area")
	Audio.play_area(&"fringe")
	check(Audio.music_is_playing(&"fringe"), "fringe music not playing")
	check(Audio.current_area() == &"fringe", "fringe area not current")
	check(count_playing(Audio._bed_players) == 1, "expected one ambience bed")
	var fringe_player: AudioStreamPlayer = Audio._active_music_player()
	Audio.play_area(&"fringe")
	check(Audio._active_music_player() == fringe_player, "same-area play_area was not a no-op")
	Audio.play_music(&"nexus")
	check(Audio.music_is_playing(&"nexus"), "play_music(area) did not switch music")
	check(Audio.current_area() == &"nexus", "play_music(area) did not switch ambience area")
	Audio.play_sfx(&"step")
	Audio.play_sfx(&"land")
	for area in Audio.AREA_IDS:
		check(Audio._area_steps[area].size() == 3, "%s footsteps missing" % area)
	Audio._tick_ambience(120.0)
	check(count_playing(Audio._ambience_players) > 0, "no ambience one-shot fired")
	Audio.set_boss_music(true)
	check(Audio.music_is_playing(&"boss"), "boss music did not start")
	Audio.set_boss_music(false)
	check(Audio.music_is_playing(&"nexus"), "area music did not return after boss")
	await get_tree().create_timer(3.4).timeout
	check(count_playing(Audio._music_players) == 1, "music crossfade left extra players")
	check(count_playing(Audio._bed_players) == 1, "ambience crossfade left extra beds")
	Audio.play_music(&"ending")
	check(Audio.music_is_playing(&"ending"), "ending did not play")
	check(Audio.current_area() == &"", "ending kept area ambience")
	var positional := AudioStreamPlayer2D.new()
	add_child(positional)
	check(not Audio.configure_positional_loop(positional, &"unknown"), "unknown loop accepted")
	check(Audio.configure_positional_loop(positional, &"lava_loop"), "lava loop refused")
	check(positional.bus == &"Ambience", "positional loop not on Ambience bus")
	positional.play()
	await get_tree().process_frame
	await Audio.shutdown()
	check(Audio._music_players.is_empty() and Audio._sfx_players.is_empty(), "players kept")
	check(Audio._music_streams.is_empty() and Audio._ambience_streams.is_empty(), "streams kept")
	check(Audio._music_player == null, "music player ref kept")
	check(is_instance_valid(positional) and positional.stream != null, "external emitter freed")
	Audio.clear_positional_player(positional)
	for message in failures:
		print("AUDIO_RUNTIME_FAIL: ", message)
	print("AUDIO_RUNTIME=PASS" if failures.is_empty() else "AUDIO_RUNTIME=FAIL")
	await get_tree().process_frame
	get_tree().quit()
"""


def verify_runtime() -> None:
    godot = shutil.which("godot")
    if godot is None:
        fail("godot executable missing")
    with tempfile.TemporaryDirectory(prefix="hollowtide-audio-") as temp_name:
        temp = Path(temp_name)
        shutil.copytree(AUDIO, temp / "assets/audio")
        (temp / "scripts/autoload").mkdir(parents=True)
        shutil.copy2(AUDIO_GD, temp / "scripts/autoload/audio.gd")
        (temp / "game_state.gd").write_text(
            'extends Node\nsignal state_changed\nvar active_beam: StringName = &"base"\n'
        )
        (temp / "main.gd").write_text(FIXTURE)
        (temp / "main.tscn").write_text(
            '[gd_scene load_steps=2 format=3]\n\n[ext_resource path="res://main.gd" '
            'type="Script" id="1"]\n\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n'
        )
        (temp / "project.godot").write_text(
            'config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n[autoload]\n'
            'GameState="*res://game_state.gd"\nAudio="*res://scripts/autoload/audio.gd"\n'
            '[audio]\ndefault_bus_layout="res://assets/audio/default_bus_layout.tres"\n'
        )
        base = [godot, "--headless", "--path", str(temp)]
        # Headless editor import of many streams occasionally segfaults on exit in Godot 4.7;
        # the import cache it leaves is complete, so retry a few times before failing.
        for _ in range(4):
            imported = subprocess.run(
                [*base, "--single-threaded-scene", "--editor", "--import", "--quit"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            if imported.returncode == 0:
                break
        if imported.returncode != 0:
            print(imported.stdout)
            fail("isolated Godot import failed")
        result = subprocess.run(
            base, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False
        )
        lines = [line for line in result.stdout.splitlines() if "AUDIO_RUNTIME" in line]
        print("\n".join(lines))
        if "AUDIO_RUNTIME=PASS" not in result.stdout or "SCRIPT ERROR" in result.stdout:
            print(result.stdout)
            fail("Audio runtime fixture failed")
    print("runtime: PASS (play_area/crossfade/no-op/aliases/boss/ambience/footsteps/teardown)")


def main() -> None:
    source = AUDIO_GD.read_text()
    verify_files(source)
    verify_music(source)
    verify_ambience(source)
    verify_wavs(source)
    verify_runtime()
    print("audio-catalog: PASS")


if __name__ == "__main__":
    main()
