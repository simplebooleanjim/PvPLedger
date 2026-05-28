#!/usr/bin/env python3
"""CLI entry point for PvPLedger Sync."""

from __future__ import annotations

import argparse
import sys
import time

from .config import (
    DEFAULT_INGEST_HOST,
    DEFAULT_INGEST_PORT,
    DEFAULT_UPLOAD_URL,
    SyncConfig,
    apply_config_defaults,
    default_config_path,
    guess_addons_dir,
    load_config,
    save_config,
)
from .downloader import local_app_data_source, local_manifest_source, sync_app_data
from .exporter import scan_exports
from .ingest_server import default_ingest_dir, default_upload_url, ensure_ingest_server_running, run_ingest_server_forever
from .manifest import fetch_manifest, format_github_error
from .startup import install_startup, is_startup_installed, uninstall_startup
from .uploader import resolve_export_spool_dir, upload_exports


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""

    parser = argparse.ArgumentParser(description="PvPLedger Sync desktop companion.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init", help="Create or update local sync config.")
    init_parser.add_argument("--addons-dir", type=str, default="", help="Path to WoW Interface/AddOns.")

    subparsers.add_parser("status", help="Show sync configuration and remote manifest state.")
    subparsers.add_parser("sync", help="Download AppData.lua if remote data is newer.")
    sync_parser = subparsers.add_parser("sync-now", help="Force download AppData.lua.")
    sync_parser.add_argument("--force", action="store_true", help="Ignored alias for force sync.")
    sync_parser.add_argument(
        "--local",
        action="store_true",
        help="Copy AppData.lua from the local PvPLedger repo instead of GitHub.",
    )

    watch_parser = subparsers.add_parser("watch", help="Poll GitHub and sync on an interval.")
    watch_parser.add_argument("--minutes", type=int, default=0, help="Override poll interval.")

    subparsers.add_parser("scan-exports", help="Inspect pending match exports in SavedVariables.")

    upload_parser = subparsers.add_parser("upload-exports", help="Upload pending match exports to the configured destination.")
    upload_parser.add_argument("--force", action="store_true", help="Upload even when export upload is disabled.")

    auth_parser = subparsers.add_parser("auth", help="Save or clear a GitHub token for private repo sync.")
    auth_parser.add_argument("--token", type=str, default="", help="GitHub personal access token.")
    auth_parser.add_argument("--clear", action="store_true", help="Remove the saved GitHub token.")

    upload_auth_parser = subparsers.add_parser(
        "upload-auth",
        help="Save or clear the community match export upload URL and token.",
    )
    upload_auth_parser.add_argument("--url", type=str, default="", help="Public ingest API URL.")
    upload_auth_parser.add_argument("--token", type=str, default="", help="Bearer token for the ingest API.")
    upload_auth_parser.add_argument("--clear", action="store_true", help="Reset upload URL/token to local defaults.")

    subparsers.add_parser("tray", help="Run the background system tray app.")
    subparsers.add_parser("serve-ingest", help="Run the local export ingest HTTP server.")
    subparsers.add_parser("install-startup", help="Start PvPLedger Sync automatically at Windows login.")
    subparsers.add_parser("uninstall-startup", help="Remove PvPLedger Sync from Windows login startup.")

    return parser.parse_args()


def cmd_init(args: argparse.Namespace) -> int:
    """Initialize sync config."""

    config = load_config()
    addons_dir = args.addons_dir or config.wow_addons_dir or (guess_addons_dir() and str(guess_addons_dir()))
    if not addons_dir:
        print("Could not detect WoW AddOns directory. Pass --addons-dir explicitly.")
        return 1

    config.wow_addons_dir = addons_dir
    config = apply_config_defaults(config)
    path = save_config(config)
    print(f"Saved config to {path}")
    print(f"WoW AddOns: {config.wow_addons_dir}")
    print(f"AppHelper target: {config.app_data_path}")
    print(f"Upload URL: {config.upload_url}")
    print(f"Ingest directory: {default_ingest_dir()}")
    return 0


