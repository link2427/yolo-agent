#!/usr/bin/env bash
#
# Browser surfaces, all baked at build time (there is no Open VSX or GitHub
# egress at runtime):
#
#   code-server   VS Code in the browser          hash-pinned tarball
#   ttyd          browser terminal                 checked against SHA256SUMS
#   File Browser  upload/download/zip web UI       hash-pinned tarball
#   extensions    curated VS Code extension set    Open VSX, versions recorded
#
# Extensions are installed into /opt/vscode-extensions (read-only image
# content). The entrypoint seeds each person's ~/.local/share/code-server from
# there and refreshes it when the image's set changes.
#
set -euo pipefail

CODE_SERVER_VERSION="${CODE_SERVER_VERSION:?}"
CODE_SERVER_SHA256="${CODE_SERVER_SHA256:?}"
TTYD_VERSION="${TTYD_VERSION:?}"
FILEBROWSER_VERSION="${FILEBROWSER_VERSION:?}"
FILEBROWSER_SHA256="${FILEBROWSER_SHA256:?}"

gh_dl() { curl -fsSL --retry 4 --retry-delay 3 -o "$2" "$1"; }

echo ">> code-server ${CODE_SERVER_VERSION}"
gh_dl "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" /tmp/code-server.tar.gz
echo "${CODE_SERVER_SHA256}  /tmp/code-server.tar.gz" | sha256sum -c - >/dev/null
mkdir -p /opt/code-server
tar -xzf /tmp/code-server.tar.gz -C /opt/code-server --strip-components=1 --no-same-owner
rm -f /tmp/code-server.tar.gz
/opt/code-server/bin/code-server --version | grep -q "$CODE_SERVER_VERSION"

echo ">> ttyd ${TTYD_VERSION}"
gh_dl "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" /tmp/ttyd.x86_64
gh_dl "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/SHA256SUMS" /tmp/ttyd.SHA256SUMS
grep ' ttyd.x86_64$' /tmp/ttyd.SHA256SUMS | (cd /tmp && sha256sum -c -) >/dev/null
install -m 0755 /tmp/ttyd.x86_64 /usr/local/bin/ttyd
rm -f /tmp/ttyd.x86_64 /tmp/ttyd.SHA256SUMS
ttyd --version | grep -q "$TTYD_VERSION"

echo ">> File Browser ${FILEBROWSER_VERSION}"
gh_dl "https://github.com/filebrowser/filebrowser/releases/download/v${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" /tmp/filebrowser.tar.gz
echo "${FILEBROWSER_SHA256}  /tmp/filebrowser.tar.gz" | sha256sum -c - >/dev/null
tar -xzf /tmp/filebrowser.tar.gz -C /tmp --no-same-owner filebrowser
install -m 0755 /tmp/filebrowser /usr/local/bin/filebrowser
rm -f /tmp/filebrowser.tar.gz /tmp/filebrowser
filebrowser version | grep -q "$FILEBROWSER_VERSION"

echo ">> VS Code extensions (Open VSX)"
# Every extension here must work with no network. 2.x shipped these, and a
# code-server on a network with no internet showed what each does (3.0.0):
#   vadimcn.vscode-lldb   the "internet error" people kept seeing: Open VSX
#                         serves a 94 KB stub that downloads the debugger from
#                         github.com on first start ("Platform package
#                         installation failed: getaddrinfo EAI_AGAIN github.com")
#   ms-python.python      tries to install its companion extensions from
#                         open-vsx.org
#   eamodio.gitlens       calls GitKraken's servers on start
#   llvm-vs-code-extensions.vscode-clangd, ms-vscode.cmake-tools
#                         offer to download clangd/cmake where they are not
#                         installed, so the core tier leaves them out
# docs/07-WEB-IDE.md has the details.
EXTENSIONS=(
  # language support that works offline
  redhat.vscode-yaml
  tamasfe.even-better-toml
  timonwong.shellcheck
  editorconfig.editorconfig
  esbenp.prettier-vscode
  # C/C++ (clangd and cmake exist only in the cpp and full tiers; yolo
  # configure leaves these three out of the core tier's extension folder)
  llvm-vs-code-extensions.vscode-clangd
  ms-vscode.cmake-tools
  twxs.cmake
  # git
  mhutchie.git-graph
  # chat-panel coding agent. Kilo Code 7 runs a bundled opencode fork that
  # reads ~/.config/kilo/kilo.json, which yolo configure writes. Cline was
  # dropped: its provider settings live only in VS Code secret storage and
  # cannot be pre-filled, so every person would have to set it up by hand.
  kilocode.Kilo-Code
  # themes and icons
  github.github-vscode-theme
  dracula-theme.theme-dracula
  Catppuccin.catppuccin-vsc
  PKief.material-icon-theme
)
mkdir -p /opt/vscode-extensions /opt/yolo/manifests
for ext in "${EXTENSIONS[@]}"; do
  /opt/code-server/bin/code-server --extensions-dir /opt/vscode-extensions \
    --user-data-dir /tmp/cs-data --install-extension "$ext" --force >/tmp/ext.log 2>&1 \
    || { echo "ERROR installing $ext:" >&2; cat /tmp/ext.log >&2; exit 1; }
done
/opt/code-server/bin/code-server --extensions-dir /opt/vscode-extensions \
  --user-data-dir /tmp/cs-data --list-extensions --show-versions \
  > /opt/yolo/manifests/vscode-extensions.txt
rm -rf /tmp/cs-data /tmp/ext.log
chown -R root:root /opt/code-server /opt/vscode-extensions
chmod -R a+rX /opt/vscode-extensions
echo ">> extensions: $(wc -l < /opt/yolo/manifests/vscode-extensions.txt)"
cat /opt/yolo/manifests/vscode-extensions.txt
