"""yolo lab gateway and monitor.

One process, standard library only:

  * /v1/*        transparent proxy to the vLLM server (OpenAI and Anthropic
                 APIs, streaming included), with model aliases
  * request log  every proxied request: person, agent, model, tokens, time to
                 first token, duration, status
  * metrics      vLLM /metrics scraped every few seconds (throughput, queue,
                 KV cache, latency histograms), plus an optional GPU exporter
  * /api/*       JSON for the dashboard
  * /            the dashboard (lab/ui/index.html)

Storage is one SQLite file. Raw samples are kept for RAW_DAYS, one-minute
rollups for ROLLUP_DAYS, requests for REQUEST_DAYS.

Configuration (environment):
  UPSTREAM_URL      vLLM base, default http://192.168.1.101:8000
  UPSTREAM_API_KEY  key sent upstream (default: pass the client's through)
  LAB_DATA          data folder, default /data
  LAB_PORT          default 4000
  ALIASES_FILE      JSON {"alias": "real-model-id"}; default $LAB_DATA/aliases.json
  GPU_URL           optional GPU exporter URL (tools/gpu-exporter.py on SEC09)
  SCRAPE_SECONDS    default 5
"""

from __future__ import annotations

import json
import math
import os
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.client import HTTPConnection, HTTPSConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

UPSTREAM = os.environ.get("UPSTREAM_URL", "http://192.168.1.101:8000").rstrip("/")
if UPSTREAM.endswith("/v1"):
    UPSTREAM = UPSTREAM[:-3]
UPSTREAM_KEY = os.environ.get("UPSTREAM_API_KEY", "")
DATA = Path(os.environ.get("LAB_DATA", "/data"))
PORT = int(os.environ.get("LAB_PORT", "4000"))
ALIASES_FILE = Path(os.environ.get("ALIASES_FILE", str(DATA / "aliases.json")))
GPU_URL = os.environ.get("GPU_URL", "").strip()
SCRAPE = float(os.environ.get("SCRAPE_SECONDS", "5"))
UI = Path(__file__).with_name("ui")
RAW_DAYS, ROLLUP_DAYS, REQUEST_DAYS = 3, 180, 180

DATA.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA / "yolo-lab.db"
_local = threading.local()


def db() -> sqlite3.Connection:
    conn = getattr(_local, "conn", None)
    if conn is None:
        conn = sqlite3.connect(DB_PATH, timeout=30, isolation_level=None)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.row_factory = sqlite3.Row
        _local.conn = conn
    return conn


def init_db() -> None:
    db().executescript(
        """
        CREATE TABLE IF NOT EXISTS requests (
          id INTEGER PRIMARY KEY, ts REAL, person TEXT, agent TEXT, client TEXT,
          api TEXT, path TEXT, model TEXT, alias TEXT, stream INTEGER, status INTEGER,
          prompt_tokens INTEGER, completion_tokens INTEGER, ttft_ms REAL,
          duration_ms REAL, error TEXT, preview TEXT);
        CREATE INDEX IF NOT EXISTS requests_ts ON requests(ts);
        CREATE TABLE IF NOT EXISTS samples (
          ts REAL PRIMARY KEY, running REAL, waiting REAL, kv REAL,
          prompt_tps REAL, gen_tps REAL, ttft_p50 REAL, ttft_p95 REAL,
          e2e_p50 REAL, itl_p50 REAL, preempt REAL, up INTEGER, model TEXT,
          gpu TEXT);
        CREATE TABLE IF NOT EXISTS rollup (
          minute INTEGER PRIMARY KEY, running REAL, waiting REAL, kv REAL,
          prompt_tps REAL, gen_tps REAL, ttft_p50 REAL, ttft_p95 REAL,
          e2e_p50 REAL, itl_p50 REAL, preempt REAL, up REAL, model TEXT);
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY, ts REAL, kind TEXT, detail TEXT);
        """
    )


# --------------------------------------------------------------------------
# aliases
# --------------------------------------------------------------------------
_alias_cache = {"mtime": None, "map": {}}


