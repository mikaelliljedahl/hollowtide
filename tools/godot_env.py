"""Environment for a Godot child process that must not touch the player's user:// directory.

Godot resolves user:// (saves, settings.cfg) from HOME on macOS
(~/Library/Application Support/Godot/app_userdata/<project>), from XDG_DATA_HOME on Linux and
from APPDATA on Windows. Only overriding every one of them isolates a run on all three, so every
tool that launches Godot for a test, capture or playtest builds its environment here.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path


def isolated_env(home: Path, base: Mapping[str, str] | None = None) -> dict[str, str]:
    """Return a copy of `base` (default: os.environ) whose user data lives under `home`."""
    home = home.resolve()
    folders = {
        "HOME": home,
        "XDG_DATA_HOME": home / ".local" / "share",
        "XDG_CONFIG_HOME": home / ".config",
        "XDG_CACHE_HOME": home / ".cache",
        "APPDATA": home / "AppData" / "Roaming",
        "LOCALAPPDATA": home / "AppData" / "Local",
    }
    env = dict(os.environ if base is None else base)
    for key, folder in folders.items():
        folder.mkdir(parents=True, exist_ok=True)
        env[key] = str(folder)
    return env
