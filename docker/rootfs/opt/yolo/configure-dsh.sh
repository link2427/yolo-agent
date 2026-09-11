#!/usr/bin/env bash
#
# Point DeepSeek Harness at the same local vLLM endpoint as the other agents.
# Writes $DSH_HOME/settings.yaml. Idempotent.
#
# DeepSeek Harness deliberately listens on container loopback only; it is
# relayed to a published port by deepseek-web-start.sh.
#
# Does NOT set DEEPSEEK_API_KEY — a cloud key would put DeepSeek models back in
# the picker, and the host has no internet route anyway.
#
# Reads VLLM_BASE_URL / VLLM_MODEL / VLLM_API_KEY / VLLM_REASONING_EFFORT /
# VLLM_CONTEXT from the environment; configure-agents.sh exports them before
# calling this script, and it can also be run standalone.
#
set -euo pipefail
umask 077
: "${HOME:=/home/agent}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

VLLM_BASE_URL="${VLLM_BASE_URL:-}"
VLLM_MODEL="${VLLM_MODEL:-}"
VLLM_API_KEY="${VLLM_API_KEY:-local}"
VLLM_CONTEXT="${VLLM_CONTEXT:-}"
VLLM_REASONING_EFFORT="${VLLM_REASONING_EFFORT:-xhigh}"
case "$VLLM_REASONING_EFFORT" in
  high) VLLM_REASONING_EFFORT="xhigh" ;;
  off|low|medium|xhigh) ;;
  *) VLLM_REASONING_EFFORT="xhigh" ;;
esac

[[ -n "$VLLM_BASE_URL" && -n "$VLLM_MODEL" ]] || {
  echo "configure-dsh: set VLLM_BASE_URL and VLLM_MODEL in the environment" >&2
  exit 1
}

# Only emit a context window when one is explicitly configured; the harness
# catalog default is used otherwise.
CONTEXT_LINE=""
if [[ -n "$VLLM_CONTEXT" ]]; then
  CONTEXT_LINE="          contextWindow: $VLLM_CONTEXT"
fi

mkdir -p "$DSH_HOME"
cfg="$DSH_HOME/settings.yaml"
cat > "$cfg" <<YAMLEOF
# Written by configure-dsh.sh. Local vLLM only; do not add DEEPSEEK_API_KEY.
llm-deepseek:
  thinking: disabled
  models: []
llm-pi-ai:
  providers:
    vllm:
      displayName: vLLM (local)
      apiKeyEnv: VLLM_API_KEY
      api: openai-completions
      baseURL: $VLLM_BASE_URL
      reasoning: $VLLM_REASONING_EFFORT
      compat:
        supportsDeveloperRole: false
        thinkingFormat: qwen-chat-template
        maxTokensField: max_tokens
      models:
        - id: $VLLM_MODEL
          name: $VLLM_MODEL
$CONTEXT_LINE
          reasoningEfforts:
            off:
            low: low
            medium: medium
            xhigh: xhigh
YAMLEOF
chmod 600 "$cfg"
echo "configure-dsh: $cfg -> $VLLM_MODEL @ $VLLM_BASE_URL (reasoning $VLLM_REASONING_EFFORT)"
