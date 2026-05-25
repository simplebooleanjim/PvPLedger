"""Minimal Battle.net client for WoW PvP leaderboard exports."""

from __future__ import annotations

import base64
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


class BlizzardApiError(RuntimeError):
    """Raised when a Battle.net API request fails."""


class BlizzardClient:
    """Client-credentials Battle.net API client for WoW game data."""

    OAUTH_URL = "https://oauth.battle.net/token"
    API_BASE = "https://{region}.api.blizzard.com"

    def __init__(self, client_id: str, client_secret: str, region: str = "us", locale: str = "en_US"):
        self.client_id = client_id
        self.client_secret = client_secret
        self.region = region.lower()
        self.locale = locale
        self._token: str | None = None
        self._token_expires_at = 0.0
        self._base_url = self.API_BASE.format(region=self.region)

    def _ensure_token(self) -> str:
        """Fetch or reuse a client-credentials OAuth token."""

        if self._token and time.time() < self._token_expires_at - 30:
            return self._token

        payload = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode("utf-8")
        credentials = base64.b64encode(f"{self.client_id}:{self.client_secret}".encode("utf-8")).decode("ascii")
        request = urllib.request.Request(
            self.OAUTH_URL,
            data=payload,
            headers={
                "Authorization": f"Basic {credentials}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="ignore")
            raise BlizzardApiError(f"OAuth failed ({exc.code}): {body}") from exc

        self._token = data["access_token"]
        self._token_expires_at = time.time() + float(data.get("expires_in", 3600))
        return self._token

    def get_json(self, path: str, *, namespace: str | None = None) -> dict[str, Any]:
        """Perform one authenticated GET request and return parsed JSON."""

        token = self._ensure_token()
        namespace = namespace or f"dynamic-{self.region}"
        query = urllib.parse.urlencode({"namespace": namespace, "locale": self.locale})
        url = f"{self._base_url}{path}?{query}"

        request = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
            method="GET",
        )

        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    return json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    return {}
                if exc.code == 429 and attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                body = exc.read().decode("utf-8", errors="ignore")
                raise BlizzardApiError(f"GET {path} failed ({exc.code}): {body}") from exc
            except urllib.error.URLError as exc:
                if attempt < 3:
                    time.sleep(1 + attempt)
                    continue
                raise BlizzardApiError(f"GET {path} failed: {exc}") from exc

        return {}

    def get_current_pvp_season_id(self) -> int:
        """Return the highest season id from the PvP season index."""

        payload = self.get_json("/data/wow/pvp-season/index")
        seasons = payload.get("seasons") or []
        season_ids = [season.get("id", 0) for season in seasons if season.get("id")]
        if not season_ids:
            raise BlizzardApiError("No PvP seasons returned by Battle.net.")
        return max(season_ids)

    def list_leaderboard_slugs(self, season_id: int) -> list[str]:
        """Return all leaderboard bracket slugs for one season."""

        payload = self.get_json(f"/data/wow/pvp-season/{season_id}/pvp-leaderboard/index")
        slugs: list[str] = []

        for leaderboard in payload.get("leaderboards") or []:
            href = ((leaderboard.get("key") or {}).get("href") or "")
            slug = slug_from_leaderboard_href(href)
            if slug:
                slugs.append(slug)

        return slugs

    def fetch_leaderboard_entries(self, season_id: int, bracket_slug: str) -> list[dict[str, Any]]:
        """Fetch all entries for one bracket slug."""

        payload = self.get_json(
            f"/data/wow/pvp-season/{season_id}/pvp-leaderboard/{bracket_slug}",
        )
        return payload.get("entries") or []


def slug_from_leaderboard_href(href: str) -> str | None:
    """Extract a bracket slug from a Battle.net leaderboard href."""

    match = re.search(r"/pvp-leaderboard/([^/?]+)", href)
    return match.group(1) if match else None
