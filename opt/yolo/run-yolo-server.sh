#!/usr/bin/env bash
#
# Launch yolo-dev in SERVER mode: detached, with code-server (:8080) and
# ttyd+tmux (:7681) exposed on the LAN (air-gapped network, no auth — see
# SECURITY.md). Same lockdown as run-yolo.sh: non-root, read-only rootfs,
# all caps dropped, strict seccomp, resource limits.
#
#   ./run-yolo-server.sh              # start
#   docker logs -f yolo-server        # watch logs
#   docker stop yolo-server           # stop
#
# Terminal persistence: ttyd wraps tmux — close the browser tab and the
# session survives; reopen http://<host>:7681 to reattach. Agent work also
# persists via each agent's own session store in the yolo-home-v4 volume.
#
set -euo pipefail

IMAGE="${YOLO_IMAGE:-yolo-dev:6.0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${YOLO_ENV_FILE:-$HERE/yolo.env}"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE missing (copy yolo.env.example to yolo.env and edit)" >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not found on this host" >&2; exit 1; }

docker rm -f yolo-server >/dev/null 2>&1 || true

docker run -d --name yolo-server --restart unless-stopped \
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
  --pids-limit 2048 \
  --ulimit nofile=2048:2048 \
  --ulimit nproc=2048:2048 \
  --stop-timeout 30 \
  -p 8080:8080 \
  -p 7681:7681 \
  --env-file "$ENV_FILE" \
  --workdir /workspace \
  "$IMAGE" /opt/yolo/server-start.sh

echo
echo "yolo-dev server running:"
echo "  VS Code (code-server): http://<this-host>:8080"
echo "  Terminal (ttyd+tmux):  http://<this-host>:7681"
echo "  Logs:  docker logs -f yolo-server"