def aliases() -> dict:
    try:
        mtime = ALIASES_FILE.stat().st_mtime
    except OSError:
        return {}
    if mtime != _alias_cache["mtime"]:
        try:
            data = json.loads(ALIASES_FILE.read_text())
            _alias_cache.update(mtime=mtime, map={str(k): str(v) for k, v in data.items()})
        except (OSError, ValueError):
            pass
    return _alias_cache["map"]


# --------------------------------------------------------------------------
# metrics scraper
# --------------------------------------------------------------------------
_METRIC = re.compile(r'^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+([-+0-9.eEInfNa]+)')


def parse_prom(text: str) -> dict:
    out: dict[str, list[tuple[dict, float]]] = {}
    for line in text.splitlines():
        if not line or line[0] == "#":
            continue
        m = _METRIC.match(line)
        if not m:
            continue
        labels = {}
        if m.group(2):
            for part in re.finditer(r'(\w+)="((?:[^"\\]|\\.)*)"', m.group(2)):
                labels[part.group(1)] = part.group(2)
        try:
            val = float(m.group(3))
        except ValueError:
            continue
        out.setdefault(m.group(1), []).append((labels, val))
    return out


def _sum(metrics: dict, *names: str) -> float | None:
    for name in names:
        if name in metrics:
            return sum(v for _, v in metrics[name])
    return None


def _hist(metrics: dict, base: str) -> list[tuple[float, float]] | None:
    """Cumulative buckets [(le, count)] summed over label sets."""
    for prefix in (base, base.replace("vllm:", "vllm_")):
        rows = metrics.get(prefix + "_bucket")
        if rows:
            acc: dict[float, float] = {}
            for labels, v in rows:
                le = labels.get("le", "+Inf")
                key = math.inf if le in ("+Inf", "Inf") else float(le)
                acc[key] = acc.get(key, 0.0) + v
            return sorted(acc.items())
    return None


def _quantile(prev, cur, q: float) -> float | None:
    """Quantile of the observations between two cumulative histogram scrapes."""
    if not cur:
        return None
    pmap = dict(prev or [])
    delta = [(le, c - pmap.get(le, 0.0)) for le, c in cur]
    total = delta[-1][1] if delta else 0
    if total <= 0:
        return None
    target = q * total
    lo_le, lo_c = 0.0, 0.0
    for le, c in delta:
        if c >= target:
            if math.isinf(le):
                return lo_le
            span = c - lo_c
            frac = (target - lo_c) / span if span > 0 else 1.0
            return lo_le + (le - lo_le) * frac
        lo_le, lo_c = le, c
    return lo_le


