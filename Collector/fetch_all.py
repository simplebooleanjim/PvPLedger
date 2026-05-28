#!/usr/bin/env python3
"""Fetch all packaged ladder snapshots for one region.

Used locally via fetch_all.bat and by GitHub Actions to refresh public data files.

Usage:
    python fetch_all.py --region US
    python fetch_all.py --region US --brackets blitz shuffle
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import date
from pathlib import Path

from export_ladder import default_output_path, fetch_and_write_snapshot, load_env_file
from render_app_data import write_app_helper_app_data
from spec_catalog import SUPPORTED_BRACKETS

DEFAULT_BRACKETS: tuple[str, ...] = SUPPORTED_BRACKETS
DATA_ADDON_DIR_NAME = "PvPLedger-Data-US"
DATA_ADDON_TOC_NAME = "PvPLedger-Data-US.toc"
APP_HELPER_DIR_NAME = "PvPLedger-AppHelper"


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments for the all-brackets fetch job."""

    parser = argparse.ArgumentParser(description="Fetch all PvPLedger ladder snapshots for one region.")
    parser.add_argument("--region", default="US", help="Ladder region code such as US or EU.")
    parser.add_argument(
        "--brackets",
        nargs="+",
        choices=SUPPORTED_BRACKETS,
        default=list(DEFAULT_BRACKETS),
        help="Brackets to refresh (defaults to all supported brackets).",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "Data",
        help="Directory where LadderData_*.lua files are written.",
    )
    parser.add_argument("--env-file", type=Path, default=Path(__file__).resolve().parent / ".env")
    parser.add_argument("--season", type=int, default=0, help="Override PvP season id (auto-detect by default).")
    parser.add_argument("--request-delay", type=float, default=0.15, help="Delay between Battle.net requests.")
    parser.add_argument("--seramate-delay", type=float, default=0.2, help="Delay between Seramate requests.")
    parser.add_argument(
        "--enrich-seramate",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Join Seramate class/spec data for arena and RBG brackets.",
    )
    parser.add_argument("--write-manifest", action="store_true", help="Write Data/ladder-manifest.json metadata.")
    parser.add_argument(
        "--sync-data-addon",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Mirror refreshed snapshots into the PvPLedger-Data-US companion addon folder.",
    )
    parser.add_argument(
        "--include-players",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Include a Name-Realm player lookup table in each ladder snapshot.",
    )
    return parser.parse_args()


def write_manifest(*, data_dir: Path, region: str, results: list[dict]) -> Path:
    """Write a small manifest describing the refreshed snapshot files."""

    manifest = {
        "region": region.upper(),
        "generatedDate": date.today().isoformat(),
        "brackets": {
            result["bracket"]: {
                "snapshotId": result["snapshotId"],
                "source": result["source"],
                "season": result["season"],
                "listedPlayers": result["listedPlayers"],
                "file": Path(result["output"]).name,
            }
            for result in results
        },
    }
    manifest_path = data_dir / "ladder-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest_path


def default_data_addon_dir(data_dir: Path) -> Path:
    """Return the companion data-addon directory shipped beside the main addon."""

    return data_dir.parent / DATA_ADDON_DIR_NAME


def write_data_addon_toc(*, addon_dir: Path, version: str) -> Path:
    """Write the companion addon TOC with a date-based version string."""

    toc_path = addon_dir / DATA_ADDON_TOC_NAME
    toc_text = f"""## Interface: 120000, 120001, 120100
## Title: |cFF66CCFFPvPLedger Data (US)|r
## Notes: Frequently updated US ladder snapshots for PvPLedger. Keep this addon updated via your addon manager for fresh ladder data without updating the main addon.
## Author: Jake
## Version: {version}
## Dependencies: PvPLedger

LadderData_US_Blitz.lua
LadderData_US_Shuffle.lua
LadderData_US_Rbg.lua
LadderData_US_Arena2v2.lua
LadderData_US_Arena3v3.lua
"""
    toc_path.write_text(toc_text, encoding="utf-8")
    return toc_path


def sync_data_addon(*, data_dir: Path, results: list[dict]) -> Path:
    """Copy refreshed snapshot Lua files into the companion data-addon folder."""

    addon_dir = default_data_addon_dir(data_dir)
    addon_dir.mkdir(parents=True, exist_ok=True)

    copied_files: list[str] = []
    for result in results:
        source = Path(result["output"])
        destination = addon_dir / source.name
        shutil.copy2(source, destination)
        copied_files.append(destination.name)

    version = date.today().strftime("%Y.%m.%d")
    write_data_addon_toc(addon_dir=addon_dir, version=version)
    print(f"Synced {len(copied_files)} snapshot file(s) to {addon_dir.resolve()}")
    return addon_dir


def main() -> int:
    """Fetch all requested brackets and optionally write a manifest file."""

    args = parse_args()
    load_env_file(args.env_file)

    season_override = args.season if args.season > 0 else None
    results: list[dict] = []

    print(f"Refreshing {len(args.brackets)} ladder snapshot(s) for {args.region.upper()}...")
    for index, bracket in enumerate(args.brackets, start=1):
        output = default_output_path(args.region, bracket, args.data_dir)
        print(f"[{index}/{len(args.brackets)}] {bracket} -> {output.name}")
        result = fetch_and_write_snapshot(
            region=args.region,
            bracket=bracket,
            output=output,
            season_id=season_override,
            enrich_seramate=args.enrich_seramate,
            request_delay=args.request_delay,
            seramate_delay=args.seramate_delay,
            include_players=args.include_players,
        )
        results.append(result)

    if args.write_manifest:
        manifest_path = write_manifest(data_dir=args.data_dir, region=args.region, results=results)
        print(f"Wrote manifest to {manifest_path.resolve()}")

    if args.sync_data_addon:
        sync_data_addon(data_dir=args.data_dir, results=results)

    app_helper_path = write_app_helper_app_data(
        data_dir=args.data_dir,
        region=args.region,
        addon_dir=args.data_dir.parent / APP_HELPER_DIR_NAME,
    )
    print(f"Wrote AppHelper bridge data to {app_helper_path.resolve()}")

    print(json.dumps({"region": args.region.upper(), "results": results}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
