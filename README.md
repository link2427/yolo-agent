# yolo-agent

Three containers for running unrestricted autonomous coding agents on an
**air-gapped** host. One folder is mounted; everything else is baked into the
image. Build on a networked machine, export, `docker load`, done — the runtime
never reaches the network again.

| Image | For | Adds over the base |
|---|---|---|
| `yolo-agent` | general development | opencode, pi, DeepSeek Harness, code-server, ttyd/tmux, Python 3.11 with ~45 packages |
| `yolo-agent-cpp` | C/C++ projects | cmake, ninja, clang, gcc/g++, gdb, ccache + **mingw-w64 cross compiler** producing 64-bit Windows PE binaries |
| `yolo-agent-reverse-engineering` | decompilation | pycdc/pycdas, pyinstxtractor-ng, decompyle3, pydumpck, jadx, Ghidra headless, radare2, angr, capstone, unicorn |

Every image is self-contained: loading one archive is enough to run that
container offline. There is no separately published base image to chase.

## The one-mount model

The container gets exactly **one** host folder, mounted at `/workspace`. Agent
state, secrets, caches, and terminals live in a named Docker volume at
`/home/agent` that is separate from your data. Nothing else from the host is
visible — no Docker socket, no home directory, no other drives.

```
host                          container
──────────────────────────    ─────────────────────────────────
/path/to/your/project    →    /workspace        (the only mount)
  (named volume)         →    /home/agent       (agent state, secrets, caches)
                              /opt/...          (read-only image content)
```

## Quick start

```bash
# 1. Configure the model endpoint (see config/*.env.example).
cp config/base.env.example config/base.env
$EDITOR config/base.env

# 2. Build and smoke-test all three images.
docker buildx bake

# 3. Build just the shippable images.
docker buildx bake images
```

Run it — pick a flavor with `-f`:

```bash
# base
docker compose run --rm agent
docker compose up -d                       # code-server :8080, ttyd :7681, dsh :3080

# C/C++
docker compose -f compose.cpp.yaml run --rm agent

# reverse engineering
docker compose -f compose.reverse.yaml run --rm agent
```

The same, without compose:

```bash
./bin/run.sh                     # base, project dir = $PWD
CONTAINER=cpp ./bin/run.sh       # C/C++
CONTAINER=reverse ./bin/run.sh   # reverse engineering
./bin/run-server.sh              # persistent IDE + terminal
```

Windows hosts have equivalent launchers: `bin\run.ps1` and
`bin\run-server.ps1`, with `-Container base|cpp|reverse`.

## The agents

Three, and only three. All are pre-configured for YOLO mode — **no permission
prompts, ever** — against your local OpenAI-compatible endpoint.

| Agent | Command | Notes |
|---|---|---|
| opencode | `opencode` | `"permission": "allow"`; provider/model written to `~/.config/opencode/opencode.json` |
| pi | `pi` | `defaultProjectTrust: "always"`; telemetry off; `~/.pi/agent/` |
| DeepSeek Harness | `dsh` / `dsh web` | local endpoint only; the DeepSeek cloud provider is deliberately left empty |

Set `VLLM_BASE_URL` and `VLLM_MODEL` in the env file and the configs are written
automatically on first launch. See [docs/09-MODEL-ENDPOINT.md](docs/09-MODEL-ENDPOINT.md).

## One Python environment

Every image ships exactly **one** Python 3.11 environment at `/opt/pyenv`, first
on `PATH`, with `VIRTUAL_ENV` already set. There is no second interpreter, no
per-agent venv, and no conda.

```bash
python3 --version          # 3.11.x
pip install <pkg>          # allowed, but see the air-gap warning below
```

`yolo-agent-reverse-engineering` extends that *same* environment with the
decompilation packages instead of creating another one.

> **Air gap:** the host has no internet, so `pip install` cannot fetch anything
> new at runtime. The environment is complete as shipped; note any package you
> need *before* building the image, and add it to `docker/requirements-*.txt`.

## Air-gapped operation

Everything — agent binaries, code-server extensions, Python packages, the C++
toolchain, Ghidra — is downloaded at **build** time and baked in. The runtime
container performs no downloads.

Tagged releases attach one offline ZIP per image:

```
yolo-agent-base-2.0.0-offline.zip
yolo-agent-cpp-2.0.0-offline.zip
yolo-agent-reverse-engineering-2.0.0-offline.zip
```

Each contains a Docker-loadable archive, launchers, the compose file, the
seccomp profile, an env template, documentation, SHA-256 checksums, and
`LOAD-OFFLINE.txt` with the exact load commands. Verify, `docker load`, run. If
a bundle exceeds GitHub's 2 GiB asset limit it is split into numbered parts with
checksums and a `REASSEMBLE.txt`.

## What changed in 2.0

- **Modularized** into three independently buildable images sharing
  `docker/install/` and `docker/rootfs/` fragments.
- **Removed** OpenHands (never worked reliably here), prime-agent, goose, and
  aider — leaving opencode, pi, and DeepSeek Harness.
- **Collapsed the Python surface** into one 3.11 environment per image.
- **Dropped the 147 MB skills library**; agents author skills in `/workspace`
  instead.
- **Added** the C/C++ and reverse-engineering containers.
- **Refreshed every pin** (opencode 1.18.30, pi 0.85.1, dsh 0.1.5-rc.1,
  code-server 4.137.0); see [PINS.md](PINS.md).

## Repository layout

```text
Dockerfile                 yolo-agent            (base)
Dockerfile.cpp             yolo-agent-cpp
Dockerfile.reverse         yolo-agent-reverse-engineering
docker-bake.hcl            build matrix for all three
compose.yaml               base container
compose.cpp.yaml           C/C++ container
compose.reverse.yaml       reverse-engineering container
config/                    seccomp profiles + env templates
docker/install/            pinned installers, shared by all three images
docker/requirements-*.txt  the Python 3.11 package sets
docker/rootfs/             files copied into every image
docker/tests/              per-image smoke suites (the build gate)
bin/                       Linux and Windows host launchers
docs/                      operator documentation
scripts/                   offline bundle packaging
history/                   recovered v5/v6 provenance (no large archives)
```

## Documentation

Start at [docs/00-INDEX.md](docs/00-INDEX.md). The most useful entries:

- [docs/02-QUICKSTART.md](docs/02-QUICKSTART.md) — build, load, and run
- [docs/04-PYTHON.md](docs/04-PYTHON.md) — the single Python environment
- [docs/05-CPP.md](docs/05-CPP.md) — Windows cross-compilation
- [docs/06-REVERSE-ENGINEERING.md](docs/06-REVERSE-ENGINEERING.md) — decompiling `.exe` files
- [docs/10-SECURITY.md](docs/10-SECURITY.md) — containment model and its limits

## Security

Read [SECURITY.md](SECURITY.md) and [PINS.md](PINS.md) before exposing browser
endpoints or changing build pins. In short: uid 10001, read-only root
filesystem, all capabilities dropped, `no-new-privileges`, a seccomp denylist,
and no Docker socket. The agents are *unrestricted inside the container* by
design — that is the point of YOLO mode — so the workspace mount is the real
security boundary. Point it at a scratch directory, not at anything you care
about.