class Scraper(threading.Thread):
    daemon = True

    def __init__(self):
        super().__init__(name="scraper")
        self.prev = None
        self.prev_t = None
        self.last_model = None
        self.last_up = None
        self.latest: dict = {}

    def fetch(self, url: str, timeout: float = 4.0) -> str:
        req = urllib.request.Request(url)
        if UPSTREAM_KEY:
            req.add_header("Authorization", "Bearer " + UPSTREAM_KEY)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", "replace")

    def event(self, kind: str, detail: str) -> None:
        db().execute("INSERT INTO events(ts, kind, detail) VALUES (?,?,?)", (time.time(), kind, detail))

    def once(self) -> None:
        now = time.time()
        row = {"ts": now, "up": 0, "model": None}
        try:
            metrics = parse_prom(self.fetch(UPSTREAM + "/metrics"))
            row["up"] = 1
        except Exception:  # noqa: BLE001
            metrics = None
        try:
            models = json.loads(self.fetch(UPSTREAM + "/v1/models"))
            ids = [m.get("id") for m in models.get("data", [])]
            row["model"] = ",".join(i for i in ids if i)
        except Exception:  # noqa: BLE001
            pass
        if metrics is not None:
            cur = {
                "prompt": _sum(metrics, "vllm:prompt_tokens_total", "vllm:prompt_tokens"),
                "gen": _sum(metrics, "vllm:generation_tokens_total", "vllm:generation_tokens"),
                "preempt": _sum(metrics, "vllm:num_preemptions_total", "vllm:num_preemptions"),
                "ttft": _hist(metrics, "vllm:time_to_first_token_seconds"),
                "e2e": _hist(metrics, "vllm:e2e_request_latency_seconds"),
                "itl": _hist(metrics, "vllm:inter_token_latency_seconds")
                or _hist(metrics, "vllm:time_per_output_token_seconds"),
            }
            row["running"] = _sum(metrics, "vllm:num_requests_running")
            row["waiting"] = _sum(metrics, "vllm:num_requests_waiting")
            kv = _sum(metrics, "vllm:kv_cache_usage_perc", "vllm:gpu_cache_usage_perc")
            row["kv"] = kv
            if self.prev and self.prev_t:
                dt = max(now - self.prev_t, 1e-6)
                for key, col in (("prompt", "prompt_tps"), ("gen", "gen_tps"), ("preempt", "preempt")):
                    a, b = self.prev.get(key), cur.get(key)
                    row[col] = max((b - a) / dt, 0.0) if a is not None and b is not None and b >= a else None
                for key, col, q in (("ttft", "ttft_p50", .5), ("ttft", "ttft_p95", .95),
                                    ("e2e", "e2e_p50", .5), ("itl", "itl_p50", .5)):
                    row[col] = _quantile(self.prev.get(key), cur.get(key), q)
            self.prev, self.prev_t = cur, now
        else:
            self.prev = None
        if GPU_URL:
            try:
                row["gpu"] = json.dumps(json.loads(self.fetch(GPU_URL, 3)))
            except Exception:  # noqa: BLE001
                row["gpu"] = None
        # events: up/down transitions and model changes
        if self.last_up is not None and row["up"] != self.last_up:
            self.event("up" if row["up"] else "down", "vLLM " + ("reachable" if row["up"] else "unreachable"))
        if row["model"] and self.last_model is not None and row["model"] != self.last_model:
            self.event("model", f"{self.last_model} → {row['model']}")
        self.last_up = row["up"]
        if row["model"]:
            self.last_model = row["model"]
        cols = ["ts", "running", "waiting", "kv", "prompt_tps", "gen_tps", "ttft_p50", "ttft_p95",
                "e2e_p50", "itl_p50", "preempt", "up", "model", "gpu"]
        db().execute(f"INSERT OR REPLACE INTO samples({','.join(cols)}) VALUES ({','.join('?' * len(cols))})",
                     [row.get(c) for c in cols])
        self.latest = row

    def rollup(self) -> None:
        c = db()
        cutoff = int(time.time() // 60) - 1
        c.execute(
            """INSERT OR REPLACE INTO rollup
               SELECT CAST(ts/60 AS INTEGER) m, avg(running), avg(waiting), avg(kv), avg(prompt_tps),
                      avg(gen_tps), avg(ttft_p50), max(ttft_p95), avg(e2e_p50), avg(itl_p50),
                      avg(preempt), avg(up), max(model)
               FROM samples WHERE ts >= ? AND CAST(ts/60 AS INTEGER) <= ? GROUP BY m""",
            ((cutoff - 15) * 60, cutoff))
        now = time.time()
        c.execute("DELETE FROM samples WHERE ts < ?", (now - RAW_DAYS * 86400,))
        c.execute("DELETE FROM rollup WHERE minute < ?", ((now - ROLLUP_DAYS * 86400) // 60,))
        c.execute("DELETE FROM requests WHERE ts < ?", (now - REQUEST_DAYS * 86400,))

    def run(self) -> None:
        last_roll = 0.0
        while True:
            started = time.time()
            try:
                self.once()
                if started - last_roll > 60:
                    self.rollup()
                    last_roll = started
            except Exception as exc:  # noqa: BLE001
                print("scrape error:", exc, flush=True)
            time.sleep(max(SCRAPE - (time.time() - started), 0.5))


SCRAPER = Scraper()


# --------------------------------------------------------------------------
# proxy
# --------------------------------------------------------------------------
HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te",
       "trailers", "transfer-encoding", "upgrade", "host", "content-length", "accept-encoding"}


def _person_agent(headers) -> tuple[str, str]:
    auth = headers.get("Authorization", "") or ""
    key = auth.split(" ", 1)[1].strip() if " " in auth else headers.get("x-api-key", "")
    person = headers.get("X-Yolo-Person") or ""
    if not person and key.startswith("yolo-"):
        person = key[5:]
    ua = (headers.get("User-Agent") or "").lower()
    agent = headers.get("X-Yolo-Agent") or ""
    if not agent:
        for needle, name in (("claude-cli", "claude"), ("claude-code", "claude"), ("opencode", "opencode"),
                             ("qwen", "qwen"), ("crush", "crush"), ("goose", "goose"), ("codex", "codex"),
                             ("pi-coding", "pi"), ("pi/", "pi"), ("cline", "cline"), ("kilo", "kilo"),
                             ("yolo-bot", "bot"), ("python", "script"), ("node", "node"), ("curl", "curl")):
            if needle in ua:
                agent = name
                break
    return person or "unknown", agent or (ua.split("/")[0][:24] or "unknown")


class Usage:
    """Picks token counts and first-token time out of streamed SSE or JSON."""

    def __init__(self):
        self.prompt = None
        self.completion = None
        self.first = None
        self.buf = b""
        self.preview = ""

    def _take(self, obj: dict) -> None:
        u = obj.get("usage") or (obj.get("message") or {}).get("usage")
        if isinstance(u, dict):
            p = u.get("prompt_tokens", u.get("input_tokens"))
            c = u.get("completion_tokens", u.get("output_tokens"))
            if p is not None:
                self.prompt = p
            if c is not None:
                self.completion = c
        if len(self.preview) < 160:
            try:
                ch = (obj.get("choices") or [{}])[0]
                piece = (ch.get("delta") or {}).get("content") or (ch.get("message") or {}).get("content") or ""
                if not piece and obj.get("type") == "content_block_delta":
                    piece = (obj.get("delta") or {}).get("text") or ""
                if isinstance(piece, str):
                    self.preview += piece
            except (AttributeError, IndexError, TypeError):
                pass

    def feed_sse(self, chunk: bytes) -> None:
        if self.first is None and chunk.strip():
            self.first = time.monotonic()
        self.buf += chunk
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            line = line.strip()
            if line.startswith(b"data:"):
                payload = line[5:].strip()
                if payload and payload != b"[DONE]":
                    try:
                        self._take(json.loads(payload))
                    except ValueError:
                        pass

    def feed_json(self, body: bytes) -> None:
        try:
            self._take(json.loads(body))
        except ValueError:
            pass


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "yolo-lab"

    def log_message(self, *args):
        pass

    # ---------------- helpers
    def _json(self, code: int, obj) -> None:
        body = json.dumps(obj, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _static(self, path: str) -> None:
        name = "index.html" if path in ("/", "") else path.lstrip("/")
        target = (UI / name).resolve()
        if not str(target).startswith(str(UI.resolve())) or not target.is_file():
            self._json(404, {"error": "not found"})
            return
        body = target.read_bytes()
        ctype = {".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css",
                 ".svg": "image/svg+xml"}.get(target.suffix, "application/octet-stream")
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ---------------- routing
    def do_GET(self):  # noqa: N802
        path, _, query = self.path.partition("?")
        if path.startswith("/v1/") or path in ("/metrics", "/health", "/version"):
            return self.proxy()
        if path.startswith("/api/"):
            return self.api(path, urllib.parse.parse_qs(query))
        return self._static(path)

    def do_POST(self):  # noqa: N802
        if self.path.startswith("/v1/"):
            return self.proxy()
        self._json(404, {"error": "not found"})

    do_DELETE = do_POST

    # ---------------- proxy
    def proxy(self) -> None:
        started = time.monotonic()
        ts = time.time()
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        path = self.path
        api = "anthropic" if path.startswith("/v1/messages") else "openai"
        model = alias = None
        stream = False
        if body and self.headers.get("Content-Type", "").startswith("application/json"):
            try:
                req = json.loads(body)
                if isinstance(req, dict):
                    model = req.get("model")
                    real = aliases().get(model) if model else None
                    if real:
                        alias, model = model, real
                        req["model"] = real
                    stream = bool(req.get("stream"))
                    if stream and api == "openai" and path.startswith(("/v1/chat/completions", "/v1/completions")):
                        so = req.get("stream_options") or {}
                        so.setdefault("include_usage", True)
                        req["stream_options"] = so
                    body = json.dumps(req).encode()
            except ValueError:
                pass
        person, agent = _person_agent(self.headers)
        u = urllib.parse.urlsplit(UPSTREAM)
        conn_cls = HTTPSConnection if u.scheme == "https" else HTTPConnection
        conn = conn_cls(u.hostname, u.port or (443 if u.scheme == "https" else 80), timeout=900)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        if UPSTREAM_KEY:
            headers["Authorization"] = "Bearer " + UPSTREAM_KEY
            headers.pop("x-api-key", None)
        headers["Content-Length"] = str(len(body))
        status, err, usage = 502, None, Usage()
        try:
            conn.request(self.command, (u.path.rstrip("/") + path), body=body, headers=headers)
            resp = conn.getresponse()
            status = resp.status
            ctype = resp.getheader("Content-Type", "")
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() not in HOP:
                    self.send_header(k, v)
            if "text/event-stream" in ctype:
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                while True:
                    chunk = resp.read1(65536) if hasattr(resp, "read1") else resp.read(4096)
                    if not chunk:
                        break
                    usage.feed_sse(chunk)
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
            else:
                data = resp.read()
                if path.rstrip("/") == "/v1/models" and resp.status == 200:
                    data = self._with_aliases(data)
                usage.first = time.monotonic()
                if "json" in ctype:
                    usage.feed_json(data)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            if status >= 400:
                err = f"HTTP {status}"
        except Exception as exc:  # noqa: BLE001
            err = str(exc)[:300]
            try:
                self._json(502, {"error": {"message": "yolo gateway: upstream unreachable: " + err}})
            except Exception:  # noqa: BLE001
                pass
        finally:
            conn.close()
        if path.startswith(("/v1/chat", "/v1/completions", "/v1/messages", "/v1/responses")) and self.command == "POST":
            dur = (time.monotonic() - started) * 1000
            ttft = (usage.first - started) * 1000 if usage.first else None
            try:
                db().execute(
                    """INSERT INTO requests(ts, person, agent, client, api, path, model, alias, stream, status,
                       prompt_tokens, completion_tokens, ttft_ms, duration_ms, error, preview)
                       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                    (ts, person, agent, self.client_address[0], api, path.split("?")[0], model, alias, int(stream),
                     status, usage.prompt, usage.completion, ttft, dur, err, usage.preview[:160]))
            except sqlite3.Error as exc:
                print("log error:", exc, flush=True)

    def _with_aliases(self, data: bytes) -> bytes:
        amap = aliases()
        if not amap:
            return data
        try:
            obj = json.loads(data)
            have = {m.get("id") for m in obj.get("data", [])}
            for alias, real in amap.items():
                if alias not in have:
                    base = next((dict(m) for m in obj["data"] if m.get("id") == real), {"object": "model"})
                    base.update(id=alias, root=real)
                    obj["data"].append(base)
            return json.dumps(obj).encode()
        except (ValueError, KeyError, TypeError):
            return data

    # ---------------- dashboard API
    def api(self, path: str, q: dict) -> None:
        c = db()
        now = time.time()
        rng = {"15m": 900, "1h": 3600, "6h": 21600, "24h": 86400, "7d": 604800, "30d": 2592000}
        span = rng.get((q.get("range") or ["1h"])[0], 3600)
        if path == "/api/live":
            latest = dict(SCRAPER.latest)
            if latest.get("gpu"):
                try:
                    latest["gpu"] = json.loads(latest["gpu"])
                except ValueError:
                    latest["gpu"] = None
            day = c.execute(
                """SELECT count(*) n, coalesce(sum(prompt_tokens),0) p, coalesce(sum(completion_tokens),0) g,
                   count(DISTINCT person) people, sum(status>=400 OR error IS NOT NULL) errors
                   FROM requests WHERE ts > ?""", (now - 86400,)).fetchone()
            ttft = [r[0] for r in c.execute(
                "SELECT ttft_ms FROM requests WHERE ts > ? AND ttft_ms IS NOT NULL ORDER BY ttft_ms",
                (now - 3600,))]
            p50 = ttft[len(ttft) // 2] if ttft else None
            spark = [dict(r) for r in c.execute(
                "SELECT ts, gen_tps, prompt_tps, running, waiting, kv, ttft_p50 FROM samples WHERE ts > ? ORDER BY ts",
                (now - 600,))]
            self._json(200, {"now": now, "upstream": UPSTREAM, "latest": latest, "day": dict(day),
                             "ttft_p50_1h": p50, "spark": spark, "aliases": aliases(),
                             "gpu_enabled": bool(GPU_URL)})
        elif path == "/api/series":
            if span <= 6 * 3600:
                rows = c.execute(
                    """SELECT ts, running, waiting, kv, prompt_tps, gen_tps, ttft_p50, ttft_p95, e2e_p50,
                       itl_p50, preempt, up FROM samples WHERE ts > ? ORDER BY ts""", (now - span,))
                step = 1 if span <= 3600 else 3
                data = [dict(r) for i, r in enumerate(rows) if i % step == 0]
            else:
                bucket = 1 if span <= 86400 else (10 if span <= 604800 else 60)
                rows = c.execute(
                    f"""SELECT (minute/{bucket})*{bucket}*60 ts, avg(running) running, avg(waiting) waiting,
                        avg(kv) kv, avg(prompt_tps) prompt_tps, avg(gen_tps) gen_tps, avg(ttft_p50) ttft_p50,
                        max(ttft_p95) ttft_p95, avg(e2e_p50) e2e_p50, avg(itl_p50) itl_p50,
                        avg(preempt) preempt, avg(up) up
                        FROM rollup WHERE minute > ? GROUP BY minute/{bucket} ORDER BY ts""",
                    ((now - span) // 60,))
                data = [dict(r) for r in rows]
            events = [dict(r) for r in c.execute(
                "SELECT ts, kind, detail FROM events WHERE ts > ? ORDER BY ts", (now - span,))]
            self._json(200, {"series": data, "events": events, "span": span, "now": now})
        elif path == "/api/usage":
            def group(col: str):
                return [dict(r) for r in c.execute(
                    f"""SELECT {col} name, count(*) requests, coalesce(sum(prompt_tokens),0) prompt,
                        coalesce(sum(completion_tokens),0) completion, avg(duration_ms) avg_ms
                        FROM requests WHERE ts > ? GROUP BY {col} ORDER BY prompt+completion DESC LIMIT 20""",
                    (now - span,))]
            hourly = [dict(r) for r in c.execute(
                """SELECT CAST(ts/3600 AS INTEGER)*3600 hour, count(*) requests,
                   coalesce(sum(prompt_tokens),0)+coalesce(sum(completion_tokens),0) tokens
                   FROM requests WHERE ts > ? GROUP BY hour ORDER BY hour""", (now - max(span, 86400),))]
            self._json(200, {"people": group("person"), "agents": group("agent"), "models": group("model"),
                             "hourly": hourly})
        elif path == "/api/requests":
            limit = min(int((q.get("limit") or ["200"])[0]), 1000)
            text = (q.get("q") or [""])[0].strip()
            sql = "SELECT * FROM requests WHERE ts > ?"
            args: list = [now - span]
            if text:
                sql += " AND (person LIKE ? OR agent LIKE ? OR model LIKE ? OR path LIKE ? OR coalesce(error,'') LIKE ?)"
                args += [f"%{text}%"] * 5
            sql += " ORDER BY ts DESC LIMIT ?"
            args.append(limit)
            self._json(200, {"requests": [dict(r) for r in c.execute(sql, args)]})
        else:
            self._json(404, {"error": "unknown api"})


def main() -> None:
    init_db()
    SCRAPER.start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print(f"yolo lab: gateway + monitor on :{PORT}, upstream {UPSTREAM}, data {DB_PATH}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
