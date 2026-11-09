# syntax=docker/dockerfile:1.12
#
# yolo-agent 3 — one Dockerfile, three tiers.
#
#   core   agents, code-server, terminal, file browser, Python 3.11, Node 22
#   cpp    core + C/C++/Fortran toolchain + mingw-w64 Windows cross compilers
#   full   cpp  + reverse-engineering tools (Ghidra, jadx, radare2, pycdc, ...)
#
# Layer plan. Each tier is a "platform" (rarely changes) plus the same "apps"
# layer (agents and yolo config, changes often):
#
#   os ─ platform-core ─────────────────────── core = platform-core + apps
#            └─ platform-cpp ───────────────── cpp  = platform-cpp  + apps
#                   └─ platform-full ───────── full = platform-full + apps
#
# The apps layer is built once and copied the same way into every tier, so it is
# stored once in `docker save` and in a registry. An agent bump re-ships only
# that layer; the toolchains are not rebuilt or re-shipped.
#
# Air gap: everything is downloaded here, at build time. The runtime performs no
# downloads.

ARG VERSION=3.0.0
ARG VCS_REF=unknown

ARG DEBIAN_IMAGE=debian:bookworm-slim
ARG NODE_IMAGE=node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5

# --- pins (keep in sync with PINS.md) ---------------------------------------
ARG OPENCODE_VERSION=1.18.30
ARG OPENCODE_SHA256=55007246858165496ff85ba1c2b648f7421e8e2013bf4189a680c9ff8e699d17
ARG PI_VERSION=0.85.1
ARG PI_SHA256=494e498f47d74d21f40b3386f6a5e921a3d49531a169cab55bbdaca0ea1fe25a
ARG CRUSH_VERSION=0.100.0
ARG CRUSH_SHA256=122d4afe0e3bb0fc4c571f58b0c08d485c8733f272e962a02064c2150cd7a152
ARG GOOSE_VERSION=1.57.0
ARG GOOSE_SHA256=10eb96cb6a159b6e1d38eeedbef6ab64cd28168aad91948f1fa5c34eefdf98e3
ARG CODEX_VERSION=0.167.0
ARG CODEX_SHA256=9d64836106d5b374e90ee4454c7ebcde7ca7106558bd7e41a34b9f26ebda251a
ARG QWEN_CODE_VERSION=0.27.0
ARG CLAUDE_CODE_VERSION=2.1.319
ARG CODE_SERVER_VERSION=4.137.0
ARG CODE_SERVER_SHA256=9303165b7fd43532091922f77e2f119ff2fa109c6b6f1c3c966fb02f3d6d9c8b
ARG TTYD_VERSION=1.7.7
ARG FILEBROWSER_VERSION=2.63.23
ARG FILEBROWSER_SHA256=b14db2bb8033caa3f80205eb6578b2ed0744ebd9e716b790bc4a9703ce909e88
ARG SKILLS_COMMIT=2c5958ecac7cee2b583967a2c4981d0f4a75c579

# =============================================================================
# os — Debian userland and the agent user (uid 10001)
# =============================================================================
FROM ${DEBIAN_IMAGE} AS os
ENV DEBIAN_FRONTEND=noninteractive
COPY docker/install/system-deps.sh /tmp/system-deps.sh
RUN bash /tmp/system-deps.sh && rm -f /tmp/system-deps.sh

FROM ${NODE_IMAGE} AS nodedist

# --- Node 22 at /usr/local ---------------------------------------------------
FROM os AS node
COPY --from=nodedist /usr/local/ /opt/node/
COPY docker/install/install-node.sh /tmp/install-node.sh
RUN bash /tmp/install-node.sh && rm -rf /tmp/install-node.sh /opt/node

# --- Python 3.11 environment at /opt/pyenv ----------------------------------
FROM os AS pyenv
COPY docker/requirements-common.txt /tmp/requirements-common.txt
COPY docker/install/install-python-env.sh /tmp/install-python-env.sh
RUN bash /tmp/install-python-env.sh /tmp/requirements-common.txt \
 && rm -f /tmp/requirements-common.txt /tmp/install-python-env.sh

