# Changelog

## 0.8.0 — 2026-06-06

### Addons

- Full UI localization (11 client locales).
- Combat analysis: CC Applied / CC Taken stats with Midnight-safe tracking (`LOSS_OF_CONTROL` + `UNIT_AURA`).
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
