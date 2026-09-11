#!/usr/bin/env bash
#
# yolo-agent base image smoke suite.
#
# Runs inside the image as the agent user during `docker buildx bake`
# (Dockerfile target `test`). It is the build gate: if an agent pin, a Python
# package, or a generated config drifts, the build fails here instead of on the
# offline host.
#
set -euxo pipefail

: "${OPENCODE_VERSION:?}"
: "${PI_VERSION:?}"
: "${DSH_VERSION:?}"
: "${CODE_SERVER_VERSION:?}"
: "${TTYD_VERSION:?}"

# --- identity and filesystem layout -----------------------------------------
test "$(id -un)" = agent
test "$(id -u)" = 10001

test -w /workspace
test -w /home/agent
test -w /tmp
test ! -w /usr
test ! -w /opt
test "$(find / -xdev -type f -perm /6000 2>/dev/null | wc -l)" -eq 0

# --- the three agents --------------------------------------------------------
# Each check reports the actual output on failure. A silent grep failure here is
# very hard to debug from CI logs: these all run as uid 10001, while the install
# steps that created them ran as root, so a permission or PATH problem shows up
# only at this point.
check_version() { # $1=command  $2=expected version output
  local out
  if ! out="$("$1" --version 2>&1)"; then
    echo "ERROR: '$1 --version' failed as $(id -un) (uid $(id -u)):" >&2
    printf '%s\n' "$out" >&2
    echo "  which $1: $(command -v "$1" || echo NOT-ON-PATH)" >&2
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -Fq "$2"; then
    echo "ERROR: '$1 --version' did not report '$2'. Output was:" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
}

# DeepSeek Harness is reached through a generated wrapper, so assert on the
# pieces it needs rather than only on the version string: the wrapper, the entry
# point it execs, and the node binary that runs it. All three were the cause of a
# build failure at least once.
dsh_entry="/opt/deepseek-harness/node_modules/@deepseek-ai/dsh/lib/bin.js"
test -x "$(command -v node)"
test -r "$dsh_entry" || { echo "ERROR: dsh entry point not readable: $dsh_entry" >&2; ls -la "$dsh_entry" >&2 || true; exit 1; }
test -r /usr/local/bin/dsh || { echo "ERROR: dsh wrapper not present" >&2; exit 1; }
"$(command -v node)" -e 'process.exit(0)' || { echo "ERROR: node cannot execute as $(id -un)" >&2; exit 1; }
"$(command -v node)" "$dsh_entry" --version >/dev/null 2>&1 \
  || { echo "ERROR: the dsh entry point itself fails when run directly as $(id -un):" >&2; "$(command -v node)" "$dsh_entry" --version 2>&1 | head -20 >&2; exit 1; }

check_version opencode "$OPENCODE_VERSION"
check_version pi "$PI_VERSION"
check_version dsh "$DSH_VERSION"
dsh --profile headless --dump-default-config >/dev/null

# The agents that were deliberately removed must not reappear.
for gone in goose aider prime-agent openhands; do
  if command -v "$gone" >/dev/null 2>&1; then
    echo "ERROR: '$gone' should not be installed in this image" >&2
    exit 1
  fi
done

# --- web IDE -----------------------------------------------------------------
code-server --version | grep -q "$CODE_SERVER_VERSION"
ttyd --version | grep -q "$TTYD_VERSION"
# 19 declared extensions, 21 entries once VS Code adds the dependency closure.
test "$(find "$HOME/.local/share/code-server/extensions" -maxdepth 1 -mindepth 1 | wc -l)" -ge 19

# --- runtimes and common tools ----------------------------------------------
node --version 2>&1 | grep -q '^v22'
npm --version >/dev/null
python3 --version 2>&1 | grep -q '3\.11'

for tool in git curl jq rg fdfind shellcheck tmux vi unzip xz tini socat file; do
  command -v "$tool" >/dev/null
done

# --- one Python 3.11 environment, many packages ------------------------------
test -x /opt/pyenv/bin/python3
test "$(readlink -f "$(command -v python3)")" = "$(readlink -f /opt/pyenv/bin/python3)"
test "$VIRTUAL_ENV" = /opt/pyenv
/opt/pyenv/bin/python - <<'PY'
import sys
assert sys.version_info[:2] == (3, 11), sys.version
import requests, httpx, yaml, pytest, numpy, pydantic, rich, typer, lxml  # noqa: F401
print("python env OK:", sys.version.split()[0])
PY

# There must be no second interpreter environment hiding in the image.
test ! -d /opt/openhands
test ! -d /opt/aider-venv
test ! -d /opt/uv-python
test ! -d "$HOME/.prime"