def cmd_status() -> int:
    """Print local and remote sync status."""

    config = load_config()
    print(f"Config: {default_config_path()}")
    print(f"WoW AddOns: {config.wow_addons_dir or '(not set)'}")
    print(f"Repo: {config.repo}@{config.branch}")
    print(f"GitHub token: {'configured' if config.resolved_github_token() else 'not set'}")
    print(f"GitHub match dump: {'enabled' if config.github_export_enabled else 'disabled'}")
    print(f"GitHub dump path: {config.github_export_path or 'Data/match-exports'}")
    print(f"Last manifest date: {config.last_manifest_generated_date or '(never)'}")
    print(f"Last AppData sync: {config.last_app_data_sync_at or '(never)'}")
    print(f"Export upload: {'enabled' if config.export_enabled else 'disabled'}")
    print(f"Export spool: {resolve_export_spool_dir(config)}")
    print(f"Upload URL: {config.upload_url or default_upload_url()}")
    print(f"Upload token: {'configured' if config.resolved_upload_token() else 'not set'}")
    print(f"Ingest server: {'enabled' if config.ingest_enabled else 'disabled'}")
    if config.ingest_enabled:
        print(f"Ingest bind: {config.ingest_host}:{config.ingest_port}")
        print(f"Ingest directory: {default_ingest_dir() if not config.ingest_dir else config.ingest_dir}")
        print(f"Ingest health: {'running' if ensure_ingest_server_running(config) else 'not running'}")
    print(f"Last export upload: {config.last_export_upload_at or '(never)'}")
    if config.last_export_upload_count:
        print(f"Last export batch: {config.last_export_upload_count} match(es), id={config.last_export_batch_id}")
    print(f"Run at login: {'enabled' if is_startup_installed() else 'disabled'}")

    try:
        manifest = fetch_manifest(
            repo=config.repo,
            branch=config.branch,
            token=config.resolved_github_token(),
        )
        print(f"Remote manifest date: {manifest.generated_date}")
        print(f"Remote brackets: {', '.join(sorted(manifest.brackets))}")
    except Exception as exc:  # noqa: BLE001 - CLI status should show network failures clearly
        print(f"Remote manifest: unavailable ({format_github_error(exc)})")
        if not config.resolved_github_token():
            print("Tip: private repos need a token. Run: run_sync.bat auth --token YOUR_TOKEN")
        if local_manifest_source().exists():
            print(f"Local fallback manifest: {local_manifest_source()}")
        else:
            print("Local fallback manifest: not found")

    if local_app_data_source().exists():
        print(f"Local fallback AppData: {local_app_data_source()}")

    export_scan = scan_exports(config.wow_addons_dir) if config.wow_addons_dir else None
    if export_scan:
        print(f"Export scan: {export_scan.note}")
        if export_scan.found:
            print(f"SavedVariables: {export_scan.path}")
            print(f"Pending matches: {export_scan.pending_matches}")
    return 0


def cmd_sync(force: bool = False, local_only: bool = False) -> int:
    """Run one AppData sync."""

    config = load_config()
    if not config.wow_addons_dir:
        print("Sync is not initialized. Run: python -m pvpledger_sync init")
        return 1

    result = sync_app_data(config, force=force, local_only=local_only)
    print(result.reason)
    if result.source:
        print(f"Source: {result.source}")
    if result.manifest_generated_date:
        print(f"Manifest date: {result.manifest_generated_date}")
    if result.app_data_path:
        print(f"AppData path: {result.app_data_path}")
    return 0 if result.updated or result.reason.startswith("Already up to date") else 1


def cmd_watch(args: argparse.Namespace) -> int:
    """Poll and sync forever."""

    config = load_config()
    interval_minutes = args.minutes or config.poll_minutes
    print(f"Watching every {interval_minutes} minute(s). Press Ctrl+C to stop.")
    while True:
        cmd_sync(force=False)
        time.sleep(max(interval_minutes, 1) * 60)


def cmd_scan_exports() -> int:
    """Scan pending exports."""

    config = load_config()
    if not config.wow_addons_dir:
        print("Sync is not initialized. Run: python -m pvpledger_sync init")
        return 1

    result = scan_exports(config.wow_addons_dir)
    print(result.note)
    if result.found:
        print(f"SavedVariables: {result.path}")
        print(f"Pending matches: {result.pending_matches}")
    return 0


