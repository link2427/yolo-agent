#!/usr/bin/env bash
#
# Install DeepSeek Harness (`dsh`) from the committed pnpm lockfile.
#
# The lockfile pins the exact top-level version AND carries an integrity hash
# for every transitive package, so `--frozen-lockfile` is what makes the Node
# dependency graph reproducible.
#
# Expects the lock directory at /tmp/deepseek-harness (package.json +
# pnpm-lock.yaml), both copied in by the Dockerfile build stage.
#
# No wrapper script: `dsh` is the pnpm-generated bin shim for the package's own
# `bin` entry. Earlier releases needed an `--expose-internals` workaround for an
# upstream HMR-loader bug; 0.1.5-rc.1 no longer imports Node internals, and the
# `dsh --version` check below is what proves the shim is actually executable.
#
set -euo pipefail

DSH_VERSION="${DSH_VERSION:-0.1.5-rc.1}"
install_root=/opt/deepseek-harness
lock_root=/tmp/deepseek-harness

locked_version="$(sed -n '/^[[:space:]]*specifier:/ { s/.*specifier:[[:space:]]*//; s/[[:space:]]*$//; p; q; }' "$lock_root/pnpm-lock.yaml")"
[[ "$locked_version" == "$DSH_VERSION" ]] || {
  echo "ERROR: DeepSeek Harness lockfile has $locked_version, expected $DSH_VERSION" >&2
  exit 1
}

mkdir -p "$install_root"
cp "$lock_root/package.json" "$lock_root/pnpm-lock.yaml" "$install_root/"

corepack enable
corepack prepare pnpm@11.7.0 --activate
pnpm --dir "$install_root" install --prod --frozen-lockfile --ignore-scripts

# Verify the installed tree is really the pinned version before we trust the shim.
installed_version="$(node -p "require('$install_root/node_modules/@deepseek-ai/dsh/package.json').version")"
[[ "$installed_version" == "$DSH_VERSION" ]] || {
  echo "ERROR: installed dsh $installed_version, expected $DSH_VERSION" >&2
  exit 1
}

# Put the package's own bin on PATH. Symlink path is stable across installs,
# so this survives a pnpm layout change better than a hardcoded shim path.
ln -sf "$install_root/node_modules/.bin/dsh" /usr/local/bin/dsh
chmod 0755 "$install_root/node_modules/.bin/dsh" 2>/dev/null || true

dsh --version | grep -Fx "$DSH_VERSION" >/dev/null
dsh --profile headless --dump-default-config >/dev/null

echo ">> install-deepseek-harness.sh: dsh $DSH_VERSION installed and verified"
