"""A stand-in for vLLM for the smoke tests: answers every request with a fixed
reply, so each agent can make a real round trip with no model and no network.

  GET  /v1/models
  POST /v1/chat/completions   OpenAI chat (streaming and not)
  POST /v1/messages           Anthropic messages (streaming and not)
  POST /v1/responses          OpenAI Responses (streaming and not)

Every request is appended to $STUB_LOG (JSON lines) so tests can check which
endpoint, model and key each agent used.

  python3 stub-llm.py [port]       (default 18000)
"""

import json
import os
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = os.environ.get("STUB_MODEL", "Qwen/Qwen3-Stub")
REPLY = os.environ.get("STUB_REPLY", "YOLO-STUB-OK")
LOG = os.environ.get("STUB_LOG", "/tmp/stub-llm.jsonl")


# Synthetic vLLM metrics: a slow load wave plus whatever real requests arrive,
# so the lab monitor has something realistic to draw.
import math
import random
import threading

_m = {"prompt": 0.0, "gen": 0.0, "preempt": 0, "n": 0, "t": time.time()}
_hist = {k: [0] * 12 for k in ("ttft", "e2e", "itl")}
_hsum = {k: 0.0 for k in _hist}
_BOUNDS = {"ttft": [0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2.5, 5, 10],
           "e2e": [0.3, 0.5, 1, 2.5, 5, 10, 15, 20, 30, 40, 60],
           "itl": [0.005, 0.01, 0.015, 0.02, 0.025, 0.03, 0.04, 0.05, 0.075, 0.1, 0.25]}
_lock = threading.Lock()


def _wave() -> float:
    t = time.time()
    return max(0.0, 0.55 + 0.35 * math.sin(t / 90) + 0.15 * math.sin(t / 17))


def _observe(kind: str, v: float) -> None:
    _hsum[kind] += v
    for i, b in enumerate(_BOUNDS[kind] + [float("inf")]):
        if v <= b:
            _hist[kind][i] += 1
            break


def _tick() -> None:
    with _lock:
        now = time.time()
        dt, _m["t"] = now - _m["t"], now
        w = _wave()
        _m["gen"] += dt * w * 900 * random.uniform(0.85, 1.15)
        _m["prompt"] += dt * w * 4200 * random.uniform(0.6, 1.4)
        for _ in range(int(dt * w * 3 + random.random())):
            ttft = random.lognormvariate(math.log(0.12 + 0.5 * w), 0.4)
            itl = random.lognormvariate(math.log(0.018 + 0.02 * w), 0.25)
            _observe("ttft", ttft)
            _observe("itl", itl)
            _observe("e2e", ttft + itl * random.randint(50, 900))
            _m["n"] += 1
        if random.random() < 0.01 * w:
            _m["preempt"] += 1


