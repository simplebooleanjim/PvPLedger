# Changelog

## 0.8.3 — 2026-06-16

### Addons

- Solo Shuffle and Battleground Blitz: Galactic Legend / Marshal / Warlord cutoffs now use **top 8 per specialization** (matches Blizzard’s Midnight change).
- Title cutoffs: resolve rank-8 thresholds from listed spec ladder players when bundled snapshots still carry legacy 0.1% (rank 3) cutoffs.
- Combat lockdown: defer UI refresh, inspect, and ladder updates during combat to reduce action-bar taint (`ADDON_ACTION_FORBIDDEN`).
- Fix ESC menu error: stop chaining ``CloseAll()`` from frame ``OnHide`` during UISpecialFrames dismiss (prevents ``ClearTarget()`` taint on ``ToggleGameMenu``).
- Combat lockdown: defer ladder/title refreshes and inspect callbacks during combat to reduce action-bar taint (`ActionButton:SetAttribute`).
- Combat lockdown: pause damage-meter polling and roster inspects while the UI is closed and combat lockdown is active; resume on regen.

### Collector

- `export_ladder.py`: per-spec Rank 1 cutoff pinned to rank 8 (replaces 0.1% with a 3-player floor). Re-export ladder data for updated cutoff ratings in snapshots.

## 0.8.2 — 2026-06-15

### Addons

- Ladder search: fix accent matching for UTF-8 names (`lunartic` finds `Lunartiç`).
- Ladder search: debounced input and faster scan (no full-ladder sort on every keystroke).

## 0.8.1 — 2026-06-06

### Addons

- Removed CC Applied / CC Taken combat stats (Midnight-safe simplification).
- Ladder search: accent-insensitive partial name matching (`jose` finds `José`).
- Combat log: skip `COMBAT_LOG_EVENT_UNFILTERED` registration on Midnight to avoid `ADDON_ACTION_FORBIDDEN` errors.

### Release tooling

- GitHub Release workflow attaches six addon zip packages on `v*` tags.
- Optional Wago API upload script (`release/upload_wago.py`).

## 0.8.0 — 2026-06-06

### Addons

- Full UI localization (11 client locales).
- Expanded optional match export (schema v2): spell breakdowns, raw combat events, CR history, account snapshots.
- Multi-region ladder companions (EU, KR, TW) and improved ladder merge logic.
- Fixed `/pvl` and minimap open path after localization init changes.

### PvPLedger Sync

- Localized tray app and Windows installer UI.
- Schema v2 upload payloads with account/character snapshots.
- Installer merge-copy (preserves dev `.git` checkouts).
- Friend bundle strips maintainer Python, test exports, and pipeline secrets.

### Release tooling

- `release/package_addons.py` — CurseForge/Wago zip builder.
- `release/build_release.bat` — addon zips + installer build.

## 0.7.0

- Initial hybrid ladder + match observation release.
- US ladder snapshots, AppHelper bridge, and desktop sync tray app.
