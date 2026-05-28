"""Remote manifest helpers for PvPLedger Sync."""

from __future__ import annotations

import base64
import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any


@dataclass
class RemoteManifest:
    """Parsed ladder manifest from GitHub."""

    region: str
    generated_date: str
    brackets: dict[str, dict[str, Any]]


def manifest_raw_url(*, repo: str, branch: str) -> str:
    """Build the raw GitHub URL for ladder-manifest.json."""

    return f"https://raw.githubusercontent.com/{repo}/{branch}/Data/ladder-manifest.json"


def app_data_raw_url(*, repo: str, branch: str) -> str:
    """Build the raw GitHub URL for AppHelper AppData.lua."""

    return f"https://raw.githubusercontent.com/{repo}/{branch}/PvPLedger-AppHelper/AppData.lua"


def github_api_contents_url(*, repo: str, branch: str, path: str) -> str:
    """Build the GitHub Contents API URL for one repository file."""

    return f"https://api.github.com/repos/{repo}/contents/{path}?ref={branch}"


def build_request_headers(*, token: str = "") -> dict[str, str]:
    """Build HTTP headers for GitHub requests."""

    headers = {
        "User-Agent": "PvPLedger-Sync/0.1",
        "Accept": "application/vnd.github+json",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def fetch_json(url: str, *, token: str = "", timeout: float = 20.0) -> dict[str, Any]:
    """Fetch and decode one JSON document."""

    request = urllib.request.Request(url, headers=build_request_headers(token=token))
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_text(url: str, *, token: str = "", timeout: float = 30.0) -> str:
    """Fetch one text document from a direct URL."""

    request = urllib.request.Request(url, headers=build_request_headers(token=token))
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8")


def fetch_repo_file_text(*, repo: str, branch: str, path: str, token: str = "") -> str:
    """Fetch one repository file, using the GitHub API when authenticated."""

    if token:
        payload = fetch_json(
            github_api_contents_url(repo=repo, branch=branch, path=path),
            token=token,
        )
        content = payload.get("content")
        encoding = payload.get("encoding")
        if not content or encoding != "base64":
            raise ValueError(f"Unexpected GitHub API response for {path}.")
        return base64.b64decode(content).decode("utf-8")

    if path.endswith(".json"):
        return fetch_text(manifest_raw_url(repo=repo, branch=branch), token=token)
    if path.endswith("AppData.lua"):
        return fetch_text(app_data_raw_url(repo=repo, branch=branch), token=token)

    return fetch_text(
        f"https://raw.githubusercontent.com/{repo}/{branch}/{path}",
        token=token,
    )


def fetch_manifest(*, repo: str, branch: str, token: str = "") -> RemoteManifest:
    """Download and parse the remote ladder manifest."""

    if token:
        payload = json.loads(
            fetch_repo_file_text(
                repo=repo,
                branch=branch,
                path="Data/ladder-manifest.json",
                token=token,
            )
        )
    else:
        payload = fetch_json(manifest_raw_url(repo=repo, branch=branch), token=token)

    return RemoteManifest(
        region=str(payload.get("region", "US")),
        generated_date=str(payload.get("generatedDate", "")),
        brackets=dict(payload.get("brackets", {})),
    )


def fetch_app_data(*, repo: str, branch: str, token: str = "") -> str:
    """Download AppHelper AppData.lua from GitHub."""

    if token:
        return fetch_repo_file_text(
            repo=repo,
            branch=branch,
            path="PvPLedger-AppHelper/AppData.lua",
            token=token,
        )
    return fetch_text(app_data_raw_url(repo=repo, branch=branch), token=token)


def manifest_is_newer(remote: RemoteManifest, last_generated_date: str) -> bool:
    """Return True when the remote manifest is newer than the cached sync state."""

    if not remote.generated_date:
        return True
    if not last_generated_date:
        return True
    return remote.generated_date > last_generated_date


def format_github_error(exc: Exception) -> str:
    """Return a concise GitHub error message for CLI output."""

    if isinstance(exc, urllib.error.HTTPError):
        if exc.code in {401, 403}:
            return (
                f"{exc} — check your GitHub token scopes "
                "(ladder sync needs Contents read; match dump upload needs Contents write)."
            )
        if exc.code == 404:
            return f"{exc} — repo/path not found, or token lacks access to this private repo."
    return str(exc)
