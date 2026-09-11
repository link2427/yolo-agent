# syntax=docker/dockerfile:1.12
#
# yolo-agent-cpp — the C/C++ image.
#
# Same agents, same Python 3.11 environment, plus a complete offline C/C++
# toolchain:
#
#   native linux/amd64 : gcc, g++, clang, clang++, lld, lldb, gdb, make, ninja,
#                        cmake, pkg-config, strace, valgrind, ccache, nasm, lcov
#   cross Windows x64  : mingw-w64 gcc/g++ (x86_64-w64-mingw32-*) -> PE32+
#
# Everything is baked in because the target host has no internet: whatever is
# not in this image can never be added later. There is no Wine, so Windows
# binaries can be cross-COMPILED but not executed here; see the docs.
#
# The base image is not published separately — this Dockerfile rebuilds it and
# copies the results forward, so `docker load` of yolo-agent-cpp alone is
# enough to run it offline.

# =============================================================================
# base — identical content to Dockerfile's runtime stage (kept in lockstep)
# =============================================================================
ARG VERSION=2.0.0
ARG VCS_REF=unknown
ARG NODE_IMAGE=node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5
ARG DEBIAN_IMAGE=debian:bookworm-slim

ARG OPENCODE_VERSION=1.18.30
ARG OPENCODE_SHA256=55007246858165496ff85ba1c2b648f7421e8e2013bf4189a680c9ff8e699d17
ARG PI_VERSION=0.85.1
ARG PI_SHA256=494e498f47d74d21f40b3386f6a5e921a3d49531a169cab55bbdaca0ea1fe25a
ARG DSH_VERSION=0.1.5-rc.1
ARG CODE_SERVER_VERSION=4.137.0
ARG CODE_SERVER_SHA256=9303165b7fd43532091922f77e2f119ff2fa109c6b6f1c3c966fb02f3d6d9c8b
ARG TTYD_VERSION=1.7.7

FROM ${DEBIAN_IMAGE} AS base
ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.title="yolo-agent-cpp" \
      org.opencontainers.image.description="yolo-agent plus an offline C/C++ toolchain and a mingw-w64 cross compiler" \
      org.opencontainers.image.source="https://github.com/link2427/yolo-agent"
ENV DEBIAN_FRONTEND=noninteractive
COPY docker/install/system-deps.sh /tmp/system-deps.sh
RUN bash /tmp/system-deps.sh && rm -f /tmp/system-deps.sh

FROM ${NODE_IMAGE} AS nodedist

FROM base AS node
COPY --from=nodedist /usr/local/ /opt/node/
COPY docker/install/install-node.sh /tmp/install-node.sh
RUN bash /tmp/install-node.sh && rm -f /tmp/install-node.sh
ENV PATH=/usr/local/bin:$PATH

FROM node AS agents
ARG OPENCODE_VERSION
ARG OPENCODE_SHA256
ARG PI_VERSION
ARG PI_SHA256
# The agent user is created in the shared `base` layer (system-deps.sh).
COPY docker/install/install-agents.sh /tmp/install-agents.sh
RUN OPENCODE_VERSION="${OPENCODE_VERSION}" OPENCODE_SHA256="${OPENCODE_SHA256}" \
    PI_VERSION="${PI_VERSION}" PI_SHA256="${PI_SHA256}" \
    bash /tmp/install-agents.sh \
 && rm -f /tmp/install-agents.sh

FROM agents AS deepseek-harness
ARG DSH_VERSION
COPY docker/deepseek-harness/ /tmp/deepseek-harness/
COPY docker/install/install-deepseek-harness.sh /tmp/install-deepseek-harness.sh
RUN DSH_VERSION="${DSH_VERSION}" bash /tmp/install-deepseek-harness.sh \
 && rm -rf /tmp/deepseek-harness /tmp/install-deepseek-harness.sh

FROM base AS pyenv
COPY docker/requirements-common.txt /tmp/requirements-common.txt
COPY docker/install/install-python-env.sh /tmp/install-python-env.sh
RUN bash /tmp/install-python-env.sh /tmp/requirements-common.txt \
 && rm -f /tmp/requirements-common.txt /tmp/install-python-env.sh

FROM base AS web-ide
# The agent user is created in the shared `base` layer (system-deps.sh).
COPY docker/install/install-web-ide.sh /tmp/install-web-ide.sh
RUN CODE_SERVER_VERSION="${CODE_SERVER_VERSION}" \
    CODE_SERVER_SHA256="${CODE_SERVER_SHA256}" \
    TTYD_VERSION="${TTYD_VERSION}" \
    HOME=/home/agent bash /tmp/install-web-ide.sh \
 && rm -f /tmp/install-web-ide.sh

