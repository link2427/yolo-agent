# 13 — Command reference

Operator cheat sheet. `flavor` is `base`, `cpp`, or `reverse` throughout. Host
commands run from the repository root unless noted; commands marked *inside the
container* run in an agent shell (compose `exec`, a launcher, or the ttyd
terminal).

Related: [01-OVERVIEW.md](01-OVERVIEW.md), [02-QUICKSTART.md](02-QUICKSTART.md),
[09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md), [10-SECURITY.md](10-SECURITY.md),
[11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md).

## Flavors at a glance

| Flavor | Image (default tag) | Compose file | Env file | Home volume | Smoke target |
|---|---|---|---|---|---|
| base | `yolo-agent:2.0.0` | `compose.yaml` | `config/base.env` | `yolo-agent-base-home-v1` | `base-test` |
| cpp | `yolo-agent-cpp:2.0.0` | `compose.cpp.yaml` | `config/cpp.env` | `yolo-agent-cpp-home-v1` | `cpp-test` |
| reverse | `yolo-agent-reverse-engineering:2.0.0` | `compose.reverse.yaml` | `config/reverse.env` | `yolo-agent-reverse-home-v1` | `reverse-test` |

The compose files and the launchers use the same home-volume names, so moving
between them reuses the same configured home. `YOLO_HOME_VOLUME` overrides the
name in both.

Two different variable channels feed a container, and confusing them is the
easiest mistake to make here:

- **Host side.** Every `${...}` in a compose file is substituted by Compose
  *before* the container exists, and the launchers read these names from their own
  environment. Values come from your shell or from a `.env` file in the repository
  root. `config/<flavor>.env` has no effect on them.
- **Container side.** `config/<flavor>.env` is handed to the container with
  `env_file:` / `--env-file`, so only variables that processes *inside* the
  container read (`VLLM_*`, `GITEA_*`, `CMAKE_BUILD_TYPE`, …) belong there.

Each flavor builds from its own Dockerfile (`Dockerfile`, `Dockerfile.cpp`,
`Dockerfile.reverse`) and runs its own seccomp profile: `config/seccomp-base.json`
for base, `config/seccomp-toolchain.json` for cpp and reverse.

## Build

### Bake (the normal path)

```bash
docker buildx bake                      # default group: base-test, cpp-test, reverse-test
docker buildx bake images               # the three shippable images, no smoke suite
docker buildx bake base                 # one image (also: cpp, reverse)
docker buildx bake base-test            # one smoke suite (also: cpp-test, reverse-test)
docker buildx bake tests                # the tests group (same three as the default)
docker buildx bake --print              # print the resolved graph, build nothing
docker buildx bake base cpp             # any combination of targets
```

`docker buildx bake` with no arguments builds the `test` target of all three
images, which chains through `runtime`: it is the real gate, and those images are
not tagged. The comment at the top of `docker-bake.hcl` calls that group `test`;
the group is actually named `tests`. Use the no-argument default.

Tags and variables come from `docker-bake.hcl`:

```bash
VERSION=2.0.1 docker buildx bake images          # default: 2.0.0
REGISTRY=ghcr.io/you docker buildx bake images   # default: ghcr.io/link2427
docker buildx bake --set 'base.cache-from=type=gha,scope=ci-base' base-test
```

Every image target produces a registry tag and a local tag (for example
`ghcr.io/link2427/yolo-agent-cpp:2.0.0` and `yolo-agent-cpp:2.0.0`). All builds
target `linux/amd64`.

### Direct `docker build`

```bash
docker build --target runtime -t yolo-agent:2.0.0 .
docker build --target runtime -f Dockerfile.cpp     -t yolo-agent-cpp:2.0.0 .
docker build --target runtime -f Dockerfile.reverse -t yolo-agent-reverse-engineering:2.0.0 .

# Smoke suite only (builds the runtime stage underneath, leaves it untagged).
docker build --target test -f Dockerfile.cpp .

# Explicit platform, when the builder default is not amd64.
docker buildx build --platform linux/amd64 --target runtime \
  -f Dockerfile.reverse -t yolo-agent-reverse-engineering:2.0.0 .
```

