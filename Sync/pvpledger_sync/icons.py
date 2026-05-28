"""Tray icon assets for PvPLedger Sync."""

from __future__ import annotations

from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from .paths import bundle_dir


def brand_icon_path() -> Path:
    """Return the bundled PvPLedger brand icon used by the tray app."""

    bundled = bundle_dir() / "assets" / "Icon.png"
    if bundled.exists():
        return bundled

    sync_root = Path(__file__).resolve().parent.parent
    return sync_root / "assets" / "Icon.png"


def build_tray_icon(size: int = 64) -> Image.Image:
    """Build the PvPLedger tray icon from the shared brand asset."""

    source = brand_icon_path()
    if source.exists():
        image = Image.open(source).convert("RGBA")
        return image.resize((size, size), Image.Resampling.LANCZOS)

    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    margin = max(4, size // 10)
    draw.ellipse((margin, margin, size - margin, size - margin), fill=(102, 204, 255, 255))

    try:
        font = ImageFont.truetype("arial.ttf", size=max(18, size // 2))
    except OSError:
        font = ImageFont.load_default()

    text = "P"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    position = ((size - text_width) / 2, (size - text_height) / 2 - 2)
    draw.text(position, text, fill=(255, 255, 255, 255), font=font)
    return image


def icon_to_bytes(size: int = 64) -> bytes:
    """Return PNG bytes for the tray icon."""

    buffer = BytesIO()
    build_tray_icon(size=size).save(buffer, format="PNG")
    return buffer.getvalue()
