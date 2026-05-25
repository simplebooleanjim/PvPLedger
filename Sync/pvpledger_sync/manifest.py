"""Remote manifest helpers for PvPLedger Sync."""

from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass
from typing import Any


@dataclass
class RemoteManifest:
    """Parsed ladder manifest from GitHub."""

    region: str
    generated_date: str
    brackets: dict[str, dict[str, Any]]


def manifest_url(*, repo: str, branch: str) -> str:
    """Build the raw GitHub URL for ladder-manifest.json."""

    return f"https://raw.githubusercontent.com/{repo}/{branch}/Data/ladder-manifest.json"


def app_data_url(*, repo: str, branch: str) -> str:
    """Build the raw GitHub URL for AppHelper AppData.lua."""

    return f"https://raw.githubusercontent.com/{repo}/{branch}/PvPLedger-AppHelper/AppData.lua"


def fetch_json(url: str, timeout: float = 20.0) -> dict[str, Any]:
    """Fetch and decode one JSON document."""

    request = urllib.request.Request(url, headers={"User-Agent": "PvPLedger-Sync/0.1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_text(url: str, timeout: float = 30.0) -> str:
    """Fetch one text document."""

    request = urllib.request.Request(url, headers={"User-Agent": "PvPLedger-Sync/0.1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8")


def fetch_manifest(*, repo: str, branch: str) -> RemoteManifest:
    """Download and parse the remote ladder manifest."""

    payload = fetch_json(manifest_url(repo=repo, branch=branch))
    return RemoteManifest(
        region=str(payload.get("region", "US")),
        generated_date=str(payload.get("generatedDate", "")),
        brackets=dict(payload.get("brackets", {})),
    )


def manifest_is_newer(remote: RemoteManifest, last_generated_date: str) -> bool:
    """Return True when the remote manifest is newer than the cached sync state."""

    if not remote.generated_date:
        return True
    if not last_generated_date:
        return True
    return remote.generated_date > last_generated_date
