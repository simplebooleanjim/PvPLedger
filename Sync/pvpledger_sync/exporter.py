"""Read exported match payloads from WoW SavedVariables."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ExportScanResult:
    """Summary of one SavedVariables scan."""

    found: bool
    path: str = ""
    pending_matches: int = 0
    note: str = ""


def find_app_helper_saved_vars(addons_dir: Path) -> Path | None:
    """Locate the newest PvPLedger_AppHelper SavedVariables file under WTF."""

    wow_root = addons_dir.parent.parent.parent
    wtf_root = wow_root / "WTF"
    if not wtf_root.exists():
        return None

    matches = sorted(wtf_root.glob("**/SavedVariables/PvPLedger_AppHelper.lua"), key=lambda p: p.stat().st_mtime, reverse=True)
    return matches[0] if matches else None


def count_pending_matches(saved_vars_text: str) -> int:
    """Estimate pending export rows from SavedVariables Lua text."""

    return len(re.findall(r'\["matchId"\]\s*=', saved_vars_text))


def scan_exports(config_addons_dir: str) -> ExportScanResult:
    """Scan for pending match exports without uploading yet."""

    addons_dir = Path(config_addons_dir)
    saved_vars_path = find_app_helper_saved_vars(addons_dir)
    if not saved_vars_path:
        return ExportScanResult(found=False, note="No PvPLedger_AppHelper SavedVariables file found yet.")

    text = saved_vars_path.read_text(encoding="utf-8", errors="ignore")
    pending = count_pending_matches(text)
    return ExportScanResult(
        found=True,
        path=str(saved_vars_path),
        pending_matches=pending,
        note="Upload endpoint not configured yet." if pending else "No pending exports.",
    )
