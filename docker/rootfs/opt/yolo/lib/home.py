"""yolo home: the start page (service `home`, container port 8000).

Serves /opt/yolo/home/index.html and a small JSON status API. Standard library
only; no external assets, because the lab has no internet.
"""

import argparse
import json
import os
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path("/opt/yolo/home")
HOME = Path(os.environ.get("HOME", "/home/agent"))

_cache = {"t": 0.0, "data": None}
_lock = threading.Lock()


def _probe_models():
    base = os.environ.get("VLLM_BASE_URL", "").rstrip("/")
    if not base:
        return {"ok": False, "error": "no endpoint configured", "models": []}
    req = urllib.request.Request(
        base + "/models",
        headers={"Authorization": "Bearer " + os.environ.get("VLLM_API_KEY", "local")},
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.load(resp)
        ms = round((time.monotonic() - started) * 1000)
        return {"ok": True, "latency_ms": ms, "models": [m.get("id") for m in data.get("data", [])]}
    except Exception as exc:  # noqa: BLE001 - any failure means "down"
        return {"ok": False, "error": str(exc)[:200], "models": []}


def _read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def status():
    with _lock:
        if _cache["data"] is not None and time.monotonic() - _cache["t"] < 10:
            return _cache["data"]
    probe = _probe_models()
    state = _read_json(HOME / ".yolo" / "state.json")
    ports = {k: os.environ.get(f"YOLO_PORT_{k.upper()}", d)
             for k, d in (("code", "8080"), ("chat", "4096"), ("term", "7681"), ("files", "8081"))}
    data = {
        "version": os.environ.get("YOLO_VERSION", "dev"),
        "tier": os.environ.get("YOLO_TIER", "?"),
        "person": os.environ.get("YOLO_PERSON") or os.environ.get("COMPOSE_PROJECT_NAME") or "",
        "endpoint": os.environ.get("VLLM_BASE_URL", ""),
        "model": state.get("model") or os.environ.get("VLLM_MODEL") or "",
        "server": probe,
        "gitea": os.environ.get("GITEA_HOST", ""),
        "git_ready": bool(state.get("git_ready")),
        "fleet": state.get("fleet", {}),
        "skills": state.get("skills", []),
        "agents": state.get("agents", []),
        "ports": ports,
    }
    with _lock:
        _cache.update(t=time.monotonic(), data=data)
    return data


class Handler(BaseHTTPRequestHandler):
    server_version = "yolo-home"

    def log_message(self, *args):  # quiet
        pass

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/api/status":
            self._send(200, json.dumps(status()).encode(), "application/json")
            return
        if path in ("/", "/index.html"):
            path = "/index.html"
        target = (ROOT / path.lstrip("/")).resolve()
        if not str(target).startswith(str(ROOT)) or not target.is_file():
            self._send(404, b"not found", "text/plain")
            return
        ctype = {".html": "text/html; charset=utf-8", ".svg": "image/svg+xml",
                 ".css": "text/css", ".js": "text/javascript"}.get(target.suffix, "application/octet-stream")
        self._send(200, target.read_bytes(), ctype)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()
    ThreadingHTTPServer(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
