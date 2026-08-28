#!/usr/bin/env bash
#
# Install prime-agent (Prime Intellect) with its IPython kernel runtime.
#
# The release tarball is verified against the OFFICIAL SHA256SUMS published in
# the GitHub release. The npm postinstall then bootstraps the kernel runtime:
#   uv -> Python 3.11 -> ~/.prime/agent/kernel-venv with ipykernel,
#   prime-agent-runtime (rlm), dill and the default RLM packages
#   (requests, httpx, pyyaml, tomli, python-dotenv, pandas, numpy, scipy,
#    beautifulsoup4, lxml, pydantic, tyro), plus preloaded fd/rg tools.
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

PRIME_AGENT_VERSION="${PRIME_AGENT_VERSION:-0.7.2}"

# npm overrides: upstream AWS SDK registry breakage (Aug 2026) — several
# @aws-sdk/* patch versions referenced by the dependency tree were never
# published (e.g. eventstream-handler-node ^3.972.32, types ^3.974.3). We pin
# the latest published versions so resolution succeeds. See PINS.md.
AWS_SDK_OVERRIDES='{"@aws-sdk/eventstream-handler-node":"3.972.9","@aws-sdk/types":"3.974.2"}'

instal_prime_agent() { # $1 = install source (tarball or dir)
  HOME=/home/agent \
  PRIME_AGENT_BOOTSTRAP_TOOLS_ON_INSTALL=1 \
  PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 \
  PRIME_AGENT_INSTALL_UV=1 \
    npm install -g --no-fund --no-audit --loglevel=error --progress=false "$1"
}

if [[ "${PRIME_AGENT_PATCHED_TARBALL:-1}" = 1 ]]; then
  echo ">> installing prime-agent ${PRIME_AGENT_VERSION} (patched: $AWS_SDK_OVERRIDES)"
  curl -fsSL -o "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz" \
    "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${PRIME_AGENT_VERSION}/prime-agent-${PRIME_AGENT_VERSION}.tgz"
  curl -fsSL -o /tmp/prime-agent.SHA256SUMS \
    "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${PRIME_AGENT_VERSION}/SHA256SUMS"
  grep "prime-agent-${PRIME_AGENT_VERSION}.tgz" /tmp/prime-agent.SHA256SUMS | (cd /tmp && sha256sum -c -) >/dev/null
  rm -rf /tmp/prime-agent-pkg && mkdir -p /tmp/prime-agent-pkg
  tar -xzf "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz" -C /tmp/prime-agent-pkg
  python3 - "$AWS_SDK_OVERRIDES" <<'PY'
import json, sys
overrides = json.loads(sys.argv[1])
f = "/tmp/prime-agent-pkg/package/package.json"
d = json.load(open(f))
d.setdefault("overrides", {}).update(overrides)
json.dump(d, open(f, "w"), indent=2)
PY
  # `npm install -g <dir>` does NOT resolve dependencies (it only links the
  # one package), so repack the patched package as a tarball and install that.
  tar -czf /tmp/prime-agent-fixed.tgz -C /tmp/prime-agent-pkg package
  instal_prime_agent /tmp/prime-agent-fixed.tgz
  rm -rf "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz" /tmp/prime-agent.SHA256SUMS /tmp/prime-agent-pkg /tmp/prime-agent-fixed.tgz
else
  echo ">> installing prime-agent ${PRIME_AGENT_VERSION}"
  curl -fsSL -o "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz" \
    "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${PRIME_AGENT_VERSION}/prime-agent-${PRIME_AGENT_VERSION}.tgz"
  curl -fsSL -o /tmp/prime-agent.SHA256SUMS \
    "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${PRIME_AGENT_VERSION}/SHA256SUMS"
  grep "prime-agent-${PRIME_AGENT_VERSION}.tgz" /tmp/prime-agent.SHA256SUMS | (cd /tmp && sha256sum -c -) >/dev/null
  instal_prime_agent "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz"
  rm -f "/tmp/prime-agent-${PRIME_AGENT_VERSION}.tgz" /tmp/prime-agent.SHA256SUMS
fi

# --- hard verification (postinstall swallows failures) -----------------------
KERNEL_PYTHON="/home/agent/.prime/agent/kernel-venv/bin/python"
test -x "$KERNEL_PYTHON" || { echo "ERROR: kernel python missing at $KERNEL_PYTHON" >&2; exit 1; }
"$KERNEL_PYTHON" -c "import ipykernel, rlm; print('prime-agent kernel OK (ipykernel + rlm)')"
test -x /home/agent/.local/bin/uv || { echo "ERROR: uv missing" >&2; exit 1; }
prime-agent --version > /tmp/prime-agent.version 2>&1
# prime-agent prints its version on stderr — check the captured file
grep -q "$PRIME_AGENT_VERSION" /tmp/prime-agent.version
command -v prime-agent >/dev/null || { echo "ERROR: prime-agent not on PATH" >&2; exit 1; }
rm -f /tmp/prime-agent.version

echo ">> install-prime-agent.sh: done (CLI + IPython kernel runtime verified)"
