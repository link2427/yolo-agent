# 01 — Overview

yolo-agent runs unrestricted autonomous coding agents inside a sealed
Linux/amd64 container on a Windows host that has **no internet access**. It is
built to be exported as a Docker image archive, carried across the air gap, and
loaded — after which it never needs the network again.

## Three images

The repository builds three containers from shared fragments. They are not
layered on a published base image: each one materializes a complete filesystem,
so loading a single archive is enough to run that container offline.

| Image | Dockerfile | Purpose | Adds over the base |
|---|---|---|---|
| `yolo-agent` | `Dockerfile` | general development | — (this *is* the base) |
| `yolo-agent-cpp` | `Dockerfile.cpp` | C and C++ projects | offline compilers, cmake, and a mingw-w64 Windows cross toolchain |
| `yolo-agent-reverse-engineering` | `Dockerfile.reverse` | decompilation and binary analysis | pycdc, pyinstxtractor-ng, pydumpck, uncompyle6, jadx, Ghidra, radare2, angr |

All three contain the same three agents (opencode, pi, DeepSeek Harness), the
same browser IDE (code-server + ttyd/tmux), and the same Python 3.11 environment
shape. The difference is the toolchain on top.

## What is in every image

- **Agents** — opencode 1.18.30, pi 0.85.1, DeepSeek Harness 0.1.5-rc.1, all
  pre-wired for YOLO mode against your local model endpoint.
- **Browser IDE** — code-server 4.137.0 with 19 pre-installed extensions (21
  entries once VS Code's dependency closure is included), and
  ttyd 1.7.7 wrapping a persistent tmux session.
- **Python** — exactly one environment at `/opt/pyenv`, Python 3.11, ~45
  packages for general development.
- **Node 22** — for the agent CLIs and the DeepSeek Harness plugin graph.

## The one-mount model

The container is given exactly one host folder:

```
host                              container
──────────────────────────────    ──────────────────────────────────────────
C:\work\my-project           →    /workspace      (rw, the only host mount)
(named docker volume)        →    /home/agent     (rw, agent state + secrets)
                                  /opt/...        (ro, image content)
                                  /tmp, /run      (tmpfs)
```

`/workspace` is the project mount. `/home/agent` is a **named volume**, not a
host path, so agent sessions, SSH keys, and git credentials persist across
container replacement without ever appearing in a host directory you might
sync or share.

The three flavors use separate volumes, so configuring one does not configure
the others:

| Flavor | Volume | Env file |
|---|---|---|
| base | `yolo-agent-base-home-v1` | `config/base.env` |
| cpp | `yolo-agent-cpp-home-v1` | `config/cpp.env` |
| reverse | `yolo-agent-reverse-home-v1` | `config/reverse.env` |

## Containment

Every container runs with:

- uid/gid **10001**, unprivileged, with a read-only root filesystem;
- **all Linux capabilities dropped** and `no-new-privileges`;
- a **seccomp denylist** (`config/seccomp-base.json` for the base image,
  `config/seccomp-toolchain.json` for cpp/reverse, which additionally allows
  `ptrace` so debuggers work);
- no Docker socket, no host PID/network namespace, no other mounts;
- memory, CPU, and PID limits.

Inside that boundary the agents are deliberately unrestricted — no permission
prompts, ever. That is what "yolo" means here, and it is why `/workspace` should
point at a scratch directory rather than anything irreplaceable. See
[10-SECURITY.md](10-SECURITY.md).

## Air-gap design rules

Three rules shape almost every decision in this repository:

1. **Fetch at build time, never at run time.** Agent binaries, VS Code
   extensions, Python wheels, the C++ toolchain, and Ghidra are all downloaded
   during `docker build` and baked in. The runtime container has no package
   manager that can reach anything.
2. **Pin everything.** The image cannot be repaired after export, so a hash
   mismatch must fail the build rather than silently ship something else. See
   [11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md).
3. **Self-contained images.** No runtime dependency on another image from a
   registry the offline host cannot reach.

## Repository layout

```text
Dockerfile                 yolo-agent (base)
Dockerfile.cpp             yolo-agent-cpp
Dockerfile.reverse         yolo-agent-reverse-engineering
docker-bake.hcl            build matrix for all three images
compose.yaml               base container
compose.cpp.yaml           C/C++ container
compose.reverse.yaml       reverse-engineering container
config/                    seccomp profiles and env templates
docker/install/            pinned installers shared by all three images
docker/requirements-*.txt  the Python 3.11 package sets
docker/rootfs/             files copied into every image
docker/tests/              per-image smoke suites (the build gate)
bin/                       Linux and Windows host launchers
scripts/                   offline bundle packaging
history/                   recovered v5/v6 provenance
```

## Version lineage

- `archive-yolo-dev-6.0-recovered` preserves the exact recovered source as
  imported history, outside the semantic-version sequence.
- `history/v5.0/` is a partial snapshot: the 5.0 Docker build context did not
  survive, so its original image checksum and build log are retained instead.
- `v1.0.0` began the reorganized, source-first release line.
- **`v2.0.0` is the modular overhaul**: three images, three agents, one Python
  environment, and OpenHands/prime-agent/goose/aider removed.
