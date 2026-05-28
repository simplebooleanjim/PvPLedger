"""Path helpers for frozen PyInstaller executables."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def is_frozen() -> bool:
    """Return True when running from a PyInstaller bundle."""

    return bool(getattr(sys, "frozen", False))


def bundle_dir() -> Path:
    """Return the directory containing bundled installer resources."""

    if is_frozen():
        return Path(getattr(sys, "_MEIPASS"))
    return Path(__file__).resolve().parent.parent


def default_install_dir() -> Path:
    """Return the default install directory for PvPLedger Sync."""

    local_appdata = os.environ.get("LOCALAPPDATA")
    if not local_appdata:
        return Path.home() / "AppData" / "Local" / "Programs" / "PvPLedger"
    return Path(local_appdata) / "Programs" / "PvPLedger"


def installed_sync_exe() -> Path:
    """Return the installed tray executable path."""

    return default_install_dir() / "PvPLedger-Sync.exe"


def resource_path(*parts: str) -> Path:
    """Return a path to one bundled resource file or directory."""

    return bundle_dir().joinpath(*parts)
