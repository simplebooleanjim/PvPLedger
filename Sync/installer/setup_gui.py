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
from pvpledger_sync.paths import default_install_dir, installed_sync_exe, is_frozen, resource_path
from pvpledger_sync.startup import install_startup
from pvpledger_sync.wow_paths import detect_wow_addons_dir


def installer_icon_path() -> Path:
    """Return the Windows ICO used by the setup window."""

    if is_frozen():
        return resource_path("PvPLedger.ico")

    return Path(__file__).resolve().parent.parent / "assets" / "PvPLedger.ico"


def replace_addon_directory(source: Path, destination: Path) -> None:
    """
    Replace one AddOns subdirectory with a bundled copy.

    Parameters
    ----------
    source:
        Bundled addon directory inside the installer resources.
    destination:
        Target path under the user's WoW AddOns folder.
    """

    if not source.exists():
        raise FileNotFoundError(f"Missing bundled addon: {source}")

    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


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

    data_addon_source = resource_path("PvPLedger-Data-US")
    if data_addon_source.exists():
        replace_addon_directory(data_addon_source, addons_path / "PvPLedger-Data-US")
        installed.append("PvPLedger-Data-US")

    if not installed:
        raise FileNotFoundError(
            "No bundled addons were found. Rebuild with build_installer.bat first."
        )

    return installed


class InstallerApp:
    """Simple Tkinter installer for PvPLedger Sync."""

    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("PvPLedger Setup")
        self.root.geometry("640x460")
        self.root.resizable(False, False)

        detected = detect_wow_addons_dir()
        self.addons_dir = tk.StringVar(value=str(detected) if detected else "")
        self.run_at_login = tk.BooleanVar(value=True)
        self.launch_now = tk.BooleanVar(value=True)
        self.status = tk.StringVar(value="Ready to install.")

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
            text="PvPLedger Setup",
            font=("Segoe UI", 16, "bold"),
        ).pack(anchor="w")
        ttk.Label(
            frame,
            text=(
                "Installs PvPLedger, the AppHelper bridge, optional US ladder data, "
                "and the background sync app.\n"
                "After install: enable the addons in WoW, then /reload when Sync says "
                "ladder data updated."
            ),
            wraplength=580,
        ).pack(anchor="w", pady=(8, 16))

        path_row = ttk.Frame(frame)
        path_row.pack(fill="x", pady=(0, 8))
        ttk.Label(path_row, text="WoW AddOns folder:").pack(anchor="w")
        entry_row = ttk.Frame(path_row)
        entry_row.pack(fill="x", pady=(4, 0))
        ttk.Entry(entry_row, textvariable=self.addons_dir).pack(side="left", fill="x", expand=True)
        ttk.Button(entry_row, text="Browse...", command=self._browse).pack(side="left", padx=(8, 0))

        ttk.Checkbutton(frame, text="Run PvPLedger Sync at Windows login", variable=self.run_at_login).pack(
            anchor="w",
            pady=(8, 4),
        )
        ttk.Checkbutton(frame, text="Launch PvPLedger Sync after install", variable=self.launch_now).pack(
            anchor="w",
        )

        ttk.Label(frame, textvariable=self.status, wraplength=580).pack(anchor="w", pady=(16, 8))

        button_row = ttk.Frame(frame)
        button_row.pack(fill="x", pady=(12, 0))
        ttk.Button(button_row, text="Install", command=self._install).pack(side="right")
        ttk.Button(button_row, text="Close", command=self.root.destroy).pack(side="right", padx=(0, 8))

    def _browse(self) -> None:
        """Prompt the user to choose the AddOns directory."""

        selected = filedialog.askdirectory(title="Select WoW Interface/AddOns folder")
        if selected:
            self.addons_dir.set(selected)

    def _install(self) -> None:
        """Run the installation steps."""

        addons_path = Path(self.addons_dir.get().strip())
        if not addons_path.exists():
            messagebox.showerror("PvPLedger Setup", "Please choose a valid WoW AddOns folder.")
            return

        try:
            self.status.set("Installing PvPLedger addons...")
            self.root.update_idletasks()

            installed_addons = install_bundled_addons(addons_path)

            self.status.set("Installing PvPLedger Sync...")
            self.root.update_idletasks()

            install_dir = default_install_dir()
            install_dir.mkdir(parents=True, exist_ok=True)
            sync_exe = installed_sync_exe()

            sync_source = resource_path("PvPLedger-Sync.exe")
            if not sync_source.exists():
                raise FileNotFoundError(
                    "Missing bundled sync executable. Rebuild with build_installer.bat first."
                )
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
            self.status.set("Installation complete.")
            messagebox.showinfo(
                "PvPLedger Setup",
                (
                    "Installation complete.\n\n"
                    f"Addons installed: {addon_list}\n"
                    f"Sync app installed to:\n{sync_exe}\n\n"
                    "Next steps:\n"
                    "1. Enable PvPLedger + PvPLedger-AppHelper in WoW\n"
                    "2. Leave PvPLedger Sync running in the tray\n"
                    "3. /reload after Sync notifies you that ladder data updated\n\n"
                    "Match exports upload automatically after games — no tokens to configure."
                ),
            )

            if self.launch_now.get():
                subprocess.Popen([str(sync_exe)], shell=False)  # noqa: S603
        except Exception as exc:  # noqa: BLE001 - installer should show the real error to the user
            messagebox.showerror("PvPLedger Setup", f"Installation failed:\n{exc}")
            self.status.set(f"Installation failed: {exc}")

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
