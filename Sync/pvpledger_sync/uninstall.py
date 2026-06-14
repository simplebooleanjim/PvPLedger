"""Uninstall helpers for the PvPLedger Sync tray app."""

from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from .i18n import t
from .paths import default_install_dir, installed_sync_exe
from .startup import uninstall_startup

_TRAY_PROCESS_NAMES = ("PvPLedger-Sync.exe",)


@dataclass
class UninstallResult:
    """Summary of one tray-app uninstall attempt."""

    stopped_tray: bool
    removed_startup: bool
    removed_executable: bool
    removed_install_dir: bool
    messages: list[str]


def stop_tray_app() -> bool:
    """
    Stop any running PvPLedger Sync tray process on Windows.

    Returns
    -------
    bool
        True when a tray process was terminated.
    """

    stopped = False
    for image_name in _TRAY_PROCESS_NAMES:
        result = subprocess.run(  # noqa: S603
            ["taskkill", "/IM", image_name, "/F"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            stopped = True
    return stopped


def uninstall_tray_app() -> UninstallResult:
    """
    Remove the installed PvPLedger Sync tray app from this Windows profile.

    Removes the login startup entry and installed executable. WoW addons and
    sync settings in ``%APPDATA%\\PvPLedger`` are left in place.

    Returns
    -------
    UninstallResult
        Details about which uninstall steps completed.
    """

    messages: list[str] = []
    stopped_tray = stop_tray_app()
    if stopped_tray:
        messages.append(t("UNINSTALL.STOPPED_TRAY"))
    else:
        messages.append(t("UNINSTALL.NO_RUNNING_TRAY"))

    removed_startup = uninstall_startup()
    if removed_startup:
        messages.append(t("UNINSTALL.REMOVED_STARTUP"))
    else:
        messages.append(t("UNINSTALL.NO_STARTUP"))

    sync_exe = installed_sync_exe()
    removed_executable = False
    if sync_exe.exists():
        sync_exe.unlink()
        removed_executable = True
        messages.append(t("UNINSTALL.REMOVED_EXE", path=sync_exe))

    install_dir = default_install_dir()
    removed_install_dir = False
    if install_dir.exists() and _directory_is_empty(install_dir):
        install_dir.rmdir()
        removed_install_dir = True
        messages.append(t("UNINSTALL.REMOVED_DIR", path=install_dir))

    if not removed_executable and not removed_startup and not stopped_tray:
        messages.append(t("UNINSTALL.NOT_INSTALLED"))

    return UninstallResult(
        stopped_tray=stopped_tray,
        removed_startup=removed_startup,
        removed_executable=removed_executable,
        removed_install_dir=removed_install_dir,
        messages=messages,
    )


def _directory_is_empty(path: Path) -> bool:
    """Return True when a directory contains no files or subdirectories."""

    try:
        next(path.iterdir())
    except StopIteration:
        return True
    except FileNotFoundError:
        return True
    return False
