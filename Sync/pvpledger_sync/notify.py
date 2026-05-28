"""Desktop notifications for PvPLedger Sync."""

from __future__ import annotations


def notify(title: str, message: str) -> None:
    """Show a desktop notification when supported on the current platform."""

    try:
        from winotify import Notification, audio

        toast = Notification(
            app_id="PvPLedger Sync",
            title=title,
            msg=message,
            duration="short",
        )
        toast.set_audio(audio.Default, loop=False)
        toast.show()
    except Exception:
        return
