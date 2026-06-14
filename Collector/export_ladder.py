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
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

from blizzard_client import BlizzardApiError, BlizzardClient, build_catalog_report
from seramate_client import SeramateApiError, enrich_player_rows, fetch_ladder_identity_lookup
from spec_catalog import (
    BRACKET_SPEC_BY_SLUG,
    PER_SPEC_BRACKETS,
    SUPPORTED_BRACKETS,
    get_bracket_specs,
    get_single_ladder_api_slug,
    is_single_ladder_bracket,
    SERAMATE_ENRICHED_BRACKETS,
    supports_seramate_enrichment,
)

# Battle.net returns every ranked player per spec bracket; the official listed
# ladder only includes the top 1000 players shown on Blizzard's site.
LISTED_RANK_CAP = 1000

# Seasonal title cutoffs (Rank 1, Gladiator, Hero, etc.) are percentiles of the
# full rated population, not just the listed top 1000. The collector has the
# complete leaderboard at fetch time, so it derives these before truncation.
# Percentages follow Blizzard's published methodology: top X% of players rated
# at or above RATED_POPULATION_FLOOR.
TITLE_CUTOFF_PERCENTILES: tuple[float, ...] = (0.1, 0.5, 1.0, 3.0)
RATED_POPULATION_FLOOR = 1000

# Per-spec Rank 1 titles (Solo Shuffle / Battleground Blitz) are awarded to at
# least a handful of players per specialization even when 0.1% of that spec's
# population would round to fewer. Blizzard guarantees a minimum number of Rank 1
# slots per spec, so the per-spec 0.1% cutoff is floored to this many ranks.
PER_SPEC_RANK1_MIN_SLOTS = 3
PER_SPEC_RANK1_PERCENTILE = 0.1


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
    faction: str = ""


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


def is_listed_ladder_entry(entry: dict[str, Any]) -> bool:
    """Return True when a Battle.net row is within the official listed ladder."""

    rank = entry.get("rank")
    return isinstance(rank, int) and 1 <= rank <= LISTED_RANK_CAP


def is_listed_ladder_player(player: PlayerRow) -> bool:
    """Return True when a player row is within the official listed ladder."""

    return 1 <= player.rank <= LISTED_RANK_CAP


def aggregate_players(players: list[PlayerRow]) -> tuple[dict[str, SpecAggregate], dict[str, Any]]:
    """Compute per-spec and overall aggregates from listed player rows."""

    listed_players = [player for player in players if player.spec_key]
    if not listed_players:
        listed_players = players

    by_spec: dict[str, list[PlayerRow]] = {}
    for player in listed_players:
        if not player.spec_key:
            continue
        by_spec.setdefault(player.spec_key, []).append(player)

    spec_aggs: dict[str, SpecAggregate] = {}
    for spec_key, rows in by_spec.items():
        ratings = sorted((row.rating for row in rows), reverse=True)
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

    all_ratings = sorted((player.rating for player in players), reverse=True)
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

    ranked = sorted(players, key=lambda row: row.rating, reverse=True)
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


def rated_population(all_ratings: list[int], floor: int = RATED_POPULATION_FLOOR) -> int:
    """Count rated players at or above the population floor.

    :param all_ratings: Every ranked player's rating from the full leaderboard.
    :param floor: Minimum rating counted toward the rated population.
    :return: Number of players at or above ``floor``.
    """

    return sum(1 for rating in all_ratings if rating >= floor)


