# PvPLedger

PvPLedger tracks your PvP matches and shows imported ladder snapshots in-game. **PvPLedger Sync** is a small Windows app that keeps ladder data up to date in the background.

---

## Download PvPLedger Sync (Windows)

CurseForge and Wago host the **WoW addons only**. The sync app is on **GitHub**:

| Download | Use when |
|----------|----------|
| **[PvPLedger-Setup.exe](https://github.com/simplebooleanjim/PvPLedger/releases/latest/download/PvPLedger-Setup.exe)** | **Recommended** — installs the addons + sync app together |
| **[PvPLedger-Sync.exe](https://github.com/simplebooleanjim/PvPLedger/releases/latest/download/PvPLedger-Sync.exe)** | You already installed the addons from CurseForge or Wago |
| **[All releases](https://github.com/simplebooleanjim/PvPLedger/releases/latest)** | Browse every download on the release page |

---

## Install

### New players (easiest)

1. Download and run **[PvPLedger-Setup.exe](https://github.com/simplebooleanjim/PvPLedger/releases/latest/download/PvPLedger-Setup.exe)**.
2. Point the installer at your WoW **AddOns** folder (usually `World of Warcraft\_retail_\Interface\AddOns`).
3. Leave **Run PvPLedger Sync at Windows login** checked.
4. Open WoW, enable **PvPLedger** and **PvPLedger-AppHelper**, then run **`/reload`**.

### Already using CurseForge or Wago

1. Install **PvPLedger** and **PvPLedger-AppHelper** from your addon manager.
2. Enable both addons in WoW and run **`/reload`**.
3. Download and run **[PvPLedger-Sync.exe](https://github.com/simplebooleanjim/PvPLedger/releases/latest/download/PvPLedger-Sync.exe)** from GitHub so ladder data updates automatically.

Optional **PvPLedger-Data-{REGION}** addons add bundled ladder snapshots for your region.

---

## In WoW

| Addon | Required? |
|-------|-----------|
| **PvPLedger** | Yes — main UI and match tracking |
| **PvPLedger-AppHelper** | Yes — receives updated ladder data from Sync |
| **PvPLedger-Data-{REGION}** | Optional |

After Sync updates ladder files, run **`/reload`** in WoW.

### Commands

| Command | What it does |
|---------|----------------|
| `/pvl` | Open the main window |
| `/pvl status` | Show snapshot age and data sources |
| `/pvl update` | Refresh ladder data from installed sources |
| `/pvl options` | Open settings |

Set your **Ladder region** in **Options → AddOns → PvPLedger** (US, EU, KR, or TW).

---

## PvPLedger Sync

Leave the sync app running while you play. It checks for newer ladder data about every **15 minutes** and shows a Windows notification when something changed — then **`/reload`** in WoW.

**Tray icon (near the clock):**

- **Left-click** — open or close PvPLedger (same as `/pvl`)
- **Right-click → Sync ladder now** — update ladder data immediately

---

## Troubleshooting

**Ladder is empty or stale**

- Run **`/reload`** in WoW.
- Make sure **PvPLedger-AppHelper** is enabled.
- Right-click the tray icon → **Sync ladder now**, then **`/reload`** again.

**Sync is not installed**

- Download **[PvPLedger-Setup.exe](https://github.com/simplebooleanjim/PvPLedger/releases/latest/download/PvPLedger-Setup.exe)** or **[PvPLedger-Sync.exe](https://github.com/simplebooleanjim/PvPLedger/releases/latest/download/PvPLedger-Sync.exe)** from GitHub.

**Wrong region**

- Set the same region in WoW (**Options → AddOns → PvPLedger**) and in the sync app settings (right-click tray icon → open settings folder, or re-run the installer).

---

## Privacy

Match sharing is **off by default**.

| Always | Only if you enable **Share match data** in addon settings |
|--------|-----------------------------------------------------------|
| Public ladder snapshots saved locally | Match combat data and account snapshots queued on logout |
| Your match history in WoW SavedVariables | Uploaded by Sync when the tray app is running |

You can turn sharing off anytime in **Options → AddOns → PvPLedger**.

---

Questions or bugs? [GitHub Issues](https://github.com/simplebooleanjim/PvPLedger/issues)
