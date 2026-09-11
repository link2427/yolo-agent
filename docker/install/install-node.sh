#!/usr/bin/env bash
#
# Install the Node runtime into /usr/local by copying it out of the official
# node image (mounted at /opt/node), then expose npm, npx and corepack.
#
# Why copy instead of installing: the Debian base keeps a clean userland whose
# system interpreter is exactly Python 3.11. Pulling Node in from the official
# image gives an identical, already-stripped runtime without letting the Node
# image's own base override the distro.
#
# Why this is its own stage in every Dockerfile: corepack/npm are needed by the
# DeepSeek Harness install, which happens BEFORE the runtime stage is assembled.
# Installing Node only in the runtime stage makes that install fail with
# "corepack: command not found".
#
set -euo pipefail

[[ -x /opt/node/bin/node ]] || {
  echo "ERROR: /opt/node/bin/node not found; this script expects the official" >&2
  echo "       node image to be copied in at /opt/node" >&2
  exit 1
}

mkdir -p /usr/local/bin /usr/local/lib
cp /opt/node/bin/node /usr/local/bin/node
cp -a /opt/node/lib/node_modules /usr/local/lib/node_modules

ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js       /usr/local/bin/npm
ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js       /usr/local/bin/npx
ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack

node --version
npm --version
corepack --version