def compute_title_cutoffs(
    all_ratings: list[int],
    percentiles: tuple[float, ...] = TITLE_CUTOFF_PERCENTILES,
    floor: int = RATED_POPULATION_FLOOR,
    rank_floors: dict[float, int] | None = None,
) -> list[dict[str, Any]]:
    """Compute the rating threshold for each seasonal title percentile.

    The cutoff rating for a percentile is the rating held by the player at the
    cutoff rank, where the cutoff rank is that percentile of the full rated
    population (players at or above ``floor``). This mirrors how Blizzard awards
    Rank 1, Gladiator, and Hero of the Alliance/Horde titles at season end.

    :param all_ratings: Every ranked player's rating from the full leaderboard.
    :param percentiles: Top-percent thresholds to evaluate (e.g. 0.1 for 0.1%).
    :param floor: Minimum rating counted toward the rated population.
    :param rank_floors: Optional minimum cutoff rank per percentile, e.g.
        ``{0.1: 3}`` to guarantee at least 3 Rank 1 slots. Clamped to population.
    :return: One ``{pct, rank, rating}`` entry per percentile, or an empty list
        when no rated players are present.
    """

    population_ratings = sorted(
        (rating for rating in all_ratings if rating >= floor),
        reverse=True,
    )
    population = len(population_ratings)
    if population == 0:
        return []

    cutoffs: list[dict[str, Any]] = []
    for percentile in percentiles:
        rank = max(1, math.ceil((percentile / 100.0) * population))
        if rank_floors:
            minimum = rank_floors.get(percentile)
            if minimum:
                rank = max(rank, minimum)
        rank = min(rank, population)
        cutoffs.append({
            "pct": percentile,
            "rank": rank,
            "rating": population_ratings[rank - 1],
        })
    return cutoffs


def compute_spec_cutoffs(
    spec_ratings: dict[str, list[int]],
    percentiles: tuple[float, ...] = TITLE_CUTOFF_PERCENTILES,
    floor: int = RATED_POPULATION_FLOOR,
) -> dict[str, dict[str, Any]]:
    """Compute per-specialization title cutoffs for per-spec brackets.

    Solo Shuffle and Battleground Blitz award Rank 1 titles to the top N% of
    *each specialization's* own ladder, not the combined ladder. This builds a
    cutoff table keyed by spec so the addon can resolve the threshold for the
    player's current spec.

    :param spec_ratings: Mapping of ``spec_key`` to that spec's full rating list.
    :param percentiles: Top-percent thresholds to evaluate (e.g. 0.1 for 0.1%).
    :param floor: Minimum rating counted toward each spec's rated population.
    :return: Mapping of ``spec_key`` to ``{population, cutoffs}``, skipping specs
        with no rated players at or above ``floor``.
    """

    rank_floors = {PER_SPEC_RANK1_PERCENTILE: PER_SPEC_RANK1_MIN_SLOTS}
    result: dict[str, dict[str, Any]] = {}
    for spec_key, ratings in spec_ratings.items():
        if not spec_key:
            continue
        cutoffs = compute_title_cutoffs(
            ratings,
            percentiles=percentiles,
            floor=floor,
            rank_floors=rank_floors,
        )
        if not cutoffs:
            continue
        result[spec_key] = {
            "population": rated_population(ratings, floor=floor),
            "cutoffs": cutoffs,
        }
    return result


def aggregate_by_class(spec_aggs: dict[str, SpecAggregate]) -> dict[str, SpecAggregate]:
    """Roll per-spec aggregates up to class-level totals."""

    by_class: dict[str, list[SpecAggregate]] = {}
    for spec_key, agg in spec_aggs.items():
        class_token = spec_key.split("_", 1)[0]
        by_class.setdefault(class_token, []).append(agg)

    class_aggs: dict[str, SpecAggregate] = {}
    for class_token, rows in by_class.items():
        listed_counts = [row.listed_count for row in rows]
        avg_ratings = [row.avg_listed_rating for row in rows if row.avg_listed_rating is not None]
        median_ratings = [row.median_listed_rating for row in rows if row.median_listed_rating is not None]
        top100_values = [row.top100_avg for row in rows if row.top100_avg is not None]
        highest_values = [row.highest for row in rows if row.highest is not None]
        buckets: dict[str, int] = {}

        for row in rows:
            for bucket, count in row.buckets.items():
                buckets[bucket] = buckets.get(bucket, 0) + count

        class_aggs[class_token] = SpecAggregate(
            listed_count=sum(listed_counts),
            avg_listed_rating=round(statistics.mean(avg_ratings), 1) if avg_ratings else None,
            median_listed_rating=round(statistics.median(median_ratings), 1) if median_ratings else None,
            top100_avg=round(statistics.mean(top100_values), 1) if top100_values else None,
            highest=max(highest_values) if highest_values else None,
            buckets=buckets,
        )

    return class_aggs


