"""Remote manifest helpers for PvPLedger Sync."""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

_APP_DATA_GENERATED_AT_PATTERN = re.compile(r'generatedAt = "([^"]+)"')


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


@dataclass
class RemoteManifest:
    """Parsed ladder manifest from GitHub."""

    region: str
    generated_date: str
    brackets: dict[str, dict[str, Any]]
    generated_at: str = ""


def manifest_raw_url(*, repo: str, branch: str, region: str = "US") -> str:
    """Build the raw GitHub URL for one regional ladder manifest."""

    filename = regional_manifest_filename(region)
    return f"https://raw.githubusercontent.com/{repo}/{branch}/Data/{filename}"


def app_data_raw_url(*, repo: str, branch: str, region: str = "US") -> str:
    """Build the raw GitHub URL for one regional AppHelper bridge file."""

    filename = regional_app_data_filename(region)
    return f"https://raw.githubusercontent.com/{repo}/{branch}/PvPLedger-AppHelper/{filename}"


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


def fetch_manifest(*, repo: str, branch: str, region: str = "US") -> RemoteManifest:
    """Download and parse the remote ladder manifest from the public repo."""

    payload = fetch_json(manifest_raw_url(repo=repo, branch=branch, region=region))
    return RemoteManifest(
        region=str(payload.get("region", region.upper())),
        generated_date=str(payload.get("generatedDate", "")),
        brackets=dict(payload.get("brackets", {})),
        generated_at=str(payload.get("generatedAt", "")),
    )


def fetch_app_data(*, repo: str, branch: str, region: str = "US") -> str:
    """Download one regional AppHelper bridge file from the public repo."""

    return fetch_text(app_data_raw_url(repo=repo, branch=branch, region=region))


def read_app_data_generated_at(content: str) -> str:
    """Extract the AppData payload timestamp from one AppData.lua header."""

    match = _APP_DATA_GENERATED_AT_PATTERN.search(content)
    return match.group(1) if match else ""


def fetch_app_data_generated_at(*, repo: str, branch: str, region: str = "US") -> str:
    """Fetch only the AppData.lua header and return its generatedAt timestamp."""

    url = app_data_raw_url(repo=repo, branch=branch, region=region)
    request = urllib.request.Request(
        url,
        headers={
            **build_request_headers(),
            "Range": "bytes=0-4095",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30.0) as response:
            header = response.read(4096).decode("utf-8", errors="ignore")
    except urllib.error.HTTPError as exc:
        if exc.code != 416:
            raise
        header = fetch_text(url, timeout=30.0)[:4096]

    return read_app_data_generated_at(header)


def manifest_is_newer(
    remote: RemoteManifest,
    last_generated_date: str,
    *,
    installed_app_data_generated_at: str = "",
    remote_app_data_generated_at: str = "",
) -> bool:
    """Return True when the remote ladder payload is newer than the cached sync state."""

    remote_generated_at = remote.generated_at or remote_app_data_generated_at
    if remote_generated_at and installed_app_data_generated_at:
        if remote_generated_at > installed_app_data_generated_at:
            return True
        if remote_generated_at == installed_app_data_generated_at:
            return False

    if remote.generated_date and last_generated_date:
        if remote.generated_date > last_generated_date:
            return True
        if remote.generated_date < last_generated_date:
            return False

    if not remote.generated_date:
        return True
    if not last_generated_date:
        return True
    return remote.generated_date > last_generated_date


def format_github_error(exc: Exception) -> str:
    """Return a concise GitHub error message for CLI output."""

    if isinstance(exc, urllib.error.HTTPError):
        if exc.code == 404:
            return f"{exc} — repo/path not found. Check repo, branch, and region settings."
    return str(exc)