# =============================================================================
# runtime — the shippable yolo-agent-cpp image
# =============================================================================
FROM base AS runtime

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    VIRTUAL_ENV=/opt/pyenv \
    HOME=/home/agent \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0 \
    DSH_HOME=/home/agent/.dsh \
    CCACHE_DIR=/home/agent/.cache/ccache \
    YOLO_FLAVOR=cpp \
    PATH=/opt/pyenv/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Node runtime. The `node` stage installed it into /usr/local; this stage
# descends from `base`, so it must copy that tree in explicitly rather than
# relying on the stage chain.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
# Symlinks are recreated rather than copied: COPY dereferences a symlink source,
# which would leave /usr/local/bin/corepack holding cli.js bytes under the wrong
# name.
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
 && node --version && npm --version && corepack --version

COPY --from=deepseek-harness /opt/opencode /opt/opencode
COPY --from=deepseek-harness /opt/pi /opt/pi
COPY --from=deepseek-harness /usr/local/bin/opencode /usr/local/bin/opencode
COPY --from=deepseek-harness /usr/local/bin/pi /usr/local/bin/pi
COPY --from=deepseek-harness /opt/deepseek-harness /opt/deepseek-harness
COPY --from=deepseek-harness /usr/local/bin/dsh /usr/local/bin/dsh

COPY --from=pyenv /opt/pyenv /opt/pyenv
COPY --from=pyenv /opt/PYTHON-MANIFEST.txt /opt/PYTHON-MANIFEST.txt

COPY --from=web-ide /opt/code-server /opt/code-server
COPY --from=web-ide /usr/local/bin/ttyd /usr/local/bin/ttyd
COPY --from=web-ide /opt/yolo/EXTENSIONS-MANIFEST.txt /opt/yolo/EXTENSIONS-MANIFEST.txt
COPY --from=web-ide --chown=agent:agent /home/agent/.local/share/code-server/extensions/ /home/agent/.local/share/code-server/extensions/

COPY docker/rootfs/home/agent/ /home/agent/
COPY docker/rootfs/opt/yolo/ /opt/yolo/
COPY config/seccomp-toolchain.json /opt/yolo/seccomp.json
COPY docs/ /opt/yolo/docs/

RUN ln -sf /opt/pyenv/bin/python3 /usr/local/bin/python3 \
 && ln -sf /opt/pyenv/bin/python3 /usr/local/bin/python \
 && ln -sf /opt/pyenv/bin/pip3 /usr/local/bin/pip3 \
 && ln -sf /opt/pyenv/bin/pip3 /usr/local/bin/pip \
 && ln -sf /opt/code-server/bin/code-server /usr/local/bin/code-server \
 && mkdir -p /workspace \
 && chmod 0755 /opt/yolo/*.sh \
 && chown -R root:root /opt/yolo /opt/code-server /opt/pyenv /opt/deepseek-harness /opt/opencode /opt/pi \
 && chown -R agent:agent /home/agent \
 && chown agent:agent /workspace

# --- C/C++ toolchain --------------------------------------------------------
# Deliberately its own layer AFTER the agent layers, so a toolchain bump
# re-runs only this step. It is installed in place rather than copied from a
# staging stage because apt payload spans /usr/bin, /usr/lib and /usr/share:
# copying whole prefixes across stages merges two filesystems and can clobber
# files the runtime already owns.
COPY docker/install/install-toolchain.sh /tmp/install-toolchain.sh
RUN bash /tmp/install-toolchain.sh && rm -f /tmp/install-toolchain.sh
# /home/agent is a volume, so this directory must exist and be agent-owned at
# image level or ccache cannot write to it at runtime.
RUN mkdir -p "$CCACHE_DIR" && chown -R agent:agent "$CCACHE_DIR"
RUN find / -xdev -type f -perm /6000 -exec chmod u-s,g-s {} + 2>/dev/null || true

VOLUME ["/workspace", "/home/agent", "/tmp"]
WORKDIR /workspace
USER agent
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "-l"]

ARG VERSION
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

# =============================================================================
# test — build-only validation, never published
# =============================================================================
FROM runtime AS test

ARG OPENCODE_VERSION
ARG PI_VERSION
ARG DSH_VERSION
ARG CODE_SERVER_VERSION
ARG TTYD_VERSION

COPY --chmod=0755 docker/tests/smoke-common.sh docker/tests/smoke-cpp.sh /tmp/
RUN OPENCODE_VERSION="${OPENCODE_VERSION}" \
    PI_VERSION="${PI_VERSION}" \
    DSH_VERSION="${DSH_VERSION}" \
    CODE_SERVER_VERSION="${CODE_SERVER_VERSION}" \
    TTYD_VERSION="${TTYD_VERSION}" \
    /tmp/smoke-common.sh \
 && /tmp/smoke-cpp.sh

