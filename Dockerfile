# syntax=docker/dockerfile:1.12

ARG NODE_IMAGE=node:22-bookworm-slim@sha256:4d676821dff059fd00d277ee4261ef34ea712317fed0737c03941481b5760c96
ARG VERSION=1.0.0
ARG VCS_REF=unknown

# Shared system toolchain. The digest is the linux/amd64 Node 22 Bookworm-slim
# manifest, matching the architecture of the recovered SCIF build.
FROM ${NODE_IMAGE} AS base

ARG OPENCODE_VERSION=1.18.13
ARG GOOSE_VERSION=1.45.0
ARG PI_VERSION=0.83.0
ARG AIDER_VERSION=0.86.2
ARG PRIME_AGENT_VERSION=0.7.2

LABEL org.opencontainers.image.title="yolo-agent" \
      org.opencontainers.image.description="Persistent, locked-down autonomous coding-agent environment" \
      org.opencontainers.image.source="https://github.com/link2427/yolo-agent"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv \
      git openssh-client curl ca-certificates \
      build-essential pkg-config \
      jq ripgrep fd-find shellcheck tmux vim-tiny unzip xz-utils tini \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

# Core agent toolchain: opencode, goose, pi, aider, and prime-agent.
FROM base AS toolchain

ARG OPENCODE_VERSION
ARG GOOSE_VERSION
ARG PI_VERSION
ARG AIDER_VERSION
ARG PRIME_AGENT_VERSION

RUN useradd --create-home --uid 10001 --home-dir /home/agent --shell /bin/bash agent

COPY docker/install/install-agents.sh /tmp/install-agents.sh
RUN OPENCODE_VERSION="${OPENCODE_VERSION}" \
    GOOSE_VERSION="${GOOSE_VERSION}" \
    PI_VERSION="${PI_VERSION}" \
    AIDER_VERSION="${AIDER_VERSION}" \
    bash /tmp/install-agents.sh \
 && rm -f /tmp/install-agents.sh

COPY docker/install/install-prime-agent.sh /tmp/install-prime-agent.sh
RUN HOME=/home/agent PRIME_AGENT_VERSION="${PRIME_AGENT_VERSION}" \
    bash /tmp/install-prime-agent.sh \
 && rm -f /tmp/install-prime-agent.sh

# Optional, independently cached feature layers.
FROM toolchain AS skills-library
COPY docker/install/install-skills.sh /tmp/install-skills.sh
RUN bash /tmp/install-skills.sh && rm -f /tmp/install-skills.sh

FROM toolchain AS web-ide
COPY docker/install/install-web-ide.sh /tmp/install-web-ide.sh
RUN HOME=/home/agent bash /tmp/install-web-ide.sh && rm -f /tmp/install-web-ide.sh

# Small headless runtime. It includes every agent but omits the large skills
# library and browser IDE. The same persisted home volume works with both
# profiles.
FROM toolchain AS runtime-common

RUN find / -xdev -type f -perm /6000 -exec chmod u-s,g-s {} \; 2>/dev/null || true
RUN mkdir -p /workspace /opt/yolo

COPY docker/rootfs/home/agent/ /home/agent/
COPY docker/rootfs/opt/yolo/ /opt/yolo/
COPY config/seccomp-yolo.json /opt/yolo/seccomp-yolo.json
COPY docs/ /opt/yolo/docs/
RUN chmod 0755 /opt/yolo/*.sh \
 && chown -R root:root /opt/yolo \
 && HOME=/home/agent /opt/yolo/make-skill-farm.sh \
 && chown -R agent:agent /home/agent /workspace

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    HOME=/home/agent \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0 \
    PRIME_AGENT_TELEMETRY=0 \
    PATH=/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/workspace", "/home/agent", "/tmp"]
WORKDIR /workspace
USER agent
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "-l"]

# Version metadata is intentionally added only after the immutable runtime
# layers, so a release-number change does not rebuild the toolchain.
FROM runtime-common AS runtime-headless
ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.variant="headless"

# Full runtime composes the independently cached skills and web IDE artifacts
# onto the exact same headless foundation.
FROM runtime-common AS runtime-full
USER root
COPY --from=skills-library /opt/skills/ /opt/skills/
COPY --from=web-ide /opt/code-server/ /opt/code-server/
COPY --from=web-ide /usr/local/bin/ttyd /usr/local/bin/ttyd
COPY --from=web-ide /opt/yolo/EXTENSIONS-MANIFEST.txt /opt/yolo/EXTENSIONS-MANIFEST.txt
COPY --from=web-ide --chown=agent:agent /home/agent/.local/share/code-server/extensions/ /home/agent/.local/share/code-server/extensions/
RUN ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server \
 && HOME=/home/agent /opt/yolo/make-skill-farm.sh \
 && chown -R root:root /opt/skills /opt/code-server /opt/yolo \
 && chown -R agent:agent /home/agent
USER agent
ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.variant="full"

# Build-only validation targets. CI and `docker buildx bake` execute these;
# they are never published.
FROM runtime-headless AS test-headless
ARG OPENCODE_VERSION
ARG GOOSE_VERSION
ARG PI_VERSION
ARG AIDER_VERSION
ARG PRIME_AGENT_VERSION
COPY --chmod=0755 docker/tests/smoke-common.sh /tmp/smoke-common.sh
RUN OPENCODE_VERSION="${OPENCODE_VERSION}" \
    GOOSE_VERSION="${GOOSE_VERSION}" \
    PI_VERSION="${PI_VERSION}" \
    AIDER_VERSION="${AIDER_VERSION}" \
    PRIME_AGENT_VERSION="${PRIME_AGENT_VERSION}" \
    /tmp/smoke-common.sh

FROM runtime-full AS test-full
ARG OPENCODE_VERSION
ARG GOOSE_VERSION
ARG PI_VERSION
ARG AIDER_VERSION
ARG PRIME_AGENT_VERSION
COPY --chmod=0755 docker/tests/smoke-common.sh docker/tests/smoke-full.sh /tmp/
RUN OPENCODE_VERSION="${OPENCODE_VERSION}" \
    GOOSE_VERSION="${GOOSE_VERSION}" \
    PI_VERSION="${PI_VERSION}" \
    AIDER_VERSION="${AIDER_VERSION}" \
    PRIME_AGENT_VERSION="${PRIME_AGENT_VERSION}" \
    /tmp/smoke-common.sh \
 && /tmp/smoke-full.sh

# Backward-compatible default target: the complete image.
FROM runtime-full AS runtime
