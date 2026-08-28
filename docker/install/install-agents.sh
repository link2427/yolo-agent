#!/usr/bin/env bash
#
# Install the four coding agents, pinned and integrity-checked.
#
#   opencode  -> standalone binary  /opt/opencode/opencode   (symlink in /usr/local/bin)
#   goose     -> standalone binary  /opt/goose/goose         (symlink in /usr/local/bin)
#   pi        -> standalone binary  /opt/pi/pi/pi            (symlink in /usr/local/bin)
#   aider     -> isolated venv      /opt/aider-venv          (symlink in /usr/local/bin)
#
# Integrity model (see PINS.md):
#   * pi      -> verified against the official SHA256SUMS published in its release.
#   * opencode/goose -> no official checksums for the CLI tarballs; the sha256s below
#     are pinned from the first verified download (TOFU) and fail the build on mismatch.
#   * aider   -> pinned exact version from PyPI over TLS.
#
set -euo pipefail

OPENCODE_VERSION="${OPENCODE_VERSION:-1.18.13}"
OPENCODE_SHA256="${OPENCODE_SHA256:-8d500b20fed2d26e537e221895b1a575476571b4f0089bb29fb13eeb8eb9e937}"
GOOSE_VERSION="${GOOSE_VERSION:-1.45.0}"
GOOSE_SHA256="${GOOSE_SHA256:-e0db638ac437ca0a60b0c1622f45322608d228d1a285214c3bf48fd9763346a5}"
PI_VERSION="${PI_VERSION:-0.83.0}"
PI_SHA256="${PI_SHA256:-b0625eb623197b0afe20c870d21ef2f34481f1504e5777df3f698a66c7636f5f}"
AIDER_VERSION="${AIDER_VERSION:-0.86.2}"

verify_sha256() { echo "$1  $2" | sha256sum -c - >/dev/null; }

# --- opencode ---------------------------------------------------------------
echo ">> installing opencode ${OPENCODE_VERSION}"
curl -fsSL -o /tmp/opencode.tar.gz \
  "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz"
verify_sha256 "$OPENCODE_SHA256" /tmp/opencode.tar.gz
mkdir -p /opt/opencode
tar -xzf /tmp/opencode.tar.gz -C /opt/opencode
chmod 0755 /opt/opencode/opencode
ln -s /opt/opencode/opencode /usr/local/bin/opencode
/usr/local/bin/opencode --version >/dev/null

# --- goose ------------------------------------------------------------------
echo ">> installing goose ${GOOSE_VERSION}"
curl -fsSL -o /tmp/goose.tar.gz \
  "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/goose-x86_64-unknown-linux-gnu.tar.gz"
verify_sha256 "$GOOSE_SHA256" /tmp/goose.tar.gz
mkdir -p /opt/goose
tar -xzf /tmp/goose.tar.gz -C /opt/goose
chmod 0755 /opt/goose/goose
ln -s /opt/goose/goose /usr/local/bin/goose
/usr/local/bin/goose --version >/dev/null

# --- pi ---------------------------------------------------------------------
echo ">> installing pi ${PI_VERSION}"
curl -fsSL -o /tmp/pi-linux-x64.tar.gz \
  "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-linux-x64.tar.gz"
# Cross-check against the official release SHA256SUMS when one is published for
# this release; fall back to the pinned hash otherwise.
if curl -fsSL -o /tmp/pi.SHA256SUMS \
      "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/SHA256SUMS" 2>/dev/null; then
  grep "pi-linux-x64.tar.gz" /tmp/pi.SHA256SUMS | (cd /tmp && sha256sum -c -) >/dev/null
else
  verify_sha256 "$PI_SHA256" /tmp/pi-linux-x64.tar.gz
fi
mkdir -p /opt/pi
tar -xzf /tmp/pi-linux-x64.tar.gz -C /opt/pi
chmod 0755 /opt/pi/pi/pi
ln -s /opt/pi/pi/pi /usr/local/bin/pi
/usr/local/bin/pi --version >/dev/null

# --- aider (isolated venv; keeps the system python clean) --------------------
echo ">> installing aider ${AIDER_VERSION}"
python3 -m venv /opt/aider-venv
/opt/aider-venv/bin/pip install --no-cache-dir --disable-pip-version-check "aider-chat==${AIDER_VERSION}"
ln -s /opt/aider-venv/bin/aider /usr/local/bin/aider
/usr/local/bin/aider --version >/dev/null

# --- cleanup -----------------------------------------------------------------
rm -f /tmp/opencode.tar.gz /tmp/goose.tar.gz /tmp/pi-linux-x64.tar.gz /tmp/pi.SHA256SUMS
echo ">> install-agents.sh: all agents installed"
