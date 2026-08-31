#!/usr/bin/env bash
# Install DeepSeek Harness from the committed pnpm lockfile.
set -euo pipefail

DSH_VERSION="${DSH_VERSION:-0.1.1-rc.2}"
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
install -m 0755 /tmp/dsh-wrapper.sh /usr/local/bin/dsh

dsh --version | grep -Fx "$DSH_VERSION" >/dev/null
echo ">> install-deepseek-harness.sh: dsh $DSH_VERSION installed and verified"
