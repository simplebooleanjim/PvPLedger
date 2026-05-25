"""Download ladder AppData payloads into the WoW addon folder."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from .config import SyncConfig, save_config
from .manifest import app_data_url, fetch_manifest, fetch_text, manifest_is_newer


@dataclass
class SyncResult:
    """Outcome of one sync attempt."""

    updated: bool
    reason: str
    manifest_generated_date: str = ""
    app_data_path: str = ""


def atomic_write_text(path: Path, content: str) -> None:
    """Write a file atomically to avoid partial reads by WoW."""

    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    temp_path.write_text(content, encoding="utf-8")
    temp_path.replace(path)


def sync_app_data(config: SyncConfig, *, force: bool = False) -> SyncResult:
    """Download AppData.lua when the remote manifest is newer."""

    if not config.wow_addons_dir:
        return SyncResult(updated=False, reason="WoW AddOns directory is not configured.")

    manifest = fetch_manifest(repo=config.repo, branch=config.branch)
    if not force and not manifest_is_newer(manifest, config.last_manifest_generated_date):
        return SyncResult(
            updated=False,
            reason="Already up to date.",
            manifest_generated_date=manifest.generated_date,
            app_data_path=str(config.app_data_path),
        )

    app_data = fetch_text(app_data_url(repo=config.repo, branch=config.branch))
    if "PVL_AppHelperPendingSnapshots" not in app_data:
        return SyncResult(updated=False, reason="Downloaded AppData.lua did not look valid.")

    atomic_write_text(config.app_data_path, app_data)
    config.last_manifest_generated_date = manifest.generated_date
    config.last_app_data_sync_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    save_config(config)

    return SyncResult(
        updated=True,
        reason="AppData.lua updated. Reload UI in WoW with /reload.",
        manifest_generated_date=manifest.generated_date,
        app_data_path=str(config.app_data_path),
    )
