#!/usr/bin/env bash
#
# yolo-agent launcher — disposable interactive shell.
#
#   ./bin/run.sh                      # base image, project dir = $PWD
#   CONTAINER=cpp ./bin/run.sh        # C/C++ cross-compilation image
#   CONTAINER=reverse ./bin/run.sh    # reverse-engineering image
#
# The container mounts exactly one host folder, at /workspace. Everything the
# agent can touch lives under that mount or in the named home volume.
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

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: $ENV_FILE missing; copy config/$CONTAINER.env.example to config/$CONTAINER.env" >&2
  exit 1
}
command -v docker >/dev/null || { echo "ERROR: docker not found" >&2; exit 1; }

exec docker run -it --rm --name "yolo-agent-$CONTAINER" \
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
  --pids-limit 512 \
  --ulimit nofile=2048:2048 \
  --ulimit nproc=2048:2048 \
  --stop-timeout 30 \
  --env-file "$ENV_FILE" \
  --env "YOLO_FLAVOR=$CONTAINER" \
  --workdir /workspace \
  "$IMAGE" "$@"