def normalize_realm_key(realm: str) -> str:
    """Normalize a realm slug or display name for stable player lookup keys."""

    return re.sub(r"[^a-z0-9]", "", realm.lower())


def make_player_lookup_key(name: str, realm: str = "") -> str:
    """Build a case- and punctuation-insensitive player lookup key."""

    normalized_name = name.lower()
    if not realm:
        return normalized_name

    return f"{normalized_name}-{normalize_realm_key(realm)}"


def format_player_display_name(name: str, realm: str = "") -> str:
    """Preserve Battle.net player and realm casing for UI display."""

    if realm:
        return f"{name}-{realm}"
    return name


def build_player_index(players: list[PlayerRow]) -> dict[str, dict[str, Any]]:
    """Build a compact player lookup keyed by normalized Name-Realm for the addon."""

    index: dict[str, dict[str, Any]] = {}
    for player in players:
        player_key = make_player_lookup_key(player.name, player.realm)
        existing = index.get(player_key)
        candidate = {
            "displayName": format_player_display_name(player.name, player.realm),
            "specKey": player.spec_key,
            "rating": player.rating,
            "rank": player.rank,
            "wins": player.wins,
            "losses": player.losses,
            "faction": player.faction,
        }

        if existing is None or player.rating > existing["rating"]:
            index[player_key] = candidate

    return index


def enrich_blizzard_players_with_seramate(
    *,
    players: list[PlayerRow],
    region: str,
    bracket: str,
    request_delay: float = 0.2,
) -> None:
    """Attach Seramate class/spec identities to listed Blizzard player rows."""

    lookup, fetch_report = fetch_ladder_identity_lookup(
        region=region,
        bracket=bracket,
        max_players=LISTED_RANK_CAP,
        request_delay=request_delay,
    )
    enrich_report = enrich_player_rows(players, lookup)
    print(
        f"Seramate enrichment: matched {enrich_report.matched}/{len(players)} listed players "
        f"using {fetch_report.pages_fetched} page(s) ({fetch_report.lookup_size} identities indexed)."
    )
    if enrich_report.unmatched:
        print(f"Warning: {enrich_report.unmatched} listed players had no Seramate class/spec match.")


def create_blizzard_client(region: str) -> BlizzardClient:
    """Create an authenticated Battle.net client from environment variables."""

    client_id = os.environ.get("BNET_CLIENT_ID")
    client_secret = os.environ.get("BNET_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise BlizzardApiError(
            "Missing BNET_CLIENT_ID or BNET_CLIENT_SECRET. "
            "Create Collector/.env from env.example or set environment variables."
        )

    return BlizzardClient(client_id, client_secret, region=region.lower())


def probe_blizzard_api(*, region: str, bracket: str = "blitz", season_id: int | None = None) -> dict[str, Any]:
    """Validate credentials and compare the spec catalog against the live season index."""

    bracket = bracket.lower()
    client = create_blizzard_client(region)
    resolved_season_id = season_id or client.get_current_pvp_season_id()
    bracket_slugs = client.list_bracket_leaderboard_slugs(resolved_season_id, bracket)

    if is_single_ladder_bracket(bracket):
        api_slug = get_single_ladder_api_slug(bracket)
        all_slugs = set(client.list_leaderboard_slugs(resolved_season_id))
        matched = api_slug in all_slugs
        return {
            "region": region.upper(),
            "bracket": bracket,
            "seasonId": resolved_season_id,
            "apiSlug": api_slug,
            "bracketSlugCount": len(all_slugs),
            "matchedCount": 1 if matched else 0,
            "missingFromApi": [] if matched else [api_slug],
            "unknownInCatalog": [],
        }

    catalog_slugs = set(BRACKET_SPEC_BY_SLUG[bracket])
    report = build_catalog_report(set(bracket_slugs), catalog_slugs)

    return {
        "region": region.upper(),
        "bracket": bracket,
        "seasonId": resolved_season_id,
        "bracketSlugCount": len(bracket_slugs),
        "catalogSlugCount": len(catalog_slugs),
        "matchedCount": len(report["matched"]),
        "missingFromApi": report["missingFromApi"],
        "unknownInCatalog": report["unknownInCatalog"],
    }