# --- code-server, ttyd, File Browser, VS Code extensions ---------------------
FROM os AS web
ARG CODE_SERVER_VERSION
ARG CODE_SERVER_SHA256
ARG TTYD_VERSION
ARG FILEBROWSER_VERSION
ARG FILEBROWSER_SHA256
COPY docker/install/install-web.sh /tmp/install-web.sh
RUN CODE_SERVER_VERSION="${CODE_SERVER_VERSION}" CODE_SERVER_SHA256="${CODE_SERVER_SHA256}" \
    TTYD_VERSION="${TTYD_VERSION}" \
    FILEBROWSER_VERSION="${FILEBROWSER_VERSION}" FILEBROWSER_SHA256="${FILEBROWSER_SHA256}" \
    bash /tmp/install-web.sh \
 && rm -f /tmp/install-web.sh

# --- agent CLIs, under /opt/agents --------------------------------------------
FROM node AS agents
ARG OPENCODE_VERSION
ARG OPENCODE_SHA256
ARG PI_VERSION
ARG PI_SHA256
ARG CRUSH_VERSION
ARG CRUSH_SHA256
ARG GOOSE_VERSION
ARG GOOSE_SHA256
ARG CODEX_VERSION
ARG CODEX_SHA256
ARG QWEN_CODE_VERSION
ARG CLAUDE_CODE_VERSION
COPY docker/install/install-agents.sh /tmp/install-agents.sh
RUN OPENCODE_VERSION="${OPENCODE_VERSION}" OPENCODE_SHA256="${OPENCODE_SHA256}" \
    PI_VERSION="${PI_VERSION}" PI_SHA256="${PI_SHA256}" \
    CRUSH_VERSION="${CRUSH_VERSION}" CRUSH_SHA256="${CRUSH_SHA256}" \
    GOOSE_VERSION="${GOOSE_VERSION}" GOOSE_SHA256="${GOOSE_SHA256}" \
    CODEX_VERSION="${CODEX_VERSION}" CODEX_SHA256="${CODEX_SHA256}" \
    QWEN_CODE_VERSION="${QWEN_CODE_VERSION}" CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION}" \
    bash /tmp/install-agents.sh \
 && rm -f /tmp/install-agents.sh

# --- skills library (Agent Skills, SKILL.md folders) ---------------------------
FROM os AS skills
ARG SKILLS_COMMIT
COPY docker/skills/ /tmp/yolo-skills/
COPY docker/install/install-skills.sh /tmp/install-skills.sh
RUN SKILLS_COMMIT="${SKILLS_COMMIT}" bash /tmp/install-skills.sh \
 && rm -rf /tmp/install-skills.sh /tmp/yolo-skills

# =============================================================================
# apps — everything that changes often, assembled once for all three tiers
# =============================================================================
FROM scratch AS apps
COPY --from=agents /opt/agents/ /opt/agents/
COPY --from=skills /opt/yolo/skills/ /opt/yolo/skills/
COPY docker/rootfs/opt/yolo/ /opt/yolo/
COPY docs/ /opt/yolo/docs/
COPY config/seccomp.json /opt/yolo/seccomp.json
COPY docker/rootfs/etc/ /etc/

FROM scratch AS apps-home
COPY docker/rootfs/home/agent/ /home/agent/

# =============================================================================
# platform-core — the rarely changing part of the core tier
# =============================================================================
FROM os AS platform-core

LABEL org.opencontainers.image.source="https://github.com/link2427/yolo-agent" \
      org.opencontainers.image.licenses="MIT"

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=pyenv /opt/pyenv /opt/pyenv
COPY --from=pyenv /opt/PYTHON-MANIFEST.txt /opt/yolo/manifests/python.txt
COPY --from=web /opt/code-server /opt/code-server
COPY --from=web /opt/vscode-extensions /opt/vscode-extensions
COPY --from=web /opt/yolo/manifests/ /opt/yolo/manifests/
COPY --from=web /usr/local/bin/ttyd /usr/local/bin/filebrowser /usr/local/bin/

# Links are made here rather than copied: COPY dereferences a symlink source.
RUN set -eu; \
    ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm; \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx; \
    ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \
    ln -sf /opt/pyenv/bin/python3 /usr/local/bin/python3; \
    ln -sf /opt/pyenv/bin/python3 /usr/local/bin/python; \
    ln -sf /opt/pyenv/bin/pip3 /usr/local/bin/pip3; \
    ln -sf /opt/pyenv/bin/pip3 /usr/local/bin/pip; \
    ln -sf /opt/code-server/bin/code-server /usr/local/bin/code-server; \
    mkdir -p /workspace /home/agent/.cache; \
    chown agent:agent /workspace /home/agent /home/agent/.cache; \
    node --version; python3 --version; code-server --version | head -1

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/agent \
    USER=agent \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    VIRTUAL_ENV=/opt/pyenv \
    PATH=/opt/yolo/bin:/opt/pyenv/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    YOLO_TIER=core

