#!/usr/bin/env bash
#
# Distro packages shared by every yolo-agent 2.x image.
#
# Base is Debian 12 (bookworm) so that the system interpreter is exactly
# Python 3.11 — the single interpreter version the whole project targets.
# Node is NOT installed here; it is copied from /opt/node (see the Dockerfile
# `nodedist` stage), which keeps the distro/userland split clean.
#
# Everything the agents need at runtime must be installed at build time: the
# offline host has no package repositories to fall back on.
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  # core userland the agents shell out to
  ca-certificates curl wget git openssh-client gnupg \
  jq ripgrep fd-find tree less file \
  unzip zip xz-utils zstd tar bzip2 p7zip-full \
  tmux procps psmisc htop lsof \
  vim-tiny nano nano-tiny \
  tini socat netcat-openbsd \
  # Python 3.11 (bookworm default) + build support for wheels
  python3 python3-pip python3-venv python3-dev \
  # native build essentials: needed by pip wheels and by every agent's
  # "just compile this" reflex
  build-essential pkg-config \
  # integrity / audit
  shellcheck
rm -rf /var/lib/apt/lists/*
apt-get clean

# No setuid/setgid binaries anywhere in the image: the runtime drops all
# capabilities, so anything setuid would only be dead weight or a hazard.
find / -xdev -type f -perm /6000 -exec chmod u-s,g-s {} + 2>/dev/null || true

python3 --version
