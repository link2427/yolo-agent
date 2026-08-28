# syntax=docker/dockerfile:1
#
# yolo-dev — locked-down local-coding agent container.
# v3 adds: prime-agent (Prime Intellect) with its IPython kernel runtime
#          pre-bootstrapped (uv + Python 3.11 + ipykernel + rlm), telemetry
#          off, and one-line vLLM endpoint configuration (VLLM_BASE_URL +
#          VLLM_MODEL in yolo.env auto-configure every agent on launch).
#
# Agents: opencode, pi, goose, aider, prime-agent — OpenAI-compatible local
# endpoint (vLLM default, LM Studio alternative). No cloud API keys.
#
# Build & export (default target = runtime):
#   container-build yolo-dev:3.0 . --target runtime --reproducible
# Validate first:
#   container-build yolo-dev:3.0 . --target test
#
# See README.md / SECURITY.md / PINS.md.

# ---- base: system + dev toolchain ---------------------------------------
FROM node:22-bookworm-slim AS base

# Pinned versions (integrity hashes in scripts/install-*.sh)
ARG OPENCODE_VERSION=1.18.13
ARG GOOSE_VERSION=1.45.0
ARG PI_VERSION=0.83.0
ARG AIDER_VERSION=0.86.2
ARG PRIME_AGENT_VERSION=0.7.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv \
      git openssh-client curl ca-certificates \
      build-essential pkg-config \
      jq ripgrep fd-find shellcheck tmux vim-tiny unzip xz-utils tini \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

# ---- agents: pinned, hash-verified tooling --------------------------------
FROM base AS agents

# The agent user must exist before prime-agent's kernel bootstrap runs, so
# uv / Python 3.11 / the kernel venv land in the volume-populated home.
RUN useradd --create-home --uid 10001 --home-dir /home/agent --shell /bin/bash agent

COPY scripts/install-agents.sh /tmp/install-agents.sh
RUN bash /tmp/install-agents.sh \
 && rm -f /tmp/install-agents.sh

COPY scripts/install-prime-agent.sh /tmp/install-prime-agent.sh
RUN HOME=/home/agent bash /tmp/install-prime-agent.sh \
 && rm -f /tmp/install-prime-agent.sh

COPY scripts/install-web-ide.sh /tmp/install-web-ide.sh
RUN HOME=/home/agent bash /tmp/install-web-ide.sh \
 && rm -f /tmp/install-web-ide.sh

# ---- skills: curated library, pinned + hash-verified -----------------------
FROM agents AS skills

COPY scripts/install-skills.sh /tmp/install-skills.sh
RUN bash /tmp/install-skills.sh \
 && rm -f /tmp/install-skills.sh

# ---- runtime: hardened, non-root, --read-only friendly ----------------------
FROM skills AS runtime

# 1) Strip every setuid/setgid bit (no sudo in this image; runtime user is unprivileged)
RUN find / -xdev -type f -perm /6000 -exec chmod u-s,g-s {} \; 2>/dev/null || true

# 2) Workspace dir (agent user already exists from the agents stage)
RUN mkdir -p /workspace

# 3) Bake YOLO defaults into $HOME, ship launcher/configurator/docs, build the
#    skills symlink farm. /opt/skills stays root-owned + read-only at runtime.
#    chown -R fixes the root-owned prime-agent kernel runtime from the build.
COPY opt/home/ /home/agent/
COPY opt/yolo/ /opt/yolo/
COPY scripts/make-skill-farm.sh /opt/yolo/make-skill-farm.sh
COPY docs/ /opt/yolo/docs/
RUN chmod 0755 /opt/yolo/configure-agents.sh /opt/yolo/configure-git.sh /opt/yolo/run-yolo.sh /opt/yolo/run-yolo-server.sh /opt/yolo/server-start.sh /opt/yolo/make-skill-farm.sh /opt/yolo/skill-use.sh \
 && chown -R root:root /opt/yolo \
 && HOME=/home/agent /opt/yolo/make-skill-farm.sh \
 && chown -R agent:agent /home/agent /workspace

# 4) Defaults: offline / telemetry-off where supported; sane locale
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    HOME=/home/agent \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0 \
    PRIME_AGENT_TELEMETRY=0 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Paths that stay writable even under `--read-only` (anonymous volumes).
VOLUME ["/workspace", "/home/agent", "/tmp"]

WORKDIR /workspace
USER agent
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "-l"]

