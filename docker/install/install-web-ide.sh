#!/usr/bin/env bash
#
# Install the browser IDE stack:
#   * code-server  (VS Code in the browser) — standalone tarball, hash-pinned
#   * ttyd          (browser terminal)        — verified against the official
#                                               SHA256SUMS published in release
#   * a curated default extension pack (themes + tooling) pre-installed from
#     Open VSX.
#
# The extension pack MUST be installed at build time: the locked runtime has no
# open-vsx.org egress, so everything ships baked.
#
# The C/C++ extensions are installed in every image (they are only a few MB) so
# that switching to yolo-agent-cpp needs no extra setup. Note the asymmetry:
# clangd, cmake-tools and lldb are INERT in the base and reverse images, because
# /usr/bin/clangd, cmake and ninja only exist in yolo-agent-cpp (installed by
# install-toolchain.sh). Installing them everywhere keeps the extension list
# identical across images, which is worth more than the small size saving.
#
# Run with HOME=/home/agent so extensions + configs land in the volume-
# populated home.
#
set -euo pipefail
: "${HOME:=/home/agent}"
CODE_SERVER_VERSION="${CODE_SERVER_VERSION:-4.137.0}"
CODE_SERVER_SHA256="${CODE_SERVER_SHA256:-9303165b7fd43532091922f77e2f119ff2fa109c6b6f1c3c966fb02f3d6d9c8b}"
TTYD_VERSION="${TTYD_VERSION:-1.7.7}"

echo ">> installing code-server ${CODE_SERVER_VERSION}"
# Prebuilt standalone tarball (avoids the npm postinstall native-module build,
# which fails in the builder). TOFU-pinned sha256 — code-server publishes no
# official checksums for its release tarballs.
curl -fsSL --retry 3 -o /tmp/code-server.tar.gz \
  "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz"
echo "$CODE_SERVER_SHA256  /tmp/code-server.tar.gz" | sha256sum -c - >/dev/null
mkdir -p /opt/code-server
tar -xzf /tmp/code-server.tar.gz -C /opt/code-server --strip-components=1
rm -f /tmp/code-server.tar.gz
chmod 0755 /opt/code-server/bin/code-server
ln -sf /opt/code-server/bin/code-server /usr/local/bin/code-server
code-server --version | grep -q "$CODE_SERVER_VERSION"

echo ">> installing ttyd ${TTYD_VERSION}"
curl -fsSL --retry 3 -o /tmp/ttyd.x86_64 \
  "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"
curl -fsSL --retry 3 -o /tmp/ttyd.SHA256SUMS \
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
  # C/C++ (usable in every image; the compilers live in yolo-agent-cpp)
  llvm-vs-code-extensions.vscode-clangd
  ms-vscode.cmake-tools
  twxs.cmake
  vadimcn.vscode-lldb
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
