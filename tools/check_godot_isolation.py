#!/usr/bin/env python3
"""Every Godot the test runner or the playtest runner launches gets its own user:// directory.

A probe writes user://settings.cfg through the game's settings code, once with the environment
tools/run_godot_check.py gives a suite and once with the one tools/playtest/run.py gives a run.
Both writes must land in the run's scratch folder, and the player's real settings.cfg must stay
byte-identical. The real file is only read, never written; the probe refuses to write anywhere
outside the scratch folder.
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = "tools/check_isolation_probe.gd"
MARKER = "screen_shake=0.37"

sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "playtest"))

import run as playtest_run  # noqa: E402
import run_godot_check  # noqa: E402

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    print(f"{'PASS' if condition else 'FAIL'}  {message}")
    if not condition:
        FAILURES.append(message)


def project_name() -> str:
    match = re.search(r'^config/name="([^"]+)"', (ROOT / "project.godot").read_text(), re.M)
    if match is None:
        raise RuntimeError("project.godot has no config/name")
    return match.group(1)


def real_settings() -> Path:
    """The player's settings.cfg for this machine, from the real (not isolated) environment."""
    if sys.platform == "darwin":
        data = Path.home() / "Library" / "Application Support"
    elif sys.platform == "win32":
        data = Path(os.environ["APPDATA"])
    else:
        data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    folder = "Godot" if sys.platform != "linux" else "godot"
    return data / folder / "app_userdata" / project_name() / "settings.cfg"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else "missing"


def written_settings(scratch: Path) -> list[Path]:
    return [path for path in scratch.rglob("settings.cfg") if MARKER in path.read_text()]


def main() -> int:
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if godot is None:
        print("godot executable missing (set GODOT)")
        return 1
    real = real_settings()
    before = digest(real)
    print(f"real settings.cfg: {real} ({before[:12]})")

    with tempfile.TemporaryDirectory(prefix="hollowtide-isolation-") as folder:
        scratch = Path(folder).resolve()
        suite = run_godot_check.Suite("isolation probe", PROBE, timeout=60.0)
        _suite, ok, _seconds, output = run_godot_check.run(suite, [godot], scratch / "suite")
        check(ok and "ISOLATION PASS" in output, "suite runner gives Godot its own user://")
        check(bool(written_settings(scratch / "suite")), "suite settings write lands in scratch")
        if not ok:
            print(output[-2000:])

        out = scratch / "playtest"
        (out / "saves").mkdir(parents=True)
        child_env = getattr(playtest_run, "child_env", None)
        check(child_env is not None, "playtest runner builds an isolated environment")
        if child_env is not None:
            done = subprocess.run(
                [godot, "--headless", "--path", str(ROOT), "--script", f"res://{PROBE}", "--"]
                + ["--test-mode", f"--test-save-root={out / 'saves'}"],
                cwd=ROOT,
                env=child_env(out),
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            text = done.stdout + done.stderr
            check(done.returncode == 0 and "ISOLATION PASS" in text, "playtest run is isolated")
            check(bool(written_settings(out)), "playtest settings write lands in scratch")
            if done.returncode != 0:
                print(text[-2000:])

    check(digest(real) == before, "the player's real settings.cfg is unchanged")
    print("godot-isolation: " + ("PASS" if not FAILURES else "FAIL"))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    raise SystemExit(main())
