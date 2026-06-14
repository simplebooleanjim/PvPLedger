#!/usr/bin/env python3
"""Install regional PvPLedger data addons into Interface/AddOns as sibling folders."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

SUPPORTED_REGIONS = ("US", "EU", "KR", "TW")


def data_addon_name(region: str) -> str:
    """Return the addon folder name for one ladder region."""

    return f"PvPLedger-Data-{region.upper()}"


def wow_addons_dir_from_repo(repo_root: Path) -> Path | None:
    """Return Interface/AddOns when the repo root lives inside a WoW install."""

    addons_dir = repo_root.parent
    if addons_dir.name == "AddOns" and addons_dir.is_dir():
        return addons_dir

    return None


def install_region(*, repo_root: Path, addons_dir: Path, region: str) -> str | None:
    """
    Copy one regional data addon from the repo checkout to AddOns.

    Returns
    -------
    str | None
        Installed addon name, or ``None`` when the source folder is missing.
    """

    source = repo_root / data_addon_name(region)
    if not source.exists():
        return None

    destination = addons_dir / data_addon_name(region)
    if destination.exists():
        shutil.rmtree(destination)

    shutil.copytree(source, destination)
    return destination.name


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""

    parser = argparse.ArgumentParser(
        description="Install PvPLedger-Data-{REGION} folders beside PvPLedger in Interface/AddOns.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Path to the PvPLedger addon repository root.",
    )
    parser.add_argument(
        "--addons-dir",
        type=Path,
        default=None,
        help="Override path to Interface/AddOns (auto-detected by default).",
    )
    parser.add_argument(
        "--regions",
        nargs="+",
        choices=SUPPORTED_REGIONS,
        default=list(SUPPORTED_REGIONS),
        help="Regional data addons to install.",
    )
    return parser.parse_args()


def main() -> int:
    """Install the requested regional data addon folders."""

    args = parse_args()
    addons_dir = args.addons_dir or wow_addons_dir_from_repo(args.repo_root)
    if not addons_dir:
        print("Could not detect Interface/AddOns. Pass --addons-dir explicitly.")
        return 1

    installed: list[str] = []
    missing: list[str] = []

    for region in args.regions:
        name = install_region(repo_root=args.repo_root, addons_dir=addons_dir, region=region)
        if name:
            installed.append(name)
            print(f"Installed {name} -> {addons_dir / name}")
        else:
            missing.append(data_addon_name(region))

    if missing:
        print(f"Skipped missing source folders: {', '.join(missing)}")

    if not installed:
        print("No regional data addons were installed.")
        return 1

    print("Done. Reload the AddOns list on the character select screen.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