def parse_savedvars_lua(path: Path) -> dict[str, Any]:
    """Parse a minimal subset of WoW SavedVariables Lua into Python data."""

    text = path.read_text(encoding="utf-8", errors="ignore")
    match = re.search(r"PvPLedgerDB\s*=\s*(\{.*\})\s*$", text, re.DOTALL)
    if not match:
        match = re.search(r"BlitzLedgerDB\s*=\s*(\{.*\})\s*$", text, re.DOTALL)
    if not match:
        return {}

    return {"rawLength": len(match.group(1)), "path": str(path)}


def entry_faction(entry: dict[str, Any]) -> str:
    """Return the player's faction ("HORDE"/"ALLIANCE") from a leaderboard entry.

    :param entry: Raw Battle.net leaderboard entry.
    :return: Uppercase faction token, or "" when unknown.
    """

    faction = entry.get("faction")
    if isinstance(faction, dict):
        faction_type = faction.get("type")
        if faction_type in ("HORDE", "ALLIANCE"):
            return faction_type
    return ""


def entry_to_player_row(entry: dict[str, Any], spec_definition) -> PlayerRow | None:
    """Convert one Battle.net leaderboard entry into a PlayerRow."""

    character = entry.get("character") or {}
    name = character.get("name")
    realm = ((character.get("realm") or {}).get("slug") or "")
    rating = entry.get("rating")
    rank = int(entry.get("rank") or 0)
    if not name or rating is None or not is_listed_ladder_entry(entry):
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
        rank=rank,
        faction=entry_faction(entry),
    )


def entry_to_rbg_player_row(entry: dict[str, Any]) -> PlayerRow | None:
    """Convert one Battle.net RBG leaderboard entry into a PlayerRow."""

    character = entry.get("character") or {}
    name = character.get("name")
    realm = ((character.get("realm") or {}).get("slug") or "")
    rating = entry.get("rating")
    rank = int(entry.get("rank") or 0)
    if not name or rating is None or not is_listed_ladder_entry(entry):
        return None

    stats = entry.get("season_match_statistics") or {}
    wins = int(stats.get("won") or 0)
    losses = int(stats.get("lost") or 0)

    return PlayerRow(
        name=name,
        realm=realm,
        class_token="",
        spec_key="",
        rating=int(rating),
        wins=wins,
        losses=losses,
        rank=rank,
        faction=entry_faction(entry),
    )


def collect_entry_ratings(entries: list[dict[str, Any]]) -> list[int]:
    """Extract every valid rating from raw leaderboard entries before truncation.

    :param entries: Raw Battle.net leaderboard entries (all ranks).
    :return: Integer ratings for every entry that reports one.
    """

    ratings: list[int] = []
    for entry in entries:
        rating = entry.get("rating")
        if isinstance(rating, (int, float)):
            ratings.append(int(rating))
    return ratings


