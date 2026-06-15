"""Shared rules for player-facing addon packages and installer bundles."""

from __future__ import annotations

from pathlib import Path

# Maintainer-only top-level directories inside the main addon repo.
EXCLUDED_TOP_LEVEL_DIRS = frozenset(
    {
        ".git",
        ".github",
        ".venv",
        ".vscode",
        "Server",
        "Sync",
        "release",
        "__pycache__",
        # Companion addons ship as separate CurseForge/Wago projects.
        "PvPLedger-AppHelper",
        "PvPLedger-Data-US",
        "PvPLedger-Data-EU",
        "PvPLedger-Data-KR",
        "PvPLedger-Data-TW",
    }
)

# Files that must never ship to players.
EXCLUDED_FILE_NAMES = frozenset(
    {
        ".env",
        ".gitignore",
        "release-config.json",
        "generate_brand_assets.py",
        "env.example",
    }
)

# Relative paths (posix-style) omitted from player packages.
EXCLUDED_RELATIVE_PATHS = frozenset(
    {
        "Data/match-exports",
        "README.md",
    }
)


def relative_posix(path: Path, root: Path) -> str:
    """
    Return one path relative to ``root`` using forward slashes.

    Parameters
    ----------
    path:
        Candidate file or directory.
    root:
        Package root directory.

    Returns
    -------
    str
        Relative path string.
    """

    return path.relative_to(root).as_posix()


def should_exclude_path(path: Path, root: Path) -> bool:
    """
    Return True when one path must be omitted from player-facing packages.

    Parameters
    ----------
    path:
        Candidate file or directory under ``root``.
    root:
        Package root directory.

    Returns
    -------
    bool
        True when the path should be excluded.
    """

    relative = relative_posix(path, root)
    parts = Path(relative).parts
    if not parts:
        return False

    if parts[0] in EXCLUDED_TOP_LEVEL_DIRS:
        return True

    if relative in EXCLUDED_RELATIVE_PATHS:
        return True

    if relative.startswith("Data/match-exports/"):
        return True

    if path.name in EXCLUDED_FILE_NAMES:
        return True

    if path.suffix in {".pyc", ".pyo"}:
        return True

    if "Collector" in parts and path.suffix in {".py", ".bat"}:
        return True

    if parts[0] == "Data" and path.name.startswith("ladder-manifest") and path.suffix == ".json":
        return True

    if parts[0] == "Media" and path.suffix == ".py":
        return True

    return False


def ignore_names(directory: str, names: list[str]) -> set[str]:
    """
    Build an ignore set for ``shutil.copytree``.

    Parameters
    ----------
    directory:
        Current directory being visited.
    names:
        Immediate child names in ``directory``.

    Returns
    -------
    set[str]
        Child names to skip during copy.
    """

    root = Path(directory)
    ignored: set[str] = set()
    for name in names:
        candidate = root / name
        if should_exclude_path(candidate, root):
            ignored.add(name)
    return ignored