`--target test` runs that flavor's smoke suite and fails the build if the suite
fails. Never publish or load a `test` image; it is validation only.

## Run

### Compose

```bash
# Interactive shell: the `agent` service is in the `cli` profile.
docker compose run --rm agent
docker compose -f compose.cpp.yaml run --rm agent
docker compose -f compose.reverse.yaml run --rm agent

# One command instead of a shell.
docker compose run --rm agent opencode

# Persistent services in the background.
docker compose up -d                                   # base: server + deepseek
docker compose -f compose.cpp.yaml up -d
docker compose -f compose.reverse.yaml up -d
```

`docker compose up -d` starts `server` (code-server + ttyd) and `deepseek`; it
does not start `agent`, because that service is profile-gated. `compose run`
enables the profile for that one container.

Every compose file reads its own env file with `required: false`, so a missing
`config/<flavor>.env` is not an error — the agents keep their baked defaults. The
workspace mount defaults to `.` (the current directory) and is overridden with
`YOLO_WORKSPACE`.

### Host launchers

```bash
./bin/run.sh                                     # base, project dir = $PWD
CONTAINER=cpp ./bin/run.sh                       # C/C++
CONTAINER=reverse ./bin/run.sh                   # reverse engineering
./bin/run.sh opencode                            # any command replaces the shell
CONTAINER=cpp ./bin/run.sh /bin/bash -lc 'cpp-build.sh /workspace/src both'

./bin/run-server.sh                              # base: IDE :8080, terminal :7681
CONTAINER=cpp ./bin/run-server.sh
CONTAINER=reverse ./bin/run-server.sh
```

`bin/run.sh` mounts the current working directory at `/workspace` — `cd` into
your project first. It requires `config/<flavor>.env` to exist and exits with an
error otherwise. It publishes no ports.

`bin/run-server.sh` publishes code-server and ttyd only; the DeepSeek Harness UI
is published by the compose files. It takes no command argument and replaces any
container already named `yolo-agent-<flavor>-server`.

### Windows (PowerShell)

```powershell
.\bin\run.ps1                              # base
.\bin\run.ps1 -Container cpp
.\bin\run.ps1 -Container reverse opencode  # remaining arguments are the command
.\bin\run.ps1 -Image yolo-agent:2.0.1      # or $env:YOLO_IMAGE
.\bin\run-server.ps1 -Container cpp
$env:CONTAINER = 'cpp'; .\bin\run.ps1      # -Container defaults to $env:CONTAINER
```

### Without a launcher

```bash
docker run --rm -it --name yolo-agent-base \
  --user 10001:10001 --read-only \
  --tmpfs /tmp:rw,nosuid,size=2g \
  -v "$PWD:/workspace" -v yolo-agent-base-home-v1:/home/agent \
  --cap-drop ALL --security-opt no-new-privileges \
  --security-opt seccomp="$(pwd)/config/seccomp-base.json" \
  --env-file config/base.env --env YOLO_FLAVOR=base \
  --workdir /workspace yolo-agent:2.0.0
```

## Inspect

### Run a command in an image without starting a container

```bash
docker run --rm yolo-agent:2.0.0 python3 --version
docker run --rm yolo-agent:2.0.0 opencode --version
docker run --rm yolo-agent-cpp:2.0.0 x86_64-w64-mingw32-g++ --version
docker run --rm yolo-agent-reverse-engineering:2.0.0 r2 -v

# Tools that print usage and exit non-zero when given no arguments:
docker run --rm yolo-agent-reverse-engineering:2.0.0 sh -c 'pycdc 2>&1 | head -3'
docker run --rm yolo-agent-reverse-engineering:2.0.0 sh -c 'ghidra-headless 2>&1 | head -5'

# Bypass the tini entrypoint if you want a raw process:
docker run --rm --entrypoint /bin/bash yolo-agent:2.0.0 -lc 'id; which python3'
```

