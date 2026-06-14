#!/usr/bin/env python3
"""Fetch all packaged ladder snapshots for one region.

Used locally via fetch_all.bat and by GitHub Actions to refresh public data files.

Usage:
    python fetch_all.py --region US
    python fetch_all.py --region EU --brackets blitz shuffle
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import date, datetime, timezone
from pathlib import Path

from export_ladder import default_output_path, fetch_and_write_snapshot, load_env_file
from render_app_data import regional_manifest_filename, write_app_helper_app_data
from spec_catalog import SUPPORTED_BRACKETS

DEFAULT_BRACKETS: tuple[str, ...] = SUPPORTED_BRACKETS
APP_HELPER_DIR_NAME = "PvPLedger-AppHelper"


def data_addon_dir_name(region: str) -> str:
    """Return the companion data-addon folder name for one region."""

    return f"PvPLedger-Data-{region.upper()}"


def data_addon_toc_name(region: str) -> str:
    """Return the companion data-addon TOC filename for one region."""

    return f"{data_addon_dir_name(region)}.toc"


def ladder_file_names(region: str) -> list[str]:
    """Return the packaged ladder filenames for one region."""

    region_upper = region.upper()
    return [
        f"LadderData_{region_upper}_Blitz.lua",
        f"LadderData_{region_upper}_Shuffle.lua",
        f"LadderData_{region_upper}_Rbg.lua",
        f"LadderData_{region_upper}_Arena2v2.lua",
        f"LadderData_{region_upper}_Arena3v3.lua",
    ]


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
    parser.add_argument("--write-manifest", action="store_true", help="Write Data/ladder-manifest metadata.")
    parser.add_argument(
        "--sync-data-addon",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Mirror refreshed snapshots into the matching PvPLedger-Data-{REGION} companion addon folder.",
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
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
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
    manifest_path = data_dir / regional_manifest_filename(region)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest_path


def default_data_addon_dir(data_dir: Path, region: str) -> Path:
    """Return the companion data-addon directory shipped beside the main addon."""

    return data_dir.parent / data_addon_dir_name(region)


def wow_addons_dir_from_data_dir(data_dir: Path) -> Path | None:
    """Return ``Interface/AddOns`` when ``data_dir`` lives inside one addon checkout."""

    if data_dir.name != "Data":
        return None

    addons_dir = data_dir.parent.parent
    if addons_dir.name == "AddOns" and addons_dir.is_dir():
        return addons_dir

    return None


def installed_data_addon_dir(data_dir: Path, region: str) -> Path | None:
    """Return the sibling AddOns install path for one regional data addon."""

    addons_dir = wow_addons_dir_from_data_dir(data_dir)
    if not addons_dir:
        return None

    return addons_dir / data_addon_dir_name(region)


def sync_data_addon(*, data_dir: Path, region: str, results: list[dict]) -> list[Path]:
    """Copy refreshed snapshot Lua files into companion data-addon folders."""

    target_dirs: list[Path] = [default_data_addon_dir(data_dir, region)]
    installed_dir = installed_data_addon_dir(data_dir, region)
    if installed_dir and installed_dir.resolve() not in {path.resolve() for path in target_dirs}:
        target_dirs.append(installed_dir)

    copied_files: list[str] = []
    version = date.today().strftime("%Y.%m.%d")

    for addon_dir in target_dirs:
        addon_dir.mkdir(parents=True, exist_ok=True)
        copied_files.clear()

        for result in results:
            source = Path(result["output"])
            destination = addon_dir / source.name
            shutil.copy2(source, destination)
            copied_files.append(destination.name)

        write_data_addon_toc(
            addon_dir=addon_dir,
            region=region,
            version=version,
            ladder_files=[Path(result["output"]).name for result in results],
        )
        print(f"Synced {len(copied_files)} snapshot file(s) to {addon_dir.resolve()}")

    return target_dirs


def write_data_addon_toc(
    *,
    addon_dir: Path,
    region: str,
    version: str,
    ladder_files: list[str] | None = None,
) -> Path:
    """Write the companion addon TOC with a date-based version string."""

    region_upper = region.upper()
    toc_path = addon_dir / data_addon_toc_name(region)
    file_lines = "\n".join(ladder_files or ladder_file_names(region))
    toc_text = f"""## Interface: 120000, 120001, 120100
## Title: |cFF66CCFFPvPLedger Data ({region_upper})|r
## Notes: Frequently updated {region_upper} ladder snapshots for PvPLedger. Keep this addon updated via your addon manager for fresh ladder data without updating the main addon.
## Author: Jake
## Version: {version}
## IconTexture: Interface\\AddOns\\PvPLedger\\Media\\Icon.tga
## Dependencies: PvPLedger

{file_lines}
"""
    toc_path.write_text(toc_text, encoding="utf-8")
    return toc_path


def main() -> int:
    """Fetch all requested brackets and optionally write a manifest file."""

    args = parse_args()
    load_env_file(args.env_file)

    season_override = args.season if args.season > 0 else None
    results: list[dict] = []

    print(f"Refreshing {len(args.brackets)} ladder snapshot(s) for {args.region.upper()}...")
    failures: list[str] = []
    for index, bracket in enumerate(args.brackets, start=1):
        output = default_output_path(args.region, bracket, args.data_dir)
        print(f"[{index}/{len(args.brackets)}] {bracket} -> {output.name}")
        try:
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
        except Exception as exc:  # noqa: BLE001 - one failed bracket should not abort the whole region refresh
            failures.append(f"{bracket}: {exc}")
            print(f"Warning: skipped {bracket} for {args.region.upper()} ({exc})")

    if not results:
        print(json.dumps({"region": args.region.upper(), "failures": failures}, indent=2))
        return 1

    if failures:
        print(f"Completed with {len(failures)} skipped bracket(s).")

    if args.write_manifest:
        manifest_path = write_manifest(data_dir=args.data_dir, region=args.region, results=results)
        print(f"Wrote manifest to {manifest_path.resolve()}")

    if args.sync_data_addon:
        sync_data_addon(data_dir=args.data_dir, region=args.region, results=results)

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
