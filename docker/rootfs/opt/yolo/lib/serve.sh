#!/usr/bin/env bash
#
# yolo serve <service> — the long-running process for one compose service.
# Each runs in the foreground; compose's restart policy supervises it.
set -euo pipefail
# shellcheck source=/opt/yolo/lib/env.sh
. /opt/yolo/lib/env.sh

svc="${1:-}"
case "$svc" in
  home)
    exec /opt/pyenv/bin/python -I -B /opt/yolo/lib/home.py --port 8000
    ;;
  code)
    # Settings and extensions are seeded into the home volume by configure
    # (which leaves the C/C++ extensions out in the core tier).
    exec code-server --bind-addr 0.0.0.0:8080 --auth none \
      --disable-telemetry --disable-update-check --disable-workspace-trust \
      --disable-getting-started-override \
      --user-data-dir "$HOME/.local/share/code-server" \
      --extensions-dir "$HOME/.local/share/code-server/extensions" \
      /workspace
    ;;
  chat)
    # The embedded web UI is served by the opencode binary itself. Never set
    # OPENCODE_DISABLE_EMBEDDED_WEB_UI: without the embedded bundle opencode
    # proxies the UI from app.opencode.ai, which does not exist offline.
    unset OPENCODE_DISABLE_EMBEDDED_WEB_UI
    cd /workspace
    exec opencode web --hostname 0.0.0.0 --port 4096
    ;;
  term)
    exec ttyd --port 7681 --writable \
      -t titleFixed="yolo terminal" -t fontSize=15 \
      -t 'theme={"background":"#0d1117","foreground":"#e6edf3"}' \
      tmux new-session -A -s main /bin/bash -l
    ;;
  files)
    db="$HOME/.yolo/filebrowser.db"
    mkdir -p "$HOME/.yolo"
    if [[ ! -f "$db" ]]; then
      filebrowser config init --database "$db" >/dev/null
      filebrowser config set --database "$db" --auth.method=noauth \
        --branding.name "yolo files" --branding.disableExternal >/dev/null
      filebrowser users add yolo "yolo-$(head -c12 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
        --database "$db" --perm.admin >/dev/null
    fi
    exec filebrowser --database "$db" --address 0.0.0.0 --port 8081 \
      --root /workspace --noauth
    ;;
  bot)
    exec /opt/pyenv/bin/python -I -B /opt/yolo/lib/bot.py
    ;;
  gateway|monitor)
    exec /opt/pyenv/bin/python -I -B /opt/yolo/lab/gateway.py
    ;;
  *)
    echo "usage: yolo serve home|code|chat|term|files|bot|gateway" >&2
    exit 2
    ;;
esac
