#!/usr/bin/env bash
#
# yolo-agent web supervisor — started by the server launcher (runs as the
# agent user inside the locked container).
#
#   code-server  -> VS Code in the browser        http://<host>:8080
#   ttyd         -> browser terminal              http://<host>:7681
#                   (wraps tmux: sessions survive tab closes; reattach with
#                    tmux attach -t yolo, or just reopen the page)
#   OpenHands    -> agent IDE with a browser UI   http://<host>:3000
#
# Each process is restarted if it crashes. Logs: /tmp/code-server.log,
# /tmp/ttyd.log, /tmp/openhands.log.
set -euo pipefail

start_code_server() {
  code-server --bind-addr 0.0.0.0:8080 --auth none --disable-telemetry \
    >>/tmp/code-server.log 2>&1 &
  echo $!
}
start_ttyd() {
  ttyd -p 7681 -t titleFixed=yolo-agent -W tmux new -A -s yolo-agent /bin/bash -l \
    >>/tmp/ttyd.log 2>&1 &
  echo $!
}
start_openhands() {
  /opt/yolo/openhands-web-start.sh >>/tmp/openhands.log 2>&1 &
  echo $!
}

echo "yolo-agent web: code-server :8080, ttyd+tmux :7681, OpenHands :3000"
CS_PID=$(start_code_server)
TTYD_PID=$(start_ttyd)
OH_PID=$(start_openhands)

while true; do
  if ! kill -0 "$CS_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) code-server exited; restarting" >>/tmp/code-server.log
    CS_PID=$(start_code_server)
  fi
  if ! kill -0 "$TTYD_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) ttyd exited; restarting" >>/tmp/ttyd.log
    TTYD_PID=$(start_ttyd)
  fi
  if ! kill -0 "$OH_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) OpenHands exited; restarting" >>/tmp/openhands.log
    OH_PID=$(start_openhands)
  fi
  sleep 5
done
