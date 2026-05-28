"""Persistent configuration for PvPLedger Sync."""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, fields
from pathlib import Path

from .paths import resource_path

DEFAULT_REPO = "simplebooleanjim/PvPLedger"
DEFAULT_BRANCH = "main"
DEFAULT_REGION = "US"
DEFAULT_POLL_MINUTES = 15
DEFAULT_INGEST_HOST = "127.0.0.1"
DEFAULT_INGEST_PORT = 8765
DEFAULT_UPLOAD_URL = f"http://{DEFAULT_INGEST_HOST}:{DEFAULT_INGEST_PORT}/api/v1/exports"


@dataclass
class SyncConfig:
    """User configuration stored outside the WoW addon folder."""

    wow_addons_dir: str = ""
    repo: str = DEFAULT_REPO
    branch: str = DEFAULT_BRANCH
    region: str = DEFAULT_REGION
    poll_minutes: int = DEFAULT_POLL_MINUTES
    upload_url: str = ""
    export_enabled: bool = True
    export_spool_dir: str = ""
    ingest_enabled: bool = True
    ingest_host: str = DEFAULT_INGEST_HOST
    ingest_port: int = DEFAULT_INGEST_PORT
    ingest_dir: str = ""
    github_token: str = ""
    upload_token: str = ""
    github_export_enabled: bool = True
    github_export_path: str = "Data/match-exports"
    last_manifest_generated_date: str = ""
    last_app_data_sync_at: str = ""
    last_export_upload_at: str = ""
    last_export_upload_count: int = 0
    last_export_batch_id: str = ""
    pending_upload_match_ids: list[str] | None = None

    def __post_init__(self) -> None:
        """Normalize optional list fields loaded from JSON."""

        if self.pending_upload_match_ids is None:
            self.pending_upload_match_ids = []

    @property
    def app_helper_dir(self) -> Path:
        """Return the installed PvPLedger-AppHelper addon directory."""

        return Path(self.wow_addons_dir) / "PvPLedger-AppHelper"

    @property
    def app_data_path(self) -> Path:
        """Return the AppData.lua path written by sync."""

        return self.app_helper_dir / "AppData.lua"

    @property
    def export_ack_path(self) -> Path:
        """Return the ExportAck.lua path written after export upload."""

        return self.app_helper_dir / "ExportAck.lua"

    def resolved_github_token(self) -> str:
        """Return the configured GitHub token, including environment overrides."""

        for value in (
            self.github_token,
            os.environ.get("PVL_GITHUB_TOKEN", ""),
            os.environ.get("GITHUB_TOKEN", ""),
        ):
            if value:
                return value.strip()
        return ""

    def resolved_upload_token(self) -> str:
        """Return the configured upload token, including environment overrides."""

        for value in (
            self.upload_token,
            os.environ.get("PVL_UPLOAD_TOKEN", ""),
        ):
            if value:
                return value.strip()
        return ""


def load_release_upload_config() -> dict[str, str]:
    """
    Load maintainer-only upload defaults bundled at installer build time.

    Returns
    -------
    dict[str, str]
        Optional ``upload_url`` and ``upload_token`` values.
    """

    release_path = Path(__file__).resolve().parent.parent / "release-config.json"
    candidate_paths = [release_path, resource_path("release-config.json")]
    for path in candidate_paths:
        if not path.exists():
            continue

        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue

        if not isinstance(payload, dict):
            continue

        result: dict[str, str] = {}
        upload_url = str(payload.get("upload_url", "")).strip()
        upload_token = str(payload.get("upload_token", "")).strip()
        if upload_url:
            result["upload_url"] = upload_url
        if upload_token:
            result["upload_token"] = upload_token
        return result

    return {}


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
    allowed = {field.name for field in fields(SyncConfig)}
    filtered = {key: value for key, value in payload.items() if key in allowed}
    return SyncConfig(**filtered)


def save_config(config: SyncConfig, path: Path | None = None) -> Path:
    """Persist sync config to disk."""

    config_path = path or default_config_path()
    config_path.write_text(json.dumps(asdict(config), indent=2) + "\n", encoding="utf-8")
    return config_path


def apply_config_defaults(config: SyncConfig) -> SyncConfig:
    """
    Fill in default sync settings for newly initialized configs.

    Parameters
    ----------
    config:
        Loaded or partially initialized sync configuration.

    Returns
    -------
    SyncConfig
        Config with default upload and ingest settings applied.
    """

    if not config.upload_url:
        config.upload_url = DEFAULT_UPLOAD_URL
    if not config.ingest_host:
        config.ingest_host = DEFAULT_INGEST_HOST
    if not config.ingest_port:
        config.ingest_port = DEFAULT_INGEST_PORT

    release_upload = load_release_upload_config()
    if release_upload.get("upload_url") and (
        not config.upload_url or config.upload_url == DEFAULT_UPLOAD_URL
    ):
        config.upload_url = release_upload["upload_url"]
    if release_upload.get("upload_token") and not config.upload_token:
        config.upload_token = release_upload["upload_token"]
    return config


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
