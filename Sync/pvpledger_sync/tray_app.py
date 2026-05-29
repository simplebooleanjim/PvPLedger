"""System tray application for PvPLedger Sync."""

from __future__ import annotations

import subprocess
import threading
import time
from pathlib import Path

import pystray
from pystray import MenuItem as Item

from .config import SyncConfig, default_config_path, load_config
from .downloader import inspect_installed_app_data, sync_app_data
from .exporter import scan_exports_for_config
from .icons import build_tray_icon
from .ingest_server import default_ingest_dir, ensure_ingest_server_running
from .notify import notify
from .single_instance import try_acquire_single_instance
from .startup import is_startup_installed
from .uploader import upload_exports


_SILENT_EXPORT_REASONS = frozenset(
    {
        "No pending match exports to upload.",
        "No PvPLedger_AppHelper SavedVariables file found yet.",
    }
)


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

        try:
            result = sync_app_data(self._config, force=force)
        except Exception as exc:  # noqa: BLE001
            message = f"Ladder sync failed: {exc}"
            self._set_status(message)
            notify("PvPLedger Sync", message)
            return

        self._config = load_config()
        self._set_status(result.reason)
        if result.updated:
            if result.player_index_count > 0:
                notify("PvPLedger Sync", result.reason)
            else:
                notify(
                    "PvPLedger Sync",
                    "Ladder aggregates synced, but View Ladder is still empty.\n"
                    "The published snapshot does not include player names yet.",
                )
        elif result.reason.startswith("Already up to date"):
            _, installed_status = inspect_installed_app_data(self._config)
            if "empty" in installed_status.lower():
                self._set_status(f"{result.reason} {installed_status}")

    def _is_idle_export_state(
        self,
        *,
        result,
        scan,
        reconcile,
    ) -> bool:
        """
        Return True when export upload has nothing actionable to report.

        Parameters
        ----------
        result:
            Upload attempt result from the uploader.
        scan:
            SavedVariables scan summary.
        reconcile:
            Optional GitHub reconciliation summary.

        Returns
        -------
        bool
            True when the tray should stay quiet.
        """

        if scan.pending_matches:
            return False
        if result.match_count > 0:
            return False
        if reconcile and reconcile.uploaded_batches > 0:
            return False
        if reconcile and reconcile.failed_batches:
            return False
        if result.reason in _SILENT_EXPORT_REASONS:
            return True
        if (
            reconcile
            and reconcile.checked_batches > 0
            and reconcile.already_synced_batches == reconcile.checked_batches
        ):
            return True
        return False

    def _run_export_upload(self) -> None:
        """Upload pending match exports and update tray state."""

        if not self._config.wow_addons_dir:
            self._set_status("Not initialized. Run: run_sync.bat init")
            return

        result = upload_exports(self._config)
        self._config = load_config()
        reconcile = result.github_reconcile
        backfilled = bool(
            reconcile
            and (reconcile.uploaded_batches > 0 or reconcile.dump_repaired)
        )
        scan = scan_exports_for_config(self._config)

        if result.uploaded and (result.match_count > 0 or backfilled):
            message = result.reason if result.match_count > 0 else reconcile.reason if reconcile else result.reason
            self._set_status(message)
            notify("PvPLedger Sync", message)
            return

        if scan.pending_matches:
            self._set_status(scan.note)
            return

        if scan.awaiting_reload_matches and result.reason in _SILENT_EXPORT_REASONS:
            return

        if backfilled and reconcile:
            self._set_status(reconcile.reason)
            notify("PvPLedger Sync", reconcile.reason)
            return

        if self._is_idle_export_state(result=result, scan=scan, reconcile=reconcile):
            return

        if result.reason:
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
