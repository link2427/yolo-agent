#!/usr/bin/env bash
set -euxo pipefail

: "${OPENCODE_VERSION:?}"
: "${GOOSE_VERSION:?}"
: "${PI_VERSION:?}"
: "${AIDER_VERSION:?}"
: "${PRIME_AGENT_VERSION:?}"
: "${DSH_VERSION:?}"
: "${OPENHANDS_VERSION:?}"

test "$(id -un)" = agent
test "$(id -u)" = 10001
opencode --version 2>&1 | grep -Fq "$OPENCODE_VERSION"
goose --version 2>&1 | grep -Fq "$GOOSE_VERSION"
pi --version 2>&1 | grep -Fq "$PI_VERSION"
aider --version 2>&1 | grep -Fq "$AIDER_VERSION"
prime-agent --version 2>&1 | grep -Fq "$PRIME_AGENT_VERSION"
dsh --version 2>&1 | grep -Fxq "$DSH_VERSION"
dsh --profile headless --dump-default-config >/dev/null

# OpenHands (current CLI, uv-managed Python 3.12 venv)
/opt/openhands/bin/openhands --version | grep -Fq "$OPENHANDS_VERSION"
node --version 2>&1 | grep -q '^v22'
python3 --version 2>&1 | grep -q '3\.11'

for tool in git curl jq rg fdfind shellcheck tmux vi unzip xz tini socat dsh; do
  command -v "$tool" >/dev/null
done

test -w /workspace
test -w /home/agent
test -w /tmp
test ! -w /usr
test ! -w /opt
test "$(find / -xdev -type f -perm /6000 2>/dev/null | wc -l)" -eq 0

test -x "$HOME/.prime/agent/kernel-venv/bin/python"
"$HOME/.prime/agent/kernel-venv/bin/python" -c 'import rlm, dill, numpy'
test -x "$HOME/.local/bin/uv"
jq -e '.telemetry.enabled == false' "$HOME/.prime/agent/settings.json" >/dev/null
test "$DSH_HOME" = "$HOME/.dsh"

jq -e '.permission == "allow"' "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.defaultProjectTrust == "always"' "$HOME/.pi/agent/settings.json" >/dev/null
grep -q '^GOOSE_MODE: auto' "$HOME/.config/goose/config.yaml"
grep -q '^yes-always: true' "$HOME/.aider.conf.yml"

VLLM_BASE_URL=http://127.0.0.1:8000/v1 \
VLLM_MODEL=Qwen/Qwen3.8-27B \
VLLM_CONTEXT=262144 \
VLLM_REASONING_EFFORT=xhigh \
  /opt/yolo/configure-agents.sh

jq -e '.enabled_providers == ["vllm"]' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.model == "vllm/Qwen/Qwen3.8-27B"' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].limit.context == 262144' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].reasoning == true' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].options.reasoningEffort == "xhigh"' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.provider.vllm.models["Qwen/Qwen3.8-27B"].variants.xhigh.reasoningEffort == "xhigh"' \
  "$HOME/.config/opencode/opencode.json" >/dev/null
jq -e '.defaultProvider == "vllm"' "$HOME/.pi/agent/settings.json" >/dev/null
jq -e '.defaultThinkingLevel == "xhigh"' "$HOME/.pi/agent/settings.json" >/dev/null
jq -e '.providers.vllm.compat.thinkingFormat == "qwen-chat-template"' \
  "$HOME/.pi/agent/models.json" >/dev/null
jq -e '.providers.vllm.models[0].reasoning == true' \
  "$HOME/.pi/agent/models.json" >/dev/null
jq -e '.providers.vllm.models[0].contextWindow == 262144' \
  "$HOME/.pi/agent/models.json" >/dev/null
jq -e '.defaultProvider == "vllm"' "$HOME/.prime/agent/settings.json" >/dev/null
jq -e '.providers.vllm.compat.thinkingFormat == "qwen-chat-template"' \
  "$HOME/.prime/agent/models.json" >/dev/null
jq -e '.providers.vllm.models[0].contextWindow == 262144' \
  "$HOME/.prime/agent/models.json" >/dev/null
jq -e '.models[0].context_limit == 262144' \
  "$HOME/.config/goose/custom_providers/vllm.json" >/dev/null
grep -q '^GOOSE_PROVIDER: vllm' "$HOME/.config/goose/config.yaml"
grep -q '^OPENAI_REASONING_EFFORT: xhigh' "$HOME/.config/goose/config.yaml"
jq -e '.["Qwen/Qwen3.8-27B"].context_window == 262144' \
  "$HOME/.aider-model-metadata.json" >/dev/null
grep -q '^reasoning-effort: xhigh' "$HOME/.aider.conf.yml"
jq -e '.llm.reasoning_effort == "xhigh"' \
  "$HOME/.openhands/agent_settings.json" >/dev/null
jq -e '.llm.extra_body.chat_template_kwargs.enable_thinking == true' \
  "$HOME/.openhands/agent_settings.json" >/dev/null

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
