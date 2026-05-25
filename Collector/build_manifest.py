#!/usr/bin/env python3
"""Build ladder-manifest.json from existing packaged Lua snapshot files."""

from __future__ import annotations

import json
import re
from datetime import date
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "Data"


def main() -> None:
    """Scan Data/LadderData_*.lua and write ladder-manifest.json."""

    brackets: dict[str, dict] = {}
    for path in sorted(DATA_DIR.glob("LadderData_*.lua")):
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
        "region": "US",
        "generatedDate": date.today().isoformat(),
        "brackets": brackets,
    }
    output = DATA_DIR / "ladder-manifest.json"
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output} ({len(brackets)} brackets)")


def _match(text: str, pattern: str) -> str | None:
    """Return the first regex capture group or None."""

    match = re.search(pattern, text)
    return match.group(1) if match else None


if __name__ == "__main__":
    main()
