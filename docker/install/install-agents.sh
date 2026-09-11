#!/usr/bin/env bash
#
# Install the two standalone agent CLIs that ship in every yolo-agent image,
# pinned and integrity-checked.
#
#   opencode -> standalone binary  /opt/opencode/opencode  (symlink in /usr/local/bin)
#   pi       -> standalone binary  /opt/pi/pi/pi           (symlink in /usr/local/bin)
#
# DeepSeek Harness (`dsh`) is installed separately by
# install-deepseek-harness.sh, because its npm plugin graph is large and is
# cached as its own build stage.
#
# Integrity model (see PINS.md):
#   * pi       -> verified against the OFFICIAL SHA256SUMS published in its
#                 release; the pinned hash is only a fallback.
#   * opencode -> no official checksums are published for the CLI tarball, so
#                 the sha256 below is pinned from the first verified download
#                 (TOFU) and fails the build on mismatch.
#
# All of this happens at BUILD time on a networked machine. The shipped image
# never downloads anything again.
#
set -euo pipefail

OPENCODE_VERSION="${OPENCODE_VERSION:-1.18.30}"
OPENCODE_SHA256="${OPENCODE_SHA256:-55007246858165496ff85ba1c2b648f7421e8e2013bf4189a680c9ff8e699d17}"
PI_VERSION="${PI_VERSION:-0.85.1}"
PI_SHA256="${PI_SHA256:-494e498f47d74d21f40b3386f6a5e921a3d49531a169cab55bbdaca0ea1fe25a}"

verify_sha256() { echo "$1  $2" | sha256sum -c - >/dev/null; }

# --- opencode ----------------------------------------------------------------
echo ">> installing opencode ${OPENCODE_VERSION}"
curl -fsSL --retry 3 -o /tmp/opencode.tar.gz \
  "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz"
verify_sha256 "$OPENCODE_SHA256" /tmp/opencode.tar.gz
mkdir -p /opt/opencode
tar -xzf /tmp/opencode.tar.gz -C /opt/opencode
rm -f /tmp/opencode.tar.gz
chmod 0755 /opt/opencode/opencode
ln -sf /opt/opencode/opencode /usr/local/bin/opencode
opencode --version >/dev/null

# --- pi ----------------------------------------------------------------------
echo ">> installing pi ${PI_VERSION}"
curl -fsSL --retry 3 -o /tmp/pi-linux-x64.tar.gz \
  "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-linux-x64.tar.gz"
# Prefer the official checksum when the release publishes one; the pinned
# TOFU hash keeps the build verifiable if that asset ever disappears.
if curl -fsSL --retry 3 -o /tmp/pi.SHA256SUMS \
      "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/SHA256SUMS" 2>/dev/null; then
  grep "pi-linux-x64.tar.gz" /tmp/pi.SHA256SUMS | (cd /tmp && sha256sum -c -) >/dev/null
else
  verify_sha256 "$PI_SHA256" /tmp/pi-linux-x64.tar.gz
fi
mkdir -p /opt/pi
tar -xzf /tmp/pi-linux-x64.tar.gz -C /opt/pi
rm -f /tmp/pi-linux-x64.tar.gz /tmp/pi.SHA256SUMS
chmod 0755 /opt/pi/pi/pi
ln -sf /opt/pi/pi/pi /usr/local/bin/pi
pi --version >/dev/null

echo ">> install-agents.sh: opencode ${OPENCODE_VERSION} + pi ${PI_VERSION} installed"
