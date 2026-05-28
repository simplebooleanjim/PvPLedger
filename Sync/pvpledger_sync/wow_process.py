"""WoW process detection helpers."""

from __future__ import annotations

import subprocess


def is_wow_running() -> bool:
    """
    Return True when World of Warcraft is currently running on Windows.

    Returns
    -------
    bool
        True if `Wow.exe` or `WowClassic.exe` is present in the task list.
    """

    for image_name in ("Wow.exe", "WowClassic.exe"):
        result = subprocess.run(  # noqa: S603
            ["tasklist", "/FI", f"IMAGENAME eq {image_name}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if image_name in result.stdout:
            return True
    return False
