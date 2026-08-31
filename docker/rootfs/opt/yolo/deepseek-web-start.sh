#!/usr/bin/env bash
# DeepSeek Harness intentionally listens only on container loopback. Relay it
# to a second container port so Docker can publish it on host loopback without
# patching or weakening the upstream Harness safety check.
set -euo pipefail

internal_port="${DSH_INTERNAL_PORT:-3080}"
relay_port="${DSH_RELAY_PORT:-3081}"

dsh web --host 127.0.0.1 --port "$internal_port" &
dsh_pid=$!
socat TCP-LISTEN:"$relay_port",fork,reuseaddr TCP:127.0.0.1:"$internal_port" &
relay_pid=$!

# shellcheck disable=SC2317 # called indirectly by the traps below
cleanup() {
  kill "$dsh_pid" "$relay_pid" 2>/dev/null || true
  wait "$dsh_pid" "$relay_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

set +e
wait -n "$dsh_pid" "$relay_pid"
status=$?
set -e
exit "$status"
