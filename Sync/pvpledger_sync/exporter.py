"""Read exported match payloads from WoW SavedVariables."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .saved_vars import find_app_helper_saved_vars, get_pending_matches, load_app_helper_saved_vars


@dataclass
class ExportScanResult:
    """Summary of one SavedVariables scan."""

    found: bool
    path: str = ""
    pending_matches: int = 0
    note: str = ""


def scan_exports(config_addons_dir: str) -> ExportScanResult:
    """
    Scan for pending match exports without uploading.

    Parameters
    ----------
    config_addons_dir:
        Path to the WoW `Interface/AddOns` directory.

    Returns
    -------
    ExportScanResult
        Scan summary for CLI and tray status output.
    """

    addons_dir = Path(config_addons_dir)
    saved_vars_path = find_app_helper_saved_vars(addons_dir)
    if not saved_vars_path:
        return ExportScanResult(found=False, note="No PvPLedger_AppHelper SavedVariables file found yet.")

    try:
        document = load_app_helper_saved_vars(saved_vars_path)
        pending = len(get_pending_matches(document))
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
            note=f"{pending} pending match export(s) ready for upload.",
        )

    return ExportScanResult(
        found=True,
        path=str(saved_vars_path),
        pending_matches=0,
        note="No pending exports.",
    )
