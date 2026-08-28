#!/usr/bin/env bash
#
# Install the browser IDE stack:
#   * code-server 4.117.0  (VS Code in the browser)   — standalone tarball,
#                                                       pinned and hash-checked
#   * ttyd 1.7.7            (browser terminal)        — pinned, verified vs the
#     official SHA256SUMS published in the release
#   * a curated default extension pack (themes + tooling) pre-installed from
#     Open VSX. This MUST happen at build time: the locked runtime has no
#     open-vsx.org egress, so everything ships baked.
#
# Run with HOME=/home/agent so extensions + configs land in the
# volume-populated home (same pattern as prime-agent's kernel).
#
set -euo pipefail
: "${HOME:=/home/agent}"
CODE_SERVER_VERSION="${CODE_SERVER_VERSION:-4.117.0}"
TTYD_VERSION="${TTYD_VERSION:-1.7.7}"

echo ">> installing code-server ${CODE_SERVER_VERSION}"
# Prebuilt standalone tarball (avoids the npm postinstall native-module build,
# which fails in the builder). TOFU-pinned sha256 — code-server publishes no
# official checksums for its release tarballs.
CODE_SERVER_SHA256="${CODE_SERVER_SHA256:-5616650cc65a82046eb7ab24b794da6632a3292d07df06908800d75544962391}"
curl -fsSL -o /tmp/code-server.tar.gz \
  "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz"
echo "$CODE_SERVER_SHA256  /tmp/code-server.tar.gz" | sha256sum -c - >/dev/null
mkdir -p /opt/code-server
tar -xzf /tmp/code-server.tar.gz -C /opt/code-server --strip-components=1
rm -f /tmp/code-server.tar.gz
chmod 0755 /opt/code-server/bin/code-server
ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server
code-server --version | grep -q "$CODE_SERVER_VERSION"

echo ">> installing ttyd ${TTYD_VERSION}"
curl -fsSL -o /tmp/ttyd.x86_64 \
  "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"
curl -fsSL -o /tmp/ttyd.SHA256SUMS \
  "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/SHA256SUMS"
grep "ttyd.x86_64" /tmp/ttyd.SHA256SUMS | (cd /tmp && sha256sum -c -) >/dev/null
install -m 0755 /tmp/ttyd.x86_64 /usr/local/bin/ttyd
rm -f /tmp/ttyd.x86_64 /tmp/ttyd.SHA256SUMS
ttyd --version | grep -q "$TTYD_VERSION"

echo ">> installing VS Code extension pack (Open VSX, pinned at build)"
EXTENSIONS=(
  # language tooling (all offline-capable once installed; Pylance is
  # MS-marketplace-only so Python IntelliSense uses the bundled Jedi LS;
  # markdown is built into VS Code — no third-party pack needed)
  ms-python.python
  redhat.vscode-yaml
  tamasfe.even-better-toml
  dbaeumer.vscode-eslint
  timonwong.shellcheck
  editorconfig.editorconfig
  esbenp.prettier-vscode
  # themes + icons (Open VSX ids differ from the marketplace ids)
  github.github-vscode-theme
  mskelton.one-dark-theme
  dracula-theme.theme-dracula
  Catppuccin.catppuccin-vsc
  PKief.material-icon-theme
  # utilities
  eamodio.gitlens
  mhutchie.git-graph
  streetsidesoftware.code-spell-checker
)
for ext in "${EXTENSIONS[@]}"; do
  code-server --install-extension "$ext" --force >/tmp/ext-install.log 2>&1 \
    || { echo "ERROR installing $ext:" >&2; cat /tmp/ext-install.log >&2; exit 1; }
done
rm -f /tmp/ext-install.log

# Record installed versions for PINS.md / audit.
mkdir -p /opt/yolo
code-server --list-extensions --show-versions > /opt/yolo/EXTENSIONS-MANIFEST.txt
echo "extensions installed: $(wc -l < /opt/yolo/EXTENSIONS-MANIFEST.txt)"

echo ">> install-web-ide.sh: done (code-server + ttyd + extension pack)"
