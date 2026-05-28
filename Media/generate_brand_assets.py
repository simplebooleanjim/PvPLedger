"""Generate WoW and Windows icon assets from Media/Icon.png."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_PNG = REPO_ROOT / "Media" / "Icon.png"
WOW_TGA = REPO_ROOT / "Media" / "Icon.tga"
APP_HELPER_TGA = REPO_ROOT / "PvPLedger-AppHelper" / "Media" / "Icon.tga"
SYNC_ICO = REPO_ROOT / "Sync" / "assets" / "PvPLedger.ico"
TRAY_PNG = REPO_ROOT / "Sync" / "assets" / "Icon.png"
WOW_SIZE = 256
ICO_SIZES = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def load_source_image() -> Image.Image:
    """Load and normalize the canonical brand icon."""

    if not SOURCE_PNG.exists():
        raise FileNotFoundError(f"Missing source icon: {SOURCE_PNG}")

    image = Image.open(SOURCE_PNG).convert("RGBA")
    return image.resize((WOW_SIZE, WOW_SIZE), Image.Resampling.LANCZOS)


def write_wow_texture(image: Image.Image, destination: Path) -> None:
    """Write a square TGA texture for WoW IconTexture metadata."""

    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="TGA")


def write_windows_icon(image: Image.Image, destination: Path) -> None:
    """Write a multi-size ICO file for Windows executables."""

    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="ICO", sizes=ICO_SIZES)


def write_tray_png(image: Image.Image, destination: Path) -> None:
    """Write a tray-friendly PNG bundled with the sync app."""

    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="PNG")


def main() -> int:
    """Generate all brand assets from Media/Icon.png."""

    image = load_source_image()
    write_wow_texture(image, WOW_TGA)
    write_wow_texture(image, APP_HELPER_TGA)
    write_windows_icon(image, SYNC_ICO)
    write_tray_png(image, TRAY_PNG)
    print(f"Wrote {WOW_TGA}")
    print(f"Wrote {APP_HELPER_TGA}")
    print(f"Wrote {SYNC_ICO}")
    print(f"Wrote {TRAY_PNG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
