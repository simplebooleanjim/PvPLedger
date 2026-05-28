"""Windows helpers for locating a WoW AddOns directory."""

from __future__ import annotations

import os
import winreg
from pathlib import Path


def _normalize_addons_dir(path: Path) -> Path | None:
    """Return the AddOns directory if the path exists."""

    if path.exists():
        return path
    return None


def detect_wow_addons_dir() -> Path | None:
    """Best-effort detection of the retail WoW AddOns folder."""

    candidates: list[Path] = []

    try:
        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
        ) as key:
            install_path, _ = winreg.QueryValueEx(key, "InstallPath")
            candidates.append(Path(install_path) / "_retail_" / "Interface" / "AddOns")
    except OSError:
        pass

    try:
        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Blizzard Entertainment\World of Warcraft",
        ) as key:
            install_path, _ = winreg.QueryValueEx(key, "InstallPath")
            candidates.append(Path(install_path) / "_retail_" / "Interface" / "AddOns")
    except OSError:
        pass

    program_files = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    candidates.extend(
        [
            Path("e:/games/World of Warcraft/_retail_/Interface/AddOns"),
            Path(program_files) / "World of Warcraft" / "_retail_" / "Interface" / "AddOns",
            Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
            / "World of Warcraft"
            / "_retail_"
            / "Interface"
            / "AddOns",
            Path.home() / "Games" / "World of Warcraft" / "_retail_" / "Interface" / "AddOns",
        ]
    )

    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate).lower()
        if key in seen:
            continue
        seen.add(key)
        resolved = _normalize_addons_dir(candidate)
        if resolved is not None:
            return resolved
    return None
