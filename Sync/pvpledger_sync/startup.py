"""Windows startup registration for PvPLedger Sync."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from .paths import default_install_dir, installed_sync_exe, is_frozen


def sync_dir() -> Path:
    """Return the Sync package directory."""

    if is_frozen():
        return default_install_dir()
    return Path(__file__).resolve().parent.parent


def sync_executable() -> Path:
    """Return the executable that should launch the tray app."""

    if is_frozen():
        exe = Path(sys.executable)
        if exe.name.lower() == "pvpledger-setup.exe":
            return installed_sync_exe()
        return exe
    installed = installed_sync_exe()
    if installed.exists():
        return installed
    return Path(sys.executable)


def pythonw_executable() -> str:
    """Return a pythonw.exe path suitable for background tray startup."""

    if is_frozen():
        return str(sync_executable())

    executable = Path(sys.executable)
    pythonw = executable.with_name("pythonw.exe")
    if pythonw.exists():
        return str(pythonw)
    return str(executable)


def startup_script_path() -> Path:
    """Return the Startup folder script path."""

    appdata = os.environ.get("APPDATA")
    if not appdata:
        raise RuntimeError("APPDATA is not set.")
    return Path(appdata) / "Microsoft/Windows/Start Menu/Programs/Startup/PvPLedger Sync.bat"


def build_startup_script() -> str:
    """Build the Startup batch file contents."""

    executable = sync_executable()
    return (
        "@echo off\r\n"
        f'start "" "{executable}"\r\n'
    )


def install_startup() -> Path:
    """Install PvPLedger Sync into the current user's Startup folder."""

    path = startup_script_path()
    path.write_text(build_startup_script(), encoding="utf-8")
    return path


def uninstall_startup() -> bool:
    """Remove PvPLedger Sync from the Startup folder."""

    path = startup_script_path()
    if not path.exists():
        return False
    path.unlink()
    return True


def is_startup_installed() -> bool:
    """Return True when the Startup script exists."""

    return startup_script_path().exists()
