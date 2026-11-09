"""yolo bot — the always-on agent (service `bot` in compose.lab.yaml).

  * Gitea webhook  POST /hook
      pull_request opened / synchronized / reopened  → review the PR
      issue_comment on a PR or issue mentioning @yolo → do what the comment asks
  * schedule       jobs from the fleet repo (bot/jobs.json), cron syntax
  * status         GET /  (recent jobs), GET /api/jobs

Each job runs a headless agent (BOT_AGENT: opencode, claude or qwen) in a fresh
checkout under /tmp/bot, then posts the result to Gitea. Jobs run one at a time
by default (BOT_CONCURRENCY).

  yolo serve bot                                  run the service
  python bot.py hook <owner/repo|org:NAME>        install the webhook in Gitea
  python bot.py run <owner/repo> <pr-number>      review one PR now (no webhook)

Environment: GITEA_HOST, GITEA_TOKEN (the bot's account), BOT_WEBHOOK_SECRET,
BOT_PUBLIC_URL (how Gitea reaches this service, e.g. http://lab:9000),
BOT_AGENT, BOT_MENTION (default @yolo), BOT_TIMEOUT (seconds, default 1800),
BOT_REVIEW_ON (default "opened reopened synchronized").
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import json
import os
import queue
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import traceback
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path(os.environ.get("HOME") or "/home/agent")
DB = HOME / ".yolo" / "bot.db"
WORK = Path("/tmp/bot")


def E(k: str, d: str = "") -> str:
    v = os.environ.get(k)
    return v if v not in (None, "") else d


GITEA = f"{E('GITEA_PROTOCOL', 'http')}://{E('GITEA_HOST', '192.168.1.27:3000')}"
TOKEN = E("GITEA_TOKEN")
SECRET = E("BOT_WEBHOOK_SECRET")
AGENT = E("BOT_AGENT", "opencode")
MENTION = E("BOT_MENTION", "@yolo")
TIMEOUT = int(E("BOT_TIMEOUT", "1800"))
REVIEW_ON = set(E("BOT_REVIEW_ON", "opened reopened synchronized").split())
PORT = int(E("BOT_PORT", "9000"))
JOBS: "queue.Queue[dict]" = queue.Queue()
_dblock = threading.Lock()


# ----------------------------------------------------------------------------
# storage
# ----------------------------------------------------------------------------
def db() -> sqlite3.Connection:
    DB.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(DB, timeout=30, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute("""CREATE TABLE IF NOT EXISTS jobs (id INTEGER PRIMARY KEY, created REAL, started REAL,
                 finished REAL, kind TEXT, repo TEXT, number INTEGER, title TEXT, status TEXT,
                 result_url TEXT, error TEXT, output TEXT)""")
    c.execute("CREATE TABLE IF NOT EXISTS schedule (name TEXT PRIMARY KEY, last REAL)")
    return c


def record(job: dict, **fields) -> None:
    with _dblock:
        c = db()
        if "id" not in job:
            cur = c.execute("INSERT INTO jobs(created, kind, repo, number, title, status) VALUES (?,?,?,?,?,?)",
                            (time.time(), job["kind"], job.get("repo"), job.get("number"), job.get("title"), "queued"))
            job["id"] = cur.lastrowid
        if fields:
            sets = ", ".join(f"{k}=?" for k in fields)
            c.execute(f"UPDATE jobs SET {sets} WHERE id=?", (*fields.values(), job["id"]))
        c.close()


# ----------------------------------------------------------------------------
# Gitea
# ----------------------------------------------------------------------------
def api(method: str, path: str, body=None, raw: bool = False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(GITEA + "/api/v1" + path, data=data, method=method,
                                 headers={"Authorization": f"token {TOKEN}", "Accept": "application/json",
                                          "Content-Type": "application/json", "User-Agent": "yolo-bot"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = resp.read()
    if raw:
        return payload.decode("utf-8", "replace")
    return json.loads(payload) if payload else {}


def me() -> str:
    try:
        return api("GET", "/user").get("login", "")
    except (OSError, ValueError):
        return ""


def git(*args, cwd=None, timeout=300):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    return subprocess.run(["git", "-c", f"http.extraHeader=Authorization: token {TOKEN}", *args],
                          cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout, check=True)


def checkout(repo: str, number: int | None, ref: str | None = None) -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    dest = WORK / f"{repo.replace('/', '__')}-{number or 'main'}-{int(time.time())}"
    git("clone", "--quiet", f"{GITEA}/{repo}.git", str(dest), timeout=600)
    if number:
        git("fetch", "--quiet", "origin", f"pull/{number}/head:pr-{number}", cwd=dest)
        git("checkout", "--quiet", f"pr-{number}", cwd=dest)
    elif ref:
        git("checkout", "--quiet", ref, cwd=dest)
    return dest


# ----------------------------------------------------------------------------
# the agent
# ----------------------------------------------------------------------------
def run_agent(prompt: str, cwd: Path) -> str:
    cmds = {
        "opencode": ["opencode", "run", prompt],
        "claude": ["claude", "-p", prompt, "--dangerously-skip-permissions", "--output-format", "text"],
        "qwen": ["qwen", "--yolo", "-p", prompt],
    }
    cmd = cmds.get(AGENT, cmds["opencode"])
    shell = ["bash", "-lc", 'exec "$@"', "agent", *cmd]
    r = subprocess.run(shell, cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT,
                       env=dict(os.environ, YOLO_GREETED="1", CI="1", TERM="dumb", NO_COLOR="1"))
    out = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", r.stdout).strip()
    if r.returncode != 0 and not out:
        raise RuntimeError(f"{AGENT} exited {r.returncode}: {r.stderr.strip()[-1500:]}")
    return out


def footer(started: float) -> str:
    model = ""
    try:
        model = json.loads((HOME / ".yolo/state.json").read_text()).get("model", "")
    except (OSError, ValueError):
        pass
    mins = (time.time() - started) / 60
    return f"\n\n---\n<sub>yolo bot · {AGENT} · {model} · {mins:.1f} min</sub>"


REVIEW_PROMPT = """You are reviewing pull request #{number} in {repo}: "{title}".

