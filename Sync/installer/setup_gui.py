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


class InstallerApp:
    """Simple Tkinter installer for PvPLedger Sync."""

    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("PvPLedger Sync Setup")
        self.root.geometry("620x420")
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
            text="PvPLedger Sync Setup",
            font=("Segoe UI", 16, "bold"),
        ).pack(anchor="w")
        ttk.Label(
            frame,
            text=(
                "This installs the PvPLedger AppHelper bridge and background sync app.\n"
                "You still need the main PvPLedger addon from CurseForge/Wago/GitHub."
            ),
            wraplength=560,
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

        ttk.Label(frame, textvariable=self.status, wraplength=560).pack(anchor="w", pady=(16, 8))

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
            messagebox.showerror("PvPLedger Sync", "Please choose a valid WoW AddOns folder.")
            return

        try:
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

            app_helper_source = resource_path("PvPLedger-AppHelper")
            if not app_helper_source.exists():
                raise FileNotFoundError(f"Missing bundled AppHelper addon: {app_helper_source}")

            app_helper_target = addons_path / "PvPLedger-AppHelper"
            if app_helper_target.exists():
                shutil.rmtree(app_helper_target)
            shutil.copytree(app_helper_source, app_helper_target)

            config = apply_config_defaults(SyncConfig(wow_addons_dir=str(addons_path)))
            save_config(config)

            if self.run_at_login.get():
                install_startup()

            self.status.set("Installation complete.")
            messagebox.showinfo(
                "PvPLedger Sync",
                (
                    "Installation complete.\n\n"
                    f"AppHelper installed to:\n{app_helper_target}\n\n"
                    f"Sync app installed to:\n{sync_exe}\n\n"
                    "Enable PvPLedger + PvPLedger AppHelper in WoW, then /reload."
                ),
            )

            if self.launch_now.get():
                subprocess.Popen([str(sync_exe)], shell=False)  # noqa: S603
        except Exception as exc:  # noqa: BLE001 - installer should show the real error to the user
            messagebox.showerror("PvPLedger Sync", f"Installation failed:\n{exc}")
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