# --- agent configuration (idempotent script, real endpoint values) ----------
VLLM_BASE_URL=http://127.0.0.1:8000/v1 \
VLLM_MODEL=Qwen/Qwen3.8-27B \
VLLM_CONTEXT=262144 \
VLLM_REASONING_EFFORT=xhigh \
  /opt/yolo/configure-agents.sh

jq -e '.permission == "allow"' "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.enabled_providers == ["vllm"]' "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.model == "vllm/Qwen/Qwen3.8-27B"' "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].limit.context == 262144' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].reasoning == true' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].options.reasoningEffort == "xhigh"' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].variants.xhigh.reasoningEffort == "xhigh"' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.options.baseURL == "http://127.0.0.1:8000/v1"' \
  "$HOME/.config/opencode/opencode.json" >/dev/null

jq -e '.defaultProjectTrust == "always"' "$HOME/.pi/agent/settings.json" >/dev/null
jq -e '.enableInstallTelemetry == false' "$HOME/.pi/agent/settings.json" >/dev/null
jq -e '.defaultProvider == "vllm"' "$HOME/.pi/agent/settings.json" >/dev/null
jq -e '.defaultThinkingLevel == "xhigh"' "$HOME/.pi/agent/settings.json" >/dev/null
jq -e '.providers.vllm.compat.thinkingFormat == "qwen-chat-template"' \
  "$HOME/.pi/agent/models.json" >/dev/null
jq -e '.providers.vllm.models[0].reasoning == true' "$HOME/.pi/agent/models.json" >/dev/null
jq -e '.providers.vllm.models[0].contextWindow == 262144' "$HOME/.pi/agent/models.json" >/dev/null

grep -q 'id: Qwen/Qwen3.8-27B' "$HOME/.dsh/settings.yaml"
grep -q 'thinkingFormat: qwen-chat-template' "$HOME/.dsh/settings.yaml"
grep -q 'contextWindow: 262144' "$HOME/.dsh/settings.yaml"
grep -q 'xhigh: xhigh' "$HOME/.dsh/settings.yaml"

# The DeepSeek cloud provider must stay empty: no key, no cloud models.
grep -q 'thinking: disabled' "$HOME/.dsh/settings.yaml"
test -z "${DEEPSEEK_API_KEY:-}"

# --- git configuration (token and SSH modes) --------------------------------
rm -f "$HOME/.git-credentials"
GITEA_HOST=server4:3000 GITEA_USER=agent GITEA_TOKEN=testtoken123 \
  /opt/yolo/configure-git.sh >/dev/null
grep -q testtoken123 "$HOME/.git-credentials"
test "$(stat -c %a "$HOME/.git-credentials")" = 600

rm -rf "$HOME/.ssh"
GITEA_HOST=server4:3000 GIT_SSH=1 GITEA_SSH_PORT=2222 \
  /opt/yolo/configure-git.sh >/dev/null
test -f "$HOME/.ssh/id_ed25519"
test -f "$HOME/.ssh/id_ed25519.pub"
grep -q 'Port 2222' "$HOME/.ssh/config"
test "$(stat -c %a "$HOME/.ssh/id_ed25519")" = 600

# --- browser surfaces actually serve HTTP -----------------------------------
wait_http() { # $1=url  $2=attempts
  local url="$1" tries="$2" i
  for ((i = 0; i < tries; i++)); do
    curl -fsS -o /dev/null "$url" 2>/dev/null && return 0
    sleep 2
  done
  return 1
}

code-server --bind-addr 127.0.0.1:8080 --auth none --disable-telemetry \
  >/tmp/code-server.log 2>&1 &
cs_pid=$!
ok=0; wait_http http://127.0.0.1:8080/ 20 && ok=1
kill "$cs_pid" 2>/dev/null || true; wait "$cs_pid" 2>/dev/null || true
test "$ok" -eq 1

ttyd -p 7681 tmux new -A -s yolo-agent-test /bin/bash >/tmp/ttyd.log 2>&1 &
ttyd_pid=$!
ok=0; wait_http http://127.0.0.1:7681/ 10 && ok=1
kill "$ttyd_pid" 2>/dev/null || true; wait "$ttyd_pid" 2>/dev/null || true
test "$ok" -eq 1

# DeepSeek Harness web UI, reached through the relay launcher.
/opt/yolo/deepseek-web-start.sh >/tmp/dsh-web.log 2>&1 &
dsh_pid=$!
ok=0; wait_http http://127.0.0.1:3081/ 30 && ok=1
kill "$dsh_pid" 2>/dev/null || true; wait "$dsh_pid" 2>/dev/null || true
if [[ "$ok" -ne 1 ]]; then cat /tmp/dsh-web.log >&2; exit 1; fi

echo "base smoke tests passed"
