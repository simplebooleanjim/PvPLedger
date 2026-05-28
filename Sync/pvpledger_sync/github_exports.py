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