def fetch_blizzard_single_ladder_players(
    *,
    bracket: str,
    api_slug: str,
    region: str,
    season_id: int | None = None,
) -> tuple[list[PlayerRow], int, list[str], list[int], dict[str, list[int]]]:
    """Fetch listed players from one combined bracket leaderboard such as RBG.

    :return: ``(listed_players, season_id, fetched_slugs, all_ratings, spec_ratings)``
        where ``all_ratings`` covers the full combined ladder for title-cutoff math
        and ``spec_ratings`` is empty (combined ladders have no per-spec cutoffs).
    """

    client = create_blizzard_client(region)
    resolved_season_id = season_id or client.get_current_pvp_season_id()
    all_slugs = set(client.list_leaderboard_slugs(resolved_season_id))

    if api_slug not in all_slugs:
        raise BlizzardApiError(
            f"{api_slug} was not found in the current season index for {bracket.upper()}."
        )

    print(f"fetch {api_slug}...")
    entries = client.fetch_leaderboard_entries(resolved_season_id, api_slug)
    all_ratings = collect_entry_ratings(entries)
    players = [row for entry in entries if (row := entry_to_rbg_player_row(entry))]

    if not players:
        raise BlizzardApiError(f"No listed {bracket} players fetched from Battle.net.")

    return players, resolved_season_id, [api_slug], all_ratings, {}


def fetch_blizzard_bracket_players(
    *,
    bracket: str,
    region: str,
    season_id: int | None = None,
    request_delay: float = 0.15,
    max_specs: int | None = None,
) -> tuple[list[PlayerRow], int, list[str], list[int], dict[str, list[int]]]:
    """Fetch listed players for all known specs in one bracket from Battle.net.

    :return: ``(listed_players, season_id, fetched_slugs, all_ratings, spec_ratings)``
        where ``all_ratings`` pools the full ladder across specs and ``spec_ratings``
        maps each ``spec_key`` to its own full rating list for per-spec cutoffs.
    """

    bracket = bracket.lower()
    if is_single_ladder_bracket(bracket):
        return fetch_blizzard_single_ladder_players(
            bracket=bracket,
            api_slug=get_single_ladder_api_slug(bracket),
            region=region,
            season_id=season_id,
        )

    client = create_blizzard_client(region)
    resolved_season_id = season_id or client.get_current_pvp_season_id()
    available_slugs = set(client.list_bracket_leaderboard_slugs(resolved_season_id, bracket))

    specs = list(get_bracket_specs(bracket))
    if max_specs is not None:
        specs = specs[:max_specs]

    players: list[PlayerRow] = []
    fetched_slugs: list[str] = []
    skipped_slugs: list[str] = []
    all_ratings: list[int] = []
    spec_ratings: dict[str, list[int]] = {}

    for index, spec_definition in enumerate(specs, start=1):
        api_slug = spec_definition.api_slug
        if api_slug not in available_slugs:
            skipped_slugs.append(api_slug)
            print(f"[{index}/{len(specs)}] skip {api_slug} (not in season index)")
            continue

        print(f"[{index}/{len(specs)}] fetch {api_slug}...")
        entries = client.fetch_leaderboard_entries(resolved_season_id, api_slug)
        fetched_slugs.append(api_slug)
        entry_ratings = collect_entry_ratings(entries)
        all_ratings.extend(entry_ratings)
        spec_ratings.setdefault(spec_definition.spec_key, []).extend(entry_ratings)

        for entry in entries:
            player = entry_to_player_row(entry, spec_definition)
            if player:
                players.append(player)

        time.sleep(request_delay)

    if skipped_slugs:
        print(f"Skipped {len(skipped_slugs)} specs not present in the current season index.")

    if not players:
        raise BlizzardApiError(
            f"No {bracket} ladder players fetched. Verify your API credentials, season id, "
            f"and that {bracket} bracket slugs match spec_catalog.py."
        )

    return players, resolved_season_id, fetched_slugs, all_ratings, spec_ratings


def fetch_blizzard_blitz_players(
    *,
    region: str,
    season_id: int | None = None,
    request_delay: float = 0.15,
    max_specs: int | None = None,
) -> tuple[list[PlayerRow], int, list[str], list[int], dict[str, list[int]]]:
    """Fetch listed Blitz players for all known specs from Battle.net."""

    return fetch_blizzard_bracket_players(
        bracket="blitz",
        region=region,
        season_id=season_id,
        request_delay=request_delay,
        max_specs=max_specs,
    )


