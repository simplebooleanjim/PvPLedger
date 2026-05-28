"""Push match export batches to a GitHub repository dump file."""

from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Any
from urllib import error, request

from .config import SyncConfig
from .manifest import build_request_headers, format_github_error, github_api_contents_url


DEFAULT_GITHUB_EXPORT_PATH = "Data/match-exports"
MATCH_DUMP_FILENAME = "match-dump.json"


@dataclass
class GitHubExportResult:
    """Outcome of one GitHub export upload."""

    uploaded: bool
    reason: str
    batch_path: str = ""
    dump_path: str = ""


@dataclass
class GitHubReconcileResult:
    """Outcome of reconciling local export batches against GitHub."""

    checked_batches: int = 0
    uploaded_batches: int = 0
    already_synced_batches: int = 0
    failed_batches: int = 0
    dump_repaired: bool = False
    dump_path: str = ""
    errors: list[str] | None = None
    reason: str = ""

    def __post_init__(self) -> None:
        """Normalize optional list fields."""

        if self.errors is None:
            self.errors = []


def empty_match_dump() -> dict[str, Any]:
    """Return an empty consolidated match dump document."""

    return {
        "schemaVersion": 1,
        "updatedAt": None,
        "source": "pvpledger-sync",
        "matchCount": 0,
        "matches": [],
    }


def merge_match_dump(existing: dict[str, Any], batch_payload: dict[str, Any]) -> dict[str, Any]:
    """
    Merge one upload batch into a consolidated match dump.

    Parameters
    ----------
    existing:
        Existing dump document loaded from GitHub, if any.
    batch_payload:
        Upload batch payload produced by the sync uploader.

    Returns
    -------
    dict[str, Any]
        Updated dump document with de-duplicated matches by ``matchId``.
    """

    matches_by_id: dict[str, dict[str, Any]] = {}
    for match in existing.get("matches") or []:
        if isinstance(match, dict) and match.get("matchId"):
            matches_by_id[str(match["matchId"])] = match

    for match in batch_payload.get("matches") or []:
        if isinstance(match, dict) and match.get("matchId"):
            matches_by_id[str(match["matchId"])] = match

    matches = list(matches_by_id.values())
    matches.sort(key=lambda row: row.get("timestamp") or 0, reverse=True)

    return {
        "schemaVersion": 1,
        "updatedAt": batch_payload.get("uploadedAt"),
        "source": "pvpledger-sync",
        "region": batch_payload.get("region"),
        "character": batch_payload.get("character"),
        "addonVersion": batch_payload.get("addonVersion"),
        "matchCount": len(matches),
        "matches": matches,
    }


