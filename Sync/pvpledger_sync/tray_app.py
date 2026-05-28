"""System tray application for PvPLedger Sync."""

from __future__ import annotations

import subprocess
import threading
import time
from pathlib import Path

import pystray
from pystray import MenuItem as Item

from .config import SyncConfig, default_config_path, load_config
from .downloader import sync_app_data
from .exporter import scan_exports
from .icons import build_tray_icon
from .ingest_server import default_ingest_dir, ensure_ingest_server_running
from .notify import notify
from .single_instance import try_acquire_single_instance
from .startup import is_startup_installed
from .uploader import upload_exports


class TrayApp:
    """Background tray controller that polls GitHub and syncs AppData.lua."""

    def __init__(self) -> None:
        self._config = load_config()
        self._icon: pystray.Icon | None = None
        self._stop_event = threading.Event()
        self._worker: threading.Thread | None = None
        self._last_message = "PvPLedger Sync is running."

    def _set_status(self, message: str) -> None:
        """Store the latest status message shown in the tray tooltip."""

        self._last_message = message
        if self._icon is not None:
            self._icon.title = f"PvPLedger Sync\n{message}"

    def _open_path(self, path: Path) -> None:
        """Open one folder in Windows Explorer."""

        if not path.exists():
            notify("PvPLedger Sync", f"Path not found:\n{path}")
            return
        subprocess.Popen(["explorer", str(path)], shell=False)  # noqa: S603

    def _run_sync(self, *, force: bool = False) -> None:
        """Execute one ladder sync attempt and update tray state."""

        if not self._config.wow_addons_dir:
            self._set_status("Not initialized. Run: run_sync.bat init")
            notify("PvPLedger Sync", "Run init before syncing.")
            return

        result = sync_app_data(self._config, force=force)
        self._config = load_config()
        self._set_status(result.reason)
        if result.updated:
            notify("PvPLedger Sync", "Ladder data updated.")

    def _run_export_upload(self) -> None:
        """Upload pending match exports and update tray state."""

        if not self._config.wow_addons_dir:
            self._set_status("Not initialized. Run: run_sync.bat init")
            return

        result = upload_exports(self._config)
        self._config = load_config()
        if result.uploaded:
            self._set_status(result.reason)
            notify("PvPLedger Sync", result.reason)
            return

        scan = scan_exports(self._config.wow_addons_dir)
        if scan.pending_matches:
            self._set_status(scan.note)
        elif result.reason != "No pending match exports to upload.":
            self._set_status(result.reason)

    def _run_cycle(self, *, force_sync: bool = False) -> None:
        """Run one background ladder sync and export upload cycle."""

        self._run_sync(force=force_sync)
        self._run_export_upload()

    def _sync_now(self, _icon: pystray.Icon, _item: Item) -> None:
        """Tray menu handler for immediate ladder sync."""

        threading.Thread(target=self._run_sync, kwargs={"force": True}, daemon=True).start()

    def _upload_exports_now(self, _icon: pystray.Icon, _item: Item) -> None:
        """Tray menu handler for immediate export upload."""

        threading.Thread(target=self._run_export_upload, daemon=True).start()

    def _open_app_helper(self, _icon: pystray.Icon, _item: Item) -> None:
        """Open the AppHelper addon folder."""

        self._open_path(self._config.app_helper_dir)

    def _open_config(self, _icon: pystray.Icon, _item: Item) -> None:
        """Open the sync config folder."""

        self._open_path(default_config_path().parent)

    def _show_status(self, _icon: pystray.Icon, _item: Item) -> None:
        """Show the latest sync status."""

        notify("PvPLedger Sync", self._last_message)

    def _open_ingest_dir(self, _icon: pystray.Icon, _item: Item) -> None:
        """Open the ingested export batch folder."""

        self._open_path(default_ingest_dir())

    def _exit(self, _icon: pystray.Icon, _item: Item) -> None:
        """Stop background polling and exit the tray app."""

        self._stop_event.set()
        if self._icon is not None:
            self._icon.stop()

    def _poll_loop(self) -> None:
        """Poll GitHub on an interval until stopped."""

        while not self._stop_event.is_set():
            self._run_cycle(force_sync=False)
            interval_seconds = max(self._config.poll_minutes, 1) * 60
            if self._stop_event.wait(interval_seconds):
                break

    def run(self) -> None:
        """Start the tray icon and background polling loop."""

        if not self._config.wow_addons_dir:
            notify(
                "PvPLedger Sync",
                "Run init first:\nrun_sync.bat init --addons-dir YOUR_ADDONS_PATH",
            )

        if self._config.ingest_enabled:
            if ensure_ingest_server_running(self._config):
                ingest_status = f"Ingest: {self._config.ingest_host}:{self._config.ingest_port}"
            else:
                ingest_status = "Ingest: failed to start"
                notify(
                    "PvPLedger Sync",
                    "Could not start the local ingest server. Check port availability.",
                )
        else:
            ingest_status = "Ingest: disabled"

        startup_label = "Run at login: enabled" if is_startup_installed() else "Run at login: disabled"
        self._set_status(f"{ingest_status} | {startup_label}")

        menu = pystray.Menu(
            Item("Sync ladder now", self._sync_now),
            Item("Upload exports now", self._upload_exports_now),
            Item("Show status", self._show_status),
            Item("Open AppHelper folder", self._open_app_helper),
            Item("Open ingest folder", self._open_ingest_dir),
            Item("Open config folder", self._open_config),
            pystray.Menu.SEPARATOR,
            Item("Exit", self._exit),
        )

        self._icon = pystray.Icon(
            "PvPLedger Sync",
            build_tray_icon(),
            "PvPLedger Sync",
            menu,
        )

        self._worker = threading.Thread(target=self._poll_loop, daemon=True)
        self._worker.start()
        self._icon.run()


def run_tray_app() -> None:
    """Launch the tray application."""

    if not try_acquire_single_instance():
        notify("PvPLedger Sync", "PvPLedger Sync is already running in the system tray.")
        return

    TrayApp().run()
