#!/usr/bin/env bash
#
# Write OpenHands (CLI) agent settings pointing at the same local vLLM
# endpoint that configure-agents.sh uses, so one yolo.env configures every
# harness. Idempotent; secrets stay in the $HOME volume (mode 600).
set -euo pipefail
umask 077
: "${HOME:=/home/agent}"

VLLM_BASE_URL="${VLLM_BASE_URL:-}"
VLLM_MODEL="${VLLM_MODEL:-}"
VLLM_API_KEY="${VLLM_API_KEY:-local}"
VLLM_REASONING_EFFORT="${VLLM_REASONING_EFFORT:-xhigh}"
case "$VLLM_REASONING_EFFORT" in
  high) VLLM_REASONING_EFFORT="xhigh" ;;
  off|low|medium|xhigh) ;;
  *) VLLM_REASONING_EFFORT="xhigh" ;;
esac
if [[ "$VLLM_REASONING_EFFORT" == "off" ]]; then
  ENABLE_THINKING=false
else
  ENABLE_THINKING=true
fi

[[ -n "$VLLM_BASE_URL" && -n "$VLLM_MODEL" ]] || {
  echo "configure-openhands: set VLLM_BASE_URL and VLLM_MODEL in yolo.env" >&2
  exit 1
}

mkdir -p "$HOME/.openhands"
cfg="$HOME/.openhands/agent_settings.json"
if [[ "$ENABLE_THINKING" == "true" ]]; then
  cat > "$cfg" <<JSONEOF
{
  "llm": {
    "model": "openai/$VLLM_MODEL",
    "base_url": "$VLLM_BASE_URL",
    "api_key": "$VLLM_API_KEY",
    "reasoning_effort": "$VLLM_REASONING_EFFORT",
    "extra_body": {
      "chat_template_kwargs": {
        "enable_thinking": true,
        "preserve_thinking": true
      },
      "reasoning_effort": "$VLLM_REASONING_EFFORT"
    }
  }
}
JSONEOF
else
  cat > "$cfg" <<JSONEOF
{
  "llm": {
    "model": "openai/$VLLM_MODEL",
    "base_url": "$VLLM_BASE_URL",
    "api_key": "$VLLM_API_KEY",
    "extra_body": {
      "chat_template_kwargs": {
        "enable_thinking": false
      }
    }
  }
}
JSONEOF
fi
chmod 600 "$cfg"
echo "configure-openhands: $cfg -> openai/$VLLM_MODEL @ $VLLM_BASE_URL (reasoning $VLLM_REASONING_EFFORT)"
