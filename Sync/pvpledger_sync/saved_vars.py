"""Parse PvPLedger AppHelper SavedVariables from WoW WTF files."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SAVED_VARS_NAME = "PvPLedger_AppHelperDB"
SAVED_VARS_FILENAMES = (
    "PvPLedger-AppHelper.lua",
    "PvPLedger_AppHelper.lua",
)
TABLE_ASSIGNMENT_PATTERN = re.compile(
    rf"{re.escape(SAVED_VARS_NAME)}\s*=\s*(\{{.*\}})\s*$",
    re.DOTALL,
)


@dataclass
class SavedVarsDocument:
    """One parsed AppHelper SavedVariables file."""

    path: Path
    data: dict[str, Any]


def resolve_wtf_root(addons_dir: Path) -> Path | None:
    """
    Resolve the WoW WTF directory from one AddOns path.

    Parameters
    ----------
    addons_dir:
        Path to the WoW `Interface/AddOns` directory.

    Returns
    -------
    Path | None
        Existing WTF directory when found.
    """

    addons_dir = addons_dir.resolve()
    wtf_root = addons_dir.parent.parent / "WTF"
    if wtf_root.exists():
        return wtf_root

    return None


def find_app_helper_saved_vars(addons_dir: Path) -> Path | None:
    """
    Locate the newest PvPLedger_AppHelper SavedVariables file under WTF.

    Parameters
    ----------
    addons_dir:
        Path to the WoW `Interface/AddOns` directory.

    Returns
    -------
    Path | None
        Newest matching SavedVariables file, if any exist.
    """

    wtf_root = resolve_wtf_root(addons_dir)
    if not wtf_root:
        return None

    matches: list[Path] = []
    for filename in SAVED_VARS_FILENAMES:
        matches.extend(wtf_root.glob(f"**/SavedVariables/{filename}"))

    if not matches:
        return None

    return max(matches, key=lambda path: path.stat().st_mtime)


def _extract_table_literal(text: str) -> str | None:
    """Extract the Lua table literal assigned to PvPLedger_AppHelperDB."""

    match = TABLE_ASSIGNMENT_PATTERN.search(text.strip())
    if match:
        return match.group(1)

    marker = f"{SAVED_VARS_NAME} = "
    start = text.find(marker)
    if start < 0:
        return None

    brace_start = text.find("{", start)
    if brace_start < 0:
        return None

    depth = 0
    for index in range(brace_start, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_start : index + 1]
    return None


def _decode_lua_table(table_literal: str) -> dict[str, Any]:
    """
    Decode one Lua table literal into Python data structures.

    Parameters
    ----------
    table_literal:
        Lua table text, for example `{ ["export"] = { ... } }`.

    Returns
    -------
    dict[str, Any]
        Parsed table contents.

    Raises
    ------
    ValueError
        When the table cannot be decoded.
    """

    try:
        from slpp import slpp as lua  # type: ignore[import-untyped]

        decoded = lua.decode(table_literal)
    except Exception as exc:  # noqa: BLE001 - fall back below
        raise ValueError(f"Failed to decode SavedVariables table: {exc}") from exc

    if not isinstance(decoded, dict):
        raise ValueError("SavedVariables root value must be a table.")
    return decoded


def load_app_helper_saved_vars(path: Path) -> SavedVarsDocument:
    """
    Load and parse one PvPLedger_AppHelper SavedVariables file.

    Parameters
    ----------
    path:
        Absolute path to the AppHelper SavedVariables file.

    Returns
    -------
    SavedVarsDocument
        Parsed SavedVariables payload.
    """

    text = path.read_text(encoding="utf-8", errors="ignore")
    table_literal = _extract_table_literal(text)
    if not table_literal:
        raise ValueError(f"Could not locate {SAVED_VARS_NAME} table in {path}")

    return SavedVarsDocument(path=path, data=_decode_lua_table(table_literal))


def get_pending_matches(document: SavedVarsDocument) -> list[dict[str, Any]]:
    """
    Return pending match export records from one SavedVariables document.

    Parameters
    ----------
    document:
        Parsed SavedVariables document.

    Returns
    -------
    list[dict[str, Any]]
        Pending match export payloads.
    """

    export_section = document.data.get("export") or {}
    pending = export_section.get("pendingMatches") or []
    if not isinstance(pending, list):
        return []

    matches: list[dict[str, Any]] = []
    for item in pending:
        if isinstance(item, dict) and item.get("matchId"):
            matches.append(item)
    return matches


def get_export_metadata(document: SavedVarsDocument) -> dict[str, Any]:
    """
    Return export/sync metadata stored alongside pending matches.

    Parameters
    ----------
    document:
        Parsed SavedVariables document.

    Returns
    -------
    dict[str, Any]
        Metadata such as addon version, snapshots, and account identity.
    """

    export_section = document.data.get("export") or {}
    sync_section = document.data.get("sync") or {}
    return {
        "schemaVersion": export_section.get("schemaVersion"),
        "lastExportedAt": export_section.get("lastExportedAt"),
        "lastMatchAt": export_section.get("lastMatchAt"),
        "addonVersion": sync_section.get("addonVersion"),
        "lastCharacter": sync_section.get("lastCharacter"),
        "accountIdentity": sync_section.get("accountIdentity"),
        "accountSnapshot": export_section.get("accountSnapshot"),
        "characterSnapshot": export_section.get("characterSnapshot"),
    }