def metrics_text() -> str:
    _tick()
    w, lab = _wave(), f'model_name="{MODEL}"'
    out = [f"vllm:num_requests_running{{{lab}}} {round(w * 9 + random.random() * 2)}",
           f"vllm:num_requests_waiting{{{lab}}} {max(0, round((w - 0.8) * 12))}",
           f"vllm:kv_cache_usage_perc{{{lab}}} {min(0.98, w * 0.75 + random.random() * 0.05):.4f}",
           f"vllm:prompt_tokens_total{{{lab}}} {_m['prompt']:.0f}",
           f"vllm:generation_tokens_total{{{lab}}} {_m['gen']:.0f}",
           f"vllm:num_preemptions_total{{{lab}}} {_m['preempt']}"]
    names = {"ttft": "vllm:time_to_first_token_seconds", "e2e": "vllm:e2e_request_latency_seconds",
             "itl": "vllm:inter_token_latency_seconds"}
    for k, name in names.items():
        acc = 0
        for b, c in zip(_BOUNDS[k] + ["+Inf"], _hist[k]):
            acc += c
            out.append(f'{name}_bucket{{{lab},le="{b}"}} {acc}')
        out.append(f"{name}_count{{{lab}}} {acc}")
        out.append(f"{name}_sum{{{lab}}} {_hsum[k]:.4f}")
    return "\n".join(out) + "\n"


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _sse_start(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

    def _ev(self, data, event=None):
        s = (f"event: {event}\n" if event else "") + f"data: {data if isinstance(data, str) else json.dumps(data)}\n\n"
        self.wfile.write(s.encode())
        self.wfile.flush()

    def _record(self, body):
        try:
            with open(LOG, "a") as f:
                f.write(json.dumps({"t": time.time(), "path": self.path, "model": body.get("model"),
                                    "stream": body.get("stream"), "auth": self.headers.get("Authorization")
                                    or self.headers.get("x-api-key"), "ua": self.headers.get("User-Agent")}) + "\n")
        except OSError:
            pass

    def do_GET(self):  # noqa: N802
        if self.path.rstrip("/").endswith("/models"):
            return self._json({"object": "list", "data": [
                {"id": MODEL, "object": "model", "owned_by": "stub", "max_model_len": 65536}]})
        if self.path.startswith("/metrics"):
            b = metrics_text().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            return self.wfile.write(b)
        return self._json({"ok": True})

    def do_POST(self):  # noqa: N802
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            body = {}
        self._record(body)
        p = self.path.split("?")[0].rstrip("/")
        if p.endswith("/chat/completions"):
            return self.chat(body)
        if p.endswith("/messages/count_tokens"):
            return self._json({"input_tokens": 10})
        if p.endswith("/messages"):
            return self.messages(body)
        if p.endswith("/responses"):
            return self.responses_api(body)
        if p.endswith("/completions"):
            return self._json({"id": "c", "object": "text_completion", "model": MODEL,
                               "choices": [{"index": 0, "text": REPLY, "finish_reason": "stop"}]})
        return self._json({"error": {"message": f"stub: no route {self.path}"}}, 404)

    # -- OpenAI chat ---------------------------------------------------------
    def chat(self, body):
        cid, now = "chatcmpl-" + uuid.uuid4().hex[:12], int(time.time())
        usage = {"prompt_tokens": 10, "completion_tokens": 3, "total_tokens": 13}
        if not body.get("stream"):
            return self._json({"id": cid, "object": "chat.completion", "created": now, "model": MODEL,
                               "choices": [{"index": 0, "finish_reason": "stop",
                                            "message": {"role": "assistant", "content": REPLY}}], "usage": usage})
        self._sse_start()
        base = {"id": cid, "object": "chat.completion.chunk", "created": now, "model": MODEL}
        self._ev({**base, "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": None}]})
        self._ev({**base, "choices": [{"index": 0, "delta": {"content": REPLY}, "finish_reason": None}]})
        self._ev({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
        self._ev({**base, "choices": [], "usage": usage})
        self._ev("[DONE]")

    # -- Anthropic messages ----------------------------------------------------
    def messages(self, body):
        mid = "msg_" + uuid.uuid4().hex[:12]
        usage = {"input_tokens": 10, "output_tokens": 3}
        msg = {"id": mid, "type": "message", "role": "assistant", "model": body.get("model") or MODEL,
               "content": [{"type": "text", "text": REPLY}], "stop_reason": "end_turn",
               "stop_sequence": None, "usage": usage}
        if not body.get("stream"):
            return self._json(msg)
        self._sse_start()
        self._ev({"type": "message_start", "message": {**msg, "content": [], "stop_reason": None,
                                                        "usage": {"input_tokens": 10, "output_tokens": 0}}},
                 "message_start")
        self._ev({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
                 "content_block_start")
        self._ev({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": REPLY}},
                 "content_block_delta")
        self._ev({"type": "content_block_stop", "index": 0}, "content_block_stop")
        self._ev({"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                  "usage": {"output_tokens": 3}}, "message_delta")
        self._ev({"type": "message_stop"}, "message_stop")

    # -- OpenAI Responses ------------------------------------------------------
    def responses_api(self, body):
        rid, iid, now = "resp_" + uuid.uuid4().hex[:12], "msg_" + uuid.uuid4().hex[:12], int(time.time())
        item = {"id": iid, "type": "message", "status": "completed", "role": "assistant",
                "content": [{"type": "output_text", "text": REPLY, "annotations": []}]}
        usage = {"input_tokens": 10, "output_tokens": 3, "total_tokens": 13,
                 "input_tokens_details": {"cached_tokens": 0}, "output_tokens_details": {"reasoning_tokens": 0}}
        resp = {"id": rid, "object": "response", "created_at": now, "status": "completed", "model": MODEL,
                "output": [item], "usage": usage}
        if not body.get("stream"):
            return self._json(resp)
        self._sse_start()
        seq = iter(range(1000))

        def ev(t, **kw):
            self._ev({"type": t, "sequence_number": next(seq), **kw}, t)

        ev("response.created", response={**resp, "status": "in_progress", "output": []})
        ev("response.in_progress", response={**resp, "status": "in_progress", "output": []})
        ev("response.output_item.added", output_index=0, item={**item, "status": "in_progress", "content": []})
        ev("response.content_part.added", item_id=iid, output_index=0, content_index=0,
           part={"type": "output_text", "text": "", "annotations": []})
        ev("response.output_text.delta", item_id=iid, output_index=0, content_index=0, delta=REPLY)
        ev("response.output_text.done", item_id=iid, output_index=0, content_index=0, text=REPLY)
        ev("response.content_part.done", item_id=iid, output_index=0, content_index=0,
           part={"type": "output_text", "text": REPLY, "annotations": []})
        ev("response.output_item.done", output_index=0, item=item)
        ev("response.completed", response=resp)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18000
    srv = ThreadingHTTPServer(("127.0.0.1", port), H)
    srv.daemon_threads = True
    srv.serve_forever()
