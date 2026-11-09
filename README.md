# yolo-agent

An agent workstation for an air-gapped lab. Each person gets their own
container with coding agents, VS Code in the browser, a browser terminal and a
file manager, all pointed at the lab's vLLM server (SEC09) and Gitea. Nothing in
it needs the internet.

## Tiers

One image, three tiers. Pick one per person in their `.env`.

| Tag | Adds |
|---|---|
| `yolo-agent:3.0.0-core` | agents, web UIs, Python 3.11, Node 22, git |
| `yolo-agent:3.0.0-cpp` | gcc/g++/clang, gfortran with LAPACK/BLAS, cmake, ninja, gdb, and the mingw-w64 cross compilers for 64-bit Windows (C, C++, Fortran) |
| `yolo-agent:3.0.0-full` | everything in cpp, plus reverse-engineering tools: Ghidra headless, jadx, radare2, pycdc, pyinstxtractor-ng, binwalk, yara |

## What each person gets

| Port | Page |
|---|---|
| 8000 | Start page with a button for everything below |
| 8080 | VS Code (code-server), with the Kilo Code agent panel |
| 4096 | Chat: opencode's web UI, a full agent in the browser |
| 7681 | Terminal (tmux; closing the tab does not kill your work) |
| 8081 | Files: upload, download and zip files in `/workspace` |

Terminal agents: **Claude Code**, **opencode**, **Qwen Code**, **pi**,
**Crush**, **Goose**, and **Codex** (experimental: it needs the Responses API).
All are configured for SEC09 when the container starts and run without
permission prompts. There are no logins on these pages; they are meant for the
lab network only.

## Lab services

Run once per lab (`compose.lab.yaml`):

| Port | Service |
|---|---|
| 4000 | Monitor: a dashboard for SEC09 (load, tokens, latency, usage per person) and a proxy for `/v1/*` |
| 9000 | Bot: reviews pull requests, answers `@yolo` in Gitea, runs scheduled jobs |

## Install

Copy the release files into one folder on the WSL side, then:

```bash
unzip yolo-agent-3.0.0-kit.zip
./yolo-agent-3.0.0/install.sh load .        # check SHA256SUMS, load the images
./yolo-agent-3.0.0/install.sh new alice     # make ~/yolo/alice and start it
```

Open `http://localhost:8000`. In the terminal, `yolo login` stores the person's
Gitea token and `yolo doctor` checks everything.

## Settings

Lab defaults are in the image (`/etc/yolo/defaults.env`): SEC09 at
`192.168.1.101:8000`, Gitea at `192.168.1.27:3000`, git identity "YOLO Agent"
<yoloagent@gmail.com>. The fleet repo in Gitea (`yolo/fleet`) overrides them for
everyone or per person, and the person's `.env` overrides that. No token is ever
in the image or this repository.

## Documentation

Start at [docs/00-INDEX.md](docs/00-INDEX.md). Most people need only
[02-QUICKSTART](docs/02-QUICKSTART.md); whoever runs the lab wants
[14-LAB](docs/14-LAB.md).

## Building

```bash
docker buildx bake            # all three tiers through their smoke tests
docker buildx bake images     # just the images
./scripts/package-offline.sh 3.0.0 yolo-agent -- dist   # the offline release
```

Pinned versions are in [PINS.md](PINS.md); changes in
[CHANGELOG.md](CHANGELOG.md).
