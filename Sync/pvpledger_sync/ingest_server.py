"""Local HTTP ingest server for PvPLedger match export batches."""

from __future__ import annotations

import json
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import error, request

from .config import DEFAULT_INGEST_HOST, DEFAULT_INGEST_PORT, SyncConfig, default_config_path

_server_lock = threading.Lock()
_server_thread: threading.Thread | None = None
_httpd: ThreadingHTTPServer | None = None
_ingest_root: Path | None = None


def default_ingest_dir() -> Path:
    """Return the default directory for ingested export batches."""

    return default_config_path().parent / "exports" / "ingested"


def default_upload_url(host: str = DEFAULT_INGEST_HOST, port: int = DEFAULT_INGEST_PORT) -> str:
    """
    Build the default upload URL for the local ingest server.

    Parameters
    ----------
    host:
        Bind host for the ingest server.
    port:
        Bind port for the ingest server.

    Returns
    -------
    str
        Full HTTP URL for POSTing export batches.
    """

    return f"http://{host}:{port}/api/v1/exports"


def resolve_ingest_dir(config: SyncConfig) -> Path:
    """
    Resolve the directory where ingested batches are stored.

    Parameters
    ----------
    config:
        Active sync configuration.

    Returns
    -------
    Path
        Root directory for ingested export batches.
    """

    if config.ingest_dir:
        return Path(config.ingest_dir)
    return default_ingest_dir()


def write_ingested_batch(*, ingest_dir: Path, payload: dict[str, Any]) -> Path:
    """
    Persist one ingested export batch to disk.

    Parameters
    ----------
    ingest_dir:
        Root directory for ingested batches.
    payload:
        Export batch payload received from Sync.

    Returns
    -------
    Path
        Path to the written JSON file.
    """

    batch_id = str(payload.get("batchId", "unknown")).strip() or "unknown"
    day_dir = ingest_dir / datetime.now(timezone.utc).strftime("%Y-%m-%d")
    day_dir.mkdir(parents=True, exist_ok=True)
    destination = day_dir / f"batch-{batch_id}.json"
    destination.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return destination


def ingest_health_url(host: str, port: int) -> str:
    """Return the health-check URL for one ingest server instance."""

    return f"http://{host}:{port}/api/v1/health"


def is_ingest_server_running(*, host: str, port: int) -> bool:
    """
    Return True when the ingest server responds to a health check.

    Parameters
    ----------
    host:
        Server host to probe.
    port:
        Server port to probe.

    Returns
    -------
    bool
        True when the health endpoint returns HTTP 200.
    """

    health_url = ingest_health_url(host, port)
    http_request = request.Request(health_url, method="GET")
    try:
        with request.urlopen(http_request, timeout=2) as response:
            return response.status == 200
    except (error.URLError, TimeoutError, ValueError):
        return False


class _IngestRequestHandler(BaseHTTPRequestHandler):
    """Handle export batch uploads and health checks."""

    server_version = "PvPLedgerIngest/0.7"

    def log_message(self, format: str, *args: object) -> None:
        """Suppress default stderr logging from the HTTP server."""

        return

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        """Write one JSON HTTP response."""

        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        """Serve health checks."""

        if self.path.rstrip("/") == "/api/v1/health":
            self._send_json(200, {"status": "ok", "service": "pvpledger-ingest"})
            return
        self._send_json(404, {"error": "Not found."})

    def do_POST(self) -> None:
        """Accept one export batch payload."""

        if self.path.rstrip("/") != "/api/v1/exports":
            self._send_json(404, {"error": "Not found."})
            return

        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            self._send_json(400, {"error": "Missing request body."})
            return

        raw_body = self.rfile.read(content_length)
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json(400, {"error": "Invalid JSON payload."})
            return

        if not isinstance(payload, dict):
            self._send_json(400, {"error": "Payload must be a JSON object."})
            return

        batch_id = str(payload.get("batchId", "")).strip()
        if not batch_id:
            self._send_json(400, {"error": "Missing batchId."})
            return

        ingest_root = _ingest_root or default_ingest_dir()
        destination = write_ingested_batch(ingest_dir=ingest_root, payload=payload)
        self._send_json(
            200,
            {
                "status": "accepted",
                "batchId": batch_id,
                "path": str(destination),
                "matchCount": payload.get("matchCount", 0),
            },
        )


def start_ingest_server(
    *,
    host: str = DEFAULT_INGEST_HOST,
    port: int = DEFAULT_INGEST_PORT,
    ingest_dir: Path | None = None,
) -> ThreadingHTTPServer:
    """
    Start the ingest HTTP server on a background thread.

    Parameters
    ----------
    host:
        Bind host, typically `127.0.0.1`.
    port:
        Bind port, typically `8765`.
    ingest_dir:
        Optional override for the ingested batch directory.

    Returns
    -------
    ThreadingHTTPServer
        Running HTTP server instance.
    """

    global _ingest_root, _httpd, _server_thread

    with _server_lock:
        if _httpd is not None:
            return _httpd

        _ingest_root = ingest_dir or default_ingest_dir()
        _ingest_root.mkdir(parents=True, exist_ok=True)

        httpd = ThreadingHTTPServer((host, port), _IngestRequestHandler)
        thread = threading.Thread(target=httpd.serve_forever, name="pvpledger-ingest", daemon=True)
        thread.start()

        _httpd = httpd
        _server_thread = thread
        return httpd


def stop_ingest_server() -> None:
    """Shut down the background ingest server, if running."""

    global _httpd, _server_thread

    with _server_lock:
        if _httpd is None:
            return
        _httpd.shutdown()
        _httpd.server_close()
        _httpd = None
        _server_thread = None


def ensure_ingest_server_running(config: SyncConfig) -> bool:
    """
    Ensure the local ingest server is running when enabled in config.

    Parameters
    ----------
    config:
        Active sync configuration.

    Returns
    -------
    bool
        True when the ingest server is available.
    """

    if not config.ingest_enabled:
        return False

    host = config.ingest_host or DEFAULT_INGEST_HOST
    port = config.ingest_port or DEFAULT_INGEST_PORT
    if is_ingest_server_running(host=host, port=port):
        return True

    try:
        start_ingest_server(host=host, port=port, ingest_dir=resolve_ingest_dir(config))
    except OSError:
        return is_ingest_server_running(host=host, port=port)

    return is_ingest_server_running(host=host, port=port)


def run_ingest_server_forever(config: SyncConfig) -> None:
    """
    Run the ingest server on the foreground thread until interrupted.

    Parameters
    ----------
    config:
        Active sync configuration used to resolve bind settings.
    """

    host = config.ingest_host or DEFAULT_INGEST_HOST
    port = config.ingest_port or DEFAULT_INGEST_PORT
    ingest_dir = resolve_ingest_dir(config)
    ingest_dir.mkdir(parents=True, exist_ok=True)

    print(f"PvPLedger ingest server listening on http://{host}:{port}")
    print(f"Ingest directory: {ingest_dir}")
    print("Press Ctrl+C to stop.")

    httpd = ThreadingHTTPServer((host, port), _IngestRequestHandler)
    global _ingest_root
    _ingest_root = ingest_dir
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping ingest server.")
    finally:
        httpd.server_close()
