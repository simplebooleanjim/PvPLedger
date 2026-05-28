"""Upload match exports collected by the PvPLedger addon."""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error, request

from .config import SyncConfig, default_config_path, save_config
from .export_ack import write_export_ack
from .github_exports import upload_exports_to_github
from .saved_vars import (
    find_app_helper_saved_vars,
    get_export_metadata,
    get_pending_matches,
    load_app_helper_saved_vars,
)


@dataclass
class UploadResult:
    """Outcome of one match export upload attempt."""

    uploaded: bool
    reason: str
    match_count: int = 0
    batch_id: str = ""
    spool_path: str = ""
    export_ack_path: str = ""
    destination: str = ""
    github_batch_path: str = ""
    github_dump_path: str = ""


def default_export_spool_dir() -> Path:
    """Return the default local directory for exported match batches."""

    return default_config_path().parent / "exports" / "inbox"


def resolve_export_spool_dir(config: SyncConfig) -> Path:
    """
    Resolve the configured export spool directory.

    Parameters
    ----------
    config:
        Active sync configuration.

    Returns
    -------
    Path
        Directory where JSON export batches are written locally.
    """

    if config.export_spool_dir:
        return Path(config.export_spool_dir)
    return default_export_spool_dir()


def _utc_now() -> str:
    """Return the current UTC timestamp in ISO-8601 format."""

    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _normalize_match_ids(match_ids: list[str]) -> list[str]:
    """Return a de-duplicated list of non-empty match IDs."""

    seen: set[str] = set()
    normalized: list[str] = []
    for match_id in match_ids:
        value = str(match_id).strip()
        if value and value not in seen:
            seen.add(value)
            normalized.append(value)
    return normalized


def _filter_pending_matches(
    matches: list[dict[str, Any]],
    *,
    acknowledged_ids: list[str],
) -> list[dict[str, Any]]:
    """
    Remove matches that were already uploaded but not yet cleared in-game.

    Parameters
    ----------
    matches:
        Pending match export records from SavedVariables.
    acknowledged_ids:
        Match IDs already uploaded in a prior Sync run.

    Returns
    -------
    list[dict[str, Any]]
        Matches that still need uploading.
    """

    blocked = set(_normalize_match_ids(acknowledged_ids))
    if not blocked:
        return matches

    return [
        match
        for match in matches
        if str(match.get("matchId", "")).strip() not in blocked
    ]


def build_upload_payload(
    *,
    matches: list[dict[str, Any]],
    metadata: dict[str, Any],
    config: SyncConfig,
    batch_id: str,
) -> dict[str, Any]:
    """
    Build the JSON payload sent to the upload destination.

    Parameters
    ----------
    matches:
        Match export records to upload.
    metadata:
        SavedVariables export/sync metadata.
    config:
        Active sync configuration.
    batch_id:
        Unique batch identifier.

    Returns
    -------
    dict[str, Any]
        Upload payload dictionary.
    """

    return {
        "schemaVersion": 1,
        "batchId": batch_id,
        "uploadedAt": _utc_now(),
        "source": "pvpledger-sync",
        "region": config.region,
        "repo": config.repo,
        "character": metadata.get("lastCharacter"),
        "addonVersion": metadata.get("addonVersion"),
        "matchCount": len(matches),
        "matches": matches,
    }


def write_spool_batch(*, spool_dir: Path, payload: dict[str, Any]) -> Path:
    """
    Persist one upload batch to the local export spool.

    Parameters
    ----------
    spool_dir:
        Root directory for export batches.
    payload:
        Upload payload to serialize as JSON.

    Returns
    -------
    Path
        Path to the written JSON file.
    """

    day_dir = spool_dir / datetime.now(timezone.utc).strftime("%Y-%m-%d")
    day_dir.mkdir(parents=True, exist_ok=True)
    destination = day_dir / f"batch-{payload['batchId']}.json"
    destination.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return destination