def cmd_upload_exports(args: argparse.Namespace) -> int:
    """Upload pending match exports."""

    config = load_config()
    if not config.wow_addons_dir:
        print("Sync is not initialized. Run: python -m pvpledger_sync init")
        return 1

    result = upload_exports(config, force=args.force)
    print(result.reason)
    if result.uploaded:
        print(f"Batch ID: {result.batch_id}")
        print(f"Destination: {result.destination}")
        if result.github_batch_path:
            print(f"GitHub batch: {result.github_batch_path}")
        if result.github_dump_path:
            print(f"GitHub dump: {result.github_dump_path}")
        print(f"Spool file: {result.spool_path}")
        print(f"ExportAck: {result.export_ack_path}")
        return 0
    return 0 if result.reason.startswith("No pending") else 1


def cmd_auth(args: argparse.Namespace) -> int:
    """Save or clear the GitHub token used for private repository sync."""

    config = load_config()
    if args.clear:
        config.github_token = ""
        save_config(config)
        print("Cleared saved GitHub token.")
        return 0

    token = args.token.strip()
    if not token:
        print("Pass --token YOUR_GITHUB_TOKEN or use --clear.")
        print("Create a token at: https://github.com/settings/tokens")
        print("Required scope: read access for ladder sync; write access for match dump uploads.")
        print("Classic token: repo. Fine-grained: Contents read/write on this repository.")
        return 1

    config.github_token = token
    path = save_config(config)
    print(f"Saved GitHub token to {path}")
    print("Token stored locally in your AppData config. Do not share this file.")
    return 0


def cmd_upload_auth(args: argparse.Namespace) -> int:
    """Save or clear the public match export upload URL and token."""

    config = apply_config_defaults(load_config())
    if args.clear:
        config.upload_url = DEFAULT_UPLOAD_URL
        config.upload_token = ""
        path = save_config(config)
        print(f"Reset upload settings to local defaults in {path}")
        print(f"Upload URL: {config.upload_url}")
        return 0

    url = args.url.strip()
    token = args.token.strip()
    if not url and not token:
        print("Pass --url and --token, or use --clear.")
        print("See Server/cloudflare/README.md for deploy steps.")
        return 1

    if url:
        config.upload_url = url
    if token:
        config.upload_token = token

    path = save_config(config)
    print(f"Saved upload settings to {path}")
    print(f"Upload URL: {config.upload_url}")
    print(f"Upload token: {'configured' if config.resolved_upload_token() else 'not set'}")
    return 0


def cmd_tray() -> int:
    """Launch the system tray application."""

    from .tray_app import run_tray_app

    run_tray_app()
    return 0


def cmd_serve_ingest() -> int:
    """Run the local export ingest HTTP server."""

    config = apply_config_defaults(load_config())
    run_ingest_server_forever(config)
    return 0


def cmd_install_startup() -> int:
    """Install the tray app into the current user's Startup folder."""

    path = install_startup()
    print(f"Installed startup script: {path}")
    print("PvPLedger Sync will launch at login.")
    return 0


def cmd_uninstall_startup() -> int:
    """Remove the tray app from the Startup folder."""

    if uninstall_startup():
        print("Removed PvPLedger Sync from Windows startup.")
        return 0
    print("Startup script was not installed.")
    return 0


def main() -> int:
    """Dispatch CLI commands."""

    args = parse_args()
    if args.command == "init":
        return cmd_init(args)
    if args.command == "status":
        return cmd_status()
    if args.command == "sync":
        return cmd_sync(force=False)
    if args.command == "sync-now":
        return cmd_sync(force=True, local_only=args.local)
    if args.command == "watch":
        return cmd_watch(args)
    if args.command == "scan-exports":
        return cmd_scan_exports()
    if args.command == "upload-exports":
        return cmd_upload_exports(args)
    if args.command == "auth":
        return cmd_auth(args)
    if args.command == "upload-auth":
        return cmd_upload_auth(args)
    if args.command == "tray":
        return cmd_tray()
    if args.command == "serve-ingest":
        return cmd_serve_ingest()
    if args.command == "install-startup":
        return cmd_install_startup()
    if args.command == "uninstall-startup":
        return cmd_uninstall_startup()
    return 1


if __name__ == "__main__":
    sys.exit(main())
