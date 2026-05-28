"""Single-instance guard for the PvPLedger Sync tray app."""

from __future__ import annotations

import sys
from ctypes import windll, wintypes

ERROR_ALREADY_EXISTS = 183
_MUTEX_NAME = "Global\\PvPLedgerSyncTray_v1"
_mutex_handle: int | None = None


def try_acquire_single_instance(mutex_name: str = _MUTEX_NAME) -> bool:
    """
    Attempt to acquire a named Windows mutex for this process.

    Parameters
    ----------
    mutex_name:
        Global mutex name shared by all PvPLedger Sync tray processes.

    Returns
    -------
    bool
        True when this process is the first instance; False when another
        instance is already running.
    """

    global _mutex_handle

    if sys.platform != "win32":
        return True

    handle = windll.kernel32.CreateMutexW(None, wintypes.BOOL(False), mutex_name)
    if not handle:
        return True

    if windll.kernel32.GetLastError() == ERROR_ALREADY_EXISTS:
        windll.kernel32.CloseHandle(handle)
        return False

    _mutex_handle = handle
    return True
