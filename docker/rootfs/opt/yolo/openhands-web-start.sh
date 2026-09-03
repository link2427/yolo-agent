#!/usr/bin/env bash
#
# OpenHands web interface (the current CLI's `openhands web` browser UI).
# Runs in the locked container with no Docker socket and no sandbox subprocess.
set -euo pipefail

: "${HOME:=/home/agent}"
PORT="${OPENHANDS_PORT:-3000}"

if [[ -n "${VLLM_BASE_URL:-}" && -n "${VLLM_MODEL:-}" ]]; then
  /opt/yolo/configure-openhands.sh
else
  echo "openhands-web-start: VLLM_BASE_URL/VLLM_MODEL unset; skipping endpoint config" >&2
fi

# Read-only /opt: keep Python bytecode and caches off the rootfs.
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/openhands-pycache}"
mkdir -p "$HOME/.openhands" "$PYTHONPYCACHEPREFIX"

echo "openhands-web-start: serving OpenHands web UI on :$PORT"
exec /opt/openhands/bin/openhands web --host 0.0.0.0 --port "$PORT"
