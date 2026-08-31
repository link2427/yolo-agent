# yolo-agent

A persistent Linux/amd64 environment for autonomous coding agents, recovered
from the original Container Forge workspace and reorganized into a reproducible
Docker build.

It includes opencode, goose, pi, aider, Prime Agent, and DeepSeek Harness. The
full profile also includes code-server, a persistent ttyd/tmux terminal, and
the pinned skills library. Runtime credentials are supplied only through an
ignored env file.

## Images

| Profile | Docker target | Contents |
| --- | --- | --- |
| Full | `runtime-full` | Agents, browser IDE, terminal, and skills library |
| Headless | `runtime-headless` | All agents without the browser IDE or skills library |

The default `runtime` target aliases the full image for compatibility.

## Build and test

```bash
# Run both image-level smoke suites.
docker buildx bake

# Build local images without running tests.
docker buildx bake images

# Build one profile directly.
docker build --target runtime-headless -t yolo-agent:1.1.0-headless .
docker build --target runtime-full -t yolo-agent:1.1.0 .
```

Each installer is isolated under `docker/install/`, so changes to the web IDE
do not invalidate the agent or skills layers. Published tags are produced by
GitHub Actions when a `v*` tag is pushed.

## Offline release bundles

Each release attaches two ready-to-burn ZIP files:

- `yolo-agent-<version>-full-offline.zip`
- `yolo-agent-<version>-headless-offline.zip`

Each ZIP contains a Docker-loadable image archive, Linux and Windows
launchers, Compose configuration, the seccomp policy, public-safe environment
template, documentation, exact offline loading instructions, source commit,
image metadata, and SHA-256 checksums. The ZIP itself has a separate
`.zip.sha256` release asset.

The ZIP uses maximum compression to stay within GitHub's asset limit. If a
bundle still exceeds 2 GiB, the release contains numbered ZIP parts and a
`REASSEMBLE.txt` file; download every part and follow those instructions.
After downloading or reassembling, unzip it and follow `LOAD-OFFLINE.txt`; no
registry or internet connection is required after `docker load`.

## Run

Create the local configuration first (Compose can start without it, but agents
will not receive your model or Git settings):

```bash
cp config/yolo.env.example config/yolo.env
```

Then use Compose:

```bash
# Disposable interactive container; home and project files persist.
docker compose run --rm agent

# Persistent browser IDE and tmux terminal.
docker compose --profile server up -d server

# Persistent DeepSeek Harness browser UI (uses DEEPSEEK_API_KEY from yolo.env).
docker compose --profile deepseek up -d deepseek
```

The safe default binds browser ports only to localhost:

- code-server: `http://127.0.0.1:8080`
- ttyd/tmux: `http://127.0.0.1:7681`
- DeepSeek Harness: `http://127.0.0.1:3080`

Set `YOLO_BIND_ADDRESS=0.0.0.0` only behind an authenticated reverse proxy or
on a trusted network. The legacy cross-platform launchers remain in `bin/`.

## Persistence

`yolo-agent-home-v1` retains agent sessions, tools installed into the user
home, SSH configuration, and terminal state. The selected project directory
is bind-mounted at `/workspace`. Closing a browser tab does not end the tmux
session; deleting the named volume does delete the persisted agent home.
DeepSeek Harness stores its profiles and sessions under `~/.dsh` in that same
volume, while project files remain in `/workspace`.

## Repository layout

```text
Dockerfile                 composable image stages and profiles
docker/install/            pinned agent, IDE, and skill installers
docker/rootfs/             files copied into the runtime image
docker/tests/              profile-specific smoke tests
bin/                       Linux and Windows host launchers
config/                    seccomp policy and public-safe env example
docs/                      current operator documentation
history/                   recovered v5/v6 provenance (no large archives)
compose.yaml               hardened local runtime
docker-bake.hcl            repeatable build matrix
.github/workflows/         CI, GHCR publishing, and offline release bundles
```

## Recovered versions

- `archive-yolo-dev-6.0-recovered` preserves the exact recovered source as
  imported history, outside the new semantic-version sequence.
- `history/v5.0/` is a partial snapshot because the 5.0 Docker build context
  did not survive. Its original image checksum and build log are retained.
- `v1.0.0` begins the reorganized, source-first release line.

Large `.docker.tar` and skill-library `.zip` exports are intentionally not
committed. See `history/README.md` and `CHANGELOG.md`.

## Security

The launch configuration uses uid 10001, a read-only root filesystem, no Linux
capabilities, `no-new-privileges`, resource limits, and a seccomp deny list. It
does not mount the Docker socket. Agents are unrestricted within the writable
home and project mounts, so use a dedicated GitHub identity or narrowly scoped
token for repositories where destructive changes matter.

Read `SECURITY.md` and `PINS.md` before exposing browser endpoints or changing
the build pins.
