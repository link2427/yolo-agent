#!/usr/bin/env bash
#
# OpenHands full web UI (legacy v0.62.0) on port 3000, running with the
# "local" runtime (no Docker socket, no sandbox subprocess) inside the locked
# container. uvicorn is launched directly as the agent user, bypassing
# upstream's root-only entrypoint.sh (which does useradd/su and needs root).
set -euo pipefail

: "${HOME:=/home/agent}"
APP_DIR=/opt/openhands
PORT="${OPENHANDS_PORT:-3000}"

# Point OpenHands at the same local vLLM endpoint as the other agents.
if [[ -n "${VLLM_BASE_URL:-}" && -n "${VLLM_MODEL:-}" ]]; then
  /opt/yolo/configure-openhands.sh
else
  echo "openhands-web-start: VLLM_BASE_URL/VLLM_MODEL unset; skipping endpoint config" >&2
fi

export RUNTIME=local
export RUN_AS_OPENHANDS=false
export SERVE_FRONTEND=true
export FILE_STORE_PATH="${OPENHANDS_FILE_STORE:-$HOME/.openhands}"
export WORKSPACE_BASE="${OPENHANDS_WORKSPACE:-/workspace}"
# Read-only /opt: keep Python bytecode and caches off the rootfs.
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/openhands-pycache}"

if [[ -n "${VLLM_BASE_URL:-}" && -n "${VLLM_MODEL:-}" ]]; then
  export LLM_MODEL="openai/${VLLM_MODEL}"
  export LLM_BASE_URL="${VLLM_BASE_URL%/}"
  export LLM_API_KEY="${VLLM_API_KEY:-local}"
  export LLM_CUSTOM_LLM_PROVIDER="openai"
fi

mkdir -p "$FILE_STORE_PATH" "$PYTHONPYCACHEPREFIX"

echo "openhands-web-start: serving OpenHands on :$PORT (RUNTIME=local)"
cd "$APP_DIR"
exec "$APP_DIR/bin/python" -m uvicorn openhands.server.listen:app \
  --host 0.0.0.0 --port "$PORT"
