"""yolo configure — write every agent's configuration from the environment.

Runs on every container start (from the entrypoint) and on `yolo sync` /
`yolo login`. Idempotent; holds a lock so several services starting together do
not race. Standard library only.

Order:
  1. sync the fleet and skills repos from Gitea (when a token is available)
  2. discover the models the endpoint serves
  3. write config for every agent (YOLO mode: no permission prompts)
  4. git identity and Gitea credential
  5. code-server settings and extensions
  6. shared instructions (AGENTS.md) and enabled skills
  7. ~/.yolo/state.json for the start page and `yolo status`
"""

from __future__ import annotations

import argparse
import fcntl
import getpass
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path(os.environ.get("HOME") or "/home/agent")
Y = HOME / ".yolo"
OPT = Path("/opt/yolo")
QUIET = False


def log(msg: str) -> None:
    if not QUIET:
        print(f"yolo: {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"yolo: {msg}", file=sys.stderr, flush=True)


def E(key: str, default: str = "") -> str:
    val = os.environ.get(key)
    return val if val not in (None, "") else default


def write(path: Path, text: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp{os.getpid()}")
    tmp.write_text(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def write_json(path: Path, obj, mode: int = 0o600) -> None:
    write(path, json.dumps(obj, indent=2) + "\n", mode)


def read_json(path: Path, default=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {} if default is None else default


def tcp_ok(hostport: str, timeout: float = 2.0) -> bool:
    host, _, port = hostport.partition(":")
    try:
        with socket.create_connection((host, int(port or 80)), timeout=timeout):
            return True
    except OSError:
        return False


# =============================================================================
# 1. fleet and skills repos
# =============================================================================
def gitea_base() -> str:
    return f"{E('GITEA_PROTOCOL', 'http')}://{E('GITEA_HOST')}"


def gitea_api(path: str, token: str | None = None, timeout: float = 4.0):
    token = token or E("GITEA_TOKEN")
    req = urllib.request.Request(gitea_base() + "/api/v1" + path,
                                 headers={"Authorization": f"token {token}", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def git_sync_repo(repo: str, dest: Path) -> bool | None:
    """Clone or fast-forward `owner/name` into dest. True if it changed,
    False if unchanged, None if unavailable."""
    token = E("GITEA_TOKEN")
    if not (E("GITEA_HOST") and token and repo):
        return None
    url = f"{gitea_base()}/{repo}.git"
    hdr = ["-c", f"http.extraHeader=Authorization: token {token}"]
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/bin/true")
    try:
        if (dest / ".git").is_dir():
            before = subprocess.run(["git", "-C", str(dest), "rev-parse", "HEAD"], capture_output=True,
                                    text=True, env=env).stdout.strip()
            r = subprocess.run(["git", *hdr, "-C", str(dest), "pull", "--ff-only", "--quiet", url],
                               capture_output=True, text=True, env=env, timeout=30)
            if r.returncode != 0:
                # Diverged or rewritten history: take the remote as the truth.
                subprocess.run(["git", *hdr, "-C", str(dest), "fetch", "--quiet", url], capture_output=True,
                               env=env, timeout=30, check=True)
                subprocess.run(["git", "-C", str(dest), "reset", "--hard", "--quiet", "FETCH_HEAD"],
                               capture_output=True, env=env, check=True)
            after = subprocess.run(["git", "-C", str(dest), "rev-parse", "HEAD"], capture_output=True,
                                   text=True, env=env).stdout.strip()
            return before != after
        tmp = dest.with_name(dest.name + ".new")
        shutil.rmtree(tmp, ignore_errors=True)
        r = subprocess.run(["git", *hdr, "clone", "--quiet", "--depth", "1", url, str(tmp)],
                           capture_output=True, text=True, env=env, timeout=60)
        if r.returncode != 0:
            shutil.rmtree(tmp, ignore_errors=True)
            return None
        shutil.rmtree(dest, ignore_errors=True)
        tmp.rename(dest)
        return True
    except (subprocess.SubprocessError, OSError):
        return None


def sync_repos() -> dict:
    host = E("GITEA_HOST")
    if not host or not E("GITEA_TOKEN"):
        return {"fleet": "no token", "skills": "no token"}
    if not tcp_ok(host):
        return {"fleet": "Gitea unreachable", "skills": "Gitea unreachable"}
    out = {}
    for key, repo, dest in (("fleet", E("YOLO_FLEET_REPO"), Y / "fleet"),
                            ("skills", E("YOLO_SKILLS_REPO"), Y / "skills-repo")):
        res = git_sync_repo(repo, dest)
        out[key] = {True: "updated", False: "current", None: "not found"}[res]
        out[key + "_changed"] = bool(res)
    return out


# =============================================================================
# 2. models
# =============================================================================
def endpoint() -> str:
    return E("VLLM_BASE_URL", "http://192.168.1.101:8000/v1").rstrip("/")


def api_key() -> str:
    key = E("VLLM_API_KEY", "local")
    if key == "local":
        # vLLM without --api-key accepts any key. Naming the person lets the lab
        # gateway attribute requests; it changes nothing against vLLM directly.
        person = E("YOLO_PERSON") or E("COMPOSE_PROJECT_NAME") or "unknown"
        key = f"yolo-{person}"
    return key


def discover_models() -> tuple[list[dict], str]:
    cache = Y / "models.json"
    try:
        req = urllib.request.Request(endpoint() + "/models", headers={"Authorization": f"Bearer {api_key()}"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = json.load(resp)
        models = [{"id": m["id"], "max_model_len": m.get("max_model_len")}
                  for m in data.get("data", []) if m.get("id")]
        if models:
            write_json(cache, {"ts": time.time(), "models": models})
            return models, "live"
    except (OSError, ValueError, KeyError):
        pass
    cached = read_json(cache).get("models") or []
    return cached, ("cache" if cached else "none")


def pick_models() -> tuple[list[dict], dict, str]:
    models, source = discover_models()
    want = E("VLLM_MODEL")
    if want and not any(m["id"] == want for m in models):
        models = [{"id": want, "max_model_len": None}] + models
    if not models:
        models = [{"id": want or "default", "max_model_len": None}]
    default = next((m for m in models if m["id"] == want), models[0])
    ctx_env = E("VLLM_CONTEXT")
    for m in models:
        if ctx_env.isdigit():
            m["context"] = int(ctx_env)
        else:
            m["context"] = int(m["max_model_len"]) if m.get("max_model_len") else 131072
        m["output"] = min(32768, max(m["context"] // 4, 4096))
        vis = E("VLLM_VISION_MODELS", "auto")
        m["vision"] = vis == "auto" or m["id"] in vis.split()
        m["reasoning"] = "qwen3" in m["id"].lower() or E("VLLM_REASONING", "") == "1"
    return models, default, source


# =============================================================================
# 3. agents
# =============================================================================
def effort() -> str:
    e = E("VLLM_REASONING_EFFORT", "xhigh")
    return {"high": "xhigh"}.get(e, e if e in ("off", "low", "medium", "xhigh") else "xhigh")


def agent_env(name: str, values: dict) -> None:
    """Per-agent environment, read by the /opt/yolo/bin/<agent> wrapper."""
    lines = [f"# written by yolo configure — do not edit; change .env or the fleet repo\n"]
    for k, v in values.items():
        lines.append(f"export {k}={shell_quote(str(v))}\n")
    write(Y / "env" / f"{name}.env", "".join(lines))


def shell_quote(s: str) -> str:
    return "'" + s.replace("'", "'\"'\"'") + "'"


def configure_opencode(models, default, base, key):
    eff = effort()
    entries = {}
    for m in models:
        e = {"name": m["id"], "limit": {"context": m["context"], "output": m["output"]},
             "modalities": {"input": ["text", "image"] if m["vision"] else ["text"], "output": ["text"]}}
        if m["reasoning"]:
            e["reasoning"] = True
            if eff != "off":
                e["options"] = {"reasoningEffort": eff}
            e["variants"] = {v: {"reasoningEffort": v} for v in ("low", "medium", "xhigh")}
        entries[m["id"]] = e
    cfg = {
        "$schema": "https://opencode.ai/config.json",
        "permission": "allow",
        "autoupdate": False,
        "share": "disabled",
        "enabled_providers": ["vllm"],
        "model": f"vllm/{default['id']}",
        "small_model": f"vllm/{default['id']}",
        "provider": {"vllm": {"npm": "@ai-sdk/openai-compatible", "name": "SEC09 vLLM",
                              "options": {"baseURL": base, "apiKey": key}, "models": entries}},
    }
    write_json(HOME / ".config/opencode/opencode.json", cfg)


def configure_pi(models, default, base, key):
    eff = effort()
    write_json(HOME / ".pi/agent/settings.json", {
        "defaultProjectTrust": "always", "enableInstallTelemetry": False,
        "defaultProvider": "vllm", "defaultModel": default["id"], "defaultThinkingLevel": eff,
    })
    entries = []
    for m in models:
        e = {"id": m["id"], "name": m["id"], "input": ["text", "image"] if m["vision"] else ["text"],
             "contextWindow": m["context"], "maxTokens": m["output"]}
        if m["reasoning"]:
            e["reasoning"] = True
            e["thinkingLevelMap"] = {"off": "off", "minimal": None, "low": "low", "medium": "medium",
                                     "high": "xhigh", "xhigh": "xhigh", "max": None}
        entries.append(e)
    write_json(HOME / ".pi/agent/models.json", {"providers": {"vllm": {
        "baseUrl": base, "api": "openai-completions", "apiKey": key, "authHeader": True,
        "compat": {"supportsDeveloperRole": False, "supportsReasoningEffort": True,
                   "thinkingFormat": "qwen-chat-template"},
        "models": entries}}})


def configure_claude(models, default, base, key):
    root = base[:-3] if base.endswith("/v1") else base
    mid = default["id"]
    env = {
        "ANTHROPIC_BASE_URL": root,
        "ANTHROPIC_AUTH_TOKEN": key,
        "ANTHROPIC_MODEL": mid,
        "ANTHROPIC_DEFAULT_OPUS_MODEL": mid,
        "ANTHROPIC_DEFAULT_SONNET_MODEL": mid,
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": mid,
        "ANTHROPIC_SMALL_FAST_MODEL": mid,
        "CLAUDE_CODE_SUBAGENT_MODEL": mid,
        "CLAUDE_CODE_MAX_OUTPUT_TOKENS": str(default["output"]),
        "CLAUDE_CODE_MAX_CONTEXT_TOKENS": str(default["context"]),
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "DISABLE_AUTOUPDATER": "1",
        "DISABLE_TELEMETRY": "1",
        "DISABLE_ERROR_REPORTING": "1",
        "DISABLE_BUG_COMMAND": "1",
        "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "1",
        "CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL": "1",
    }
    settings_path = HOME / ".claude/settings.json"
    settings = read_json(settings_path)
    settings.update({
        "permissions": {**settings.get("permissions", {}), "defaultMode": "bypassPermissions"},
        "skipDangerousModePermissionPrompt": True,
        "autoUpdates": False,
        "env": {**settings.get("env", {}), **env},
    })
    write_json(settings_path, settings)
    state_path = HOME / ".claude.json"
    state = read_json(state_path)
    projects = state.setdefault("projects", {})
    for p in ("/workspace", str(HOME)):
        projects.setdefault(p, {}).update(hasTrustDialogAccepted=True, hasCompletedProjectOnboarding=True)
    state.update(hasCompletedOnboarding=True, bypassPermissionsModeAccepted=True, autoUpdates=False,
                 theme=state.get("theme", "dark"), hasSeenTasksHint=True)
    write_json(state_path, state)
    agent_env("claude", env)


def configure_codex(models, default, base, key):
    toml = [
        "# written by yolo configure — do not edit; change .env or the fleet repo",
        f'model = "{default["id"]}"',
        'model_provider = "vllm"',
        'approval_policy = "never"',
        'sandbox_mode = "danger-full-access"',
        "check_for_update_on_startup = false",
        f"model_context_window = {default['context']}",
        f'model_reasoning_effort = "{ {"xhigh": "high", "off": "minimal"}.get(effort(), effort()) }"',
        "hide_agent_reasoning = false",
        "",
        "[analytics]",
        "enabled = false",
        "",
        "[feedback]",
        "enabled = false",
        "",
        "[history]",
        'persistence = "save-all"',
        "",
        "[model_providers.vllm]",
        'name = "SEC09 vLLM"',
        f'base_url = "{base}"',
        'env_key = "YOLO_CODEX_API_KEY"',
        'wire_api = "responses"',
        "",
        '[projects."/workspace"]',
        'trust_level = "trusted"',
        "",
    ]
    write(HOME / ".codex/config.toml", "\n".join(toml))
    agent_env("codex", {"YOLO_CODEX_API_KEY": key, "CODEX_HOME": str(HOME / ".codex")})


def configure_qwen(models, default, base, key):
    path = HOME / ".qwen/settings.json"
    s = read_json(path)
    s.setdefault("security", {}).setdefault("auth", {})["selectedType"] = "openai"
    s.setdefault("model", {})["name"] = default["id"]
    s.setdefault("privacy", {})["usageStatisticsEnabled"] = False
    g = s.setdefault("general", {})
    g.update(enableAutoUpdate=False, disableAutoUpdate=True, disableUpdateNag=True)
    s.setdefault("tools", {})["approvalMode"] = "yolo"
    s.setdefault("ui", {}).setdefault("hideTips", True)
    s.setdefault("context", {})["fileName"] = ["QWEN.md", "AGENTS.md"]
    write_json(path, s)
    agent_env("qwen", {"OPENAI_BASE_URL": base, "OPENAI_API_KEY": key, "OPENAI_MODEL": default["id"],
                       "QWEN_CODE_SUPPRESS_YOLO_WARNING": "1"})


def configure_crush(models, default, base, key):
    entries = [{"id": m["id"], "name": m["id"], "context_window": m["context"],
                "default_max_tokens": m["output"], "can_reason": m["reasoning"],
                "supports_attachments": m["vision"]} for m in models]
    cfg = {
        "$schema": "https://charm.land/crush.json",
        "providers": {"vllm": {"name": "SEC09 vLLM", "type": "openai-compat", "base_url": base,
                               "api_key": key, "models": entries}},
        "models": {"large": {"model": default["id"], "provider": "vllm"},
                   "small": {"model": default["id"], "provider": "vllm"}},
        "options": {"disable_metrics": True, "disable_provider_auto_update": True,
                    "context_paths": [str(Y / "AGENTS.md")]},
        "permissions": {"allowed_tools": ["view", "ls", "grep", "glob", "edit", "write", "multiedit",
                                          "bash", "fetch", "download", "agent", "diagnostics",
                                          "sourcegraph", "todos", "job_output", "job_kill"]},
    }
    write_json(HOME / ".config/crush/crush.json", cfg)
    agent_env("crush", {"CRUSH_DISABLE_METRICS": "1", "CRUSH_DISABLE_PROVIDER_AUTO_UPDATE": "1"})


def configure_goose(models, default, base, key):
    root = base[:-3] if base.endswith("/v1") else base
    yaml = "\n".join([
        "# written by yolo configure — do not edit; change .env or the fleet repo",
        "GOOSE_PROVIDER: openai",
        f"GOOSE_MODEL: {json.dumps(default['id'])}",
        f"OPENAI_HOST: {json.dumps(root)}",
        "OPENAI_BASE_PATH: v1/chat/completions",
        "GOOSE_MODE: auto",
        "GOOSE_TELEMETRY_ENABLED: false",
        f"GOOSE_CONTEXT_LIMIT: {default['context']}",
        "extensions:",
        "  developer:",
        "    enabled: true",
        "    name: developer",
        "    type: builtin",
        "    timeout: 300",
        "    bundled: true",
        "",
    ])
    write(HOME / ".config/goose/config.yaml", yaml)
    agent_env("goose", {"OPENAI_API_KEY": key, "GOOSE_DISABLE_KEYRING": "1",
                        "GOOSE_TELEMETRY_ENABLED": "false", "OTEL_SDK_DISABLED": "true"})


AGENTS = {
    "opencode": configure_opencode, "claude": configure_claude, "qwen": configure_qwen,
    "pi": configure_pi, "crush": configure_crush, "goose": configure_goose, "codex": configure_codex,
}


def configure_vscode_agents(models, default, base, key):
    """Kilo Code (the VS Code chat panel) imports a settings export on start-up;
    vscode_agents writes it."""
    from vscode_agents import seed  # noqa: PLC0415 - optional module
    seed(HOME, default, base, key)


# =============================================================================
# 4. git
# =============================================================================
def configure_git() -> dict:
    def git(*args):
        subprocess.run(["git", "config", "--global", *args], check=False)

    git("user.name", E("GIT_NAME", "YOLO Agent"))
    git("user.email", E("GIT_EMAIL", "yoloagent@gmail.com"))
    git("init.defaultBranch", "main")
    git("pull.ff", "only")
    git("safe.directory", "*")
    git("credential.helper", "store")
    git("core.editor", "vim")
    host, token = E("GITEA_HOST"), E("GITEA_TOKEN")
    info = {"git_ready": False, "gitea_user": None}
    if not (host and token):
        return info
    user = E("GITEA_USER")
    if not user and tcp_ok(host):
        try:
            user = gitea_api("/user", token).get("login")
        except (OSError, ValueError):
            user = None
    user = user or "yolo-agent"
    proto = E("GITEA_PROTOCOL", "http")
    write(HOME / ".git-credentials", f"{proto}://{user}:{token}@{host}\n")
    info.update(git_ready=True, gitea_user=user)
    return info


# =============================================================================
# 5. code-server
# =============================================================================
def link_extensions(src: Path, ext: Path, tier: str) -> None:
    """Make the image's extensions visible in the person's extensions folder as
    symlinks (nothing is copied, so the home volume stays small and an image
    upgrade updates them at once). Extensions the person installed are kept.
    The core tier has no clangd or cmake, so those extensions are left out:
    they would offer to download the tools and fail (no internet)."""
    skip = ("llvm-vs-code-extensions.vscode-clangd-", "ms-vscode.cmake-tools-", "twxs.cmake-")         if tier == "core" else ()
    ext.mkdir(parents=True, exist_ok=True)
    image = {p.name for p in src.iterdir() if p.is_dir() and not p.name.startswith(skip)}
    for p in ext.iterdir():
        target = os.readlink(p) if p.is_symlink() else ""
        if target.startswith(str(src) + "/") and Path(target).name not in image:
            p.unlink()                                  # old version or skipped
        elif not p.is_symlink() and p.is_dir() and p.name in image:
            shutil.rmtree(p, ignore_errors=True)        # copy from yolo 3.0 betas
    for name in image:
        link = ext / name
        if not link.is_symlink():
            link.symlink_to(src / name)
    # The registry (extensions.json): the person's own entries plus the image's,
    # pointing at the links.
    reg = ext / "extensions.json"
    try:
        mine = json.loads(reg.read_text()) if reg.is_file() else []
    except ValueError:
        mine = []
    try:
        theirs = json.loads((src / "extensions.json").read_text())
    except (OSError, ValueError):
        theirs = []
    image_ids = {e.get("identifier", {}).get("id", "").lower() for e in theirs
                 if e.get("relativeLocation") in image}
    entries = [e for e in mine if (ext / (e.get("relativeLocation") or "?")).exists()
               and not (ext / e["relativeLocation"]).is_symlink()
               and e.get("identifier", {}).get("id", "").lower() not in image_ids]
    for e in theirs:
        rel = e.get("relativeLocation")
        if rel in image:
            e = json.loads(json.dumps(e))
            e.setdefault("location", {"$mid": 1, "scheme": "file"})["path"] = str(ext / rel)
            entries.append(e)
    write(reg, json.dumps(entries), 0o644)


def configure_code_server() -> None:
    data = HOME / ".local/share/code-server"
    src = Path("/opt/vscode-extensions")
    if src.is_dir():
        link_extensions(src, data / "extensions", os.environ.get("YOLO_TIER", ""))
    user = data / "User"
    base_settings = read_json(OPT / "vscode/settings.json")
    base_settings.update(read_json(Y / "vscode-extra.json"))
    settings_path = user / "settings.json"
    current = read_json(settings_path)
    managed = set(current.pop("yolo.managedKeys", []))
    # Keys the person set themselves stay; keys yolo set before are refreshed.
    merged = {k: v for k, v in current.items() if k not in managed}
    for k, v in base_settings.items():
        merged.setdefault(k, v)
    merged["yolo.managedKeys"] = sorted(k for k in base_settings if merged.get(k) == base_settings[k])
    write_json(settings_path, merged, 0o644)


# =============================================================================
# 6. instructions and skills
# =============================================================================
def configure_instructions(fleet: Path) -> None:
    parts = [(OPT / "AGENTS.md").read_text()] if (OPT / "AGENTS.md").is_file() else []
    if (fleet / "AGENTS.md").is_file():
        parts.append("\n\n# Team instructions (fleet repo)\n\n" + (fleet / "AGENTS.md").read_text())
    person = E("YOLO_PERSON")
    if person and (fleet / "people" / f"{person}.md").is_file():
        parts.append("\n\n# Personal instructions\n\n" + (fleet / "people" / f"{person}.md").read_text())
    text = "".join(parts)
    write(Y / "AGENTS.md", text, 0o644)
    for target in (HOME / ".claude/CLAUDE.md", HOME / ".codex/AGENTS.md", HOME / ".qwen/QWEN.md",
                   HOME / ".pi/agent/AGENTS.md", HOME / ".config/goose/.goosehints",
                   HOME / ".config/opencode/AGENTS.md", HOME / ".config/kilo/AGENTS.md"):
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink() or target.exists():
            target.unlink()
        target.symlink_to(Y / "AGENTS.md")


def configure_skills() -> list[str]:
    r = subprocess.run([sys.executable, "-I", "-B", str(OPT / "lib/skills.py"), "apply", "--quiet"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        warn("skills: " + (r.stderr.strip() or r.stdout.strip()))
    return read_json(Y / "skills/enabled.json", []) if (Y / "skills/enabled.json").exists() else []


# =============================================================================
# login
# =============================================================================
def login(token: str | None) -> int:
    host = E("GITEA_HOST")
    if not token:
        if not sys.stdin.isatty():
            warn("usage: yolo login <token>")
            return 2
        print(f"Gitea access token for {host} (Settings → Applications → Generate token,")
        print("with repository read/write and issue/PR write):")
        token = getpass.getpass("token: ").strip()
    if not token:
        return 2
    try:
        who = gitea_api("/user", token).get("login")
    except urllib.error.HTTPError as exc:
        warn(f"Gitea rejected the token (HTTP {exc.code})")
        return 1
    except OSError as exc:
        warn(f"cannot reach Gitea at {host}: {exc}; saving the token anyway")
        who = None
    write(Y / "secrets.env", f"GITEA_TOKEN={shell_quote(token)}\n")
    print(f"Saved. Gitea user: {who or 'unknown (not verified)'}. Reconfiguring…")
    os.execv("/bin/bash", ["bash", "-c", ". /opt/yolo/lib/env.sh; exec /opt/yolo/bin/yolo configure"])
    return 0


# =============================================================================
# main
# =============================================================================
def main() -> int:
    global QUIET
    ap = argparse.ArgumentParser(prog="yolo configure")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--sync", action="store_true", help="always sync the fleet repo, then reconfigure")
    ap.add_argument("--no-sync", action="store_true")
    ap.add_argument("--login", nargs="?", const="", default=None)
    args = ap.parse_args()
    QUIET = args.quiet

    if args.login is not None:
        return login(args.login or None)

    Y.mkdir(parents=True, exist_ok=True)
    os.chmod(Y, 0o700)
    lock = open(Y / ".configure.lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)

    sync = {"fleet": "skipped", "skills": "skipped"}
    if not args.no_sync:
        sync = sync_repos()
        if sync.get("fleet_changed"):
            # fleet.env may have changed: reload settings in a fresh shell.
            lock.close()
            log("fleet repo updated; reloading settings")
            os.execv("/bin/bash", ["bash", "-c",
                     ". /opt/yolo/lib/env.sh; exec /opt/pyenv/bin/python -I -B /opt/yolo/lib/configure.py --no-sync"
                     + (" --quiet" if QUIET else "")])
    else:
        prev = read_json(Y / "state.json").get("fleet") or {}
        sync = {"fleet": prev.get("fleet", "skipped"), "skills": prev.get("skills", "skipped")}

    models, default, source = pick_models()
    base, key = endpoint(), api_key()
    done, failed = [], []
    for name, fn in AGENTS.items():
        try:
            fn(models, default, base, key)
            done.append(name)
        except Exception as exc:  # noqa: BLE001 - one agent must not stop the rest
            failed.append(name)
            warn(f"{name}: {exc}")
    sys.path.insert(0, str(OPT / "lib"))
    try:
        configure_vscode_agents(models, default, base, key)
    except Exception as exc:  # noqa: BLE001
        warn(f"vscode agents: {exc}")
    git = configure_git()
    try:
        configure_code_server()
    except Exception as exc:  # noqa: BLE001
        warn(f"code-server: {exc}")
    configure_instructions(Y / "fleet")
    skills = configure_skills()

    state = {
        "ts": time.time(), "model": default["id"], "models": [m["id"] for m in models],
        "model_source": source, "endpoint": base, "agents": done, "agents_failed": failed,
        "fleet": sync, "skills": skills, **git,
    }
    write_json(Y / "state.json", state, 0o644)
    src = {"live": "", "cache": " (server unreachable; using the last known list)",
           "none": " (server unreachable; no model list yet)"}[source]
    log(f"{len(done)} agents → {base} model {default['id']}{src}; git "
        + (f"ready as {git['gitea_user']}" if git["git_ready"] else "has no Gitea token (yolo login)"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
