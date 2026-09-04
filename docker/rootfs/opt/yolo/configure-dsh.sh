#!/usr/bin/env bash
#
# Point DeepSeek Harness at the same local vLLM endpoint as the other agents.
# Does not set DEEPSEEK_API_KEY. Idempotent; writes $DSH_HOME/settings.yaml.
set -euo pipefail
umask 077
: "${HOME:=/home/agent}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

VLLM_BASE_URL="${VLLM_BASE_URL:-}"
VLLM_MODEL="${VLLM_MODEL:-}"
VLLM_API_KEY="${VLLM_API_KEY:-local}"
VLLM_CONTEXT="${VLLM_CONTEXT:-262144}"
VLLM_REASONING_EFFORT="${VLLM_REASONING_EFFORT:-xhigh}"
case "$VLLM_REASONING_EFFORT" in
  high) VLLM_REASONING_EFFORT="xhigh" ;;
  off|low|medium|xhigh) ;;
  *) VLLM_REASONING_EFFORT="xhigh" ;;
esac

[[ -n "$VLLM_BASE_URL" && -n "$VLLM_MODEL" ]] || {
  echo "configure-dsh: set VLLM_BASE_URL and VLLM_MODEL in yolo.env" >&2
  exit 1
}

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
          contextWindow: $VLLM_CONTEXT
          reasoningEfforts:
            off:
            low: low
            medium: medium
            xhigh: xhigh
YAMLEOF
chmod 600 "$cfg"
echo "configure-dsh: $cfg -> $VLLM_MODEL @ $VLLM_BASE_URL (reasoning $VLLM_REASONING_EFFORT)"
