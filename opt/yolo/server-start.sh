#!/usr/bin/env bash
#
# yolo-dev:4.0 web supervisor — started by run-yolo-server.sh (runs as the
# agent user inside the locked container).
#
#   code-server  -> VS Code in the browser        http://<host>:8080
#   ttyd         -> browser terminal              http://<host>:7681
#                   (wraps tmux: sessions survive tab closes; reattach with
#                    tmux attach -t yolo, or just reopen the page)
#
# Both processes are restarted if they crash. Logs: /tmp/code-server.log,
# /tmp/ttyd.log.
set -euo pipefail

start_code_server() {
  code-server --bind-addr 0.0.0.0:8080 --auth none --disable-telemetry \
    >>/tmp/code-server.log 2>&1 &
  echo $!
}
start_ttyd() {
  ttyd -p 7681 -t titleFixed=yolo-dev -W tmux new -A -s yolo /bin/bash -l \
    >>/tmp/ttyd.log 2>&1 &
  echo $!
}

echo "yolo-dev web: code-server on :8080, ttyd+tmux on :7681"
CS_PID=$(start_code_server)
TTYD_PID=$(start_ttyd)

while true; do
  if ! kill -0 "$CS_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) code-server exited; restarting" >>/tmp/code-server.log
    CS_PID=$(start_code_server)
  fi
  if ! kill -0 "$TTYD_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) ttyd exited; restarting" >>/tmp/ttyd.log
    TTYD_PID=$(start_ttyd)
  fi
  sleep 5
done
