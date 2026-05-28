"""Download ladder AppData payloads into the WoW addon folder."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError

from .config import SyncConfig, save_config
from .manifest import RemoteManifest, fetch_app_data, fetch_manifest, manifest_is_newer


@dataclass
class SyncResult:
    """Outcome of one sync attempt."""

    updated: bool
    reason: str
    manifest_generated_date: str = ""
    app_data_path: str = ""
    source: str = ""


def repo_root_dir() -> Path:
    """Return the PvPLedger repository root bundled beside Sync/."""

    return Path(__file__).resolve().parent.parent.parent


def local_app_data_source() -> Path:
    """Return the repo-local AppData.lua used as an offline fallback."""

    return repo_root_dir() / "PvPLedger-AppHelper" / "AppData.lua"


def local_manifest_source() -> Path:
    """Return the repo-local ladder manifest used as an offline fallback."""

    return repo_root_dir() / "Data" / "ladder-manifest.json"


def load_local_manifest() -> RemoteManifest:
    """Load ladder-manifest.json from the local repository checkout."""

    payload = json.loads(local_manifest_source().read_text(encoding="utf-8"))
    return RemoteManifest(
        region=str(payload.get("region", "US")),
        generated_date=str(payload.get("generatedDate", "")),
        brackets=dict(payload.get("brackets", {})),
    )


def atomic_write_text(path: Path, content: str) -> None:
    """Write a file atomically to avoid partial reads by WoW."""

    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    temp_path.write_text(content, encoding="utf-8")
    temp_path.replace(path)


def validate_app_data(content: str) -> bool:
    """Return True when AppData.lua contains the expected bridge payload."""

    return "PVL_AppHelperPendingSnapshots" in content


def finalize_sync(
    config: SyncConfig,
    *,
    app_data_path: Path,
    manifest_generated_date: str,
    source: str,
) -> SyncResult:
    """Persist sync metadata after AppData.lua was written."""

    config.last_manifest_generated_date = manifest_generated_date
    config.last_app_data_sync_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    save_config(config)
    return SyncResult(
        updated=True,
        reason=f"AppData.lua updated from {source}.",
        manifest_generated_date=manifest_generated_date,
        app_data_path=str(app_data_path),
        source=source,
    )


def sync_app_data_from_local(config: SyncConfig, *, force: bool = False) -> SyncResult:
    """Copy AppData.lua from the local PvPLedger repository checkout."""

    source_path = local_app_data_source()
    if not source_path.exists():
        return SyncResult(
            updated=False,
            reason=f"Local AppData source not found: {source_path}",
        )

    manifest = load_local_manifest()
    if not force and not manifest_is_newer(manifest, config.last_manifest_generated_date):
        return SyncResult(
            updated=False,
            reason="Already up to date (local repo).",
            manifest_generated_date=manifest.generated_date,
            app_data_path=str(config.app_data_path),
            source="local-repo",
        )

    content = source_path.read_text(encoding="utf-8")
    if not validate_app_data(content):
        return SyncResult(updated=False, reason="Local AppData.lua did not look valid.")

    atomic_write_text(config.app_data_path, content)
    return finalize_sync(
        config,
        app_data_path=config.app_data_path,
        manifest_generated_date=manifest.generated_date,
        source="local-repo",
    )


def sync_app_data_from_remote(config: SyncConfig, *, force: bool = False) -> SyncResult:
    """Download AppData.lua from GitHub."""

    token = config.resolved_github_token()
    manifest = fetch_manifest(repo=config.repo, branch=config.branch, token=token)
    if not force and not manifest_is_newer(manifest, config.last_manifest_generated_date):
        return SyncResult(
            updated=False,
            reason="Already up to date.",
            manifest_generated_date=manifest.generated_date,
            app_data_path=str(config.app_data_path),
            source="github",
        )

    app_data = fetch_app_data(repo=config.repo, branch=config.branch, token=token)
    if not validate_app_data(app_data):
        return SyncResult(updated=False, reason="Downloaded AppData.lua did not look valid.")

    atomic_write_text(config.app_data_path, app_data)
    return finalize_sync(
        config,
        app_data_path=config.app_data_path,
        manifest_generated_date=manifest.generated_date,
        source="github",
    )


def sync_app_data(config: SyncConfig, *, force: bool = False, local_only: bool = False) -> SyncResult:
    """Sync AppData.lua from GitHub, falling back to the local repo when remote is unavailable."""

    if not config.wow_addons_dir:
        return SyncResult(updated=False, reason="WoW AddOns directory is not configured.")

    if local_only:
        return sync_app_data_from_local(config, force=force)

    try:
        return sync_app_data_from_remote(config, force=force)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        local_result = sync_app_data_from_local(config, force=force)
        if local_result.updated or local_result.reason == "Already up to date (local repo).":
            if not local_result.updated:
                local_result.reason = (
                    f"{local_result.reason} GitHub was unavailable ({exc}); used local repo copy."
                )
            else:
                local_result.reason = (
                    f"{local_result.reason} GitHub was unavailable ({exc}); used local repo copy."
                )
            return local_result

        return SyncResult(
            updated=False,
            reason=(
                f"GitHub sync failed ({exc}) and local fallback also failed: {local_result.reason}"
            ),
        )
