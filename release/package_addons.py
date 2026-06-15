#!/usr/bin/env python3
"""Build CurseForge/Wago-ready addon zip packages."""

from __future__ import annotations

import argparse
import shutil
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from release.exclude_rules import should_exclude_path  # noqa: E402

ADDON_FOLDER_NAMES: tuple[str, ...] = (
    "PvPLedger",
    "PvPLedger-AppHelper",
    "PvPLedger-Data-US",
    "PvPLedger-Data-EU",
    "PvPLedger-Data-KR",
    "PvPLedger-Data-TW",
)


def resolve_addon_source(folder_name: str) -> Path:
    """
    Resolve the source directory for one addon package.

    GitHub CI keeps companion addons inside the repository root. Local dev
    checkouts may also keep sibling folders under ``Interface/AddOns``.

    Parameters
    ----------
    folder_name:
        Addon folder name (for example ``PvPLedger-AppHelper``).

    Returns
    -------
    Path
        Existing source directory, preferring in-repo copies for CI.
    """

    if folder_name == "PvPLedger":
        return REPO_ROOT

    candidates = (
        REPO_ROOT / folder_name,
        REPO_ROOT.parent / folder_name,
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate

    return candidates[0]

DATA_COMPANION_FOLDERS = frozenset(
    {
        "PvPLedger-Data-US",
        "PvPLedger-Data-EU",
        "PvPLedger-Data-KR",
        "PvPLedger-Data-TW",
    }
)


def copy_filtered_tree(source: Path, destination: Path) -> None:
    """
    Copy one addon directory into a staging folder with maintainer paths removed.

    Parameters
    ----------
    source:
        Source addon directory.
    destination:
        Destination directory to create.
    """

    if destination.exists():
        shutil.rmtree(destination)

    def _ignore(directory: str, names: list[str]) -> set[str]:
        current = Path(directory)
        ignored: set[str] = set()
        for name in names:
            candidate = current / name
            if should_exclude_path(candidate, source):
                ignored.add(name)
        return ignored

    shutil.copytree(source, destination, ignore=_ignore)


def stage_data_companion_icon(*, folder_name: str, staging_dir: Path) -> None:
    """
    Copy the shared addon icon into a data companion staging folder.

    Parameters
    ----------
    folder_name:
        Staged addon folder name (for example ``PvPLedger-Data-US``).
    staging_dir:
        Directory containing staged addon folders.
    """

    icon_source = REPO_ROOT / "Media" / "Icon.tga"
    if not icon_source.exists():
        return

    media_dir = staging_dir / folder_name / "Media"
    media_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(icon_source, media_dir / "Icon.tga")


def write_zip(*, staging_dir: Path, zip_path: Path, folder_name: str) -> None:
    """
    Zip one staged addon folder for upload sites.

    Parameters
    ----------
    staging_dir:
        Directory containing the staged addon folder.
    zip_path:
        Output zip path.
    folder_name:
        Root folder name inside the zip archive.
    """

    source = staging_dir / folder_name
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_dir():
                continue
            relative = path.relative_to(staging_dir)
            archive.write(path, relative.as_posix())


def build_packages(*, output_dir: Path) -> list[Path]:
    """
    Build all release zip packages.

    Parameters
    ----------
    output_dir:
        Directory where zip files are written.

    Returns
    -------
    list[Path]
        Created zip file paths.
    """

    staging_root = output_dir / "_staging"
    if staging_root.exists():
        shutil.rmtree(staging_root)
    staging_root.mkdir(parents=True, exist_ok=True)

    created: list[Path] = []
    for folder_name in ADDON_FOLDER_NAMES:
        source_dir = resolve_addon_source(folder_name)
        if not source_dir.exists():
            print(f"skip {folder_name}: missing source at {source_dir}")
            continue

        copy_filtered_tree(source_dir, staging_root / folder_name)
        if folder_name in DATA_COMPANION_FOLDERS:
            stage_data_companion_icon(folder_name=folder_name, staging_dir=staging_root)
        zip_path = output_dir / f"{folder_name}.zip"
        write_zip(staging_dir=staging_root, zip_path=zip_path, folder_name=folder_name)
        created.append(zip_path)
        print(f"built {zip_path}")

    shutil.rmtree(staging_root)
    return created


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""

    parser = argparse.ArgumentParser(description="Build CurseForge/Wago addon zip packages.")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / "release" / "dist",
        help="Directory where zip files are written.",
    )
    return parser.parse_args()


def main() -> int:
    """Build release zip packages."""

    args = parse_args()
    packages = build_packages(output_dir=args.output_dir)
    if not packages:
        print("No packages were built.")
        return 1

    print(f"Built {len(packages)} package(s) in {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
