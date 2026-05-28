# PvPLedger public ingest API (Cloudflare Worker)

Hosts the community match export endpoint used by **PvPLedger Sync**. Same HTTP contract as the local dev server in `Sync/pvpledger_sync/ingest_server.py`.

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/v1/health` | Health check |
| `POST` | `/api/v1/exports` | Accept one JSON export batch |

Accepted batches are stored in **Cloudflare R2** at:

`ingested/YYYY-MM-DD/batch-{batchId}.json`

## Prerequisites

- [Cloudflare account](https://dash.cloudflare.com/sign-up) (free tier works)
- [Node.js 18+](https://nodejs.org/)
- Wrangler CLI (installed via `npm install` below)

## One-time setup

```bash
cd Server/cloudflare
npm install
npx wrangler login
npx wrangler r2 bucket create pvpledger-exports
```

Generate an upload token (save it somewhere safe):

```bash
# PowerShell
[Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }) -as [byte[]])

# Or Python
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

Set the token as a Worker secret (required for production):

```bash
npx wrangler secret put INGEST_TOKEN
# paste token when prompted
```

## Deploy

```bash
npm run deploy
```

Wrangler prints your worker URL, e.g.:

`https://pvpledger-ingest.<account>.workers.dev`

Your upload endpoint is:

`https://pvpledger-ingest.<account>.workers.dev/api/v1/exports`

Verify:

```bash
curl https://pvpledger-ingest.<account>.workers.dev/api/v1/health
```

## Configure PvPLedger Sync (your machine / testers)

From the `Sync` folder:

```bat
run_sync.bat upload-auth --url https://pvpledger-ingest.<account>.workers.dev/api/v1/exports --token YOUR_TOKEN
run_sync.bat status
run_sync.bat upload-exports
```

Or set env vars instead of saving to config:

- `PVL_UPLOAD_TOKEN` — Bearer token sent with uploads

## Ship to end users (installer build)

1. Copy `Sync/release-config.example.json` → `Sync/release-config.json`
2. Fill in your deployed `upload_url` and `upload_token`
3. Rebuild the installer — `release-config.json` is baked into Setup (gitignored, never commit)

```bat
cd Sync
build_installer.bat
```

## Optional: rate limiting

In the Cloudflare dashboard → your Worker → **Settings** → bind a **Rate Limiting** rule (recommended: ~30 POSTs/minute per IP on `/api/v1/exports`).

## Download ingested batches

List objects in the R2 bucket `pvpledger-exports` via dashboard, or:

```bash
npx wrangler r2 object list pvpledger-exports --prefix ingested/
npx wrangler r2 object get pvpledger-exports ingested/2026-05-25/batch-abc123.json --file batch.json
```

## Local dev (no Cloudflare)

The Sync tray app still runs a localhost ingest server on `127.0.0.1:8765` for development. Point `upload_url` there unless you've configured the public endpoint above.
