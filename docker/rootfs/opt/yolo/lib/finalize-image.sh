#!/usr/bin/env bash
#
# Final per-tier check, run as root at the end of each tier. It changes nothing
# (so the tier's last layer stays empty) and fails the build if the apps layer
# did not land correctly.
set -euo pipefail

for a in opencode claude qwen pi crush goose codex; do
  [[ -x "/opt/yolo/bin/$a" ]] || { echo "missing wrapper: $a" >&2; exit 1; }
  [[ -x "/opt/agents/bin/$a" ]] || { echo "missing agent: $a" >&2; exit 1; }
done
for f in /opt/yolo/bin/yolo /opt/yolo/bin/entrypoint /opt/yolo/lib/serve.sh \
         /opt/yolo/lib/configure.py /etc/yolo/defaults.env /opt/yolo/skills/INDEX.tsv; do
  [[ -e "$f" ]] || { echo "missing: $f" >&2; exit 1; }
done
[[ "$(stat -c %u /home/agent/.bashrc)" == 10001 ]] || { echo "home files not owned by agent" >&2; exit 1; }
if find /opt/yolo /opt/agents -xdev -perm /6000 -type f | grep -q .; then
  echo "setuid file in the apps layer" >&2; exit 1
fi
echo "tier ${YOLO_TIER}: apps layer verified"
