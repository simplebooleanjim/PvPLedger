"""PyInstaller entry point for the PvPLedger Sync tray app."""

from pvpledger_sync.tray_app import run_tray_app


def main() -> None:
    """Launch the tray application."""

    run_tray_app()


if __name__ == "__main__":
    main()