# ---- test: build with `--target test` to validate ---------------------------
FROM runtime AS test
RUN set -eux; \
    id -un | grep -qx agent; \
    [ "$(id -u)" = 10001 ]; \
    pi --version | grep -q 0.83.0; \
    opencode --version | grep -q 1.18.13; \
    goose --version | grep -q 1.45.0; \
    aider --version | grep -q 0.86.2; \
    prime-agent --version 2>&1 | grep -q 0.7.2; \
    node --version | grep -q '^v22'; \
    python3 --version | grep -q '3\.11'; \
    command -v git curl jq rg fd fdfind tmux vim unzip xz tini >/dev/null; \
    [ -w /workspace ] && [ -w /home/agent ] && [ -w /tmp ]; \
    [ ! -w /usr ] && [ ! -w /opt ]; \
    [ "$(find / -xdev -type f -perm /6000 2>/dev/null | wc -l)" -eq 0 ]; \
    echo "--- prime-agent kernel runtime ---"; \
    test -x "$HOME/.prime/agent/kernel-venv/bin/python"; \
    "$HOME/.prime/agent/kernel-venv/bin/python" -c "import ipykernel, rlm; print('kernel ok')"; \
    test -x "$HOME/.local/bin/uv"; \
    jq -e '.telemetry.enabled == false' "$HOME/.prime/agent/settings.json" >/dev/null; \
    echo "--- skills library (v6: 30 curated default, 920 total) ---"; \
    farm_total="$(find "$HOME/.agents/skills" -maxdepth 1 -mindepth 1 | wc -l)"; \
    [ "$farm_total" -eq 30 ]; \
    broken=0; for l in "$HOME"/.agents/skills/*; do [ -e "$l" ] || broken=$((broken+1)); done; \
    [ "$broken" -eq 0 ]; \
    [ -s "$HOME/.agents/SKILLS-LIBRARY.txt" ]; \
    grep -q '^test-driven-development' "$HOME/.agents/SKILLS-LIBRARY.txt"; \
    /opt/yolo/skill-use.sh tdd >/dev/null; \
    [ "$(find "$HOME/.agents/skills" -maxdepth 1 -mindepth 1 | wc -l)" -eq 31 ]; \
    [ "$(find /opt/skills -name SKILL.md -type f | wc -l)" -gt 500 ]; \
    echo "--- baked YOLO configs ---"; \
    jq -e '.permission == "allow"' "$HOME/.config/opencode/opencode.json" >/dev/null; \
    jq -e '.defaultProjectTrust == "always"' "$HOME/.pi/agent/settings.json" >/dev/null; \
    grep -q '^GOOSE_MODE: auto' "$HOME/.config/goose/config.yaml"; \
    grep -q '^yes-always: true' "$HOME/.aider.conf.yml"; \
    echo "--- configurator dry-run (endpoint + YOLO + farm + prime-agent + context) ---"; \
    VLLM_BASE_URL=http://127.0.0.1:8000/v1 VLLM_MODEL=Qwen/Qwen3-Coder-30B-AWQ VLLM_CONTEXT=262144 \
      /opt/yolo/configure-agents.sh; \
    jq -e '.permission == "allow"' "$HOME/.config/opencode/opencode.json" >/dev/null; \
    jq -e '.provider.openai.models["Qwen/Qwen3-Coder-30B-AWQ"].limit.context == 262144' "$HOME/.config/opencode/opencode.json" >/dev/null; \
    jq -e . "$HOME/.pi/agent/models.json" >/dev/null; \
    jq -e '.providers.vllm.models[0].contextWindow == 262144' "$HOME/.pi/agent/models.json" >/dev/null; \
    jq -e '.providers.vllm.models[0].contextWindow == 262144' "$HOME/.prime/agent/models.json" >/dev/null; \
    jq -e '.models[0].context_limit == 262144' "$HOME/.config/goose/custom_providers/vllm.json" >/dev/null; \
    grep -q 'model-metadata-file' "$HOME/.aider.conf.yml"; \
    jq -e '.["Qwen/Qwen3-Coder-30B-AWQ"].context_window == 262144' "$HOME/.aider-model-metadata.json" >/dev/null; \
    grep -q 'Qwen/Qwen3-Coder-30B-AWQ' "$HOME/.aider.conf.yml"; \
    grep -q '^GOOSE_PROVIDER: vllm' "$HOME/.config/goose/config.yaml"; \
    echo "--- git (token mode) ---"; \
    rm -f "$HOME/.git-credentials"; \
    GITEA_HOST=server4:3000 GITEA_USER=agent GITEA_TOKEN=testtoken123 \
      /opt/yolo/configure-git.sh >/dev/null; \
    grep -q 'testtoken123' "$HOME/.git-credentials"; \
    [ "$(stat -c %a "$HOME/.git-credentials")" = 600 ]; \
    [ "$(git config --global user.name)" = Agent ]; \
    [ "$(git config --global credential.helper)" = store ]; \
    echo "--- git (ssh mode) ---"; \
    rm -rf "$HOME/.ssh"; \
    GITEA_HOST=server4:3000 GIT_SSH=1 GITEA_SSH_PORT=2222 \
      /opt/yolo/configure-git.sh >/dev/null; \
    [ -f "$HOME/.ssh/id_ed25519" ] && [ -f "$HOME/.ssh/id_ed25519.pub" ]; \
    grep -q 'Port 2222' "$HOME/.ssh/config"; \
    [ "$(stat -c %a "$HOME/.ssh/id_ed25519")" = 600 ]; \
    echo "--- web IDE (code-server + ttyd + extensions) ---"; \
    code-server --version | grep -q 4.117.0; \
    ttyd --version | grep -q 1.7.7; \
    [ "$(find "$HOME/.local/share/code-server/extensions" -maxdepth 1 -mindepth 1 | wc -l)" -ge 10 ]; \
    code-server --bind-addr 127.0.0.1:8080 --auth none --disable-telemetry >/tmp/cs.log 2>&1 & cs=$!; \
    ok=0; for i in $(seq 1 20); do if curl -fsS -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then ok=1; break; fi; sleep 2; done; \
    kill $cs 2>/dev/null || true; wait $cs 2>/dev/null || true; \
    [ "$ok" -eq 1 ]; echo "code-server HTTP OK"; \
    ttyd -p 7681 tmux new -A -s yolo-test /bin/bash >/tmp/ttyd.log 2>&1 & td=$!; \
    ok=0; for i in $(seq 1 10); do if curl -fsS -o /dev/null http://127.0.0.1:7681/ 2>/dev/null; then ok=1; break; fi; sleep 1; done; \
    kill $td 2>/dev/null || true; wait $td 2>/dev/null || true; \
    [ "$ok" -eq 1 ]; echo "ttyd HTTP OK"; \
    echo "ALL SMOKE TESTS PASSED"