def post_upload_payload(*, upload_url: str, payload: dict[str, Any], upload_token: str = "") -> None:
    """
    POST one export payload to a configured HTTP endpoint.

    Parameters
    ----------
    upload_url:
        Destination URL for match export ingestion.
    payload:
        JSON-serializable upload payload.
    upload_token:
        Optional bearer token for authenticated ingest endpoints.

    Raises
    ------
    error.URLError
        When the HTTP request fails.
    ValueError
        When the server returns a non-success status code.
    """

    headers = {
        "Content-Type": "application/json",
        "User-Agent": "PvPLedger-Sync/0.7",
    }
    if upload_token:
        headers["Authorization"] = f"Bearer {upload_token}"

    body = json.dumps(payload).encode("utf-8")
    http_request = request.Request(
        upload_url,
        data=body,
        headers=headers,
        method="POST",
    )

    try:
        with request.urlopen(http_request, timeout=30) as response:
            if response.status >= 400:
                raise ValueError(f"Upload failed with HTTP {response.status}.")
    except error.HTTPError as exc:
        if exc.code == 401:
            raise ValueError(
                "Upload failed with HTTP 401 (unauthorized). "
                "Configure your upload token with: run_sync.bat upload-auth --token YOUR_TOKEN"
            ) from exc
        raise ValueError(f"Upload failed with HTTP {exc.code}.") from exc


def upload_exports(config: SyncConfig, *, force: bool = False) -> UploadResult:
    """
    Upload pending match exports and write ExportAck.lua for the addon bridge.

    Parameters
    ----------
    config:
        Active sync configuration.
    force:
        When True, ignore the desktop-side export enable flag.

    Returns
    -------
    UploadResult
        Upload attempt summary.
    """

    if not config.wow_addons_dir:
        return UploadResult(uploaded=False, reason="Sync is not initialized.")

    if not config.export_enabled and not force:
        return UploadResult(uploaded=False, reason="Match export upload is disabled.")

    saved_vars_path = find_app_helper_saved_vars(Path(config.wow_addons_dir))
    if not saved_vars_path:
        return UploadResult(uploaded=False, reason="No PvPLedger_AppHelper SavedVariables file found yet.")

    try:
        document = load_app_helper_saved_vars(saved_vars_path)
    except ValueError as exc:
        return UploadResult(uploaded=False, reason=str(exc))

    pending_matches = get_pending_matches(document)
    current_ids = {str(match.get("matchId", "")).strip() for match in pending_matches}
    config.pending_upload_match_ids = [
        match_id
        for match_id in _normalize_match_ids(config.pending_upload_match_ids)
        if match_id in current_ids
    ]

    pending_matches = _filter_pending_matches(
        pending_matches,
        acknowledged_ids=config.pending_upload_match_ids,
    )

    if not pending_matches:
        return UploadResult(
            uploaded=False,
            reason="No pending match exports to upload.",
            match_count=0,
        )

    batch_id = uuid.uuid4().hex
    metadata = get_export_metadata(document)
    payload = build_upload_payload(
        matches=pending_matches,
        metadata=metadata,
        config=config,
        batch_id=batch_id,
    )

    spool_path = write_spool_batch(
        spool_dir=resolve_export_spool_dir(config),
        payload=payload,
    )

    destination = "local-spool"
    if config.upload_url:
        post_upload_payload(
            upload_url=config.upload_url,
            payload=payload,
            upload_token=config.resolved_upload_token(),
        )
        destination = config.upload_url

    github_batch_path = ""
    github_dump_path = ""
    if config.github_export_enabled:
        try:
            github_result = upload_exports_to_github(config, payload)
            if github_result.uploaded:
                github_batch_path = github_result.batch_path
                github_dump_path = github_result.dump_path
                if destination == "local-spool":
                    destination = f"github:{config.repo}/{config.branch}"
                else:
                    destination = f"{destination}; github:{config.repo}/{config.branch}"
            elif github_result.reason and not github_result.reason.endswith("disabled in sync config."):
                destination = f"{destination} ({github_result.reason})"
        except ValueError as exc:
            destination = f"{destination} (GitHub export failed: {exc})"

    uploaded_match_ids = [str(match["matchId"]) for match in pending_matches if match.get("matchId")]
    export_ack_path = config.app_helper_dir / "ExportAck.lua"
    write_export_ack(
        destination=export_ack_path,
        uploaded_match_ids=uploaded_match_ids,
        batch_id=batch_id,
        uploaded_at=payload["uploadedAt"],
    )

    config.pending_upload_match_ids = _normalize_match_ids(
        config.pending_upload_match_ids + uploaded_match_ids
    )
    config.last_export_upload_at = payload["uploadedAt"]
    config.last_export_upload_count = len(uploaded_match_ids)
    config.last_export_batch_id = batch_id
    save_config(config)

    return UploadResult(
        uploaded=True,
        reason=f"Uploaded {len(uploaded_match_ids)} match export(s).",
        match_count=len(uploaded_match_ids),
        batch_id=batch_id,
        spool_path=str(spool_path),
        export_ack_path=str(export_ack_path),
        destination=destination,
        github_batch_path=github_batch_path,
        github_dump_path=github_dump_path,
    )
