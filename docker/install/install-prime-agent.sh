#!/usr/bin/env bash
#
# Install prime-agent (Prime Intellect) with its Python kernel runtime.
#
# The release tarball is verified against the OFFICIAL SHA256SUMS published in
# the GitHub release. The npm postinstall then bootstraps the kernel runtime:
#   uv -> Python 3.11 -> ~/.prime/agent/kernel-venv with prime-agent-runtime
#   (rlm), dill, and the default RLM packages. 0.9.1 uses a custom rlm REPL,
#   not ipykernel.
#
# The postinstall wraps the bootstrap in try/catch ("postinstall setup
# skipped"), so a silent failure would NOT fail npm. We therefore re-verify
# the kernel ourselves and exit non-zero if anything is missing.
#
# Must run with HOME=/home/agent (the agent home) so uv, python and the venv
# land in the volume-populated home. Runs as root during the build; ownership
# is fixed up in the runtime stage.
#
set -euo pipefail

PRIME_AGENT_VERSION="${PRIME_AGENT_VERSION:-0.9.1}"

install_prime_agent() { # $1 = install source (tarball or dir)
  HOME=/home/agent \
  PRIME_AGENT_BOOTSTRAP_TOOLS_ON_INSTALL=1 \
  PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 \
  PRIME_AGENT_INSTALL_UV=1 \
    npm install -g --no-fund --no-audit --loglevel=error --progress=false "$1"
}

echo ">> installing prime-agent ${PRIME_AGENT_VERSION}"
curl -fsSL -o "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz" \
  "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${PRIME_AGENT_VERSION}/prime-agent-${PRIME_AGENT_VERSION}.tgz"
curl -fsSL -o /tmp/prime-agent.SHA256SUMS \
  "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${PRIME_AGENT_VERSION}/SHA256SUMS"
grep "prime-agent-${PRIME_AGENT_VERSION}.tgz" /tmp/prime-agent.SHA256SUMS | (cd /tmp && sha256sum -c -) >/dev/null
install_prime_agent "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz"
rm -f "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz" /tmp/prime-agent.SHA256SUMS

# --- hard verification (postinstall swallows failures) -----------------------
KERNEL_PYTHON="/home/agent/.prime/agent/kernel-venv/bin/python"
test -x "$KERNEL_PYTHON" || { echo "ERROR: kernel python missing at $KERNEL_PYTHON" >&2; exit 1; }
"$KERNEL_PYTHON" -c "import rlm, dill, numpy; print('prime-agent kernel OK (rlm)')"
test -x /home/agent/.local/bin/uv || { echo "ERROR: uv missing" >&2; exit 1; }
prime-agent --version > /tmp/prime-agent.version 2>&1
# prime-agent prints its version on stderr — check the captured file
grep -q "$PRIME_AGENT_VERSION" /tmp/prime-agent.version
command -v prime-agent >/dev/null || { echo "ERROR: prime-agent not on PATH" >&2; exit 1; }
rm -f /tmp/prime-agent.version

echo ">> install-prime-agent.sh: done (CLI + kernel runtime verified)"
