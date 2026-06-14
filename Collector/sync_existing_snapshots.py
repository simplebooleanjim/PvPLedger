#!/usr/bin/env python3
"""Sync existing LadderData snapshot files into regional data addons and AppHelper."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from fetch_all import sync_data_addon, write_manifest
from render_app_data import write_app_helper_app_data

APP_HELPER_DIR_NAME = "PvPLedger-AppHelper"


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""

    parser = argparse.ArgumentParser(description="Sync existing packaged ladder files for one region.")
    parser.add_argument("--region", required=True, help="Region code such as KR or TW.")
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "Data",
        help="Directory containing LadderData_{REGION}_*.lua files.",
    )
    return parser.parse_args()


def collect_existing_results(*, data_dir: Path, region: str) -> list[dict]:
    """Build fetch-style result metadata from packaged ladder files."""

    results: list[dict] = []
    for path in sorted(data_dir.glob(f"LadderData_{region.upper()}_*.lua")):
        text = path.read_text(encoding="utf-8")
        bracket_match = re.search(r'bracket = "([^"]+)"', text)
        if not bracket_match:
            continue

        def extract(pattern: str, *, cast=int, default=None):
            match = re.search(pattern, text)
            if not match:
                return default
            return cast(match.group(1))

        results.append(
            {
                "region": region.upper(),
                "bracket": bracket_match.group(1),
                "snapshotId": extract(r'snapshotId = "([^"]+)"', cast=str, default=""),
                "source": extract(r'source = "([^"]+)"', cast=str, default="blizzard-api"),
                "season": extract(r"season = (\d+)", default=0),
                "listedPlayers": extract(r"listedCount = (\d+)", default=0),
                "output": str(path.resolve()),
            }
        )

    return results


def main() -> int:
    """Sync all existing snapshot files for one region."""

    args = parse_args()
    results = collect_existing_results(data_dir=args.data_dir, region=args.region)
    if not results:
        print(f"No LadderData_{args.region.upper()}_*.lua files found in {args.data_dir}")
        return 1

    write_manifest(data_dir=args.data_dir, region=args.region, results=results)
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
    raise SystemExit(main())