# =============================================================================
# platform-cpp — adds the C/C++/Fortran toolchain
# =============================================================================
FROM platform-core AS platform-cpp
COPY docker/install/install-toolchain.sh /tmp/install-toolchain.sh
RUN bash /tmp/install-toolchain.sh && rm -f /tmp/install-toolchain.sh \
 && { find / -xdev -type f -perm /6000 -exec chmod u-s,g-s {} + 2>/dev/null || true; }
ENV CCACHE_DIR=/home/agent/.cache/ccache \
    YOLO_TIER=cpp

# =============================================================================
# platform-full — adds the reverse-engineering toolchain
# =============================================================================
FROM platform-cpp AS platform-full
COPY docker/requirements-common.txt docker/requirements-reverse.txt \
     docker/requirements-reverse-nodeps.txt docker/install/install-python-env.sh /tmp/
# Extends the same /opt/pyenv rather than creating a second environment.
RUN bash /tmp/install-python-env.sh /tmp/requirements-common.txt \
      /tmp/requirements-reverse.txt /tmp/requirements-reverse-nodeps.txt \
 && mv /opt/PYTHON-MANIFEST.txt /opt/yolo/manifests/python.txt \
 && rm -f /tmp/requirements-*.txt /tmp/install-python-env.sh
COPY docker/install/install-reverse-tools.sh /tmp/install-reverse-tools.sh
RUN bash /tmp/install-reverse-tools.sh && rm -f /tmp/install-reverse-tools.sh \
 && ln -sf /opt/jadx/bin/jadx /usr/local/bin/jadx \
 && ln -sf /opt/ghidra/support/analyzeHeadless /usr/local/bin/ghidra-headless \
 && chown -R root:root /opt/java /opt/jadx /opt/ghidra \
 && { find / -xdev -type f -perm /6000 -exec chmod u-s,g-s {} + 2>/dev/null || true; }
ENV JAVA_HOME=/opt/java \
    PATH=/opt/yolo/bin:/opt/pyenv/bin:/opt/java/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    YOLO_TIER=full

# =============================================================================
# the three shippable tiers: platform + the shared apps layers
# =============================================================================
FROM platform-core AS core
COPY --from=apps / /
COPY --from=apps-home --chown=10001:10001 / /
RUN /opt/yolo/lib/finalize-image.sh
VOLUME ["/workspace", "/home/agent"]
WORKDIR /workspace
USER agent
EXPOSE 8080 7681 4096 8081 8000
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/yolo/bin/entrypoint"]
CMD ["/bin/bash", "-l"]
ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.title="yolo-agent" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"
ENV YOLO_VERSION=${VERSION}

FROM platform-cpp AS cpp
COPY --from=apps / /
COPY --from=apps-home --chown=10001:10001 / /
RUN /opt/yolo/lib/finalize-image.sh
VOLUME ["/workspace", "/home/agent"]
WORKDIR /workspace
USER agent
EXPOSE 8080 7681 4096 8081 8000
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/yolo/bin/entrypoint"]
CMD ["/bin/bash", "-l"]
ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.title="yolo-agent" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"
ENV YOLO_VERSION=${VERSION}

FROM platform-full AS full
COPY --from=apps / /
COPY --from=apps-home --chown=10001:10001 / /
RUN /opt/yolo/lib/finalize-image.sh
VOLUME ["/workspace", "/home/agent"]
WORKDIR /workspace
USER agent
EXPOSE 8080 7681 4096 8081 8000
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/yolo/bin/entrypoint"]
CMD ["/bin/bash", "-l"]
ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.title="yolo-agent" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"
ENV YOLO_VERSION=${VERSION}

# =============================================================================
# tests — build-only, never published
# =============================================================================
FROM core AS core-test
COPY --chmod=0755 docker/tests/ /tmp/tests/
RUN --network=none /tmp/tests/smoke-core.sh

FROM cpp AS cpp-test
COPY --chmod=0755 docker/tests/ /tmp/tests/
RUN --network=none /tmp/tests/smoke-core.sh && /tmp/tests/smoke-cpp.sh

FROM full AS full-test
COPY --chmod=0755 docker/tests/ /tmp/tests/
RUN --network=none /tmp/tests/smoke-core.sh && /tmp/tests/smoke-cpp.sh && /tmp/tests/smoke-reverse.sh
