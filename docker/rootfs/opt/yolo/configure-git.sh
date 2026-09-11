#!/usr/bin/env bash
#
# Configure git for the agents to push to the air-gapped Gitea server.
# Two modes, picked via the env file (config/<flavor>.env):
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

# --- optional /etc/hosts entry -------------------------------------------------
# GITEA_HOST_IP exists for the case where the Gitea host name does not resolve
# inside the container (no internal DNS). /etc/hosts is root-owned and the
# container runs as uid 10001, so this usually cannot be written at runtime;
# fail soft and tell the operator exactly what to do instead.
if [[ -n "${GITEA_HOST_IP:-}" ]]; then
  host_only="${GITEA_HOST%%:*}"
  if getent hosts "$host_only" >/dev/null 2>&1; then
    echo "git: $host_only already resolves; ignoring GITEA_HOST_IP"
  elif printf '%s %s\n' "$GITEA_HOST_IP" "$host_only" >> /etc/hosts 2>/dev/null; then
    echo "git: mapped $host_only -> $GITEA_HOST_IP in /etc/hosts"
  else
    echo "git: could not write /etc/hosts (expected: it is root-owned)." >&2
    echo "     Use the IP directly instead:  GITEA_HOST=${GITEA_HOST_IP}:${GITEA_HOST##*:}" >&2
    echo "     or add at launch:             docker run --add-host $host_only:$GITEA_HOST_IP ..." >&2
  fi
fi

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
    echo "ERROR: set GITEA_TOKEN=... in the env file (or GIT_SSH=1 for key auth)" >&2
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
