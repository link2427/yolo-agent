#!/usr/bin/env bash
set -euo pipefail

test -d /opt/skills
test "$(find /opt/skills -name SKILL.md -type f | wc -l)" -gt 500
test -s "$HOME/.agents/SKILLS-LIBRARY.txt"
test "$(find "$HOME/.agents/skills" -maxdepth 1 -mindepth 1 | wc -l)" -eq 30
/opt/yolo/skill-use.sh tdd >/dev/null
test "$(find "$HOME/.agents/skills" -maxdepth 1 -mindepth 1 | wc -l)" -eq 31

code-server --version | grep -q 4.117.0
ttyd --version | grep -q 1.7.7
test "$(find "$HOME/.local/share/code-server/extensions" -maxdepth 1 -mindepth 1 | wc -l)" -ge 10

code-server --bind-addr 127.0.0.1:8080 --auth none --disable-telemetry >/tmp/code-server.log 2>&1 &
code_server_pid=$!
ok=0
for _ in $(seq 1 20); do
  if curl -fsS -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
    ok=1
    break
  fi
  sleep 2
done
kill "$code_server_pid" 2>/dev/null || true
wait "$code_server_pid" 2>/dev/null || true
test "$ok" -eq 1

ttyd -p 7681 tmux new -A -s yolo-agent-test /bin/bash >/tmp/ttyd.log 2>&1 &
ttyd_pid=$!
ok=0
for _ in $(seq 1 10); do
  if curl -fsS -o /dev/null http://127.0.0.1:7681/ 2>/dev/null; then
    ok=1
    break
  fi
  sleep 1
done
kill "$ttyd_pid" 2>/dev/null || true
wait "$ttyd_pid" 2>/dev/null || true
test "$ok" -eq 1

echo "full-profile smoke tests passed"
