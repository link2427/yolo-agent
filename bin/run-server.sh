#!/usr/bin/env bash
#
# yolo-agent launcher — persistent browser stack.
#
#   ./bin/run-server.sh                      # base image: IDE + terminal
#   CONTAINER=cpp ./bin/run-server.sh        # C/C++ image (same web surfaces)
#   CONTAINER=reverse ./bin/run-server.sh    # reverse-engineering image
#
# The DeepSeek Harness UI is published by compose instead (see compose.yaml);
# this launcher brings up the IDE and terminal only, which is what you want on a
# box where the agent runs in its own shell.
#
set -euo pipefail

CONTAINER="${CONTAINER:-base}"
case "$CONTAINER" in
  base)    DEFAULT_IMAGE="yolo-agent:2.0.0";                    SECCOMP="seccomp-base.json" ;;
  cpp)     DEFAULT_IMAGE="yolo-agent-cpp:2.0.0";                SECCOMP="seccomp-toolchain.json" ;;
  reverse) DEFAULT_IMAGE="yolo-agent-reverse-engineering:2.0.0"; SECCOMP="seccomp-toolchain.json" ;;
  *) echo "ERROR: CONTAINER must be base, cpp, or reverse (got '$CONTAINER')" >&2; exit 2 ;;
esac

IMAGE="${YOLO_IMAGE:-$DEFAULT_IMAGE}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${YOLO_ENV_FILE:-$ROOT/config/$CONTAINER.env}"
HOME_VOLUME="${YOLO_HOME_VOLUME:-yolo-agent-$CONTAINER-home-v1}"
BIND_ADDRESS="${YOLO_BIND_ADDRESS:-0.0.0.0}"
NAME="yolo-agent-$CONTAINER-server"

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: $ENV_FILE missing; copy config/$CONTAINER.env.example to config/$CONTAINER.env" >&2
  exit 1
}
command -v docker >/dev/null || { echo "ERROR: docker not found" >&2; exit 1; }

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped \
  --user 10001:10001 \
  --read-only \
  --tmpfs /tmp:rw,nosuid,size=2g \
  --tmpfs /run:rw,noexec,nosuid,size=64m \
  --tmpfs /dev/shm:rw,noexec,nosuid,size=256m \
  -v "$HOME_VOLUME:/home/agent" \
  -v "${PWD}:/workspace" \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --security-opt seccomp="$ROOT/config/$SECCOMP" \
  --memory "${YOLO_MEM:-8g}" \
  --cpus "${YOLO_CPUS:-4}" \
  --pids-limit 2048 \
  --ulimit nofile=2048:2048 \
  --ulimit nproc=2048:2048 \
  --stop-timeout 30 \
  -p "$BIND_ADDRESS:${YOLO_CODE_PORT:-8080}:8080" \
  -p "$BIND_ADDRESS:${YOLO_TERMINAL_PORT:-7681}:7681" \
  --env-file "$ENV_FILE" \
  --env "YOLO_FLAVOR=$CONTAINER" \
  --workdir /workspace \
  "$IMAGE" /opt/yolo/server-start.sh

echo "yolo-agent ($CONTAINER) server running:"
echo "  VS Code:  http://$BIND_ADDRESS:${YOLO_CODE_PORT:-8080}"
echo "  Terminal: http://$BIND_ADDRESS:${YOLO_TERMINAL_PORT:-7681}"
echo "  Logs:     docker logs -f $NAME"
echo "  Stop:     docker rm -f $NAME"
