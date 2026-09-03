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

[[ -n "$VLLM_BASE_URL" && -n "$VLLM_MODEL" ]] || {
  echo "configure-openhands: set VLLM_BASE_URL and VLLM_MODEL in yolo.env" >&2
  exit 1
}

mkdir -p "$HOME/.openhands"
cfg="$HOME/.openhands/agent_settings.json"
cat > "$cfg" <<JSONEOF
{
  "llm": {
    "model": "openai/$VLLM_MODEL",
    "base_url": "$VLLM_BASE_URL",
    "api_key": "$VLLM_API_KEY"
  }
}
JSONEOF
chmod 600 "$cfg"
echo "configure-openhands: $cfg -> openai/$VLLM_MODEL @ $VLLM_BASE_URL"
