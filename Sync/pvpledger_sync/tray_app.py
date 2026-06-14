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
from .i18n import init_i18n, t
from .icons import build_tray_icon
from .ingest_server import default_ingest_dir, ensure_ingest_server_running
from .notify import notify
from .single_instance import try_acquire_single_instance
from .startup import is_startup_installed
from .uploader import upload_exports


_SILENT_EXPORT_REASON_KEYS = frozenset(
    {
        "UPLOAD.NO_PENDING_EXPORTS",
        "UPLOAD.NO_SAVED_VARS",
    }
)


class TrayApp:
    """Background tray controller that polls GitHub and syncs AppData.lua."""

    def __init__(self) -> None:
        self._config = load_config()
        self._icon: pystray.Icon | None = None
        self._stop_event = threading.Event()
        self._worker: threading.Thread | None = None
        self._last_message = t("TRAY.RUNNING")

    def _set_status(self, message: str) -> None:
        """Store the latest status message shown in the tray tooltip."""

        self._last_message = message
        if self._icon is not None:
            self._icon.title = f"{t('APP.NAME')}\n{message}"

    def _open_path(self, path: Path) -> None:
        """Open one folder in Windows Explorer."""

        if not path.exists():
            notify(t("APP.NAME"), t("TRAY.PATH_NOT_FOUND", path=path))
            return
        subprocess.Popen(["explorer", str(path)], shell=False)  # noqa: S603

    def _run_sync(self, *, force: bool = False) -> None:
        """Execute one ladder sync attempt and update tray state."""

        if not self._config.wow_addons_dir:
            self._set_status(t("TRAY.NOT_INITIALIZED"))
            notify(t("APP.NAME"), t("TRAY.RUN_INIT_BEFORE_SYNC"))
            return

        try:
            result = sync_app_data(self._config, force=force)
        except Exception as exc:  # noqa: BLE001
            message = t("TRAY.LADDER_SYNC_FAILED", error=exc)
            self._set_status(message)
            notify(t("APP.NAME"), message)
            return

        self._config = load_config()
        self._set_status(result.reason)
        if result.updated:
            reload_hint = t("TRAY.RELOAD_HINT")
            if result.player_index_count > 0:
                notify(t("APP.NAME"), f"{result.reason}{reload_hint}")
            else:
                notify(
                    t("APP.NAME"),
                    f"{t('TRAY.LADDER_AGGREGATES_EMPTY')}{reload_hint}",
                )
        elif result.reason_key in {
            "SYNC.ALREADY_UP_TO_DATE_LOCAL",
            "SYNC.ALREADY_UP_TO_DATE_INSTALLED",
        }:
            player_count, installed_status = inspect_installed_app_data(self._config)
            if player_count <= 0:
                self._set_status(f"{result.reason} {installed_status}")

    def _is_idle_export_state(
        self,
        *,
        result,
        scan,
    ) -> bool:
        """
        Return True when export upload has nothing actionable to report.

        Parameters
        ----------
        result:
            Upload attempt result from the uploader.
        scan:
            SavedVariables scan summary.

        Returns
        -------
        bool
            True when the tray should stay quiet.
        """

        if scan.pending_matches:
            return False
        if result.match_count > 0:
            return False
        if result.reason_key in _SILENT_EXPORT_REASON_KEYS:
            return True
        return False

    def _run_export_upload(self) -> None:
        """Upload pending match exports and update tray state."""

        if not self._config.wow_addons_dir:
            self._set_status(t("TRAY.NOT_INITIALIZED"))
            return

        result = upload_exports(self._config)
        self._config = load_config()
        scan = scan_exports_for_config(self._config)

        if result.uploaded and result.match_count > 0:
            self._set_status(result.reason)
            notify(t("APP.NAME"), result.reason)
            return

        if scan.pending_matches:
            self._set_status(scan.note)
            return

        if scan.awaiting_reload_matches and result.reason_key in _SILENT_EXPORT_REASON_KEYS:
            return

        if self._is_idle_export_state(result=result, scan=scan):
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

        notify(t("APP.NAME"), self._last_message)

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
            notify(t("APP.NAME"), t("TRAY.RUN_INIT_FIRST"))

        if self._config.ingest_enabled:
            if ensure_ingest_server_running(self._config):
                ingest_status = t(
                    "TRAY.INGEST_RUNNING",
                    host=self._config.ingest_host,
                    port=self._config.ingest_port,
                )
            else:
                ingest_status = t("TRAY.INGEST_FAILED_START")
                notify(t("APP.NAME"), t("TRAY.INGEST_FAILED_PORT"))
        else:
            ingest_status = t("TRAY.INGEST_DISABLED")

        startup_label = (
            t("TRAY.STARTUP_ENABLED")
            if is_startup_installed()
            else t("TRAY.STARTUP_DISABLED")
        )
        self._set_status(f"{ingest_status} | {startup_label}")

        menu = pystray.Menu(
            Item(t("TRAY.MENU_SYNC_LADDER"), self._sync_now),
            Item(t("TRAY.MENU_UPLOAD_EXPORTS"), self._upload_exports_now),
            Item(t("TRAY.MENU_SHOW_STATUS"), self._show_status),
            Item(t("TRAY.MENU_OPEN_APPHELPER"), self._open_app_helper),
            Item(t("TRAY.MENU_OPEN_INGEST"), self._open_ingest_dir),
            Item(t("TRAY.MENU_OPEN_CONFIG"), self._open_config),
            pystray.Menu.SEPARATOR,
            Item(t("TRAY.MENU_EXIT"), self._exit),
        )

        self._icon = pystray.Icon(
            t("APP.NAME"),
            build_tray_icon(),
            t("APP.NAME"),
            menu,
        )

        self._worker = threading.Thread(target=self._poll_loop, daemon=True)
        self._worker.start()
        self._icon.run()


def run_tray_app() -> None:
    """Launch the tray application."""

    init_i18n()

    if not try_acquire_single_instance():
        notify(t("APP.NAME"), t("TRAY.ALREADY_RUNNING"))
        return

    TrayApp().run()
