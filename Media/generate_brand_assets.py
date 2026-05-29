"""Generate WoW and Windows icon assets from Media/Icon.png."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_PNG = REPO_ROOT / "Media" / "Icon.png"
WOW_TGA = REPO_ROOT / "Media" / "Icon.tga"
UI_LOGO_TGA = REPO_ROOT / "Media" / "PvPLedgerLogo.tga"
APP_HELPER_TGA = REPO_ROOT / "PvPLedger-AppHelper" / "Media" / "Icon.tga"
SYNC_ICO = REPO_ROOT / "Sync" / "assets" / "PvPLedger.ico"
TRAY_PNG = REPO_ROOT / "Sync" / "assets" / "Icon.png"
WOW_SIZE = 256
ICO_SIZES = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

# In-game UI logo: pixels at or below this per-channel brightness are treated as
# background and made transparent so the shield reads cleanly over dark frames.
UI_LOGO_BG_THRESHOLD = 26


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


def write_ui_logo(image: Image.Image, destination: Path) -> None:
    """Write the in-game UI logo as a transparent, top-origin 32-bit TGA.

    The dark background is keyed to transparency so the shield reads over the
    addon's dark window frames, and the TGA is written top-origin (descriptor
    bit 0x20) so WoW renders it upright rather than upside down.

    :param image: Square RGBA brand image.
    :param destination: Output TGA path (created/overwritten).
    """

    logo = image.copy()
    pixels = logo.load()
    width, height = logo.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if max(r, g, b) <= UI_LOGO_BG_THRESHOLD:
                pixels[x, y] = (r, g, b, 0)

    rgba = logo.tobytes()  # Row-major, top-to-bottom, RGBA.
    bgra = bytearray(len(rgba))
    for i in range(0, len(rgba), 4):
        r, g, b, a = rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]
        bgra[i], bgra[i + 1], bgra[i + 2], bgra[i + 3] = b, g, r, a

    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,        # id length
        0,        # color map type
        2,        # uncompressed true-color
        0, 0, 0,  # color map spec
        0,        # x origin
        0,        # y origin
        width,
        height,
        32,       # bits per pixel
        0x28,     # descriptor: top-origin (0x20) + 8 alpha bits (0x08)
    )

    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as handle:
        handle.write(header)
        handle.write(bytes(bgra))


def main() -> int:
    """Generate all brand assets from Media/Icon.png."""

    image = load_source_image()
    write_wow_texture(image, WOW_TGA)
    write_wow_texture(image, APP_HELPER_TGA)
    write_ui_logo(image, UI_LOGO_TGA)
    write_windows_icon(image, SYNC_ICO)
    write_tray_png(image, TRAY_PNG)
    print(f"Wrote {WOW_TGA}")
    print(f"Wrote {APP_HELPER_TGA}")
    print(f"Wrote {UI_LOGO_TGA}")
    print(f"Wrote {SYNC_ICO}")
    print(f"Wrote {TRAY_PNG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
