# yolo-agent

A persistent Linux/amd64 environment for autonomous coding agents, recovered
from the original Container Forge workspace and reorganized into a reproducible
Docker build.

It includes opencode, goose, pi, aider, Prime Agent, DeepSeek Harness, and
OpenHands, plus code-server, a persistent ttyd/tmux terminal, and the pinned
skills library. Runtime credentials are supplied only through an ignored env
file.

## The image

`yolo-agent` is a single always-on browser runtime. It ships every agent
harness, the browser IDE (code-server), the terminal (ttyd/tmux), OpenHands
(`openhands web` on port 3000), and DeepSeek Harness. There is no separate headless
variant: every web surface is exposed by default, because this build targets
an air-gapped internal network.

## Build and test

```bash
# Build the image and run its smoke suite.
docker buildx bake

# Build the image without running the smoke suite.
docker buildx bake images

# Build directly.
docker build --target runtime -t yolo-agent:2.0.1 .
```

Each installer is isolated under `docker/install/`, so changes to the web IDE
or skills do not invalidate the agent layers. Published tags are produced by
GitHub Actions when a `v*` tag is pushed.

## Offline release bundles

Each release attaches one ready-to-burn ZIP:

- `yolo-agent-<version>-offline.zip`

The ZIP contains a Docker-loadable image archive, Linux and Windows launchers,
Compose configuration, the seccomp policy, the public-safe environment
template, documentation, exact offline loading instructions, the source
commit, image metadata, and SHA-256 checksums. The ZIP itself has a separate
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

# Persistent browser stack (code-server, ttyd, OpenHands, DeepSeek Harness).
docker compose up -d
```

The browser ports are bound to `0.0.0.0` by default (internal network use):

- code-server: `http://<host>:8080`
- ttyd/tmux: `http://<host>:7681`
- OpenHands: `http://<host>:3000`
- DeepSeek Harness: `http://<host>:3080`

Set `YOLO_BIND_ADDRESS=127.0.0.1` if you ever want host-loopback binding. The
legacy cross-platform launchers remain in `bin/`.

## Persistence

`yolo-agent-home-v1` retains agent sessions, tools installed into the user
home, SSH configuration, and terminal state. The selected project directory
is bind-mounted at `/workspace`. Closing a browser tab does not end the tmux
session; deleting the named volume does delete the persisted agent home.
DeepSeek Harness stores its profiles and sessions under `~/.dsh` in that same
volume, while project files remain in `/workspace`. OpenHands keeps its
conversations and settings under `~/.openhands`.

## Repository layout

```text
Dockerfile                 composable image stages (single runtime)
docker/install/            pinned agent, IDE, OpenHands, and skill installers
docker/rootfs/             files copied into the runtime image
docker/tests/              image smoke tests
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
