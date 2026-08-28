#!/usr/bin/env bash
#
# Configure git for the agents to push to the air-gapped Gitea server.
# Two modes, picked via yolo.env:
#
#   token mode (default):  GITEA_HOST=server4:3000 GITEA_USER=agent GITEA_TOKEN=...
#   ssh mode:              GITEA_HOST=server4:3000 GIT_SSH=1 [GITEA_SSH_PORT=2222]
#
# Optional: GIT_NAME / GIT_EMAIL (defaults: "Agent" / "agent@gitea.local").
# Also honored: GITEA_SSH_HOST (default: GITEA_HOST without the port).
#
# Idempotent; safe to re-run. Secrets live ONLY in the $HOME volume (mode
# 600) — never in the image, which is what makes the disc tar safe.
set -euo pipefail
umask 077
: "${HOME:=/home/agent}"

GITEA_HOST="${GITEA_HOST:-}"
[[ -n "$GITEA_HOST" ]] || {
  echo "usage: GITEA_HOST=<host[:port]> [GITEA_TOKEN=<token> | GIT_SSH=1] $(basename "$0")" >&2
  exit 1
}
# tolerate a pasted scheme
GITEA_HOST="${GITEA_HOST#http://}"
GITEA_HOST="${GITEA_HOST#https://}"

GIT_NAME="${GIT_NAME:-Agent}"
GIT_EMAIL="${GIT_EMAIL:-agent@gitea.local}"
GITEA_USER="${GITEA_USER:-agent}"

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

if [[ "${GIT_SSH:-0}" = 1 ]]; then
  # --- SSH key mode ---------------------------------------------------------
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  KEY="$HOME/.ssh/id_ed25519"
  if [[ ! -f "$KEY" ]]; then
    ssh-keygen -t ed25519 -N "" -C "$GIT_EMAIL" -f "$KEY" >/dev/null
    echo "git (SSH mode): new ed25519 keypair created."
    echo "Add this PUBLIC key to the Gitea agent user (Settings -> SSH / GPG Keys):"
    cat "$KEY.pub"
    echo
  fi
  ssh_host="${GITEA_SSH_HOST:-${GITEA_HOST%%:*}}"
  ssh_port="${GITEA_SSH_PORT:-22}"
  cat > "$HOME/.ssh/config" <<EOF
Host gitea
  HostName $ssh_host
  Port $ssh_port
  User git
  StrictHostKeyChecking accept-new
  IdentityFile $KEY
EOF
  chmod 600 "$HOME/.ssh/config" "$KEY"
  echo "git (SSH mode) configured: ssh://git@$ssh_host:$ssh_port/<user>/<repo>.git"
  echo "Tip: git clone ssh://git@$ssh_host:$ssh_port/${GITEA_USER}/REPO.git"
else
  # --- token mode -----------------------------------------------------------
  [[ -n "${GITEA_TOKEN:-}" ]] || {
    echo "ERROR: set GITEA_TOKEN=... in yolo.env (or GIT_SSH=1 for key auth)" >&2
    exit 1
  }
  printf '%s\n' "http://$GITEA_USER:$GITEA_TOKEN@$GITEA_HOST" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
  git config --global credential.helper store
  echo "git (token mode) configured for http://$GITEA_USER@$GITEA_HOST"
  echo "Credential in $HOME/.git-credentials (mode 600, volume-only — not in the image)."
  echo "Tip: git clone http://$GITEA_USER@$GITEA_HOST/${GITEA_USER}/REPO.git  (no prompt)"
fi

echo "git identity: $GIT_NAME <$GIT_EMAIL> (global gitconfig — used by all agents and code-server)"
