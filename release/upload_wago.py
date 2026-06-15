#!/usr/bin/env python3
"""Upload built addon zip packages to Wago Addons via API."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = Path(__file__).resolve().parent / "wago-projects.json"
EXAMPLE_CONFIG = Path(__file__).resolve().parent / "wago-projects.example.json"
WAGO_API_BASE = "https://addons.wago.io/api/projects"


def load_config(path: Path) -> dict:
    """
    Load the Wago project mapping file.

    Parameters
    ----------
    path:
        Path to ``wago-projects.json``.

    Returns
    -------
    dict
        Parsed configuration object.
    """

    if not path.exists():
        raise FileNotFoundError(
            f"Missing {path}. Copy {EXAMPLE_CONFIG.name} to {path.name} and fill in Wago project IDs."
        )

    return json.loads(path.read_text(encoding="utf-8"))


def build_metadata(*, label: str, config: dict, changelog: str) -> dict:
    """
    Build the Wago version metadata payload.

    Parameters
    ----------
    label:
        Release label (usually the git tag).
    config:
        Parsed Wago project configuration.
    changelog:
        Markdown changelog body.

    Returns
    -------
    dict
        Metadata object accepted by the Wago API.
    """

    metadata = {
        "label": label,
        "stability": config.get("stability", "stable"),
        "changelog": changelog,
        "supported_retail_patch": config.get("supported_retail_patch", "12.0.0"),
    }
    return metadata


def upload_project_version(
    *,
    project_id: str,
    zip_path: Path,
    metadata: dict,
    api_token: str,
) -> None:
    """
    Upload one zip file to a Wago project.

    Parameters
    ----------
    project_id:
        Wago project ID from the developer dashboard.
    zip_path:
        Built addon zip path.
    metadata:
        Version metadata payload.
    api_token:
        Wago API bearer token.

    Raises
    ------
    urllib.error.HTTPError
        When the Wago API rejects the upload.
    """

    boundary = "----PvPLedgerWagoBoundary7d4f2c9a"
    metadata_json = json.dumps(metadata, ensure_ascii=False)
    zip_bytes = zip_path.read_bytes()

    body = bytearray()
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(b'Content-Disposition: form-data; name="metadata"\r\n\r\n')
    body.extend(metadata_json.encode("utf-8"))
    body.extend(b"\r\n")
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(
        f'Content-Disposition: form-data; name="file"; filename="{zip_path.name}"\r\n'.encode()
    )
    body.extend(b"Content-Type: application/zip\r\n\r\n")
    body.extend(zip_bytes)
    body.extend(f"\r\n--{boundary}--\r\n".encode())

    request = urllib.request.Request(
        f"{WAGO_API_BASE}/{project_id}/version",
        data=bytes(body),
        method="POST",
        headers={
            "Authorization": f"Bearer {api_token}",
            "Accept": "application/json",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )

    with urllib.request.urlopen(request, timeout=120) as response:
        print(f"uploaded {zip_path.name} -> {project_id} ({response.status})")


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""

    parser = argparse.ArgumentParser(description="Upload release zips to Wago Addons.")
    parser.add_argument(
        "--tag",
        required=True,
        help="Release label, usually the git tag (for example v0.8.0).",
    )
    parser.add_argument(
        "--dist-dir",
        type=Path,
        default=REPO_ROOT / "release" / "dist",
        help="Directory containing built zip files.",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help="Path to wago-projects.json.",
    )
    parser.add_argument(
        "--changelog-file",
        type=Path,
        default=REPO_ROOT / "release" / "CHANGELOG.md",
        help="Changelog markdown used for all Wago uploads.",
    )
    return parser.parse_args()


def read_changelog(path: Path) -> str:
    """
    Read changelog text for Wago metadata.

    Parameters
    ----------
    path:
        Changelog markdown path.

    Returns
    -------
    str
        Changelog body.
    """

    if not path.exists():
        return "See GitHub release notes."

    return path.read_text(encoding="utf-8")


def main() -> int:
    """Upload configured addon packages to Wago."""

    args = parse_args()
    api_token = os.environ.get("WAGO_API_TOKEN", "").strip()
    if not api_token:
        print("WAGO_API_TOKEN is not set. Skipping Wago upload.")
        return 0

    try:
        config = load_config(args.config)
    except FileNotFoundError as exc:
        print(exc)
        return 1

    changelog = read_changelog(args.changelog_file)
    metadata = build_metadata(label=args.tag, config=config, changelog=changelog)
    projects: dict = config.get("projects", {})

    uploaded = 0
    for project_name, project_config in projects.items():
        project_id = str(project_config.get("wago_id", "")).strip()
        if not project_id or project_id.startswith("REPLACE_WITH"):
            print(f"skip {project_name}: wago_id not configured")
            continue

        zip_name = str(project_config.get("zip", f"{project_name}.zip"))
        zip_path = args.dist_dir / zip_name
        if not zip_path.exists():
            print(f"skip {project_name}: missing {zip_path}")
            continue

        try:
            upload_project_version(
                project_id=project_id,
                zip_path=zip_path,
                metadata=metadata,
                api_token=api_token,
            )
            uploaded += 1
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            print(f"failed {project_name}: HTTP {exc.code} {error_body[:300]}")
            return 1

    if uploaded == 0:
        print("No Wago projects were uploaded. Fill release/wago-projects.json first.")
        return 1

    print(f"Uploaded {uploaded} package(s) to Wago.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
