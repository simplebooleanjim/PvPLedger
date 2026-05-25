#!/usr/bin/env python3
"""External collector for PvPLedger.

This script is the offline half of the hybrid architecture:
1. Pull official Blitz ladder snapshots from the Battle.net API.
2. Parse PvPLedger SavedVariables from the WoW WTF folder.
3. Emit compact aggregate Lua files for the in-game addon.

Usage:
    python export_ladder.py --fetch-blizzard --region US --output ../Data/LadderData_US_Blitz.lua
    python export_ladder.py --parse-savedvars "C:/.../WTF/Account/.../SavedVariables/PvPLedger.lua"
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import statistics
import time
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any

from blizzard_client import BlizzardApiError, BlizzardClient
from spec_catalog import BLITZ_SPECS


@dataclass
class PlayerRow:
    """One listed ladder player."""

    name: str
    realm: str
    class_token: str
    spec_key: str
    rating: int
    wins: int = 0
    losses: int = 0
    rank: int = 0


@dataclass
class SpecAggregate:
    """Aggregate stats for one class/spec on the listed ladder."""

    listed_count: int = 0
    avg_listed_rating: float | None = None
    median_listed_rating: float | None = None
    top100_avg: float | None = None
    highest: int | None = None
    buckets: dict[str, int] = field(default_factory=dict)


def rating_bucket(rating: int, width: int = 100) -> str:
    """Return a human-readable rating bucket label."""

    lower = (rating // width) * width
    upper = lower + width - 1
    return f"{lower}-{upper}"


def build_spec_key(class_token: str, spec_token: str) -> str:
    """Build a stable spec key such as EVOKER_DEVASTATION."""

    return f"{class_token.upper()}_{spec_token.upper()}"


def load_env_file(path: Path) -> None:
    """Load KEY=VALUE pairs from a simple .env file into os.environ."""

    if not path.exists():
        return

    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def aggregate_players(players: list[PlayerRow]) -> tuple[dict[str, SpecAggregate], dict[str, Any]]:
    """Compute per-spec and overall aggregates from listed player rows."""

    by_spec: dict[str, list[PlayerRow]] = {}
    for player in players:
        by_spec.setdefault(player.spec_key, []).append(player)

    spec_aggs: dict[str, SpecAggregate] = {}
    for spec_key, rows in by_spec.items():
        ratings = sorted(row.rating for row in rows)
        top100 = ratings[:100]
        buckets: dict[str, int] = {}
        for row in rows:
            bucket = rating_bucket(row.rating)
            buckets[bucket] = buckets.get(bucket, 0) + 1

        spec_aggs[spec_key] = SpecAggregate(
            listed_count=len(rows),
            avg_listed_rating=round(statistics.mean(ratings), 1),
            median_listed_rating=round(statistics.median(ratings), 1),
            top100_avg=round(statistics.mean(top100), 1) if top100 else None,
            highest=max(ratings),
            buckets=buckets,
        )

    all_ratings = sorted(player.rating for player in players)
    overall = {
        "listedCount": len(all_ratings),
        "avgListedRating": round(statistics.mean(all_ratings), 1) if all_ratings else None,
        "medianListedRating": round(statistics.median(all_ratings), 1) if all_ratings else None,
        "top100Avg": round(statistics.mean(all_ratings[:100]), 1) if all_ratings else None,
        "cutoffs": build_cutoffs(players),
        "buckets": aggregate_bucket_map(players),
    }

    return spec_aggs, overall


def aggregate_bucket_map(players: list[PlayerRow]) -> dict[str, int]:
    """Build overall rating bucket counts."""

    buckets: dict[str, int] = {}
    for player in players:
        bucket = rating_bucket(player.rating)
        buckets[bucket] = buckets.get(bucket, 0) + 1
    return buckets


def build_cutoffs(players: list[PlayerRow]) -> list[dict[str, Any]]:
    """Estimate cutoff ratings for common top-N thresholds."""

    if not players:
        return []

    ranked = sorted(players, key=lambda row: row.rank or math.inf)
    thresholds = [
        ("Top 500", 500),
        ("Top 1000", 1000),
        ("Top 5000", 5000),
    ]

    cutoffs = []
    for label, rank in thresholds:
        if len(ranked) >= rank:
            cutoffs.append({
                "label": label,
                "rank": rank,
                "rating": ranked[rank - 1].rating,
            })
    return cutoffs


def parse_savedvars_lua(path: Path) -> dict[str, Any]:
    """Parse a minimal subset of WoW SavedVariables Lua into Python data."""

    text = path.read_text(encoding="utf-8", errors="ignore")
    match = re.search(r"PvPLedgerDB\s*=\s*(\{.*\})\s*$", text, re.DOTALL)
    if not match:
        match = re.search(r"BlitzLedgerDB\s*=\s*(\{.*\})\s*$", text, re.DOTALL)
    if not match:
        return {}

    return {"rawLength": len(match.group(1)), "path": str(path)}


def entry_to_player_row(entry: dict[str, Any], spec_definition) -> PlayerRow | None:
    """Convert one Battle.net leaderboard entry into a PlayerRow."""

    character = entry.get("character") or {}
    name = character.get("name")
    realm = ((character.get("realm") or {}).get("slug") or "")
    rating = entry.get("rating")
    if not name or rating is None:
        return None

    stats = entry.get("season_match_statistics") or {}
    wins = int(stats.get("won") or 0)
    losses = int(stats.get("lost") or 0)

    return PlayerRow(
        name=name,
        realm=realm,
        class_token=spec_definition.class_token,
        spec_key=spec_definition.spec_key,
        rating=int(rating),
        wins=wins,
        losses=losses,
        rank=int(entry.get("rank") or 0),
    )


def fetch_blizzard_blitz_players(
    *,
    region: str,
    season_id: int | None = None,
    request_delay: float = 0.15,
    max_specs: int | None = None,
) -> tuple[list[PlayerRow], int, list[str]]:
    """Fetch listed Blitz players for all known specs from Battle.net."""

    client_id = os.environ.get("BNET_CLIENT_ID")
    client_secret = os.environ.get("BNET_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise BlizzardApiError(
            "Missing BNET_CLIENT_ID or BNET_CLIENT_SECRET. "
            "Create collector/.env from env.example or set environment variables."
        )

    client = BlizzardClient(client_id, client_secret, region=region.lower())
    resolved_season_id = season_id or client.get_current_pvp_season_id()
    available_slugs = set(client.list_leaderboard_slugs(resolved_season_id))

    specs = list(BLITZ_SPECS)
    if max_specs is not None:
        specs = specs[:max_specs]

    players: list[PlayerRow] = []
    fetched_slugs: list[str] = []
    skipped_slugs: list[str] = []

    for index, spec_definition in enumerate(specs, start=1):
        api_slug = spec_definition.api_slug
        if api_slug not in available_slugs:
            skipped_slugs.append(api_slug)
            print(f"[{index}/{len(specs)}] skip {api_slug} (not in season index)")
            continue

        print(f"[{index}/{len(specs)}] fetch {api_slug}...")
        entries = client.fetch_leaderboard_entries(resolved_season_id, api_slug)
        fetched_slugs.append(api_slug)

        for entry in entries:
            player = entry_to_player_row(entry, spec_definition)
            if player:
                players.append(player)

        time.sleep(request_delay)

    if skipped_slugs:
        print(f"Skipped {len(skipped_slugs)} specs not present in the current season index.")

    if not players:
        raise BlizzardApiError(
            "No Blitz ladder players fetched. Verify your API credentials, season id, "
            "and that Blitz bracket slugs match spec_catalog.py."
        )

    return players, resolved_season_id, fetched_slugs


def render_lua_snapshot(
    *,
    region: str,
    bracket: str,
    season: int,
    players: list[PlayerRow],
    source: str,
) -> str:
    """Render a compact Lua snapshot file for the addon."""

    spec_aggs, overall = aggregate_players(players)
    snapshot_id = f"{region.lower()}-{bracket}-s{season}-{date.today().isoformat()}"

    lines = [
        "--- Imported ladder snapshot generated by PvPLedger collector.",
        "PvPLedgerLadderData = {",
        f'    snapshotId = "{snapshot_id}",',
        f'    region = "{region.upper()}",',
        f'    bracket = "{bracket}",',
        f"    season = {season},",
        f'    snapshotDate = "{date.today().isoformat()}",',
        f'    source = "{source}",',
        "    overall = {",
        f"        listedCount = {overall['listedCount']},",
        f"        avgListedRating = {lua_number(overall['avgListedRating'])},",
        f"        medianListedRating = {lua_number(overall['medianListedRating'])},",
        f"        top100Avg = {lua_number(overall['top100Avg'])},",
        "        cutoffs = {",
    ]

    for cutoff in overall["cutoffs"]:
        lines.extend([
            "            {",
            f'                label = "{cutoff["label"]}",',
            f'                rank = {cutoff["rank"]},',
            f'                rating = {cutoff["rating"]},',
            "            },",
        ])

    lines.extend([
        "        },",
        "        buckets = {",
    ])

    for bucket, count in sorted(overall["buckets"].items()):
        lines.append(f'            ["{bucket}"] = {count},')

    lines.extend([
        "        },",
        "    },",
        "    byClass = {},",
        "    bySpec = {",
    ])

    for spec_key in sorted(spec_aggs):
        agg = spec_aggs[spec_key]
        lines.extend([
            f'        ["{spec_key}"] = {{',
            f"            listedCount = {agg.listed_count},",
            f"            avgListedRating = {lua_number(agg.avg_listed_rating)},",
            f"            medianListedRating = {lua_number(agg.median_listed_rating)},",
            f"            top100Avg = {lua_number(agg.top100_avg)},",
            f"            highest = {lua_number(agg.highest)},",
            "            buckets = {",
        ])
        for bucket, count in sorted(agg.buckets.items()):
            lines.append(f'                ["{bucket}"] = {count},')
        lines.extend([
            "            },",
            "        },",
        ])

    lines.extend([
        "    },",
        "    players = {},",
        "}",
        "",
    ])

    return "\n".join(lines)


def lua_number(value: Any) -> str:
    """Render a Python numeric value as Lua, using nil for missing values."""

    if value is None:
        return "nil"
    if isinstance(value, float):
        return f"{value:.1f}"
    return str(value)


def load_sample_players() -> list[PlayerRow]:
    """Return a tiny sample dataset for local smoke testing."""

    return [
        PlayerRow("Alpha", "Area52", "EVOKER", "EVOKER_DEVASTATION", 2450, 120, 40, 1),
        PlayerRow("Bravo", "Stormrage", "HUNTER", "HUNTER_MARKSMANSHIP", 2380, 95, 52, 2),
        PlayerRow("Charlie", "Tichondrius", "PRIEST", "PRIEST_SHADOW", 2310, 88, 61, 3),
    ]


def main() -> None:
    """CLI entry point."""

    parser = argparse.ArgumentParser(description="Build PvPLedger imported ladder Lua snapshots.")
    parser.add_argument("--region", default="US")
    parser.add_argument("--bracket", default="blitz")
    parser.add_argument("--season", type=int, default=0, help="Override PvP season id (auto-detect by default).")
    parser.add_argument("--source", default="sample")
    parser.add_argument("--output", type=Path, default=Path("../Data/LadderData_US_Blitz.lua"))
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    parser.add_argument("--parse-savedvars", type=Path, help="Path to PvPLedger SavedVariables file.")
    parser.add_argument("--players-json", type=Path, help="Optional JSON file containing player rows.")
    parser.add_argument("--fetch-blizzard", action="store_true", help="Pull live Blitz ladder data from Battle.net.")
    parser.add_argument("--max-specs", type=int, help="Limit fetched specs for testing.")
    parser.add_argument("--request-delay", type=float, default=0.15, help="Delay between Battle.net requests.")
    args = parser.parse_args()

    load_env_file(args.env_file)

    if args.parse_savedvars:
        parsed = parse_savedvars_lua(args.parse_savedvars)
        print(json.dumps(parsed, indent=2))

    season = args.season
    source = args.source
    players: list[PlayerRow]

    if args.fetch_blizzard:
        season_override = args.season if args.season > 0 else None
        players, season, fetched_slugs = fetch_blizzard_blitz_players(
            region=args.region,
            season_id=season_override,
            request_delay=args.request_delay,
            max_specs=args.max_specs,
        )
        source = "blizzard-api"
        print(
            f"Fetched {len(players)} listed players across {len(fetched_slugs)} specs "
            f"for season {season} ({args.region.upper()})."
        )
    elif args.players_json:
        payload = json.loads(args.players_json.read_text(encoding="utf-8"))
        players = [
            PlayerRow(
                name=row["name"],
                realm=row["realm"],
                class_token=row["class"],
                spec_key=build_spec_key(row["class"], row["spec"]),
                rating=int(row["rating"]),
                wins=int(row.get("wins", 0)),
                losses=int(row.get("losses", 0)),
                rank=int(row.get("rank", 0)),
            )
            for row in payload
        ]
    else:
        players = load_sample_players()

    lua_text = render_lua_snapshot(
        region=args.region,
        bracket=args.bracket,
        season=season,
        players=players,
        source=source,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(lua_text, encoding="utf-8")
    print(f"Wrote snapshot to {args.output.resolve()}")


if __name__ == "__main__":
    main()
