"""Install PvPLedger Sync and AppHelper for end users."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from pvpledger_sync.config import SyncConfig, apply_config_defaults, save_config
from pvpledger_sync.i18n import init_i18n, t
from pvpledger_sync.paths import default_install_dir, installed_sync_exe, is_frozen, resource_path
from pvpledger_sync.startup import install_startup
from pvpledger_sync.uninstall import uninstall_tray_app
from pvpledger_sync.wow_paths import detect_wow_addons_dir


def installer_icon_path() -> Path:
    """Return the Windows ICO used by the setup window."""

    if is_frozen():
        return resource_path("PvPLedger.ico")

    return Path(__file__).resolve().parent.parent / "assets" / "PvPLedger.ico"


def replace_addon_directory(source: Path, destination: Path) -> None:
    """
    Install one AddOns subdirectory by merging a bundled copy into the target.

    Uses merge-copy instead of deleting the destination first so developer
    checkouts keep local folders such as ``.git``, ``Sync``, and ``Server``.

    Parameters
    ----------
    source:
        Bundled addon directory inside the installer resources.
    destination:
        Target path under the user's WoW AddOns folder.
    """

    if not source.exists():
        raise FileNotFoundError(t("SETUP.MISSING_BUNDLED_ADDON", path=source))

    source = source.resolve()
    destination = destination.resolve()
    if source == destination:
        return

    destination.mkdir(parents=True, exist_ok=True)

    for entry in source.iterdir():
        target_entry = destination / entry.name
        if entry.is_dir():
            if target_entry.exists() and target_entry.is_file():
                target_entry.unlink()
            shutil.copytree(entry, target_entry, dirs_exist_ok=True)
        else:
            shutil.copy2(entry, target_entry)


def resolve_data_addon_source(addons_path: Path, data_addon_name: str) -> Path | None:
    """
    Resolve one regional data-addon source directory.

    Parameters
    ----------
    addons_path:
        Path to the user's WoW ``Interface/AddOns`` directory.
    data_addon_name:
        Folder name such as ``PvPLedger-Data-EU``.

    Returns
    -------
    Path | None
        Bundled installer source, or a nested checkout copy when present.
    """

    bundled = resource_path(data_addon_name)
    if bundled.exists():
        return bundled

    nested = addons_path / "PvPLedger" / data_addon_name
    if nested.exists():
        return nested

    return None


def install_bundled_addons(addons_path: Path) -> list[str]:
    """
    Install all bundled PvPLedger addon folders into one AddOns directory.

    Parameters
    ----------
    addons_path:
        Path to the user's WoW ``Interface/AddOns`` directory.

    Returns
    -------
    list[str]
        Human-readable names of addons that were installed.
    """

    installed: list[str] = []

    main_addon_source = resource_path("PvPLedger")
    if main_addon_source.exists():
        replace_addon_directory(main_addon_source, addons_path / "PvPLedger")
        installed.append("PvPLedger")

    app_helper_source = resource_path("PvPLedger-AppHelper")
    if app_helper_source.exists():
        replace_addon_directory(app_helper_source, addons_path / "PvPLedger-AppHelper")
        installed.append("PvPLedger-AppHelper")

    for data_addon_name in ("PvPLedger-Data-US", "PvPLedger-Data-EU", "PvPLedger-Data-KR", "PvPLedger-Data-TW"):
        data_addon_source = resolve_data_addon_source(addons_path, data_addon_name)
        if data_addon_source and data_addon_source.exists():
            replace_addon_directory(data_addon_source, addons_path / data_addon_name)
            installed.append(data_addon_name)

    if not installed:
        raise FileNotFoundError(t("SETUP.MISSING_BUNDLED_ADDONS"))

    return installed


class InstallerApp:
    """Simple Tkinter installer for PvPLedger Sync."""

    def __init__(self) -> None:
        init_i18n()

        self.root = tk.Tk()
        self.root.title(t("APP.SETUP_TITLE"))
        self.root.geometry("640x460")
        self.root.resizable(False, False)

        detected = detect_wow_addons_dir()
        self.addons_dir = tk.StringVar(value=str(detected) if detected else "")
        self.run_at_login = tk.BooleanVar(value=True)
        self.launch_now = tk.BooleanVar(value=True)
        self.status = tk.StringVar(value=t("SETUP.READY"))

        self._build_ui()
        self._apply_window_icon()

    def _apply_window_icon(self) -> None:
        """Apply the PvPLedger icon to the installer window when available."""

        icon_path = installer_icon_path()
        if icon_path.exists():
            self.root.iconbitmap(default=str(icon_path))

    def _build_ui(self) -> None:
        """Build the installer window."""

        frame = ttk.Frame(self.root, padding=16)
        frame.pack(fill="both", expand=True)

        ttk.Label(
            frame,
            text=t("SETUP.HEADING"),
            font=("Segoe UI", 16, "bold"),
        ).pack(anchor="w")
        ttk.Label(
            frame,
            text=t("SETUP.DESCRIPTION"),
            wraplength=580,
        ).pack(anchor="w", pady=(8, 16))

        path_row = ttk.Frame(frame)
        path_row.pack(fill="x", pady=(0, 8))
        ttk.Label(path_row, text=t("SETUP.ADDONS_FOLDER")).pack(anchor="w")
        entry_row = ttk.Frame(path_row)
        entry_row.pack(fill="x", pady=(4, 0))
        ttk.Entry(entry_row, textvariable=self.addons_dir).pack(side="left", fill="x", expand=True)
        ttk.Button(entry_row, text=t("SETUP.BROWSE"), command=self._browse).pack(side="left", padx=(8, 0))

        ttk.Checkbutton(frame, text=t("SETUP.RUN_AT_LOGIN"), variable=self.run_at_login).pack(
            anchor="w",
            pady=(8, 4),
        )
        ttk.Checkbutton(frame, text=t("SETUP.LAUNCH_AFTER_INSTALL"), variable=self.launch_now).pack(
            anchor="w",
        )

        ttk.Label(frame, textvariable=self.status, wraplength=580).pack(anchor="w", pady=(16, 8))

        button_row = ttk.Frame(frame)
        button_row.pack(fill="x", pady=(12, 0))
        ttk.Button(button_row, text=t("SETUP.INSTALL"), command=self._install).pack(side="right")
        ttk.Button(button_row, text=t("SETUP.UNINSTALL_SYNC"), command=self._uninstall).pack(side="right", padx=(0, 8))
        ttk.Button(button_row, text=t("SETUP.CLOSE"), command=self.root.destroy).pack(side="right", padx=(0, 8))

    def _browse(self) -> None:
        """Prompt the user to choose the AddOns directory."""

        selected = filedialog.askdirectory(title=t("SETUP.BROWSE_DIALOG_TITLE"))
        if selected:
            self.addons_dir.set(selected)

    def _uninstall(self) -> None:
        """Remove the installed PvPLedger Sync tray app."""

        install_dir = default_install_dir()
        confirmed = messagebox.askyesno(
            t("APP.SETUP_TITLE"),
            t("SETUP.UNINSTALL_CONFIRM", install_dir=install_dir),
        )
        if not confirmed:
            return

        try:
            self.status.set(t("SETUP.UNINSTALLING"))
            self.root.update_idletasks()

            result = uninstall_tray_app()
            summary = "\n".join(f"- {line}" for line in result.messages)
            self.status.set(t("SETUP.UNINSTALL_COMPLETE"))

            if result.removed_executable or result.removed_startup or result.stopped_tray:
                messagebox.showinfo(
                    t("APP.SETUP_TITLE"),
                    t("SETUP.UNINSTALL_SUCCESS", summary=summary),
                )
            else:
                messagebox.showwarning(
                    t("APP.SETUP_TITLE"),
                    t("SETUP.UNINSTALL_NOT_FOUND", summary=summary),
                )
        except Exception as exc:  # noqa: BLE001 - installer should show the real error to the user
            messagebox.showerror(t("APP.SETUP_TITLE"), t("SETUP.UNINSTALL_FAILED", error=exc))
            self.status.set(t("SETUP.UNINSTALL_FAILED", error=exc))

    def _install(self) -> None:
        """Run the installation steps."""

        addons_path = Path(self.addons_dir.get().strip())
        if not addons_path.exists():
            messagebox.showerror(t("APP.SETUP_TITLE"), t("SETUP.INVALID_ADDONS_PATH"))
            return

        try:
            self.status.set(t("SETUP.INSTALLING_ADDONS"))
            self.root.update_idletasks()

            installed_addons = install_bundled_addons(addons_path)

            self.status.set(t("SETUP.INSTALLING_SYNC"))
            self.root.update_idletasks()

            install_dir = default_install_dir()
            install_dir.mkdir(parents=True, exist_ok=True)
            sync_exe = installed_sync_exe()

            sync_source = resource_path("PvPLedger-Sync.exe")
            if not sync_source.exists():
                raise FileNotFoundError(t("SETUP.MISSING_SYNC_EXE"))
            shutil.copy2(sync_source, sync_exe)

            config = apply_config_defaults(
                SyncConfig(
                    wow_addons_dir=str(addons_path),
                    export_enabled=True,
                    ingest_enabled=False,
                )
            )
            save_config(config)

            if self.run_at_login.get():
                install_startup()

            addon_list = ", ".join(installed_addons)
            self.status.set(t("SETUP.INSTALL_COMPLETE_STATUS"))
            messagebox.showinfo(
                t("APP.SETUP_TITLE"),
                t(
                    "SETUP.INSTALL_COMPLETE_BODY",
                    addons=addon_list,
                    sync_exe=sync_exe,
                ),
            )

            if self.launch_now.get():
                subprocess.Popen([str(sync_exe)], shell=False)  # noqa: S603
        except Exception as exc:  # noqa: BLE001 - installer should show the real error to the user
            messagebox.showerror(t("APP.SETUP_TITLE"), t("SETUP.INSTALL_FAILED", error=exc))
            self.status.set(t("SETUP.INSTALL_FAILED", error=exc))

    def run(self) -> None:
        """Start the installer UI."""

        self.root.mainloop()


def main() -> None:
    """Launch the installer UI."""

    InstallerApp().run()


if __name__ == "__main__":
    if not is_frozen():
        sync_root = Path(__file__).resolve().parent.parent
        sys.path.insert(0, str(sync_root))
    main()
