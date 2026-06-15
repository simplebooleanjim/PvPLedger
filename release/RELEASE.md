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

## 4. GitHub Release (Sync installer + addon zips)

Each release should include:

| Asset | Built on | Purpose |
|-------|----------|---------|
| `PvPLedger-Setup.exe` | Windows (`release\build_release.bat`) | Player installer |
| `PvPLedger-Sync.exe` | Windows | Tray app only |
| `PvPLedger*.zip` (6 files) | Linux CI or `python release\package_addons.py` | CurseForge / Wago / manual install |

### Automatic addon zips on GitHub

Workflow: `.github/workflows/release-addons.yml`

- **On git tag push** (`v*`): builds all six addon zips and attaches them to the GitHub Release.
- **Manual rerun:** Actions → *Release addon packages* → Run workflow → set tag (for example `v0.8.0`) to attach zips to an existing release.

This gives Wago (and WowUp “install from GitHub”) a stable download URL per release, for example:

`https://github.com/simplebooleanjim/PvPLedger/releases/download/v0.8.0/PvPLedger.zip`

### Wago Addons API upload (optional)

1. Create each addon on [addons.wago.io](https://addons.wago.io).
2. Copy `release/wago-projects.example.json` → `release/wago-projects.json` and fill in each `wago_id`.
3. Add repository secret **`WAGO_API_TOKEN`** from [addons.wago.io/account/apikeys](https://addons.wago.io/account/apikeys).
4. Optionally add `## X-Wago-ID: <id>` to each addon `.toc` (shown on the Wago developer dashboard).

On the next tag push (or workflow rerun), CI uploads the same zips to Wago automatically.

Local manual upload:

```bat
set WAGO_API_TOKEN=your-token
python release\upload_wago.py --tag v0.8.0
```

### Manual GitHub release checklist

1. Create or update release `v0.8.0`
2. Attach `PvPLedger-Setup.exe` and `PvPLedger-Sync.exe` (Windows build)
3. Run the **Release addon packages** workflow (or attach `release/dist/*.zip` manually)
4. Paste `release/CHANGELOG.md` section for 0.8.0 as release notes
5. Link CurseForge/Wago addon pages in the release description

## 5. Post-release

- Verify GitHub Actions ladder refresh still commits `AppData.lua`
- Monitor ingest bucket/worker for export batch volume
- Rotate ingest token if the Sync exe was shared publicly with a baked-in token
