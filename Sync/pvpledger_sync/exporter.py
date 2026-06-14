"""Read exported match payloads from WoW SavedVariables."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .config import SyncConfig
from .i18n import t
from .saved_vars import find_app_helper_saved_vars, get_pending_matches, load_app_helper_saved_vars


@dataclass
class ExportScanResult:
    """Summary of one SavedVariables scan."""

    found: bool
    path: str = ""
    pending_matches: int = 0
    awaiting_reload_matches: int = 0
    note: str = ""
    note_key: str = ""


def _exclude_acknowledged_matches(
    matches: list[dict[str, Any]],
    acknowledged_match_ids: list[str] | None,
) -> list[dict[str, Any]]:
    """
    Remove matches that Sync already uploaded but WoW has not cleared yet.

    Parameters
    ----------
    matches:
        Pending match export records from SavedVariables.
    acknowledged_match_ids:
        Match IDs already uploaded in a prior Sync run.

    Returns
    -------
    list[dict[str, Any]]
        Matches that still need uploading.
    """

    if not acknowledged_match_ids:
        return matches

    blocked = {
        str(match_id).strip()
        for match_id in acknowledged_match_ids
        if str(match_id).strip()
    }
    if not blocked:
        return matches

    return [
        match
        for match in matches
        if str(match.get("matchId", "")).strip() not in blocked
    ]


def scan_exports(
    config_addons_dir: str,
    *,
    acknowledged_match_ids: list[str] | None = None,
) -> ExportScanResult:
    """
    Scan for pending match exports without uploading.

    Parameters
    ----------
    config_addons_dir:
        Path to the WoW `Interface/AddOns` directory.
    acknowledged_match_ids:
        Match IDs already uploaded by Sync but not yet cleared in-game.

    Returns
    -------
    ExportScanResult
        Scan summary for CLI and tray status output.
    """

    addons_dir = Path(config_addons_dir)
    saved_vars_path = find_app_helper_saved_vars(addons_dir)
    if not saved_vars_path:
        return ExportScanResult(
            found=False,
            note=t("EXPORT.NO_SAVED_VARS"),
            note_key="EXPORT.NO_SAVED_VARS",
        )

    try:
        document = load_app_helper_saved_vars(saved_vars_path)
        stored_pending = get_pending_matches(document)
        pending_matches = _exclude_acknowledged_matches(
            stored_pending,
            acknowledged_match_ids,
        )
        pending = len(pending_matches)
        awaiting_reload = len(stored_pending) - pending
    except ValueError as exc:
        return ExportScanResult(
            found=True,
            path=str(saved_vars_path),
            pending_matches=0,
            note=str(exc),
        )

    if pending:
        return ExportScanResult(
            found=True,
            path=str(saved_vars_path),
            pending_matches=pending,
            awaiting_reload_matches=awaiting_reload,
            note=t("EXPORT.PENDING_READY", count=pending),
            note_key="EXPORT.PENDING_READY",
        )

    if awaiting_reload:
        return ExportScanResult(
            found=True,
            path=str(saved_vars_path),
            pending_matches=0,
            awaiting_reload_matches=awaiting_reload,
            note=t("EXPORT.AWAITING_RELOAD", count=awaiting_reload),
            note_key="EXPORT.AWAITING_RELOAD",
        )

    return ExportScanResult(
        found=True,
        path=str(saved_vars_path),
        pending_matches=0,
        note=t("EXPORT.NO_PENDING"),
        note_key="EXPORT.NO_PENDING",
    )


def scan_exports_for_config(config: SyncConfig) -> ExportScanResult:
    """
    Scan SavedVariables using sync config, excluding already-uploaded matches.

    Parameters
    ----------
    config:
        Active sync configuration.

    Returns
    -------
    ExportScanResult
        Scan summary for CLI and tray status output.
    """

    if not config.wow_addons_dir:
        return ExportScanResult(
            found=False,
            note=t("EXPORT.ADDONS_NOT_CONFIGURED"),
            note_key="EXPORT.ADDONS_NOT_CONFIGURED",
        )

    return scan_exports(
        config.wow_addons_dir,
        acknowledged_match_ids=config.pending_upload_match_ids,
    )
