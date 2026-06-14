#!/usr/bin/env python3
"""Build regional ladder-manifest.json files from packaged Lua snapshot files."""

from __future__ import annotations

import argparse
import json
import re
from datetime import date
from pathlib import Path

from render_app_data import regional_manifest_filename

DATA_DIR = Path(__file__).resolve().parent.parent / "Data"


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments for manifest generation."""

    parser = argparse.ArgumentParser(description="Build ladder-manifest metadata from packaged ladder files.")
    parser.add_argument("--region", default="US", help="Ladder region code such as US or EU.")
    parser.add_argument("--data-dir", type=Path, default=DATA_DIR, help="Directory containing LadderData_*.lua files.")
    return parser.parse_args()


def main() -> None:
    """Scan regional LadderData files and write ladder-manifest metadata."""

    args = parse_args()
    region = args.region.upper()
    brackets: dict[str, dict] = {}
    for path in sorted(args.data_dir.glob(f"LadderData_{region}_*.lua")):
        text = path.read_text(encoding="utf-8")
        bracket_match = re.search(r'bracket = "([^"]+)"', text)
        if not bracket_match:
            continue

        brackets[bracket_match.group(1)] = {
            "snapshotId": _match(text, r'snapshotId = "([^"]+)"'),
            "source": _match(text, r'source = "([^"]+)"'),
            "season": int(_match(text, r"season = (\d+)") or 0) or None,
            "snapshotDate": _match(text, r'snapshotDate = "([^"]+)"'),
            "file": path.name,
        }

    manifest = {
        "region": region,
        "generatedDate": date.today().isoformat(),
        "brackets": brackets,
    }
    output = args.data_dir / regional_manifest_filename(region)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output} ({len(brackets)} brackets)")


def _match(text: str, pattern: str) -> str | None:
    """Return the first regex capture group or None."""

    match = re.search(pattern, text)
    return match.group(1) if match else None


if __name__ == "__main__":
    main()
