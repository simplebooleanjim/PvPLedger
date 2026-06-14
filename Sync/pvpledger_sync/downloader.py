"""Download ladder AppData payloads into the WoW addon folder."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError

from .config import SyncConfig, save_config
from .i18n import t
from .manifest import (
    RemoteManifest,
    fetch_app_data,
    fetch_app_data_generated_at,
    fetch_manifest,
    manifest_is_newer,
    read_app_data_generated_at,
)

_PLAYER_INDEX_PATTERN = re.compile(r'\bspecKey = "')


@dataclass
class SyncResult:
    """Outcome of one sync attempt."""

    updated: bool
    reason: str
    reason_key: str = ""
    manifest_generated_date: str = ""
    app_data_path: str = ""
    source: str = ""
    player_index_count: int = 0


def count_players_in_app_data(content: str) -> int:
    """
    Count indexed player rows in one AppData.lua payload.

    Parameters
    ----------
    content:
        Raw AppData.lua text.

    Returns
    -------
    int
        Number of Name-Realm player entries found.
    """

    return len(_PLAYER_INDEX_PATTERN.findall(content))


def describe_player_index_status(player_count: int) -> str:
    """
    Build a short status line for the ladder player index.

    Parameters
    ----------
    player_count:
        Number of indexed players in AppData.lua.

    Returns
    -------
    str
        Human-readable status for CLI and tray output.
    """

    if player_count <= 0:
        return t("SYNC.PLAYER_INDEX_EMPTY")
    return t("SYNC.PLAYER_INDEX_COUNT", count=f"{player_count:,}")


def repo_root_dir() -> Path:
    """Return the PvPLedger repository root bundled beside Sync/."""

    return Path(__file__).resolve().parent.parent.parent


def regional_manifest_path(region: str) -> Path:
    """Return the repo-local ladder manifest path for one region."""

    return repo_root_dir() / "Data" / regional_manifest_filename(region)


def regional_app_data_path(region: str) -> Path:
    """Return the repo-local AppHelper bridge path for one region."""

    return repo_root_dir() / "PvPLedger-AppHelper" / regional_app_data_filename(region)


def regional_manifest_filename(region: str) -> str:
    """Return the ladder manifest filename for one region."""

    region_upper = region.upper()
    if region_upper == "US":
        return "ladder-manifest.json"
    return f"ladder-manifest-{region_upper}.json"


def regional_app_data_filename(region: str) -> str:
    """Return the AppHelper bridge filename for one region."""

    region_upper = region.upper()
    if region_upper == "US":
        return "AppData.lua"
    return f"AppData-{region_upper}.lua"


def local_app_data_source(region: str = "US") -> Path:
    """Return the repo-local AppData bridge file used as an offline fallback."""

    return regional_app_data_path(region)


def local_manifest_source(region: str = "US") -> Path:
    """Return the repo-local ladder manifest used as an offline fallback."""

    return regional_manifest_path(region)


def load_local_manifest(region: str = "US") -> RemoteManifest:
    """Load ladder-manifest.json from the local repository checkout."""

    payload = json.loads(local_manifest_source(region).read_text(encoding="utf-8"))
    return RemoteManifest(
        region=str(payload.get("region", "US")),
        generated_date=str(payload.get("generatedDate", "")),
        brackets=dict(payload.get("brackets", {})),
        generated_at=str(payload.get("generatedAt", "")),
    )


def read_installed_app_data_generated_at(config: SyncConfig) -> str:
    """Return the generatedAt timestamp from the installed AppData.lua header."""

    path = config.app_data_path
    if not path.exists():
        return ""

    header = path.read_text(encoding="utf-8", errors="ignore")[:4096]
    return read_app_data_generated_at(header)


def should_sync_local_payload(config: SyncConfig, *, force: bool) -> bool:
    """Return True when the local repository AppData.lua should be copied."""

    if force:
        return True

    source_path = local_app_data_source(config.region)
    if not source_path.exists():
        return False

    installed_generated_at = read_installed_app_data_generated_at(config)
    local_generated_at = read_app_data_generated_at(
        source_path.read_text(encoding="utf-8", errors="ignore")[:4096]
    )
    if not installed_generated_at:
        return True
    if not local_generated_at:
        return manifest_is_newer(load_local_manifest(config.region), config.last_manifest_generated_date)

    return local_generated_at > installed_generated_at


def should_sync_remote_payload(config: SyncConfig, manifest: RemoteManifest, *, force: bool) -> bool:
    """Return True when a remote AppData.lua download should run."""

    if force:
        return True

    installed_generated_at = read_installed_app_data_generated_at(config)
    remote_generated_at = manifest.generated_at
    if not remote_generated_at:
        try:
            remote_generated_at = fetch_app_data_generated_at(
                repo=config.repo,
                branch=config.branch,
                region=config.region,
            )
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
            remote_generated_at = ""

    return manifest_is_newer(
        manifest,
        config.last_manifest_generated_date,
        installed_app_data_generated_at=installed_generated_at,
        remote_app_data_generated_at=remote_generated_at,
    )


def atomic_write_text(path: Path, content: str) -> None:
    """Write a file atomically to avoid partial reads by WoW."""

    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    temp_path.write_text(content, encoding="utf-8")
    temp_path.replace(path)


def validate_app_data(content: str) -> bool:
    """Return True when AppData.lua contains the expected bridge payload."""

    return (
        "PVL_AppHelperPendingSnapshots" in content
        or "PVL_AppHelperPendingSnapshotsByRegion" in content
    )


def finalize_sync(
    config: SyncConfig,
    *,
    app_data_path: Path,
    manifest_generated_date: str,
    source: str,
    content: str,
) -> SyncResult:
    """Persist sync metadata after AppData.lua was written."""

    player_index_count = count_players_in_app_data(content)
    config.last_manifest_generated_date = (
        read_app_data_generated_at(content)
        or manifest_generated_date
    )
    config.last_app_data_sync_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    save_config(config)
    reason = t("SYNC.APPDATA_UPDATED_FROM", source=source)
    if player_index_count <= 0:
        reason = f"{reason} {t('SYNC.LADDER_AGGREGATES_NO_PLAYERS')}"
    else:
        reason = f"{reason} {describe_player_index_status(player_index_count)}"
    return SyncResult(
        updated=True,
        reason=reason,
        reason_key="SYNC.APPDATA_UPDATED",
        manifest_generated_date=manifest_generated_date,
        app_data_path=str(app_data_path),
        source=source,
        player_index_count=player_index_count,
    )


def sync_app_data_from_local(config: SyncConfig, *, force: bool = False) -> SyncResult:
    """Copy AppData.lua from the local PvPLedger repository checkout."""

    source_path = local_app_data_source(config.region)
    if not source_path.exists():
        return SyncResult(
            updated=False,
            reason=t("SYNC.LOCAL_SOURCE_NOT_FOUND", path=source_path),
            reason_key="SYNC.LOCAL_SOURCE_NOT_FOUND",
        )

    manifest = load_local_manifest(config.region)
    if not should_sync_local_payload(config, force=force):
        return SyncResult(
            updated=False,
            reason=t("SYNC.ALREADY_UP_TO_DATE_LOCAL"),
            reason_key="SYNC.ALREADY_UP_TO_DATE_LOCAL",
            manifest_generated_date=manifest.generated_date,
            app_data_path=str(config.app_data_path),
            source="local-repo",
        )

    content = source_path.read_text(encoding="utf-8")
    if not validate_app_data(content):
        return SyncResult(
            updated=False,
            reason=t("SYNC.LOCAL_APPDATA_INVALID"),
            reason_key="SYNC.LOCAL_APPDATA_INVALID",
        )

    atomic_write_text(config.app_data_path, content)
    return finalize_sync(
        config,
        app_data_path=config.app_data_path,
        manifest_generated_date=manifest.generated_date,
        source="local-repo",
        content=content,
    )


def sync_app_data_from_remote(config: SyncConfig, *, force: bool = False) -> SyncResult:
    """Download AppData.lua from GitHub."""

    manifest = fetch_manifest(repo=config.repo, branch=config.branch, region=config.region)
    if not should_sync_remote_payload(config, manifest, force=force):
        installed_generated_at = read_installed_app_data_generated_at(config)
        detail = installed_generated_at or "unknown timestamp"
        return SyncResult(
            updated=False,
            reason=t("SYNC.ALREADY_UP_TO_DATE_INSTALLED", detail=detail),
            reason_key="SYNC.ALREADY_UP_TO_DATE_INSTALLED",
            manifest_generated_date=manifest.generated_date,
            app_data_path=str(config.app_data_path),
            source="github",
        )

    app_data = fetch_app_data(repo=config.repo, branch=config.branch, region=config.region)
    if not validate_app_data(app_data):
        return SyncResult(
            updated=False,
            reason=t("SYNC.DOWNLOADED_INVALID"),
            reason_key="SYNC.DOWNLOADED_INVALID",
        )

    expected_region = f'region = "{config.region.upper()}"'
    if expected_region not in app_data[:4096]:
        return SyncResult(
            updated=False,
            reason=t("SYNC.REGION_MISMATCH", region=config.region.upper()),
            reason_key="SYNC.REGION_MISMATCH",
        )

    atomic_write_text(config.app_data_path, app_data)
    return finalize_sync(
        config,
        app_data_path=config.app_data_path,
        manifest_generated_date=manifest.generated_date,
        source="github",
        content=app_data,
    )


def sync_app_data(config: SyncConfig, *, force: bool = False, local_only: bool = False) -> SyncResult:
    """Sync AppData.lua from GitHub, falling back to the local repo when remote is unavailable."""

    if not config.wow_addons_dir:
        return SyncResult(
            updated=False,
            reason=t("SYNC.ADDONS_NOT_CONFIGURED"),
            reason_key="SYNC.ADDONS_NOT_CONFIGURED",
        )

    if local_only:
        return sync_app_data_from_local(config, force=force)

    try:
        return sync_app_data_from_remote(config, force=force)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
        local_result = sync_app_data_from_local(config, force=force)
        if local_result.updated or local_result.reason_key == "SYNC.ALREADY_UP_TO_DATE_LOCAL":
            if not local_result.updated:
                local_result.reason = t(
                    "SYNC.GITHUB_UNAVAILABLE_LOCAL",
                    reason=local_result.reason,
                    error=exc,
                )
            else:
                local_result.reason = t(
                    "SYNC.GITHUB_UNAVAILABLE_LOCAL",
                    reason=local_result.reason,
                    error=exc,
                )
            return local_result

        return SyncResult(
            updated=False,
            reason=t(
                "SYNC.GITHUB_AND_LOCAL_FAILED",
                error=exc,
                reason=local_result.reason,
            ),
            reason_key="SYNC.GITHUB_AND_LOCAL_FAILED",
        )


def inspect_installed_app_data(config: SyncConfig) -> tuple[int, str]:
    """
    Read the installed AppHelper AppData.lua and summarize player index coverage.

    Parameters
    ----------
    config:
        Loaded sync configuration.

    Returns
    -------
    tuple[int, str]
        Player count and a short status line for CLI/tray output.
    """

    path = config.app_data_path
    if not path.exists():
        return 0, t("SYNC.INSTALLED_NOT_FOUND")

    content = path.read_text(encoding="utf-8")
    if not validate_app_data(content):
        return 0, t("SYNC.INSTALLED_INVALID")

    player_count = count_players_in_app_data(content)
    return player_count, describe_player_index_status(player_count)
