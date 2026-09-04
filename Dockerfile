# syntax=docker/dockerfile:1.12

ARG NODE_IMAGE=node:22-bookworm-slim@sha256:4d676821dff059fd00d277ee4261ef34ea712317fed0737c03941481b5760c96
ARG VERSION=1.2.2
ARG VCS_REF=unknown

# Shared system toolchain. The digest is the linux/amd64 Node 22 Bookworm-slim
# manifest, matching the architecture of the recovered SCIF build.
FROM ${NODE_IMAGE} AS base

ARG OPENCODE_VERSION=1.18.27
ARG GOOSE_VERSION=1.48.0
ARG PI_VERSION=0.84.4
ARG AIDER_VERSION=0.86.2
ARG PRIME_AGENT_VERSION=0.9.1
ARG DSH_VERSION=0.1.1-rc.2
ARG OPENHANDS_VERSION=1.16.0

LABEL org.opencontainers.image.title="yolo-agent" \
      org.opencontainers.image.description="Persistent, locked-down autonomous coding-agent environment" \
      org.opencontainers.image.source="https://github.com/link2427/yolo-agent"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv \
      git openssh-client curl ca-certificates \
      build-essential pkg-config \
      jq ripgrep fd-find shellcheck tmux vim-tiny unzip xz-utils tini socat \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

# Core agent toolchain: opencode, goose, pi, aider, and prime-agent.
FROM base AS toolchain

ARG OPENCODE_VERSION
ARG GOOSE_VERSION
ARG PI_VERSION
ARG AIDER_VERSION
ARG PRIME_AGENT_VERSION
ARG DSH_VERSION

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

# DeepSeek Harness is independently cached because its npm plugin graph is
# large and changes independently from the other agents.
FROM toolchain AS deepseek-harness
ARG DSH_VERSION
COPY docker/install/deepseek-harness/ /tmp/deepseek-harness/
COPY docker/install/install-deepseek-harness.sh /tmp/install-deepseek-harness.sh
COPY docker/install/dsh-wrapper.sh /tmp/dsh-wrapper.sh
RUN DSH_VERSION="${DSH_VERSION}" bash /tmp/install-deepseek-harness.sh \
 && rm -rf /tmp/install-deepseek-harness /tmp/install-deepseek-harness.sh /tmp/dsh-wrapper.sh

# Optional, independently cached feature layers.
FROM toolchain AS skills-library
COPY docker/install/install-skills.sh /tmp/install-skills.sh
RUN bash /tmp/install-skills.sh && rm -f /tmp/install-skills.sh

FROM toolchain AS web-ide
COPY docker/install/install-web-ide.sh /tmp/install-web-ide.sh
RUN HOME=/home/agent bash /tmp/install-web-ide.sh && rm -f /tmp/install-web-ide.sh

# OpenHands: the current CLI (its `openhands web` browser UI), installed into a
# uv-managed Python 3.12 venv. No Docker socket and no separate frontend build.
FROM base AS openhands
ARG OPENHANDS_VERSION
ARG UV_VERSION=0.12.9
ARG UV_SHA256=ec7a99cd05e0cd7f80243f135ce1361c76835cb0ee60055d14d20eba8eba1460
RUN curl -fsSL -o /tmp/uv.tgz \
      "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
 && echo "${UV_SHA256}  /tmp/uv.tgz" | sha256sum -c - \
 && tar -xzf /tmp/uv.tgz -C /tmp \
 && mv /tmp/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv \
 && rm -rf /tmp/uv.tgz /tmp/uv-x86_64-unknown-linux-gnu
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python
RUN uv python install 3.12 \
 && uv venv /opt/openhands --python 3.12 \
 && uv pip install --python /opt/openhands/bin/python --no-cache "openhands==${OPENHANDS_VERSION}"

# Single always-on runtime: every agent plus the browser IDE, terminal,
# OpenHands, DeepSeek Harness, and the pinned skills library. There is no
# separate headless profile.
FROM deepseek-harness AS runtime

RUN find / -xdev -type f -perm /6000 -exec chmod u-s,g-s {} \; 2>/dev/null || true
RUN mkdir -p /workspace /opt/yolo

COPY docker/rootfs/home/agent/ /home/agent/
COPY docker/rootfs/opt/yolo/ /opt/yolo/
COPY config/seccomp-yolo.json /opt/yolo/seccomp-yolo.json
COPY docs/ /opt/yolo/docs/

# OpenHands (uv-managed Python 3.12 venv).
COPY --from=openhands /opt/uv-python /opt/uv-python
COPY --from=openhands /opt/openhands /opt/openhands

# Browser IDE, terminal, and skills library (independently cached stages).
COPY --from=skills-library /opt/skills/ /opt/skills/
COPY --from=web-ide /opt/code-server/ /opt/code-server/
COPY --from=web-ide /usr/local/bin/ttyd /usr/local/bin/ttyd
COPY --from=web-ide /opt/yolo/EXTENSIONS-MANIFEST.txt /opt/yolo/EXTENSIONS-MANIFEST.txt
COPY --from=web-ide --chown=agent:agent /home/agent/.local/share/code-server/extensions/ /home/agent/.local/share/code-server/extensions/

RUN ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server \
 && chmod 0755 /opt/yolo/*.sh \
 && chown -R root:root /opt/yolo /opt/skills /opt/code-server /opt/openhands /opt/uv-python \
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
    DSH_HOME=/home/agent/.dsh \
    PATH=/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/workspace", "/home/agent", "/tmp"]
WORKDIR /workspace
USER agent
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "-l"]

ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Build-only validation target. CI and `docker buildx bake` execute this;
# it is never published.
FROM runtime AS test
ARG OPENCODE_VERSION
ARG GOOSE_VERSION
ARG PI_VERSION
ARG AIDER_VERSION
ARG PRIME_AGENT_VERSION
ARG DSH_VERSION
ARG OPENHANDS_VERSION
COPY --chmod=0755 docker/tests/smoke-common.sh docker/tests/smoke-full.sh /tmp/
RUN OPENCODE_VERSION="${OPENCODE_VERSION}" \
    GOOSE_VERSION="${GOOSE_VERSION}" \
    PI_VERSION="${PI_VERSION}" \
    AIDER_VERSION="${AIDER_VERSION}" \
    PRIME_AGENT_VERSION="${PRIME_AGENT_VERSION}" \
    DSH_VERSION="${DSH_VERSION}" \
    OPENHANDS_VERSION="${OPENHANDS_VERSION}" \
    /tmp/smoke-common.sh \
 && /tmp/smoke-full.sh
