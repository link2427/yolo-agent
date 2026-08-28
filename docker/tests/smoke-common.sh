#!/usr/bin/env bash
set -euo pipefail

: "${OPENCODE_VERSION:?}"
: "${GOOSE_VERSION:?}"
: "${PI_VERSION:?}"
: "${AIDER_VERSION:?}"
: "${PRIME_AGENT_VERSION:?}"

test "$(id -un)" = agent
test "$(id -u)" = 10001
opencode --version | grep -Fq "$OPENCODE_VERSION"
goose --version | grep -Fq "$GOOSE_VERSION"
pi --version | grep -Fq "$PI_VERSION"
aider --version | grep -Fq "$AIDER_VERSION"
prime-agent --version 2>&1 | grep -Fq "$PRIME_AGENT_VERSION"
node --version | grep -q '^v22'
python3 --version | grep -q '3\.11'

for tool in git curl jq rg fdfind shellcheck tmux vim unzip xz tini; do
  command -v "$tool" >/dev/null
done

test -w /workspace
test -w /home/agent
test -w /tmp
test ! -w /usr
test ! -w /opt
test "$(find / -xdev -type f -perm /6000 2>/dev/null | wc -l)" -eq 0

test -x "$HOME/.prime/agent/kernel-venv/bin/python"
"$HOME/.prime/agent/kernel-venv/bin/python" -c 'import ipykernel, rlm'
test -x "$HOME/.local/bin/uv"
jq -e '.telemetry.enabled == false' "$HOME/.prime/agent/settings.json" >/dev/null

jq -e '.permission == "allow"' "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.defaultProjectTrust == "always"' "$HOME/.pi/agent/settings.json" >/dev/null
grep -q '^GOOSE_MODE: auto' "$HOME/.config/goose/config.yaml"
grep -q '^yes-always: true' "$HOME/.aider.conf.yml"

VLLM_BASE_URL=http://127.0.0.1:8000/v1 \
VLLM_MODEL=Qwen/Qwen3-Coder-30B-AWQ \
VLLM_CONTEXT=262144 \
  /opt/yolo/configure-agents.sh

jq -e '.provider.openai.models["Qwen/Qwen3-Coder-30B-AWQ"].limit.context == 262144' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.providers.vllm.models[0].contextWindow == 262144' \
  "$HOME/.pi/agent/models.json" >/dev/null
jq -e '.providers.vllm.models[0].contextWindow == 262144' \
  "$HOME/.prime/agent/models.json" >/dev/null
jq -e '.models[0].context_limit == 262144' \
  "$HOME/.config/goose/custom_providers/vllm.json" >/dev/null
jq -e '.["Qwen/Qwen3-Coder-30B-AWQ"].context_window == 262144' \
  "$HOME/.aider-model-metadata.json" >/dev/null

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

echo "common smoke tests passed"
