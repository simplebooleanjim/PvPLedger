#!/usr/bin/env python3
"""Strip bloated player indexes from PvPLedger SavedVariables files."""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path


def strip_imported_players(text: str) -> tuple[str, int]:
    """Remove imported.players tables from WoW SavedVariables Lua text."""

    pattern = re.compile(r'(\["players"\]\s*=\s*)\{', re.MULTILINE)
    removed = 0
    pieces: list[str] = []
    last = 0

    for match in pattern.finditer(text):
        pieces.append(text[last:match.start()])
        brace_index = match.end() - 1
        depth = 0
        index = brace_index
        while index < len(text):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    index += 1
                    break
            index += 1

        pieces.append('["players"] = {}')
        removed += 1
        last = index

        while last < len(text) and text[last] in " \t\r\n":
            last += 1
        if last < len(text) and text[last] == ",":
            last += 1

    pieces.append(text[last:])
    return "".join(pieces), removed


def prune_file(path: Path, *, backup: bool = True) -> None:
    """Prune one SavedVariables file in place."""

    if not path.exists():
        print(f"Skip missing file: {path}")
        return

    original = path.read_text(encoding="utf-8", errors="ignore")
    pruned, removed = strip_imported_players(original)
    if removed == 0:
        print(f"No imported player tables found: {path}")
        return

    if backup:
        backup_path = path.with_suffix(path.suffix + ".bak")
        shutil.copy2(path, backup_path)
        print(f"Backup written to {backup_path}")

    path.write_text(pruned, encoding="utf-8")
    before_kb = len(original.encode("utf-8")) / 1024
    after_kb = len(pruned.encode("utf-8")) / 1024
    print(f"Pruned {removed} player table(s) in {path}")
    print(f"Size: {before_kb:.1f} KB -> {after_kb:.1f} KB")


def main() -> None:
    """CLI entry point."""

    parser = argparse.ArgumentParser(description="Remove bloated player indexes from PvPLedger SavedVariables.")
    parser.add_argument("paths", nargs="+", type=Path, help="SavedVariables/PvPLedger.lua paths")
    parser.add_argument("--no-backup", action="store_true", help="Do not write .bak backups.")
    args = parser.parse_args()

    for path in args.paths:
        prune_file(path, backup=not args.no_backup)


if __name__ == "__main__":
    main()
