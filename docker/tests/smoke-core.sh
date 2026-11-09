#!/usr/bin/env bash
#
# yolo-agent core smoke suite. Runs in every tier, as the agent user, with no
# lab network: a stub model server on 127.0.0.1 stands in for SEC09.
set -euxo pipefail

# --- identity and filesystem ------------------------------------------------
test "$(id -u)" = 10001
test -w /workspace && test -w /home/agent && test -w /tmp
test ! -w /usr && test ! -w /opt && test ! -w /etc
test "$(find / -xdev -type f -perm /6000 2>/dev/null | wc -l)" -eq 0

# --- runtimes and base tools -------------------------------------------------
node --version | grep -q '^v22'
npm --version >/dev/null
python3 --version 2>&1 | grep -q '3\.11'
test "$(readlink -f "$(command -v python3)")" = "$(readlink -f /opt/pyenv/bin/python3)"
python3 -c 'import requests, httpx, yaml, pytest, numpy, pydantic, rich, lxml'
for t in git git-lfs curl jq rg fdfind shellcheck tmux vi unzip xz tini socat file rsync sqlite3 patch \
         code-server ttyd filebrowser yolo yolo-gitea; do
  command -v "$t" >/dev/null
done

# --- agents: every wrapper runs, offline ------------------------------------
cat /opt/agents/VERSIONS.txt
for a in opencode claude qwen pi crush goose codex; do
  test "$(command -v "$a")" = "/opt/yolo/bin/$a"
  ver="$(awk -v a="$a" '$1==a{print $2}' /opt/agents/VERSIONS.txt)"
  test -n "$ver"
  out="$(timeout 60 "$a" --version 2>&1)" || { echo "$a --version failed: $out" >&2; exit 1; }
  printf '%s\n' "$out" | grep -Fq "$ver" || { echo "$a: expected $ver, got: $out" >&2; exit 1; }
done

# --- stub model server --------------------------------------------------------
here="$(cd "$(dirname "$0")" && pwd)"
export STUB_LOG=/tmp/stub-llm.jsonl
python3 "$here/stub-llm.py" 18000 & stub=$!
trap 'kill $stub 2>/dev/null || true; kill $(jobs -p) 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -fs http://127.0.0.1:18000/v1/models >/dev/null && break; sleep 0.5; done

# --- configure ----------------------------------------------------------------
export VLLM_BASE_URL=http://127.0.0.1:18000/v1 GITEA_HOST=127.0.0.1:9 YOLO_PERSON=smoke
yolo configure
S="$HOME/.yolo/state.json"
jq -e '.model == "Qwen/Qwen3-Stub" and (.agents_failed | length) == 0' "$S"
for a in opencode pi claude codex qwen crush goose; do jq -e --arg a "$a" '.agents | index($a)' "$S" >/dev/null; done

O="$HOME/.config/opencode/opencode.json"
jq -e '.provider.vllm.options.baseURL == "http://127.0.0.1:18000/v1"' "$O"
jq -e '.provider.vllm.models["Qwen/Qwen3-Stub"].limit.context == 65536' "$O"
jq -e '.model == "vllm/Qwen/Qwen3-Stub"' "$O"
jq -e '.providers.vllm.models[0].id == "Qwen/Qwen3-Stub"' "$HOME/.pi/agent/models.json"
jq -e '.env.ANTHROPIC_BASE_URL == "http://127.0.0.1:18000" and .env.ANTHROPIC_MODEL == "Qwen/Qwen3-Stub"' \
  "$HOME/.claude/settings.json"
jq -e '.env.ANTHROPIC_AUTH_TOKEN == "yolo-smoke"' "$HOME/.claude/settings.json"
jq -e '.hasCompletedOnboarding == true' "$HOME/.claude.json"
grep -q 'base_url = "http://127.0.0.1:18000/v1"' "$HOME/.codex/config.toml"
jq -e '.model.name == "Qwen/Qwen3-Stub"' "$HOME/.qwen/settings.json"
jq -e '.providers.vllm.base_url == "http://127.0.0.1:18000/v1"' "$HOME/.config/crush/crush.json"
grep -q 'GOOSE_MODEL: "Qwen/Qwen3-Stub"' "$HOME/.config/goose/config.yaml"
test -L "$HOME/.claude/CLAUDE.md" && grep -q 'air-gapped' "$HOME/.claude/CLAUDE.md"
jq -e '.["kilo-code.new.model.modelID"] == "Qwen/Qwen3-Stub"' "$HOME/.local/share/code-server/User/settings.json"
jq -e '.provider.vllm.options.baseURL == "http://127.0.0.1:18000/v1"' "$HOME/.config/kilo/kilo.json"
test "$(find -L "$HOME/.local/share/code-server/extensions" -maxdepth 1 -mindepth 1 -type d | wc -l)" -ge 10

