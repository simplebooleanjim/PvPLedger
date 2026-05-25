"""Seramate public API client for enriching combined-ladder snapshots with class/spec data."""

from __future__ import annotations

import json
import math
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any

from spec_catalog import get_seramate_ladder_slug

SERAMATE_API_BASE = "https://api.seramate.com/api/public"
SERAMATE_USER_AGENT = "PvPLedger-collector/0.5.3"
SERAMATE_PER_PAGE_OPTIONS = (10, 20, 50, 100)
DEFAULT_PER_PAGE = 50
DEFAULT_REQUEST_DELAY = 0.2

SERAMATE_CLASS_CODE_TO_TOKEN: dict[str, str] = {
    "Death-Knight": "DEATHKNIGHT",
    "Death Knight": "DEATHKNIGHT",
    "Demon-Hunter": "DEMONHUNTER",
    "Demon Hunter": "DEMONHUNTER",
    "Druid": "DRUID",
    "Evoker": "EVOKER",
    "Hunter": "HUNTER",
    "Mage": "MAGE",
    "Monk": "MONK",
    "Paladin": "PALADIN",
    "Priest": "PRIEST",
    "Rogue": "ROGUE",
    "Shaman": "SHAMAN",
    "Warlock": "WARLOCK",
    "Warrior": "WARRIOR",
}


class SeramateApiError(RuntimeError):
    """Raised when Seramate API requests fail."""


@dataclass(frozen=True)
class SeramateSpecIdentity:
    """Resolved class/spec tokens for one Seramate character row."""

    class_token: str
    spec_token: str

    @property
    def spec_key(self) -> str:
        """Return the CLASS_SPEC aggregate key used by the addon."""

        return f"{self.class_token}_{self.spec_token}"


@dataclass
class SeramateEnrichmentReport:
    """Summary of a Blizzard-to-Seramate enrichment pass."""

    matched: int = 0
    unmatched: int = 0
    pages_fetched: int = 0
    lookup_size: int = 0


def normalize_realm_key(realm: str) -> str:
    """Normalize a realm slug or display name for stable player lookup keys."""

    return re.sub(r"[^a-z0-9]", "", realm.lower())


def make_player_lookup_key(name: str, realm: str = "") -> str:
    """Build a case- and punctuation-insensitive player lookup key."""

    normalized_name = name.lower()
    if not realm:
        return normalized_name

    return f"{normalized_name}-{normalize_realm_key(realm)}"


def normalize_region_code(region: str) -> str:
    """Convert addon region codes such as US into Seramate region slugs."""

    return region.lower()


def normalize_spec_token(spec_code: str) -> str:
    """Convert Seramate spec labels into addon spec tokens."""

    return re.sub(r"[^A-Za-z0-9]", "", spec_code).upper()


def resolve_seramate_identity(class_code: str | None, spec_code: str | None) -> SeramateSpecIdentity | None:
    """Map Seramate class/spec codes into addon aggregate tokens."""

    if not class_code or not spec_code:
        return None

    class_token = SERAMATE_CLASS_CODE_TO_TOKEN.get(class_code)
    if class_token is None:
        class_token = re.sub(r"[^A-Za-z0-9]", "", class_code).upper()

    spec_token = normalize_spec_token(spec_code)
    if not class_token or not spec_token:
        return None

    return SeramateSpecIdentity(class_token=class_token, spec_token=spec_token)


def build_ladder_list_url(*, region: str, bracket_slug: str, page: int, per_page: int) -> str:
    """Build one Seramate ladder list request URL."""

    if per_page not in SERAMATE_PER_PAGE_OPTIONS:
        raise SeramateApiError(
            f"per_page must be one of {SERAMATE_PER_PAGE_OPTIONS}, got {per_page}."
        )

    query = urllib.parse.urlencode({
        "realms": "[]",
        "races": "[]",
        "specs": "[]",
        "factions": "[]",
        "realmCategories": "[]",
        "per_page": per_page,
    })
    region_code = normalize_region_code(region)
    return f"{SERAMATE_API_BASE}/ladder/{region_code}/list/{bracket_slug}/{page}?{query}"


def fetch_json(url: str) -> dict[str, Any]:
    """Perform one GET request against the Seramate public API."""

    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": SERAMATE_USER_AGENT,
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        raise SeramateApiError(f"Seramate request failed ({exc.code}): {body}") from exc
    except urllib.error.URLError as exc:
        raise SeramateApiError(f"Seramate request failed: {exc}") from exc

    if not isinstance(payload, dict):
        raise SeramateApiError("Seramate response was not a JSON object.")

    return payload


def entry_to_lookup_identity(entry: dict[str, Any]) -> tuple[str, SeramateSpecIdentity] | None:
    """Convert one Seramate ladder row into a player lookup identity."""

    basic = entry.get("basic_character_data") or {}
    character = entry.get("character") or {}
    name = basic.get("name") or character.get("name")
    realm = basic.get("realm_slug") or ((character.get("realm") or {}).get("code") or "")
    if not name or not realm:
        return None

    class_code = ((character.get("class") or {}).get("code") or "")
    spec_code = ((character.get("spec") or {}).get("code") or "")
    identity = resolve_seramate_identity(class_code, spec_code)
    if identity is None:
        return None

    return make_player_lookup_key(name, realm), identity


def fetch_ladder_identity_lookup(
    *,
    region: str,
    bracket: str,
    max_players: int = 1000,
    per_page: int = DEFAULT_PER_PAGE,
    request_delay: float = DEFAULT_REQUEST_DELAY,
) -> tuple[dict[str, SeramateSpecIdentity], SeramateEnrichmentReport]:
    """Fetch Seramate ladder pages and build a Name-Realm class/spec lookup table."""

    bracket_slug = get_seramate_ladder_slug(bracket)
    lookup: dict[str, SeramateSpecIdentity] = {}
    report = SeramateEnrichmentReport()
    page = 1
    total_pages = 1
    max_pages = max(1, math.ceil(max_players / per_page))

    while page <= total_pages and page <= max_pages and len(lookup) < max_players:
        url = build_ladder_list_url(
            region=region,
            bracket_slug=bracket_slug,
            page=page,
            per_page=per_page,
        )
        print(f"[seramate {page}/{total_pages}] fetch {bracket_slug}...")
        payload = fetch_json(url)
        rows = payload.get("data") or []
        total_items = payload.get("total_items") or payload.get("total") or 0
        total_pages = max(total_pages, int(payload.get("total_pages") or 0))
        if total_pages <= 0 and total_items:
            total_pages = max(1, math.ceil(total_items / per_page))

        report.pages_fetched += 1
        for entry in rows:
            resolved = entry_to_lookup_identity(entry)
            if resolved is None:
                continue
            player_key, identity = resolved
            lookup.setdefault(player_key, identity)

        if not rows:
            break

        page += 1
        if page <= total_pages and len(lookup) < max_players:
            time.sleep(request_delay)

    report.lookup_size = len(lookup)
    return lookup, report


def enrich_player_rows(players: list[Any], lookup: dict[str, SeramateSpecIdentity]) -> SeramateEnrichmentReport:
    """Attach Seramate class/spec tokens to Blizzard player rows in-place."""

    report = SeramateEnrichmentReport(lookup_size=len(lookup))
    for player in players:
        identity = lookup.get(make_player_lookup_key(player.name, player.realm))
        if identity is None:
            report.unmatched += 1
            continue

        player.class_token = identity.class_token
        player.spec_key = identity.spec_key
        report.matched += 1

    return report
