# PvPLedger 0.8.0 — Full experience release checklist

This guide covers publishing **addons + Sync + ingest** together.

## 1. Build artifacts

From the repository root:

```bat
release\build_release.bat
```

Outputs:

| Artifact | Path | Upload target |
|----------|------|----------------|
| Main addon zip | `release/dist/PvPLedger.zip` | CurseForge + Wago |
| AppHelper zip | `release/dist/PvPLedger-AppHelper.zip` | CurseForge + Wago (required dependency) |
| Data-US zip | `release/dist/PvPLedger-Data-US.zip` | Optional companion |
| Data-EU/KR/TW zip | `release/dist/PvPLedger-Data-*.zip` | Optional companions |
| Windows installer | `Sync/dist/PvPLedger-Setup.exe` | GitHub Release |
| Tray app only | `Sync/dist/PvPLedger-Sync.exe` | GitHub Release (optional) |

Addon-only rebuild (no installer):

```bat
python release\package_addons.py
```

## 2. Before you publish

- [ ] Tag git commit `v0.8.0`
- [ ] Confirm `release-config.json` exists locally (gitignored) before building Setup if you want public ingest baked in
- [ ] Deploy Cloudflare worker (`Server/cloudflare`) and verify `GET /api/v1/health`
- [ ] Refresh stale ladder data (US `PvPLedger-Data-US` is older than EU/KR/TW) via CI or `Collector/fetch_all.py`
- [ ] Smoke test from **zips only** on a clean AddOns folder:
  - `/pvl` opens UI
  - Ladder browser shows players
  - One arena/BG records combat stats (including CC)
  - Optional: enable **Share match data** → logout → Sync upload

## 3. CurseForge / Wago

Create one project per addon (recommended):

1. **PvPLedger** — upload `PvPLedger.zip`
2. **PvPLedger-AppHelper** — upload `PvPLedger-AppHelper.zip`, mark as required dependency of main addon
3. **PvPLedger-Data-{REGION}** — optional companions

Project metadata:

- **Game version:** The War Within / Midnight (`120000+`)
- **License:** MIT (see `LICENSE`)
- **Dependencies:** PvPLedger requires PvPLedger-AppHelper
- **Description:** Link to GitHub Release for `PvPLedger-Setup.exe`
- **Privacy:** Copy the “Privacy & data collection” section from `README.md`

## 4. GitHub Release (Sync installer)

1. Create release `v0.8.0`
2. Attach `PvPLedger-Setup.exe` and `PvPLedger-Sync.exe`
3. Paste `release/CHANGELOG.md` section for 0.8.0 as release notes
4. Link CurseForge/Wago addon pages in the release description

## 5. Post-release

- Verify GitHub Actions ladder refresh still commits `AppData.lua`
- Monitor ingest bucket/worker for export batch volume
- Rotate ingest token if the Sync exe was shared publicly with a baked-in token
