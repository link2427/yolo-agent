#!/usr/bin/env python3
"""Tiny GPU exporter for the lab monitor. Run it on SEC09 (the vLLM host):

    python3 gpu-exporter.py --port 9400

then set GPU_URL=http://192.168.1.101:9400 in the lab .env. It serves the
output of nvidia-smi as JSON on any path. Standard library only; no install.
"""

import argparse
import json
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIELDS = ["index", "name", "utilization.gpu", "memory.used", "memory.total", "temperature.gpu", "power.draw"]
KEYS = ["index", "name", "utilization", "memory_used", "memory_total", "temperature", "power"]


def num(v):
    try:
        return float(v)
    except ValueError:
        return None


def read():
    out = subprocess.run(["nvidia-smi", f"--query-gpu={','.join(FIELDS)}", "--format=csv,noheader,nounits"],
                         capture_output=True, text=True, timeout=10, check=True).stdout
    gpus = []
    for line in out.strip().splitlines():
        vals = [v.strip() for v in line.split(",")]
        g = dict(zip(KEYS, vals))
        for k in KEYS[2:]:
            g[k] = num(g.get(k, ""))
        gpus.append(g)
    return {"gpus": gpus}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):  # noqa: N802
        try:
            body, code = json.dumps(read()).encode(), 200
        except Exception as exc:  # noqa: BLE001
            body, code = json.dumps({"error": str(exc)}).encode(), 500
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9400)
    ap.add_argument("--host", default="0.0.0.0")
    a = ap.parse_args()
    ThreadingHTTPServer((a.host, a.port), H).serve_forever()