def render_lua_snapshot(
    *,
    region: str,
    bracket: str,
    season: int,
    players: list[PlayerRow],
    source: str,
    include_players: bool = False,
    title_cutoffs: list[dict[str, Any]] | None = None,
    rated_population_count: int | None = None,
    spec_cutoffs: dict[str, dict[str, Any]] | None = None,
) -> str:
    """Render a compact Lua snapshot file for the addon.

    :param title_cutoffs: Seasonal title percentile thresholds for ``overall``.
    :param rated_population_count: Full rated population used for percentiles.
    :param spec_cutoffs: Per-spec title cutoffs for per-spec brackets (Shuffle,
        Blitz), keyed by ``spec_key`` -> ``{population, cutoffs}``.
    """

    spec_aggs, overall = aggregate_players(players)
    class_aggs = aggregate_by_class(spec_aggs) if spec_aggs else {}
    player_index = build_player_index(players) if include_players else {}
    snapshot_id = f"{region.lower()}-{bracket}-s{season}-{date.today().isoformat()}"
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    region_upper = region.upper()
    lines = [
        "--- Imported ladder snapshot generated by PvPLedger collector.",
        "PvPLedgerLadderData = PvPLedgerLadderData or {}",
        f"PvPLedgerLadderData.{region_upper} = PvPLedgerLadderData.{region_upper} or {{}}",
        f"PvPLedgerLadderData.{region_upper}.{bracket} = {{",
        f'    snapshotId = "{snapshot_id}",',
        f'    region = "{region_upper}",',
        f'    bracket = "{bracket}",',
        f"    season = {season},",
        f'    snapshotDate = "{date.today().isoformat()}",',
        f'    generatedAt = "{generated_at}",',
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

    lines.append("        },")

    if rated_population_count is not None:
        lines.append(f"        ratedPopulation = {rated_population_count},")

    lines.append("        titleCutoffs = {")
    for cutoff in (title_cutoffs or []):
        lines.extend([
            "            {",
            f'                pct = {lua_number(cutoff["pct"])},',
            f'                rank = {cutoff["rank"]},',
            f'                rating = {cutoff["rating"]},',
            "            },",
        ])
    lines.append("        },")

    if spec_cutoffs:
        lines.append("        specCutoffs = {")
        for spec_key in sorted(spec_cutoffs):
            spec_entry = spec_cutoffs[spec_key]
            lines.extend([
                f'            ["{spec_key}"] = {{',
                f"                population = {spec_entry['population']},",
                "                cutoffs = {",
            ])
            for cutoff in spec_entry["cutoffs"]:
                lines.extend([
                    "                    {",
                    f'                        pct = {lua_number(cutoff["pct"])},',
                    f'                        rank = {cutoff["rank"]},',
                    f'                        rating = {cutoff["rating"]},',
                    "                    },",
                ])
            lines.extend([
                "                },",
                "            },",
            ])
        lines.append("        },")

    lines.extend([
        "    },",
        "    byClass = {",
    ])

    for class_token in sorted(class_aggs):
        agg = class_aggs[class_token]
        lines.extend([
            f'        ["{class_token}"] = {{',
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
        "    players = {",
    ])

    for player_key in sorted(player_index):
        row = player_index[player_key]
        lines.extend([
            f'        ["{escape_lua_string(player_key)}"] = {{',
            f'            displayName = "{escape_lua_string(row["displayName"])}",',
            f'            specKey = "{row["specKey"]}",',
            f"            rating = {row['rating']},",
            f"            rank = {row['rank']},",
            f"            wins = {row['wins']},",
            f"            losses = {row['losses']},",
            f'            faction = "{row["faction"]}",',
            "        },",
        ])

    lines.extend([
        "    },",
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


def escape_lua_string(value: str) -> str:
    """Escape a string for safe inclusion in a Lua string literal."""

    return value.replace("\\", "\\\\").replace('"', '\\"')


def load_sample_players() -> list[PlayerRow]:
    """Return a tiny sample dataset for local smoke testing."""

    return [
        PlayerRow("Alpha", "Area52", "EVOKER", "EVOKER_DEVASTATION", 2450, 120, 40, 1),
        PlayerRow("Bravo", "Stormrage", "HUNTER", "HUNTER_MARKSMANSHIP", 2380, 95, 52, 2),
        PlayerRow("Charlie", "Tichondrius", "PRIEST", "PRIEST_SHADOW", 2310, 88, 61, 3),
    ]


def default_output_path(region: str, bracket: str, data_dir: Path | None = None) -> Path:
    """Return the default Lua snapshot path for one region and bracket."""

    base = data_dir or Path("../Data")
    bracket_label = bracket.capitalize()
    return base / f"LadderData_{region.upper()}_{bracket_label}.lua"


def fetch_and_write_snapshot(
    *,
    region: str,
    bracket: str,
    output: Path,
    season_id: int | None = None,
    enrich_seramate: bool | None = None,
    request_delay: float = 0.15,
    seramate_delay: float = 0.2,
    include_players: bool = False,
    max_specs: int | None = None,
) -> dict[str, Any]:
    """Fetch one bracket from Battle.net and write a compact Lua snapshot file."""

    bracket = bracket.lower()
    players, season, fetched_slugs, all_ratings, spec_ratings = fetch_blizzard_bracket_players(
        bracket=bracket,
        region=region,
        season_id=season_id,
        request_delay=request_delay,
        max_specs=max_specs,
    )
    source = "blizzard-api"
    should_enrich = (
        enrich_seramate
        if enrich_seramate is not None
        else supports_seramate_enrichment(bracket)
    )
    if should_enrich:
        if not supports_seramate_enrichment(bracket):
            raise SeramateApiError(
                f"Seramate enrichment is only supported for {', '.join(SERAMATE_ENRICHED_BRACKETS)}."
            )
        try:
            enrich_blizzard_players_with_seramate(
                players=players,
                region=region,
                bracket=bracket,
                request_delay=seramate_delay,
            )
            source = "blizzard-api+seramate"
        except SeramateApiError as exc:
            print(f"Warning: Seramate enrichment unavailable for {region.upper()} {bracket} ({exc}).")

    if is_single_ladder_bracket(bracket):
        print(
            f"Fetched {len(players)} listed players (top {LISTED_RANK_CAP}) "
            f"for {bracket} season {season} ({region.upper()})."
        )
    else:
        print(
            f"Fetched {len(players)} listed players (top {LISTED_RANK_CAP} per spec) "
            f"across {len(fetched_slugs)} specs for {bracket} season {season} ({region.upper()})."
        )

    title_cutoffs = compute_title_cutoffs(all_ratings)
    population = rated_population(all_ratings)
    print(
        f"Title cutoffs: {len(title_cutoffs)} percentile threshold(s) computed "
        f"from {population} rated players (>= {RATED_POPULATION_FLOOR})."
    )

    spec_cutoffs = None
    if bracket in PER_SPEC_BRACKETS and spec_ratings:
        spec_cutoffs = compute_spec_cutoffs(spec_ratings)
        print(
            f"Per-spec cutoffs: computed for {len(spec_cutoffs)} specialization(s) "
            f"(Rank 1 titles are awarded per spec for {bracket})."
        )

    lua_text = render_lua_snapshot(
        region=region,
        bracket=bracket,
        season=season,
        players=players,
        source=source,
        include_players=include_players,
        title_cutoffs=title_cutoffs,
        rated_population_count=population,
        spec_cutoffs=spec_cutoffs,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(lua_text, encoding="utf-8")
    print(f"Wrote snapshot to {output.resolve()}")

    snapshot_id = f"{region.lower()}-{bracket}-s{season}-{date.today().isoformat()}"
    return {
        "region": region.upper(),
        "bracket": bracket,
        "season": season,
        "source": source,
        "snapshotId": snapshot_id,
        "output": str(output.resolve()),
        "listedPlayers": len(players),
        "specSlugsFetched": len(fetched_slugs),
    }


def main() -> None:
    """CLI entry point."""

    parser = argparse.ArgumentParser(description="Build PvPLedger imported ladder Lua snapshots.")
    parser.add_argument("--region", default="US")
    parser.add_argument("--bracket", default="blitz", choices=SUPPORTED_BRACKETS)
    parser.add_argument("--season", type=int, default=0, help="Override PvP season id (auto-detect by default).")
    parser.add_argument("--source", default="sample")
    parser.add_argument(
        "--output",
        type=Path,
        help="Output Lua path (defaults to ../Data/LadderData_{region}_{Bracket}.lua).",
    )
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    parser.add_argument("--parse-savedvars", type=Path, help="Path to PvPLedger SavedVariables file.")
    parser.add_argument("--players-json", type=Path, help="Optional JSON file containing player rows.")
    parser.add_argument("--fetch-blizzard", action="store_true", help="Pull live ladder data from Battle.net.")
    parser.add_argument("--probe-blizzard", action="store_true", help="Validate credentials and compare spec slugs to Battle.net.")
    parser.add_argument("--include-players", action="store_true", help="Include a Name-Realm player lookup table in the Lua snapshot.")
    parser.add_argument(
        "--enrich-seramate",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Join Seramate ladder class/spec data onto combined Blizzard ladders (default for arena/RBG).",
    )
    parser.add_argument("--seramate-delay", type=float, default=0.2, help="Delay between Seramate API requests.")
    parser.add_argument("--max-specs", type=int, help="Limit fetched specs for testing.")
    parser.add_argument("--request-delay", type=float, default=0.15, help="Delay between Battle.net requests.")
    args = parser.parse_args()
    if args.output is None:
        args.output = default_output_path(args.region, args.bracket)

    load_env_file(args.env_file)

    if args.probe_blizzard:
        report = probe_blizzard_api(
            region=args.region,
            bracket=args.bracket,
            season_id=args.season if args.season > 0 else None,
        )
        print(json.dumps(report, indent=2))
        if report["missingFromApi"]:
            print(
                f"Warning: {len(report['missingFromApi'])} catalog slugs were not found in the live season index."
            )
        if report["unknownInCatalog"]:
            print(
                f"Note: {len(report['unknownInCatalog'])} live {args.bracket} slugs are not mapped in spec_catalog.py."
            )
        return

    if args.parse_savedvars:
        parsed = parse_savedvars_lua(args.parse_savedvars)
        print(json.dumps(parsed, indent=2))

    if args.fetch_blizzard:
        fetch_and_write_snapshot(
            region=args.region,
            bracket=args.bracket,
            output=args.output,
            season_id=args.season if args.season > 0 else None,
            enrich_seramate=args.enrich_seramate,
            request_delay=args.request_delay,
            seramate_delay=args.seramate_delay,
            include_players=args.include_players,
            max_specs=args.max_specs,
        )
        return

    season = args.season
    source = args.source
    players: list[PlayerRow]

    if args.players_json:
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
                faction=str(row.get("faction", "")),
            )
            for row in payload
        ]
    else:
        players = load_sample_players()

    include_players = args.include_players
    sample_ratings = [player.rating for player in players]
    lua_text = render_lua_snapshot(
        region=args.region,
        bracket=args.bracket,
        season=season,
        players=players,
        source=source,
        include_players=include_players,
        title_cutoffs=compute_title_cutoffs(sample_ratings),
        rated_population_count=rated_population(sample_ratings),
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(lua_text, encoding="utf-8")
    print(f"Wrote snapshot to {args.output.resolve()}")


if __name__ == "__main__":
    main()
