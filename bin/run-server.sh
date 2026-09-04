#!/usr/bin/env bash
set -euo pipefail

IMAGE="${YOLO_IMAGE:-yolo-agent:1.2.2}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${YOLO_ENV_FILE:-$ROOT/config/yolo.env}"
HOME_VOLUME="${YOLO_HOME_VOLUME:-yolo-agent-home-v1}"
BIND_ADDRESS="${YOLO_BIND_ADDRESS:-0.0.0.0}"

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: $ENV_FILE missing; copy config/yolo.env.example to config/yolo.env" >&2
  exit 1
}
command -v docker >/dev/null || { echo "ERROR: docker not found" >&2; exit 1; }

docker rm -f yolo-agent-server >/dev/null 2>&1 || true
docker run -d --name yolo-agent-server --restart unless-stopped \
  --user 10001:10001 \
  --read-only \
  --tmpfs /tmp:rw,nosuid,size=2g \
  --tmpfs /run:rw,noexec,nosuid,size=64m \
  --tmpfs /dev/shm:rw,noexec,nosuid,size=256m \
  -v "$HOME_VOLUME:/home/agent" \
  -v "${PWD}:/workspace" \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --security-opt seccomp="$ROOT/config/seccomp-yolo.json" \
  --memory "${YOLO_MEM:-8g}" \
  --cpus "${YOLO_CPUS:-4}" \
  --pids-limit 2048 \
  --ulimit nofile=2048:2048 \
  --ulimit nproc=2048:2048 \
  --stop-timeout 30 \
  -p "$BIND_ADDRESS:${YOLO_CODE_PORT:-8080}:8080" \
  -p "$BIND_ADDRESS:${YOLO_TERMINAL_PORT:-7681}:7681" \
  -p "$BIND_ADDRESS:${YOLO_OPENHANDS_PORT:-3000}:3000" \
  --env-file "$ENV_FILE" \
  --workdir /workspace \
  "$IMAGE" /opt/yolo/server-start.sh

echo "yolo-agent server running:"
echo "  VS Code: http://$BIND_ADDRESS:${YOLO_CODE_PORT:-8080}"
echo "  Terminal: http://$BIND_ADDRESS:${YOLO_TERMINAL_PORT:-7681}"
echo "  OpenHands: http://$BIND_ADDRESS:${YOLO_OPENHANDS_PORT:-3000}"
echo "  Logs: docker logs -f yolo-agent-server"