# Settings precedence: container env beats defaults; a second run is stable.
yolo configure >/dev/null
jq -e '.model == "Qwen/Qwen3-Stub"' "$S"

# Model server down: configure still writes configs from the cache and exits 0.
VLLM_BASE_URL=http://127.0.0.1:9/v1 yolo configure
jq -e '.model == "Qwen/Qwen3-Stub"' "$S"
yolo configure >/dev/null   # back to the stub

# --- every agent completes a real round trip through its generated config ---
cd /workspace
for cmd in "opencode run hello" "claude -p hello" "qwen -p hello" "pi -p hello" "crush run -q hello"            "goose run -t hello --no-session" "codex exec --skip-git-repo-check hello"; do
  # Crush drops its output when the whole stream arrives at once; the stub
  # paces its chunks (STUB_DELAY) for that, and each agent gets three tries.
  for _try in 1 2 3; do
    out="$(timeout 120 $cmd 2>&1 </dev/null)" || { echo "FAIL: $cmd"; printf '%s
' "$out" | tail -20; exit 1; }
    grep -q YOLO-STUB-OK <<<"$out" && break
  done
  grep -q YOLO-STUB-OK <<<"$out" || { echo "FAIL (no reply): $cmd"; printf '%s
' "$out" | tail -20; exit 1; }
  echo "ok: $cmd"
done
# Kilo Code (the VS Code panel) runs its bundled kilo CLI with ~/.config/kilo.
kilo="$(ls -d /opt/vscode-extensions/kilocode.kilo-code-*)/bin/kilo"
out="$(timeout 120 "$kilo" run hello 2>&1 </dev/null)"; grep -q YOLO-STUB-OK <<<"$out" || { echo "$out" | tail; exit 1; }
cd - >/dev/null
# Every request carried the person's key and the configured model.
jq -se 'all(.[]; .auth == "Bearer yolo-smoke" and .model == "Qwen/Qwen3-Stub")' "$STUB_LOG"

# --- skills -------------------------------------------------------------------
yolo skills list | grep -q yolo-airgap
for d in .claude/skills .agents/skills; do test -e "$HOME/$d/yolo-airgap/SKILL.md"; done
yolo skills enable pdf
test -e "$HOME/.claude/skills/pdf/SKILL.md"
yolo skills disable pdf
test ! -e "$HOME/.claude/skills/pdf"

# --- status ------------------------------------------------------------------
yolo status
yolo agents
yolo tools

# --- web services -------------------------------------------------------------
wait_http() { for _ in $(seq "${2:-60}"); do curl -fsS --max-time 5 -o /dev/null "$1" 2>/dev/null && return 0; sleep 1; done
              echo "no answer from $1" >&2; return 1; }
yolo serve home >/tmp/home.log 2>&1 &
yolo serve code >/tmp/code.log 2>&1 &
yolo serve term >/tmp/term.log 2>&1 &
yolo serve files >/tmp/files.log 2>&1 &
yolo serve chat >/tmp/chat.log 2>&1 &
wait_http http://127.0.0.1:8000/
curl -fsS --max-time 10 http://127.0.0.1:8000/api/status | jq -e '.model == "Qwen/Qwen3-Stub"'
wait_http http://127.0.0.1:8080/healthz || { cat /tmp/code.log; exit 1; }
wait_http http://127.0.0.1:7681/ || { cat /tmp/term.log; exit 1; }
wait_http http://127.0.0.1:8081/health || { cat /tmp/files.log; exit 1; }
wait_http http://127.0.0.1:4096/ 90 || { cat /tmp/chat.log; exit 1; }
curl -fsS --max-time 10 http://127.0.0.1:4096/ | grep -qi '<html' || { echo "opencode web served no UI" >&2; exit 1; }

# --- lab gateway, against the stub -------------------------------------------
UPSTREAM_URL=http://127.0.0.1:18000 LAB_DATA=/tmp/lab LAB_PORT=4000 SCRAPE_SECONDS=2 \
  yolo serve gateway >/tmp/gw.log 2>&1 &
wait_http http://127.0.0.1:4000/ || { cat /tmp/gw.log; exit 1; }
curl -fsS --max-time 10 http://127.0.0.1:4000/v1/models | jq -e '.data[0].id == "Qwen/Qwen3-Stub"'
curl -fsS --max-time 10 http://127.0.0.1:4000/api/live | jq -e 'type == "object"'
curl -fsS --max-time 10 http://127.0.0.1:4000/ | grep -q 'SEC09'

# --- bot module loads ---------------------------------------------------------
python3 -I -B -c 'import sys; sys.path.insert(0, "/opt/yolo/lib"); import bot; assert bot.cron_match("*/15 9-17 * * 1-5", __import__("datetime").datetime(2026, 11, 9, 9, 30))'

echo "smoke-core: OK (tier ${YOLO_TIER})"
