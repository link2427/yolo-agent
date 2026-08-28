#!/usr/bin/env bash
#
# Launch the yolo-dev container with the locked-down runtime posture.
# Run this ON THE DESTINATION DOCKER HOST, from the directory you want the
# agent to work in (it is mounted read-write as /workspace).
#
#   ./run-yolo.sh              # interactive shell as the agent user
#   ./run-yolo.sh opencode     # run a command directly
#
# Configuration lives in yolo.env (see yolo.env.example). Secrets are passed
# via that env file at runtime — never baked into the image.
#
# What this enforces (details in SECURITY.md):
#   * non-root user (uid 10001)          * all capabilities dropped
#   * read-only rootfs                   * no-new-privileges
#   * strict seccomp profile             * pids/memory/cpu/nofile limits
#   * no docker socket, no host mounts except the workspace bind
#
set -euo pipefail

IMAGE="${YOLO_IMAGE:-yolo-dev:6.0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${YOLO_ENV_FILE:-$HERE/yolo.env}"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE missing (copy yolo.env.example to yolo.env and edit)" >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not found on this host" >&2; exit 1; }

# Optional: reach a model server running on THIS host (Linux Docker Engine).
# Docker Desktop resolves host.docker.internal automatically.
# EXTRA_HOSTS=(--add-host host.docker.internal:host-gateway)

exec docker run -it --rm --name yolo \
  --user 10001:10001 \
  --read-only \
  --tmpfs /tmp:rw,nosuid,size=2g \
  --tmpfs /run:rw,noexec,nosuid,size=64m \
  --tmpfs /dev/shm:rw,noexec,nosuid,size=256m \
  -v "yolo-home-v6:/home/agent" \
  -v "${PWD}:/workspace" \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --security-opt seccomp="${HERE}/seccomp-yolo.json" \
  --memory "${YOLO_MEM:-8g}" \
  --cpus "${YOLO_CPUS:-4}" \
  --pids-limit 512 \
  --ulimit nofile=2048:2048 \
  --ulimit nproc=2048:2048 \
  --stop-timeout 30 \
  --env-file "$ENV_FILE" \
  --workdir /workspace \
  "${EXTRA_HOSTS[@]:-}" \
  "$IMAGE" "$@"