These run as uid 10001 (the image's `USER`), so they see what an agent sees. The
entrypoint is `/usr/bin/tini --`, which is why a bare command works.

### Bill of materials

```bash
docker run --rm yolo-agent:2.0.0 cat /opt/PYTHON-MANIFEST.txt
docker run --rm yolo-agent:2.0.0 cat /opt/yolo/EXTENSIONS-MANIFEST.txt
docker run --rm yolo-agent:2.0.0 cat /opt/deepseek-harness/package.json
docker run --rm yolo-agent-reverse-engineering:2.0.0 sh -c \
  'wc -l < /opt/PYTHON-MANIFEST.txt'

# The same files from a running container.
docker compose exec server cat /opt/PYTHON-MANIFEST.txt
```

`/opt/PYTHON-MANIFEST.txt` is the frozen `pip list` of the image's single
`/opt/pyenv` environment. `/opt/yolo/EXTENSIONS-MANIFEST.txt` is
`code-server --list-extensions --show-versions`. `/opt/deepseek-harness/package.json`
holds the pinned `@deepseek-ai/dsh` version next to its `pnpm-lock.yaml`. See
[11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md) for what to do with them.

### Image metadata

```bash
docker image inspect yolo-agent:2.0.0
docker image inspect --format '{{.Config.User}} {{.Config.Entrypoint}}' yolo-agent:2.0.0
docker image inspect --format '{{json .Config.Labels}}' yolo-agent:2.0.0 | jq
docker image inspect --format '{{.Config.Env}}' yolo-agent-cpp:2.0.0
docker history --no-trunc yolo-agent:2.0.0 | head -40
docker image ls yolo-agent yolo-agent-cpp yolo-agent-reverse-engineering
```

`docker history` shows layer commands, not a package list. For what actually
shipped, read the manifests above and `IMAGE-INSPECT.json` in an offline
bundle.

## Agents (inside the container)

| Task | Command | Config file it reads |
|---|---|---|
| opencode | `opencode` | `~/.config/opencode/opencode.json` |
| pi | `pi` | `~/.pi/agent/settings.json` + `~/.pi/agent/models.json` |
| DeepSeek Harness CLI | `dsh --version` | `/home/agent/.dsh/settings.yaml` (`DSH_HOME`) |
| DeepSeek Harness web UI | `dsh web --host 127.0.0.1 --port 3080` | the same `settings.yaml` |
| Harness default config, without starting | `dsh --profile headless --dump-default-config` | — |
| Rewrite all three configs from the env file | `/opt/yolo/configure-agents.sh` | `VLLM_*` from the environment |
| Rewrite the harness config only | `/opt/yolo/configure-dsh.sh` | `VLLM_*` from the environment |

`~/.bashrc` runs `configure-agents.sh` automatically on an interactive launch,
but only when both `VLLM_BASE_URL` and `VLLM_MODEL` are set **and**
`opencode.json` has no `provider` key yet. After editing `config/<flavor>.env`,
re-run it by hand or delete the flavor's home volume:

```bash
/opt/yolo/configure-agents.sh
jq -e '.provider.vllm' ~/.config/opencode/opencode.json
```

The compose `deepseek` service runs `/opt/yolo/deepseek-web-start.sh`, which
starts `dsh web` on container loopback `127.0.0.1:3080` and relays it to
`0.0.0.0:3081` with socat; Docker publishes the host side as `YOLO_DSH_PORT`
(default `3080`). A bare `dsh web` from a shell has no relay.

Terminal persistence (ttyd wraps tmux):

```bash
tmux ls
tmux attach -t yolo-agent       # session name used by server-start.sh
tmux kill-session -t yolo-agent
```

## Configuration

Copy the template for the flavor you are about to run, then edit it. Every value
in the shipped templates is commented out on purpose, so an unedited copy cannot
point the agents at an address that does not exist — uncomment and edit what you
need. A populated `config/<flavor>.env` is never baked into an image or an
offline bundle.

```bash
cp config/base.env.example    config/base.env       # base
cp config/cpp.env.example     config/cpp.env        # C/C++
cp config/reverse.env.example config/reverse.env    # reverse engineering
$EDITOR config/base.env
```

| Flavor | Env file read by compose and `bin/run*.sh` | Override the path with |
|---|---|---|
| base | `config/base.env` | `YOLO_ENV_FILE` |
| cpp | `config/cpp.env` | `YOLO_ENV_FILE` |
| reverse | `config/reverse.env` | `YOLO_ENV_FILE` |

### Container-side variables

Set these in `config/<flavor>.env`. They are read by processes inside the
container, so the change takes effect on the next launch (or when the
configurator re-runs).

Model endpoint: read by `configure-agents.sh` / `configure-dsh.sh` and written
into the agent configs. Full treatment in
[09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md).

| Variable | Default | Meaning |
|---|---|---|
| `VLLM_BASE_URL` | none — commented out in the template; required to configure the agents | OpenAI-compatible base URL, including `/v1` |
| `VLLM_MODEL` | none — commented out in the template; required to configure the agents | model id served by that endpoint |
| `VLLM_CONTEXT` | unset → agent catalog default | context window in tokens; must match the server's `--max-model-len` |
| `VLLM_REASONING_EFFORT` | `xhigh` | `off`, `low`, `medium`, `xhigh`; `high` is an alias for `xhigh`, anything else warns and falls back to `xhigh` |
| `VLLM_API_KEY` | `local` | bearer token; harmless on keyless servers |
| `LM_STUDIO_BASE_URL` | unset | use instead of `VLLM_BASE_URL`; also switches opencode to an `lmstudio` provider |
| `LM_STUDIO_MODEL` | falls back to `VLLM_MODEL` | model id for the LM Studio path |

Git: read by `/opt/yolo/configure-git.sh`, which `.bashrc` runs on every launch
when `GITEA_HOST` is set. Details in [08-GIT-GITEA.md](08-GIT-GITEA.md).

| Variable | Default | Meaning |
|---|---|---|
| `GITEA_HOST` | unset | `host` or `host:port`; unset means the configurator never runs |
| `GITEA_USER` | `agent` | user name in the credential URL |
| `GITEA_TOKEN` | unset | required in token mode; written to `~/.git-credentials` (mode 600) |
| `GIT_SSH` | `0` | set to `1` for key mode instead of a token |
| `GITEA_SSH_PORT` | `22` | Gitea's SSH port (often `2222`) |
| `GITEA_SSH_HOST` | `GITEA_HOST` without its port | SSH host written to `~/.ssh/config` |
| `GIT_NAME` | `Agent` | `git config --global user.name` |
| `GIT_EMAIL` | `agent@gitea.local` | `git config --global user.email` |

C++ (`config/cpp.env`): see [05-CPP.md](05-CPP.md).

| Variable | Default | Meaning |
|---|---|---|
| `CMAKE_BUILD_TYPE` | `Release` | build type used by `cpp-build.sh` |
| `YOLO_BUILD_JOBS` | `nproc` | parallel jobs for `cpp-build.sh` |
| `YOLO_CMAKE_TOOLCHAINS` | `/opt/yolo/cmake-toolchains` | directory holding the two toolchain files |
| `CCACHE_DIR` | `/home/agent/.cache/ccache` | baked into the image; in the home volume, so the cache survives container replacement |
| `CCACHE_MAXSIZE` | unset (ccache's own default) | ccache cache ceiling, read by ccache itself |

Reverse engineering (`config/reverse.env`): see
[06-REVERSE-ENGINEERING.md](06-REVERSE-ENGINEERING.md).

| Variable | Default | Meaning |
|---|---|---|
| `GHIDRA_USER_DIR` | `$HOME/.ghidra` | writable directory for Ghidra projects and caches; point it at `/workspace/.ghidra` for large projects |
| `JAVA_OPTS` | unset | extra JVM options for the Ghidra launcher, for example `-Xmx4g` |

Harness internals: set inside the image; override only if you know why.

| Variable | Default | Meaning |
|---|---|---|
| `DSH_HOME` | `/home/agent/.dsh` | where `settings.yaml` is written and read |
| `DSH_INTERNAL_PORT` | `3080` | loopback port `dsh web` binds |
| `DSH_RELAY_PORT` | `3081` | container port socat relays to (the one compose publishes) |

Do not set `DEEPSEEK_API_KEY` or `OPENAI_API_KEY`: they put cloud models back in
the agent pickers and cannot work on a host with no internet route.

### Host-side variables

Compose substitutes these before the container exists; the launchers read them
from their own environment. Set them in the shell or in a `.env` file in the
repository root — **not** in `config/<flavor>.env`, where they have no effect.

```bash
YOLO_BIND_ADDRESS=127.0.0.1 docker compose up -d
YOLO_MEM=16g YOLO_CPUS=8 docker compose -f compose.cpp.yaml up -d
docker compose config                       # show the resolved values

# For settings you want every time, use a .env file in the repository root:
cat .env
# YOLO_BIND_ADDRESS=127.0.0.1
# YOLO_CODE_PORT=9090
```

Browser surfaces:

| Variable | Default | Meaning |
|---|---|---|
| `YOLO_BIND_ADDRESS` | `0.0.0.0` | host address the published ports bind to; `127.0.0.1` keeps them off the LAN |
| `YOLO_CODE_PORT` | `8080` | host port → code-server `8080` |
| `YOLO_TERMINAL_PORT` | `7681` | host port → ttyd `7681` |
| `YOLO_DSH_PORT` | `3080` | host port → the relay `3081` (compose only; `bin/run-server.sh` publishes no DSH port) |

Container selection and storage:

| Variable | Default | Meaning |
|---|---|---|
| `YOLO_IMAGE` | the per-flavor tag above | image to run |
| `YOLO_WORKSPACE` | `.` | host directory mounted at `/workspace`; **compose only** — `bin/run*.sh` always mount `$PWD` |
| `YOLO_HOME_VOLUME` | the per-flavor name above | named volume mounted at `/home/agent` |
| `YOLO_ENV_FILE` | `config/<flavor>.env` | env file used by `bin/run*.sh` |
| `CONTAINER` | `base` | flavor for `bin/run*.sh`; the PowerShell scripts also read it |

Resource limits — the same names everywhere, with different defaults:

| Variable | Default | Meaning |
|---|---|---|
| `YOLO_MEM` | `8g` (`bin/`); `8g` base, `12g` cpp and reverse (compose) | container memory limit |
| `YOLO_CPUS` | `4` (`bin/`); `4` base, `6` cpp and reverse (compose) | CPU limit |

`YOLO_FLAVOR` is set for you: the launchers pass `--env YOLO_FLAVOR=<flavor>`, and
the cpp and reverse images bake it in. It only drives the login banner.

### Verify an endpoint

```bash
curl "$VLLM_BASE_URL/models"                                                 # host
docker compose exec server sh -lc 'curl -s "$VLLM_BASE_URL/models" | head'   # container
```

## C++ helper (inside the `cpp` container)

```bash
cpp-build.sh <source-dir> [linux|windows|both] [extra cmake args...]

cpp-build.sh .                                   # both targets, Release
cpp-build.sh . windows                           # 64-bit Windows PE only
cpp-build.sh . linux -DBUILD_TESTS=ON
CMAKE_BUILD_TYPE=Debug YOLO_BUILD_JOBS=8 cpp-build.sh . both
```

Outputs `<src>/build-linux/` (ELF 64-bit plus `compile_commands.json`) and
`<src>/build-win/` (PE32+). It is a convenience wrapper; plain cmake and ninja
work the same way:

```bash
cmake -S . -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake
cmake --build build-win --parallel "$(nproc)"

cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake
cmake --build build-linux --parallel "$(nproc)"
ctest --test-dir build-linux --output-on-failure

file build-win/app.exe          # PE32+ executable (console) x86-64
```

Toolchain files:

| File | Target | Compilers |
|---|---|---|
| `/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake` | native linux/amd64 | `clang` / `clang++` with `-fuse-ld=lld` |
| `/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake` | Windows x86_64 | `x86_64-w64-mingw32-gcc` / `-g++`, static libgcc and libstdc++ |

The mingw toolchain sets `CMAKE_TRY_COMPILE_TARGET_TYPE` to `STATIC_LIBRARY`
because nothing here can run a PE: there is no Wine. Guard tests and `try_run`
with `if(NOT CMAKE_CROSSCOMPILING)`.

## Reverse-engineering tools (inside the `reverse` container)

| Command | Path | What it does |
|---|---|---|
| `pyinstxtractor-ng` | `/opt/pyenv/bin/pyinstxtractor-ng` | unpacks a PyInstaller archive without running it |
| `pycdc` | `/usr/local/bin/pycdc` | decompiles Python bytecode (built from source) |
| `pycdas` | `/usr/local/bin/pycdas` | disassembles Python bytecode |
| `uncompyle6` | `/opt/pyenv/bin/uncompyle6` | Python bytecode decompiler (via pydumpck) |
| `pydumpck` | `/opt/pyenv/bin/pydumpck` | all-in-one orchestrator for `.exe`/`.pyz`/`.pyc`/`.elf` |
| `jadx` | `/usr/local/bin/jadx` → `/opt/jadx/bin/jadx` | DEX/APK to Java source (CLI only; no GUI) |
| `ghidra-headless` | `/usr/local/bin/ghidra-headless` → `/opt/ghidra/support/analyzeHeadless` | Ghidra's headless analyzer |
| `r2` | `/usr/bin/r2` | radare2 |
| `java` | `/opt/java/bin/java` (`JAVA_HOME=/opt/java`) | Temurin JDK 21, used by Ghidra and jadx |
| `gdb`, `objdump`, `readelf`, `strace`, `ltrace` | `/usr/bin` | native inspection |
| `binwalk`, `foremost`, `yara` | `/usr/bin` | carving and signature scanning |
| `xxd`, `hexedit`, `7z`, `cabextract` | `/usr/bin` | hex and archive handling |
| `python3` | `/opt/pyenv/bin/python3` | the single 3.11 environment, with `angr`, `capstone`, `unicorn`, `lief`, `pefile`, `pyelftools`, `xdis` |

```bash
pyinstxtractor-ng target.exe                    # writes target.exe_extracted/
pycdas target.exe_extracted/app.pyc             # disassembly of headerless bytecode
pycdc  target.exe_extracted/app.pyc             # decompile attempt
pydumpck target.exe
jadx -d out/ target.apk
r2 -q -c 'ij' target                            # binary info as JSON
ghidra-headless /home/agent/ghidra-proj proj -import target.exe
```

Ghidra needs a writable project directory: `/home/agent` (the volume) or
`/workspace`. Set `GHIDRA_USER_DIR=/workspace/.ghidra` for large projects, and
raise `JAVA_OPTS` when the default heap is too small.

## Maintenance

```bash
docker volume ls
docker volume ls --filter name=yolo-agent
docker volume rm yolo-agent-base-home-v1        # launcher-created base volume

docker compose logs -f                          # all services of the selected flavor
docker compose logs -f server
docker compose ps
docker compose down                             # stop and remove compose containers
docker rm -f yolo-agent-cpp-server              # launcher-created server container
docker rm -f yolo-agent-base                    # launcher-created one-shot container, if stuck

docker image ls
docker image rm yolo-agent:2.0.0
```

Removing a home volume deletes agent configuration, sessions, SSH keys, git
credentials, and the ccache. Remove the container using it first — Docker refuses
to delete a volume that is in use. Recreating the volume is safe: the agents
regenerate their configs on the next launch from the env file.

```bash
# Full reset of one flavor, launcher-managed (base shown).
docker rm -f yolo-agent-base yolo-agent-base-server
docker volume rm yolo-agent-base-home-v1

# Full reset of a compose-managed flavor.
docker compose -f compose.cpp.yaml down
docker volume rm yolo-agent-cpp-home-v1
```

## Offline packaging

```bash
./scripts/package-offline.sh <version> base:<tag> cpp:<tag> reverse:<tag> -- <output-dir>

# The real invocation for a 2.0.0 release:
./scripts/package-offline.sh 2.0.0 \
  base:yolo-agent:2.0.0 \
  cpp:yolo-agent-cpp:2.0.0 \
  reverse:yolo-agent-reverse-engineering:2.0.0 \
  -- dist
```

The first argument is the version, each `name:tag` produces one bundle (`name`
selects the compose file, seccomp profile, and env template), and everything
after `--` is the output directory (default `dist`). It needs `docker`, `zip`,
`sha256sum`, `git`, `stat`, and `split`, and each image must already exist
locally because the script inspects it and then `docker save`s it.

Products:

```
dist/yolo-agent-<image>-<version>-offline.zip
dist/yolo-agent-<image>-<version>-offline.zip.sha256
```

`<image>` matches the image name, so the reverse bundle is
`yolo-agent-reverse-engineering-2.0.0-offline.zip` with archive
`yolo-agent-reverse-engineering_2.0.0.docker.tar`. Inside each ZIP: the image
archive, `bin/`, the
compose file, the seccomp profile, the env template, `docs/`, `README.md`,
`SECURITY.md`, `PINS.md`, `VERSION`, `SOURCE-COMMIT.txt`, `IMAGE-INSPECT.json`,
`SHA256SUMS`, and `LOAD-OFFLINE.txt`. The staging directory is deleted after
zipping.

If a ZIP reaches GitHub's 2 GiB asset limit it ships as `.part-NN` files with a
`.parts.sha256` and a `.REASSEMBLE.txt`, and the ZIP itself is removed.

### On the offline host

```bash
# 1. Verify the ZIP, next to it (the sidecar stores only the basename).
sha256sum -c yolo-agent-base-2.0.0-offline.zip.sha256

# 2. Unpack and verify the image archive.
unzip yolo-agent-base-2.0.0-offline.zip
cd yolo-agent-base-2.0.0-offline
sha256sum -c SHA256SUMS

# 3. Load and configure.
docker load --input yolo-agent-base_2.0.0.docker.tar
cp config/base.env.example config/base.env
$EDITOR config/base.env

# 4. Run.
docker compose run --rm agent
docker compose up -d
```

`LOAD-OFFLINE.txt` inside the bundle repeats this with the exact filenames and
the PowerShell equivalents. The bundled compose file defaults to the local tag
(`yolo-agent:2.0.0` and friends); if you saved a different tag — a `ghcr.io/...`
tag from CI, say — set `YOLO_IMAGE=<name:tag>` when running compose.

## Paths inside the image

| Path | Contents |
|---|---|
| `/workspace` | the one host mount; agents work here |
| `/home/agent` | home volume: agent configs, sessions, `.git-credentials`, `.ssh`, ccache |
| `/opt/pyenv` | the single Python 3.11 environment (`python3`, `pip`) |
| `/opt/PYTHON-MANIFEST.txt` | frozen package list baked at build time |
| `/opt/yolo` | `configure-*.sh`, `server-start.sh`, `deepseek-web-start.sh`, `cpp-build.sh`, `cmake-toolchains/`, `seccomp.json`, `docs/`, `EXTENSIONS-MANIFEST.txt` |
| `/opt/code-server` | code-server install (symlinked into `/usr/local/bin`) |
| `/opt/deepseek-harness` | pinned `dsh` install with `package.json` and `pnpm-lock.yaml` |
| `/opt/opencode`, `/opt/pi` | the two standalone agent binaries |
| `/opt/java`, `/opt/jadx`, `/opt/ghidra` | reverse image only |
| `/tmp/code-server.log`, `/tmp/ttyd.log` | web supervisor logs |
