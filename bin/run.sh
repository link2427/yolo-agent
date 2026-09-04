#!/usr/bin/env bash
set -euo pipefail

IMAGE="${YOLO_IMAGE:-yolo-agent:2.0.1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${YOLO_ENV_FILE:-$ROOT/config/yolo.env}"
HOME_VOLUME="${YOLO_HOME_VOLUME:-yolo-agent-home-v1}"

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: $ENV_FILE missing; copy config/yolo.env.example to config/yolo.env" >&2
  exit 1
}
command -v docker >/dev/null || { echo "ERROR: docker not found" >&2; exit 1; }

exec docker run -it --rm --name yolo-agent \
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
  --pids-limit 512 \
  --ulimit nofile=2048:2048 \
  --ulimit nproc=2048:2048 \
  --stop-timeout 30 \
  --env-file "$ENV_FILE" \
  --workdir /workspace \
  "$IMAGE" "$@"
