#!/usr/bin/env python3
"""CLI entry point for PvPLedger Sync."""

from __future__ import annotations

import argparse
import sys
import time

from .config import SyncConfig, default_config_path, guess_addons_dir, load_config, save_config
from .downloader import sync_app_data
from .exporter import scan_exports
from .manifest import fetch_manifest


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

    watch_parser = subparsers.add_parser("watch", help="Poll GitHub and sync on an interval.")
    watch_parser.add_argument("--minutes", type=int, default=0, help="Override poll interval.")

    subparsers.add_parser("scan-exports", help="Inspect pending match exports in SavedVariables.")

    return parser.parse_args()


def cmd_init(args: argparse.Namespace) -> int:
    """Initialize sync config."""

    config = load_config()
    addons_dir = args.addons_dir or config.wow_addons_dir or (guess_addons_dir() and str(guess_addons_dir()))
    if not addons_dir:
        print("Could not detect WoW AddOns directory. Pass --addons-dir explicitly.")
        return 1

    config.wow_addons_dir = addons_dir
    path = save_config(config)
    print(f"Saved config to {path}")
    print(f"WoW AddOns: {config.wow_addons_dir}")
    print(f"AppHelper target: {config.app_data_path}")
    return 0


def cmd_status() -> int:
    """Print local and remote sync status."""

    config = load_config()
    print(f"Config: {default_config_path()}")
    print(f"WoW AddOns: {config.wow_addons_dir or '(not set)'}")
    print(f"Repo: {config.repo}@{config.branch}")
    print(f"Last manifest date: {config.last_manifest_generated_date or '(never)'}")
    print(f"Last AppData sync: {config.last_app_data_sync_at or '(never)'}")

    try:
        manifest = fetch_manifest(repo=config.repo, branch=config.branch)
        print(f"Remote manifest date: {manifest.generated_date}")
        print(f"Remote brackets: {', '.join(sorted(manifest.brackets))}")
    except Exception as exc:  # noqa: BLE001 - CLI status should show network failures clearly
        print(f"Remote manifest: unavailable ({exc})")

    export_scan = scan_exports(config.wow_addons_dir) if config.wow_addons_dir else None
    if export_scan:
        print(f"Export scan: {export_scan.note}")
        if export_scan.found:
            print(f"SavedVariables: {export_scan.path}")
            print(f"Pending matches: {export_scan.pending_matches}")
    return 0


def cmd_sync(force: bool = False) -> int:
    """Run one AppData sync."""

    config = load_config()
    if not config.wow_addons_dir:
        print("Sync is not initialized. Run: python -m pvpledger_sync init")
        return 1

    result = sync_app_data(config, force=force)
    print(result.reason)
    if result.manifest_generated_date:
        print(f"Manifest date: {result.manifest_generated_date}")
    if result.app_data_path:
        print(f"AppData path: {result.app_data_path}")
    return 0 if result.updated or result.reason == "Already up to date." else 1


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
        return cmd_sync(force=True)
    if args.command == "watch":
        return cmd_watch(args)
    if args.command == "scan-exports":
        return cmd_scan_exports()
    return 1


if __name__ == "__main__":
    sys.exit(main())