def _github_request(
    *,
    method: str,
    url: str,
    token: str,
    body: dict[str, Any] | None = None,
    timeout: float = 60.0,
) -> dict[str, Any]:
    """Execute one GitHub REST API request and decode a JSON response."""

    data = None
    headers = build_request_headers(token=token)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    http_request = request.Request(url, data=data, headers=headers, method=method)
    try:
        with request.urlopen(http_request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except error.HTTPError as exc:
        raise ValueError(format_github_error(exc)) from exc


def get_repo_file(*, repo: str, branch: str, path: str, token: str) -> tuple[str | None, str | None]:
    """
    Load one repository file through the GitHub Contents API.

    Returns
    -------
    tuple[str | None, str | None]
        File SHA and decoded text content. Both values are ``None`` when missing.
    """

    url = github_api_contents_url(repo=repo, branch=branch, path=path)
    try:
        payload = _github_request(method="GET", url=url, token=token)
    except ValueError as exc:
        if "404" in str(exc):
            return None, None
        raise

    sha = payload.get("sha")
    content = payload.get("content")
    encoding = payload.get("encoding")
    if not content or encoding != "base64":
        return sha, None

    text = base64.b64decode(content).decode("utf-8")
    return sha, text


def put_repo_file(
    *,
    repo: str,
    branch: str,
    path: str,
    content: str,
    message: str,
    token: str,
    sha: str | None = None,
) -> None:
    """Create or update one repository file through the GitHub Contents API."""

    url = github_api_contents_url(repo=repo, branch=branch, path=path)
    body: dict[str, Any] = {
        "message": message,
        "content": base64.b64encode(content.encode("utf-8")).decode("ascii"),
    }
    if sha:
        body["sha"] = sha

    _github_request(method="PUT", url=url, token=token, body=body)


def resolve_github_export_root(config: SyncConfig) -> str:
    """Return the configured GitHub export directory inside the repository."""

    export_path = (config.github_export_path or DEFAULT_GITHUB_EXPORT_PATH).strip().strip("/")
    return export_path or DEFAULT_GITHUB_EXPORT_PATH


def resolve_github_batch_repo_path(config: SyncConfig, batch_id: str) -> str:
    """
    Build the repository path for one export batch file.

    Parameters
    ----------
    config:
        Active sync configuration.
    batch_id:
        Export batch identifier.

    Returns
    -------
    str
        Repository-relative batch JSON path.
    """

    export_root = resolve_github_export_root(config)
    return f"{export_root}/batches/batch-{batch_id}.json"


def resolve_github_dump_repo_path(config: SyncConfig) -> str:
    """Return the repository path for the consolidated match dump file."""

    export_root = resolve_github_export_root(config)
    return f"{export_root}/{MATCH_DUMP_FILENAME}"


def match_ids_from_payload(payload: dict[str, Any]) -> set[str]:
    """
    Extract match IDs from one export batch payload.

    Parameters
    ----------
    payload:
        Export batch payload.

    Returns
    -------
    set[str]
        Unique match IDs contained in the payload.
    """

    match_ids: set[str] = set()
    for match in payload.get("matches") or []:
        if isinstance(match, dict) and match.get("matchId"):
            match_ids.add(str(match["matchId"]))
    return match_ids


def match_ids_from_dump(dump: dict[str, Any]) -> set[str]:
    """
    Extract match IDs from one consolidated dump document.

    Parameters
    ----------
    dump:
        Consolidated match dump payload.

    Returns
    -------
    set[str]
        Unique match IDs contained in the dump.
    """

    return match_ids_from_payload({"matches": dump.get("matches") or []})


def github_batch_exists(config: SyncConfig, batch_id: str) -> bool:
    """
    Return True when one export batch file already exists on GitHub.

    Parameters
    ----------
    config:
        Active sync configuration.
    batch_id:
        Export batch identifier.

    Returns
    -------
    bool
        True when the batch file is present in the configured repository.
    """

    token = config.resolved_github_token()
    if not token:
        return False

    sha, _ = get_repo_file(
        repo=config.repo,
        branch=config.branch,
        path=resolve_github_batch_repo_path(config, batch_id),
        token=token,
    )
    return sha is not None


def ensure_github_match_dump(config: SyncConfig, payloads: list[dict[str, Any]]) -> bool:
    """
    Repair the consolidated GitHub dump when local batches contain missing matches.

    Parameters
    ----------
    config:
        Active sync configuration.
    payloads:
        Local export batch payloads to reconcile into the dump.

    Returns
    -------
    bool
        True when the dump file was updated on GitHub.
    """

    token = config.resolved_github_token()
    if not token or not payloads:
        return False

    expected_ids: set[str] = set()
    for payload in payloads:
        expected_ids.update(match_ids_from_payload(payload))
    if not expected_ids:
        return False

    dump_path = resolve_github_dump_repo_path(config)
    dump_sha, dump_text = get_repo_file(
        repo=config.repo,
        branch=config.branch,
        path=dump_path,
        token=token,
    )
    if dump_text:
        try:
            existing_dump = json.loads(dump_text)
        except json.JSONDecodeError:
            existing_dump = empty_match_dump()
    else:
        existing_dump = empty_match_dump()

    if not isinstance(existing_dump, dict):
        existing_dump = empty_match_dump()

    missing_ids = expected_ids - match_ids_from_dump(existing_dump)
    if not missing_ids:
        return False

    merged_dump = existing_dump
    for payload in sorted(payloads, key=lambda row: row.get("uploadedAt") or ""):
        merged_dump = merge_match_dump(merged_dump, payload)

    dump_json = json.dumps(merged_dump, indent=2) + "\n"
    put_repo_file(
        repo=config.repo,
        branch=config.branch,
        path=dump_path,
        content=dump_json,
        message=(
            f"PvPLedger Sync: repair match dump ({len(missing_ids)} missing match(es) restored)"
        ),
        token=token,
        sha=dump_sha,
    )
    return True


def reconcile_github_exports(
    config: SyncConfig,
    *,
    payloads: list[dict[str, Any]] | None = None,
) -> GitHubReconcileResult:
    """
    Verify local export batches against GitHub and upload any missing files.

    Parameters
    ----------
    config:
        Active sync configuration.
    payloads:
        Optional preloaded local batch payloads. When omitted, the local spool
        and ingest directories are scanned automatically.

    Returns
    -------
    GitHubReconcileResult
        Reconciliation summary.
    """

    if not config.github_export_enabled:
        return GitHubReconcileResult(reason="GitHub export disabled in sync config.")

    token = config.resolved_github_token()
    if not token:
        return GitHubReconcileResult(reason="GitHub export skipped (no token configured).")

    if payloads is None:
        from .uploader import iter_local_batch_payloads

        payloads = iter_local_batch_payloads(config)

    if not payloads:
        return GitHubReconcileResult(reason="No local export batches to reconcile.")

    result = GitHubReconcileResult(checked_batches=len(payloads))
    for payload in payloads:
        batch_id = str(payload.get("batchId", "")).strip()
        if not batch_id:
            result.failed_batches += 1
            result.errors.append("Skipped one local batch with no batchId.")
            continue

        if github_batch_exists(config, batch_id):
            result.already_synced_batches += 1
            continue

        try:
            upload_result = upload_exports_to_github(config, payload)
            if upload_result.uploaded:
                result.uploaded_batches += 1
            else:
                result.failed_batches += 1
                result.errors.append(f"{batch_id}: {upload_result.reason}")
        except ValueError as exc:
            result.failed_batches += 1
            result.errors.append(f"{batch_id}: {exc}")

    try:
        if ensure_github_match_dump(config, payloads):
            result.dump_repaired = True
            result.dump_path = resolve_github_dump_repo_path(config)
    except ValueError as exc:
        result.failed_batches += 1
        result.errors.append(f"dump repair: {exc}")

    result.reason = (
        f"Checked {result.checked_batches} local batch(es): "
        f"{result.uploaded_batches} uploaded, "
        f"{result.already_synced_batches} already on GitHub."
    )
    if result.dump_repaired:
        result.reason += " Match dump repaired."
    if result.failed_batches:
        result.reason += f" {result.failed_batches} failed."
    return result


def upload_exports_to_github(config: SyncConfig, payload: dict[str, Any]) -> GitHubExportResult:
    """
    Upload one export batch and refresh the consolidated GitHub match dump.

    Parameters
    ----------
    config:
        Active sync configuration.
    payload:
        Upload batch payload already written to the local spool.

    Returns
    -------
    GitHubExportResult
        GitHub upload summary.
    """

    token = config.resolved_github_token()
    if not token:
        return GitHubExportResult(
            uploaded=False,
            reason="GitHub export skipped (no token configured).",
        )

    if not config.github_export_enabled:
        return GitHubExportResult(
            uploaded=False,
            reason="GitHub export disabled in sync config.",
        )

    batch_id = str(payload.get("batchId", "")).strip()
    if not batch_id:
        return GitHubExportResult(uploaded=False, reason="GitHub export skipped (missing batchId).")

    export_root = resolve_github_export_root(config)
    batch_path = f"{export_root}/batches/batch-{batch_id}.json"
    dump_path = f"{export_root}/{MATCH_DUMP_FILENAME}"

    batch_json = json.dumps(payload, indent=2) + "\n"
    put_repo_file(
        repo=config.repo,
        branch=config.branch,
        path=batch_path,
        content=batch_json,
        message=f"PvPLedger Sync: add match export batch {batch_id}",
        token=token,
    )

    dump_sha, dump_text = get_repo_file(
        repo=config.repo,
        branch=config.branch,
        path=dump_path,
        token=token,
    )
    if dump_text:
        try:
            existing_dump = json.loads(dump_text)
        except json.JSONDecodeError:
            existing_dump = empty_match_dump()
    else:
        existing_dump = empty_match_dump()

    if not isinstance(existing_dump, dict):
        existing_dump = empty_match_dump()

    merged_dump = merge_match_dump(existing_dump, payload)
    dump_json = json.dumps(merged_dump, indent=2) + "\n"
    put_repo_file(
        repo=config.repo,
        branch=config.branch,
        path=dump_path,
        content=dump_json,
        message=f"PvPLedger Sync: update match dump ({payload.get('matchCount', 0)} new match(es))",
        token=token,
        sha=dump_sha,
    )

    return GitHubExportResult(
        uploaded=True,
        reason=f"Uploaded {payload.get('matchCount', 0)} match(es) to GitHub.",
        batch_path=batch_path,
        dump_path=dump_path,
    )