PR description:
{body}

The PR branch is checked out in the current directory. The base branch is
`origin/{base}`. Steps:

1. Run `git diff origin/{base}...HEAD --stat` and then read the full diff.
2. Read the surrounding code where needed to understand the change.
3. If the project has a quick build or test command (see README, Makefile,
   CMakeLists.txt, package.json, pyproject.toml), run it and note the result.
   Do not install anything: there is no internet.
4. Do not modify, commit or push anything.

Reply with the review only, in Markdown, in this shape:

## Summary
One short paragraph: what the change does and whether it is ready.

## Problems
A numbered list. Each item: `path:line`, severity (blocker / should fix / nit),
what is wrong, and how to fix it. Write "None found." if there are none.

## Checks
What you built or ran, and the result. Say plainly what you could not check.
"""

REQUEST_PROMPT = """You are working in {repo}{where}. A person wrote this request to you:

{request}

The repository is checked out in the current directory{branch_note}.
There is no internet; do not try to install anything.

If the request needs code changes: make them, run the relevant build or tests,
commit with a clear message, and push to the current branch (`git push origin
HEAD:{push_ref}`). Never force-push. If it is a question, answer it.

Finish with a short Markdown reply for the person: what you did, what you
checked, and anything left for them to decide.
"""


def do_review(job: dict) -> str:
    repo, n = job["repo"], job["number"]
    pr = api("GET", f"/repos/{repo}/pulls/{n}")
    started = time.time()
    path = checkout(repo, n)
    try:
        git("fetch", "--quiet", "origin", pr["base"]["ref"], cwd=path)
        text = run_agent(REVIEW_PROMPT.format(number=n, repo=repo, title=pr.get("title", ""),
                                              body=(pr.get("body") or "(none)")[:6000],
                                              base=pr["base"]["ref"]), path)
    finally:
        shutil.rmtree(path, ignore_errors=True)
    body = "### 🤖 yolo review\n\n" + (text or "_The agent returned no review._") + footer(started)
    res = api("POST", f"/repos/{repo}/pulls/{n}/reviews",
              {"body": body, "event": "COMMENT", "commit_id": pr.get("head", {}).get("sha")})
    return res.get("html_url") or f"{GITEA}/{repo}/pulls/{n}"


def do_request(job: dict) -> str:
    repo, n = job["repo"], job.get("number")
    started = time.time()
    is_pr, branch = False, None
    if n:
        issue = api("GET", f"/repos/{repo}/issues/{n}")
        is_pr = bool(issue.get("pull_request"))
        if is_pr:
            pr = api("GET", f"/repos/{repo}/pulls/{n}")
            branch = pr["head"]["ref"]
            same_repo = (pr.get("head", {}).get("repo") or {}).get("full_name") == repo
            if not same_repo:
                branch = None
    path = checkout(repo, n if is_pr else None)
    try:
        if branch:
            git("checkout", "--quiet", "-B", branch, cwd=path)
        where = f", on {'pull request' if is_pr else 'issue'} #{n}" if n else ""
        text = run_agent(REQUEST_PROMPT.format(
            repo=repo, where=where, request=job["request"][:8000],
            branch_note=(f" on the PR branch `{branch}`" if branch else ""),
            push_ref=branch or "yolo/" + dt.datetime.now().strftime("%Y%m%d-%H%M%S")), path)
    finally:
        shutil.rmtree(path, ignore_errors=True)
    body = (text or "_No reply from the agent._") + footer(started)
    if n:
        return api("POST", f"/repos/{repo}/issues/{n}/comments", {"body": body}).get("html_url", "")
    return api("POST", f"/repos/{repo}/issues",
               {"title": job.get("title") or "yolo bot", "body": body}).get("html_url", "")


def worker() -> None:
    while True:
        job = JOBS.get()
        record(job, status="running", started=time.time())
        try:
            url = do_review(job) if job["kind"] == "review" else do_request(job)
            record(job, status="done", finished=time.time(), result_url=url)
            print(f"bot: {job['kind']} {job.get('repo')}#{job.get('number')} done → {url}", flush=True)
        except Exception as exc:  # noqa: BLE001
            record(job, status="failed", finished=time.time(), error=f"{exc}"[:2000])
            print(f"bot: job failed: {exc}\n{traceback.format_exc()}", flush=True)
        finally:
            JOBS.task_done()


def enqueue(job: dict) -> None:
    record(job)
    JOBS.put(job)


# ----------------------------------------------------------------------------
# schedule (minimal cron: minute hour day-of-month month day-of-week)
# ----------------------------------------------------------------------------
def _field(spec: str, value: int, lo: int, hi: int) -> bool:
    for part in spec.split(","):
        step = 1
        if "/" in part:
            part, s = part.split("/", 1)
            step = int(s)
        if part in ("*", ""):
            a, b = lo, hi
        elif "-" in part:
            a, b = (int(x) for x in part.split("-", 1))
        else:
            a = b = int(part)
        if a <= value <= b and (value - a) % step == 0:
            return True
    return False


def cron_match(expr: str, t: dt.datetime) -> bool:
    m, h, dom, mon, dow = expr.split()
    return (_field(m, t.minute, 0, 59) and _field(h, t.hour, 0, 23) and _field(dom, t.day, 1, 31)
            and _field(mon, t.month, 1, 12) and _field(dow, (t.isoweekday() % 7), 0, 6))


def scheduler() -> None:
    jobs_file = HOME / ".yolo/fleet/bot/jobs.json"
    last_minute = None
    while True:
        now = dt.datetime.now()
        minute = now.replace(second=0, microsecond=0)
        if minute != last_minute:
            last_minute = minute
            try:
                jobs = json.loads(jobs_file.read_text()) if jobs_file.is_file() else []
            except (OSError, ValueError) as exc:
                print(f"bot: cannot read {jobs_file}: {exc}", flush=True)
                jobs = []
            for j in jobs:
                try:
                    if j.get("enabled", True) and cron_match(j["cron"], minute):
                        enqueue({"kind": "request", "repo": j["repo"], "number": j.get("issue"),
                                 "title": f"[yolo] {j['name']} {minute:%Y-%m-%d}", "request": j["prompt"]})
                except (KeyError, ValueError) as exc:
                    print(f"bot: bad job {j!r}: {exc}", flush=True)
        time.sleep(15)


# ----------------------------------------------------------------------------
# webhook server
# ----------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "yolo-bot"

    def log_message(self, *a):
        pass

    def _send(self, code: int, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        c = db()
        rows = [dict(r) for r in c.execute(
            "SELECT id, created, started, finished, kind, repo, number, title, status, result_url, error "
            "FROM jobs ORDER BY id DESC LIMIT 100")]
        c.close()
        if self.path.startswith("/api/jobs"):
            return self._send(200, json.dumps(rows).encode())
        items = "".join(
            f"<tr><td>{r['id']}</td><td>{dt.datetime.fromtimestamp(r['created']):%m-%d %H:%M}</td>"
            f"<td>{r['kind']}</td><td>{r['repo'] or ''}#{r['number'] or ''}</td><td>{r['status']}</td>"
            f"<td>{('<a href=' + json.dumps(r['result_url']) + '>result</a>') if r['result_url'] else (r['error'] or '')[:120]}</td></tr>"
            for r in rows)
        html = ("<!doctype html><meta charset=utf-8><title>yolo bot</title><style>body{font:14px system-ui;"
                "margin:32px;background:#0f1013;color:#eceef2}td,th{padding:6px 12px;border-bottom:1px solid #262931;"
                "text-align:left}a{color:#ff7a45}</style><h1>yolo bot</h1>"
                f"<p>agent {AGENT} · queue {JOBS.qsize()} · mention {MENTION}</p>"
                f"<table><tr><th>#</th><th>when</th><th>kind</th><th>target</th><th>status</th><th></th></tr>{items}</table>")
        self._send(200, html.encode(), "text/html; charset=utf-8")

    def do_POST(self):  # noqa: N802
        if not self.path.startswith("/hook"):
            return self._send(404, b'{"error":"not found"}')
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if SECRET:
            sig = self.headers.get("X-Gitea-Signature", "")
            good = hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(sig, good):
                return self._send(401, b'{"error":"bad signature"}')
        event = self.headers.get("X-Gitea-Event", "")
        try:
            ev = json.loads(body)
        except ValueError:
            return self._send(400, b'{"error":"bad json"}')
        repo = (ev.get("repository") or {}).get("full_name")
        sender = (ev.get("sender") or {}).get("login", "")
        accepted = None
        if event == "pull_request" and ev.get("action") in REVIEW_ON:
            pr = ev.get("pull_request") or {}
            if not pr.get("draft") and "[skip review]" not in (pr.get("title") or ""):
                accepted = {"kind": "review", "repo": repo, "number": pr.get("number"), "title": pr.get("title")}
        elif event == "issue_comment" and ev.get("action") == "created":
            comment = (ev.get("comment") or {}).get("body") or ""
            if MENTION.lower() in comment.lower() and sender != BOT_LOGIN:
                issue = ev.get("issue") or {}
                accepted = {"kind": "request", "repo": repo, "number": issue.get("number"),
                            "title": issue.get("title"), "request": comment}
        if accepted and repo:
            enqueue(accepted)
            return self._send(202, json.dumps({"queued": accepted["kind"]}).encode())
        return self._send(200, b'{"ignored":true}')


BOT_LOGIN = ""


def install_hook(target: str) -> int:
    url = E("BOT_PUBLIC_URL")
    if not url:
        print("set BOT_PUBLIC_URL (how Gitea reaches the bot, e.g. http://192.168.1.50:9000)", file=sys.stderr)
        return 2
    hook = {"type": "gitea", "active": True, "events": ["pull_request", "issue_comment"],
            "config": {"url": url.rstrip("/") + "/hook", "content_type": "json", "secret": SECRET}}
    path = f"/orgs/{target[4:]}/hooks" if target.startswith("org:") else f"/repos/{target}/hooks"
    try:
        res = api("POST", path, hook)
    except urllib.error.HTTPError as exc:
        print(f"Gitea refused: HTTP {exc.code} {exc.read().decode()[:300]}", file=sys.stderr)
        return 1
    print(f"webhook {res.get('id')} installed on {target} → {hook['config']['url']}")
    return 0


def main(argv: list[str]) -> int:
    global BOT_LOGIN
    if not TOKEN:
        print("yolo bot: GITEA_TOKEN is required (the bot's own Gitea account)", file=sys.stderr)
        return 2
    if argv[:1] == ["hook"] and len(argv) == 2:
        return install_hook(argv[1])
    if argv[:1] == ["run"] and len(argv) == 3:
        job = {"kind": "review", "repo": argv[1], "number": int(argv[2])}
        record(job)
        print(do_review(job))
        return 0
    BOT_LOGIN = me()
    for _ in range(max(int(E("BOT_CONCURRENCY", "1")), 1)):
        threading.Thread(target=worker, daemon=True).start()
    threading.Thread(target=scheduler, daemon=True).start()
    print(f"yolo bot: :{PORT}/hook, agent {AGENT}, Gitea {GITEA} as {BOT_LOGIN or '?'}", flush=True)
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
