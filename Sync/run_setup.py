#!/usr/bin/env python3
"""Run the PvPLedger Sync GUI installer without building an exe."""

from __future__ import annotations

import sys
from pathlib import Path

sync_root = Path(__file__).resolve().parent
sys.path.insert(0, str(sync_root))
sys.path.insert(0, str(sync_root / "installer"))

from setup_gui import main

if __name__ == "__main__":
    main()
