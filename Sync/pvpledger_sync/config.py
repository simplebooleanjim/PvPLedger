"""Persistent configuration for PvPLedger Sync."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

DEFAULT_REPO = "simplebooleanjim/PvPLedger"
DEFAULT_BRANCH = "main"
DEFAULT_REGION = "US"
DEFAULT_POLL_MINUTES = 15


@dataclass
class SyncConfig:
    """User configuration stored outside the WoW addon folder."""

    wow_addons_dir: str = ""
    repo: str = DEFAULT_REPO
    branch: str = DEFAULT_BRANCH
    region: str = DEFAULT_REGION
    poll_minutes: int = DEFAULT_POLL_MINUTES
    upload_url: str = ""
    last_manifest_generated_date: str = ""
    last_app_data_sync_at: str = ""

    @property
    def app_helper_dir(self) -> Path:
        """Return the installed PvPLedger-AppHelper addon directory."""

        return Path(self.wow_addons_dir) / "PvPLedger-AppHelper"

    @property
    def app_data_path(self) -> Path:
        """Return the AppData.lua path written by sync."""

        return self.app_helper_dir / "AppData.lua"


def default_config_path() -> Path:
    """Return the default config file location on Windows."""

    appdata = Path.home() / "AppData" / "Roaming" / "PvPLedger"
    appdata.mkdir(parents=True, exist_ok=True)
    return appdata / "sync-config.json"


def load_config(path: Path | None = None) -> SyncConfig:
    """Load sync config from disk or return defaults."""

    config_path = path or default_config_path()
    if not config_path.exists():
        return SyncConfig()

    payload = json.loads(config_path.read_text(encoding="utf-8"))
    return SyncConfig(**payload)


def save_config(config: SyncConfig, path: Path | None = None) -> Path:
    """Persist sync config to disk."""

    config_path = path or default_config_path()
    config_path.write_text(json.dumps(asdict(config), indent=2) + "\n", encoding="utf-8")
    return config_path


def guess_addons_dir() -> Path | None:
    """Best-effort detection of a retail WoW AddOns directory."""

    candidates = [
        Path("e:/games/World of Warcraft/_retail_/Interface/AddOns"),
        Path.home() / "Games" / "World of Warcraft" / "_retail_" / "Interface" / "AddOns",
        Path("C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns"),
        Path("C:/Program Files/World of Warcraft/_retail_/Interface/AddOns"),
    ]
    for candidate in candidates:
        if (candidate / "PvPLedger").exists() or (candidate / "PvPLedger-AppHelper").exists():
            return candidate
        if candidate.exists():
            return candidate
    return None
