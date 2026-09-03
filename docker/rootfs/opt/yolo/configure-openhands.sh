#!/usr/bin/env bash
#
# Write OpenHands (v0.62) config pointing at the same local vLLM endpoint
# that configure-agents.sh uses, so one yolo.env configures every harness.
# Idempotent; secrets stay in the $HOME volume (mode 600), never the image.
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

base="${VLLM_BASE_URL%/}"
cfg="$HOME/.openhands/config.toml"
mkdir -p "$HOME/.openhands"

cat > "$cfg" <<CFGEOF
[llm]
model = "openai/$VLLM_MODEL"
base_url = "$base"
api_key = "$VLLM_API_KEY"
custom_llm_provider = "openai"

[core]
workspace_base = "/workspace"
CFGEOF
chmod 600 "$cfg"
echo "configure-openhands: $cfg -> openai/$VLLM_MODEL @ $base"
