"""yolo status | doctor | models | agents | tools"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import urllib.request
from pathlib import Path

HOME = Path(os.environ.get("HOME") or "/home/agent")
Y = HOME / ".yolo"
TTY = sys.stdout.isatty()


def c(code: str, s: str) -> str:
    return f"\033[{code}m{s}\033[0m" if TTY else s


OK, BAD, DIM, B = (lambda s: c("32", s)), (lambda s: c("31", s)), (lambda s: c("2", s)), (lambda s: c("1", s))

AGENTS = [
    ("claude", "Claude Code", "claude"),
    ("opencode", "opencode (also the Chat page)", "opencode"),
    ("qwen", "Qwen Code", "qwen"),
    ("pi", "pi", "pi"),
    ("crush", "Crush", "crush"),
    ("goose", "Goose", "goose session"),
    ("codex", "Codex (experimental: Responses API)", "codex"),
]


def state() -> dict:
    try:
        return json.loads((Y / "state.json").read_text())
    except (OSError, ValueError):
        return {}


def tcp(hostport: str) -> bool:
    host, _, port = hostport.partition(":")
    try:
        with socket.create_connection((host, int(port or 80)), timeout=2):
            return True
    except OSError:
        return False


def models_live() -> tuple[bool, list]:
    base = os.environ.get("VLLM_BASE_URL", "").rstrip("/")
    try:
        req = urllib.request.Request(base + "/models", headers={"Authorization": "Bearer x"})
        with urllib.request.urlopen(req, timeout=4) as r:
            return True, json.load(r).get("data", [])
    except Exception:  # noqa: BLE001
        return False, []


def status(doctor: bool = False) -> int:
    s = state()
    up, models = models_live()
    gitea = os.environ.get("GITEA_HOST", "")
    print(B(f"yolo-agent {os.environ.get('YOLO_VERSION', 'dev')}") + DIM(f"  tier {os.environ.get('YOLO_TIER', '?')}"))
    print(f"  model server  {os.environ.get('VLLM_BASE_URL', '')}  " + (OK("up") if up else BAD("unreachable")))
    print(f"  model         {s.get('model', '?')}" + DIM(f"  ({len(models)} served)" if up else ""))
    print(f"  gitea         {gitea}  " + (OK("up") if gitea and tcp(gitea) else BAD("unreachable")))
    print(f"  git           " + (OK(f"ready as {s.get('gitea_user')}") if s.get("git_ready")
                                 else BAD("no Gitea token") + DIM("  → yolo login")))
    fleet = s.get("fleet") or {}
    print(f"  fleet repo    {fleet.get('fleet', 'not synced')}" + DIM(f"  ({os.environ.get('YOLO_FLEET_REPO', '')})"))
    sk = s.get("skills") or []
    print(f"  skills        {', '.join(sk) if sk else 'none enabled'}")
    print(f"  agents        {', '.join(s.get('agents', []))}"
          + (BAD(f"  failed: {', '.join(s['agents_failed'])}") if s.get("agents_failed") else ""))
    if not doctor:
        return 0
    print()
    problems = 0

    def check(ok: bool, what: str, fix: str = "") -> None:
        nonlocal problems
        print(("  " + OK("✓") if ok else "  " + BAD("✗")) + f" {what}" + ("" if ok or not fix else DIM(f"  → {fix}")))
        problems += 0 if ok else 1

    check(up, "model server answers /v1/models", "check SEC09 is running and VLLM_BASE_URL in .env")
    check(not up or any(m.get("id") == s.get("model") for m in models), "configured model is served",
          "run: yolo configure  (or set VLLM_MODEL in .env)")
    check(bool(s.get("git_ready")), "Gitea token stored", "yolo login")
    check(os.access("/workspace", os.W_OK), "/workspace is writable",
          "the workspace folder on the host must be writable by uid 10001")
    for name, _, _ in AGENTS:
        check(shutil.which(name) is not None and (Path("/opt/agents/bin") / name).exists(), f"{name} installed")
    for p in (".config/opencode/opencode.json", ".claude/settings.json", ".codex/config.toml",
              ".qwen/settings.json", ".pi/agent/models.json", ".config/crush/crush.json",
              ".config/goose/config.yaml"):
        check((HOME / p).is_file(), f"~/{p} written", "yolo configure")
    try:
        mounts = Path("/proc/mounts").read_text()
        slow = any(l.split()[1] == "/workspace" and l.split()[2] in ("9p", "drvfs", "fuse.grpcfuse", "virtiofs")
                   for l in mounts.splitlines() if len(l.split()) > 2)
        check(not slow, "/workspace is on a fast filesystem",
              "keep the person's folder on the WSL disk (~/yolo/<name>), not under /mnt/c")
    except OSError:
        pass
    print()
    print(OK("all good") if problems == 0 else BAD(f"{problems} problem(s)"))
    return 0 if problems == 0 else 1


def models() -> int:
    up, ms = models_live()
    if not up:
        print(BAD("model server unreachable: ") + os.environ.get("VLLM_BASE_URL", ""))
        return 1
    current = state().get("model")
    for m in ms:
        mark = "★" if m.get("id") == current else " "
        print(f"{mark} {m.get('id')}" + DIM(f"   max context {m.get('max_model_len', '?')}"))
    print(DIM("\n★ = default for the agents. Change it with VLLM_MODEL in .env or the fleet repo."))
    return 0


def agents() -> int:
    print(B("Agents") + DIM("  (all run without permission prompts)"))
    for name, desc, cmd in AGENTS:
        ver = "?"
        try:
            vf = Path("/opt/agents/VERSIONS.txt").read_text()
            ver = next((l.split(None, 1)[1] for l in vf.splitlines() if l.startswith(name + " ")), "?")
        except OSError:
            pass
        print(f"  {cmd:<15} {desc}" + DIM(f"   {ver.strip()}"))
    print(DIM("\nIn the browser: the Chat page (opencode), and Kilo Code in VS Code."))
    return 0


def tools() -> int:
    tier = os.environ.get("YOLO_TIER", "core")
    groups = [("core", ["python3", "pip", "node", "npm", "git", "gcc", "make", "jq", "rg", "fdfind", "sqlite3",
                        "tmux", "curl", "shellcheck"])]
    if tier in ("cpp", "full"):
        groups.append(("cpp", ["g++", "gfortran", "clang", "clang++", "lld", "cmake", "ninja", "ccache", "gdb",
                               "valgrind", "x86_64-w64-mingw32-gcc", "x86_64-w64-mingw32-g++",
                               "x86_64-w64-mingw32-gfortran", "cpp-build"]))
    if tier == "full":
        groups.append(("reverse", ["pyinstxtractor-ng", "pycdc", "pycdas", "uncompyle6", "pydumpck", "jadx",
                                   "ghidra-headless", "r2", "binwalk", "yara", "java"]))
    for g, names in groups:
        print(B(g))
        print("  " + "  ".join((n if shutil.which(n) else BAD(n + "?")) for n in names))
    print(DIM(f"\nPython packages: pip list   ({sum(1 for _ in open('/opt/yolo/manifests/python.txt'))} installed)"
              if Path("/opt/yolo/manifests/python.txt").exists() else ""))
    return 0


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else "status"
    return {"status": lambda: status(False), "doctor": lambda: status(True), "models": models,
            "agents": agents, "tools": tools}[cmd]()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
