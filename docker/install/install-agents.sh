#!/usr/bin/env bash
#
# Install every agent CLI under /opt/agents, with launchers in /opt/agents/bin.
#
#   opencode     binary      github.com/anomalyco/opencode        sha256 pinned
#   pi           binary      github.com/earendil-works/pi          sha256 pinned
#   crush        binary      github.com/charmbracelet/crush        sha256 pinned
#   goose        binary      github.com/aaif-goose/goose           sha256 pinned
#   codex        binary      github.com/openai/codex               sha256 pinned
#   qwen         npm         @qwen-code/qwen-code                  version pinned
#   claude       npm         @anthropic-ai/claude-code             version pinned
#
# The npm packages are verified by npm's registry integrity hashes. Claude
# Code's npm package installs its native linux-x64 binary from an optional
# dependency, which happens here, at build time.
#
set -euo pipefail

: "${OPENCODE_VERSION:?}" "${OPENCODE_SHA256:?}"
: "${PI_VERSION:?}" "${PI_SHA256:?}"
: "${CRUSH_VERSION:?}" "${CRUSH_SHA256:?}"
: "${GOOSE_VERSION:?}" "${GOOSE_SHA256:?}"
: "${CODEX_VERSION:?}" "${CODEX_SHA256:?}"
: "${QWEN_CODE_VERSION:?}" "${CLAUDE_CODE_VERSION:?}"

A=/opt/agents
mkdir -p "$A/bin"

fetch() { # url sha256 dest
  curl -fsSL --retry 4 --retry-delay 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c - >/dev/null
}

echo ">> opencode ${OPENCODE_VERSION}"
fetch "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
  "$OPENCODE_SHA256" /tmp/opencode.tgz
mkdir -p "$A/opencode"
tar -xzf /tmp/opencode.tgz -C "$A/opencode" --no-same-owner
ln -sf ../opencode/opencode "$A/bin/opencode"

echo ">> pi ${PI_VERSION}"
fetch "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-linux-x64.tar.gz" \
  "$PI_SHA256" /tmp/pi.tgz
mkdir -p "$A/pi"
tar -xzf /tmp/pi.tgz -C "$A/pi" --no-same-owner
ln -sf ../pi/pi/pi "$A/bin/pi"

echo ">> crush ${CRUSH_VERSION}"
fetch "https://github.com/charmbracelet/crush/releases/download/v${CRUSH_VERSION}/crush_${CRUSH_VERSION}_Linux_x86_64.tar.gz" \
  "$CRUSH_SHA256" /tmp/crush.tgz
mkdir -p "$A/crush"
tar -xzf /tmp/crush.tgz -C "$A/crush" --no-same-owner --strip-components=1
ln -sf ../crush/crush "$A/bin/crush"

echo ">> goose ${GOOSE_VERSION}"
fetch "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/goose-x86_64-unknown-linux-gnu.tar.gz" \
  "$GOOSE_SHA256" /tmp/goose.tgz
mkdir -p "$A/goose"
tar -xzf /tmp/goose.tgz -C "$A/goose" --no-same-owner
ln -sf ../goose/goose "$A/bin/goose"

echo ">> codex ${CODEX_VERSION}"
fetch "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-x86_64-unknown-linux-musl.tar.gz" \
  "$CODEX_SHA256" /tmp/codex.tgz
mkdir -p "$A/codex"
tar -xzf /tmp/codex.tgz -C "$A/codex" --no-same-owner
mv "$A/codex/codex-x86_64-unknown-linux-musl" "$A/codex/codex"
ln -sf ../codex/codex "$A/bin/codex"

echo ">> npm agents: qwen-code ${QWEN_CODE_VERSION}, claude-code ${CLAUDE_CODE_VERSION}"
export npm_config_update_notifier=false npm_config_fund=false npm_config_audit=false
npm install --global --prefix "$A/npm" --no-progress \
  "@qwen-code/qwen-code@${QWEN_CODE_VERSION}" \
  "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
ln -sf ../npm/bin/qwen "$A/bin/qwen"
ln -sf ../npm/bin/claude "$A/bin/claude"
# Optional dependencies for other platforms are not installed by npm, but make
# sure no stray cache or platform package is left behind.
rm -rf /root/.npm /tmp/*.tgz

chown -R root:root "$A"
chmod -R a+rX "$A"

echo ">> versions (each binary must run and report its pinned version)"
check() { # name version cmd...
  local n="$1" v="$2" out; shift 2
  out="$(OTEL_SDK_DISABLED=true HOME=/tmp/agent-home "$@" --version 2>&1)" || { echo "$n --version failed: $out" >&2; exit 1; }
  grep -Fq "$v" <<<"$out" || { echo "$n: expected $v, got: $out" >&2; exit 1; }
  printf '%-9s %s\n' "$n" "$v"
}
{
  check opencode "$OPENCODE_VERSION" "$A/bin/opencode"
  check pi "$PI_VERSION" "$A/bin/pi"
  check crush "$CRUSH_VERSION" "$A/bin/crush"
  check goose "$GOOSE_VERSION" "$A/bin/goose"
  check codex "$CODEX_VERSION" "$A/bin/codex"
  check qwen "$QWEN_CODE_VERSION" "$A/bin/qwen"
  check claude "$CLAUDE_CODE_VERSION" env DISABLE_AUTOUPDATER=1 "$A/bin/claude"
} > "$A/VERSIONS.txt"
cat "$A/VERSIONS.txt"
rm -rf /tmp/agent-home
du -sh "$A"/* | sort -h
