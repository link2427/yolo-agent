# 12 — Troubleshooting

Every entry below is a symptom, its cause, and a fix you can run. Unless a step
says "on the host", run it inside the container — an interactive shell from
`docker compose run --rm agent` (or `./bin/run.sh`) has the flavor's env file in
its environment.

Two facts explain most of what goes wrong here:

1. **The host is air-gapped.** Nothing is downloaded at runtime, so anything not
   baked into the image cannot be added while the container is running.
2. **Each flavor has its own env file and its own home volume.** Configuring
   `base` does not configure `cpp` or `reverse`.

| Symptom | Section |
|---|---|
| An install or a download fails | [Confirm the air gap first](#confirm-the-air-gap-first) |
| Agents report no models | [Agents have no model](#agents-have-no-model) |
| You edited a config and nothing changed | [You changed the config and nothing happened](#you-changed-the-config-and-nothing-happened) |
| `port is already allocated` | [A published port is already in use](#a-published-port-is-already-in-use) |
| No browser UI | [code-server or the DeepSeek Harness UI is not reachable](#code-server-or-the-deepseek-harness-ui-is-not-reachable) |
| `ptrace` / `gdb` / `strace` fail | [gdb, strace, or ptrace fails](#gdb-strace-or-ptrace-fails) |
| `pip install` finds nothing | [pip install cannot find a package](#pip-install-cannot-find-a-package) |
| The build stops in a smoke test | [The build fails at a smoke test](#the-build-fails-at-a-smoke-test) |
| A cross-built `.exe` will not run | [A cross-compiled Windows binary will not run](#a-cross-compiled-windows-binary-will-not-run) |
| Ghidra will not start | [Ghidra fails to start](#ghidra-fails-to-start) |
| `Read-only file system` | [Read-only file system](#read-only-file-system) |
| `Permission denied` in `/workspace` | [Permission denied writing to the workspace](#permission-denied-writing-to-the-workspace) |
| Is this tool even in this image? | [Find out what is actually in an image](#find-out-what-is-actually-in-an-image) |
| You want a clean slate | [Full reset of one flavor](#full-reset-of-one-flavor) |

## Confirm the air gap first

**Symptom.** `pip install`, `npm install`, `apt-get install`, an agent
self-update, or a code-server extension install fails with a network error, "no
matching distribution", or a long retry loop.

**Cause.** The host has no internet route. Every download happened at build time;
the runtime container is not supposed to reach anything.

**Fix.** Confirm it, then stop treating the failure as a bug:

```bash
# On the host: expect a failure.
curl -fsS --max-time 5 https://pypi.org/simple/ ; echo "curl exit=$?"

# In any image: expect the same.
docker run --rm yolo-agent:2.0.0 curl -fsS --max-time 5 https://github.com
```

What this means in practice:

- There is no pip, npm, apt, or Open VSX egress at runtime, and the agents are
  configured not to try: opencode has `"autoupdate": false`, pi runs with
  `PI_OFFLINE=1`, sharing and telemetry are off.
- The LAN model endpoint and your Gitea server are the only things the container
  talks to. If the endpoint is unreachable, see the next section.
- A missing tool is a **build** change (see
  [pip install cannot find a package](#pip-install-cannot-find-a-package)), not a
  runtime fix.

## Agents have no model

**Symptom.** `opencode` shows no model, pi reports no provider, or `dsh` starts
with an empty model list. Sometimes the model list is stale, pointing at an
endpoint you no longer use.

**Cause.** One of:

- The flavor's env file does not exist, or `VLLM_BASE_URL` / `VLLM_MODEL` are not
  set in it. Compose treats the env file as optional (`required: false`), so
  nothing fails loudly — the container simply has no endpoint. The `bin/`
  launchers do fail loudly instead.
- The values were added to a different flavor's env file (`config/base.env` while
  you are running the `cpp` container, for example).
- The agent config already exists, so the launch-time configuration did not run
  again. `~/.bashrc` runs `/opt/yolo/configure-agents.sh` only when
  `VLLM_BASE_URL` and `VLLM_MODEL` are set **and**
  `~/.config/opencode/opencode.json` does not yet contain `"provider"`.

**Fix.** Check what this flavor actually loaded, then re-apply:

```bash
# Which env file is in play for this flavor? (run from the repository root)
docker compose -f compose.cpp.yaml run --rm -T agent env | grep -E '^(VLLM|LM_STUDIO)_'

# Inside the container: was the config ever written?
jq -e '.provider.vllm' ~/.config/opencode/opencode.json
grep -E 'id:|baseURL:' ~/.dsh/settings.yaml

# Re-apply from the environment the container already has.
/opt/yolo/configure-agents.sh

# Or with explicit values (useful outside a flavor shell).
VLLM_BASE_URL=http://192.168.1.50:8000/v1 VLLM_MODEL=Qwen/Qwen3.8-27B \
  /opt/yolo/configure-agents.sh
```

Then confirm the endpoint answers from **inside** the container — the container's
network is not the host's network:

```bash
curl -fsS "$VLLM_BASE_URL/models"
```

If that fails, fix the address first: `VLLM_BASE_URL` must include the `/v1`
path, and it must be an address the container can route to. If vLLM runs on the
Docker host itself, use `host.docker.internal` on Docker Desktop or the host's LAN
address on Linux — the launchers do not add host aliases.

Two smaller traps in the same area:

- `LM_STUDIO_BASE_URL` takes precedence over `VLLM_BASE_URL` when both are set.
  Comment out the pair you are not using.
- An invalid `VLLM_REASONING_EFFORT` is not fatal: anything other than
  `off|low|medium|xhigh` (with `high` accepted as an alias for `xhigh`) prints a
  warning and falls back to `xhigh`.

Full details: [09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md).

## You changed the config and nothing happened

**Symptom.** You edited the env file, relaunched, and the container still uses
the old endpoint, the old token, or the old hostname.

**Cause.** Two different mechanisms are at work:

- **Git and the git identity reconfigure on every interactive launch**, because
  `~/.bashrc` calls `/opt/yolo/configure-git.sh` whenever `GITEA_HOST` is set.
  Editing the env file is enough.
- **Agent configs are written on first launch only**, because the auto-run is
  guarded by "the opencode config does not yet contain `provider`".
- In both cases the setting must be in **this flavor's** env file, and the
  container must see **this flavor's** home volume. A second flavor has a
  different volume, so it looks unconfigured even though the first one works.

**Fix.** Identify the flavor and the volume, then re-apply or reset:

```bash
# Which volumes exist for the three flavors?
docker volume ls | grep yolo-agent

# Which env file did this flavor load? (from the repository root)
docker compose -f compose.reverse.yaml run --rm -T agent env | grep -E '^(VLLM|LM_STUDIO|GITEA)_'

# Re-apply the agent configs without deleting anything.
/opt/yolo/configure-agents.sh
```

See [Full reset of one flavor](#full-reset-of-one-flavor) if you want a clean home
volume instead.

One more trap: `YOLO_HOME_VOLUME` overrides the volume name. If you set it for the
launcher, set the same value for compose, or the two will use different volumes
and the configuration will appear to vanish.

## A published port is already in use

**Symptom.** `Bind for 0.0.0.0:8080 failed: port is already allocated`, or the
`server`/`deepseek` service restarts in a loop.

**Cause.** Something else on the host holds 8080, 7681, or 3080 — often another
flavor's server container, which publishes the same three ports.

**Fix.** Find the owner, then move this flavor's published ports:

```bash
docker ps --format '{{.Names}}\t{{.Ports}}'

# On the host, in front of the compose or launcher command:
YOLO_CODE_PORT=8090 YOLO_TERMINAL_PORT=7691 YOLO_DSH_PORT=3090 docker compose up -d
YOLO_CODE_PORT=8090 YOLO_TERMINAL_PORT=7691 ./bin/run-server.sh
```

`YOLO_CODE_PORT`, `YOLO_TERMINAL_PORT`, `YOLO_DSH_PORT`, and `YOLO_BIND_ADDRESS`
are read by **compose and the launchers from the shell environment** (or from a
`.env` file next to the compose file). Putting them in `config/<flavor>.env` only
exports them into the container — it does not move the host-side port, so the bind
still fails.

## code-server or the DeepSeek Harness UI is not reachable

**Symptom.** `http://<host>:8080` or `http://<host>:3080` does not answer while
the container is running.

**Cause.** One of four things:

- code-server and ttyd bind `0.0.0.0` **inside** the container, and the host-side
  publish uses `YOLO_BIND_ADDRESS`. With `YOLO_BIND_ADDRESS=127.0.0.1` the port
  exists only on host loopback.
- The DeepSeek Harness UI is a deliberate two-step relay: `dsh web` listens on
  container loopback only (upstream safety check), `deepseek-web-start.sh` relays
  `127.0.0.1:3080` to `3081` with socat, and compose publishes
  `${YOLO_DSH_PORT:-3080}:3081`.
- `bin/run-server.sh` publishes **only** 8080 and 7681. If you used the launcher,
  there is no Harness port on the host at all — the compose file owns that
  service.
- A service crashed and is being restarted by its supervisor.

**Fix.**

```bash
# Bring up the Harness service and read its log.
docker compose up -d deepseek
docker compose logs --tail=50 deepseek

# Reachable from the host?
curl -fsS -o /dev/null http://127.0.0.1:3080/ && echo "harness reachable"

# Alive inside the container? (relay port, then the IDE log)
docker compose exec deepseek curl -fsS -o /dev/null http://127.0.0.1:3081/ && echo "relay ok"
docker compose exec server tail -50 /tmp/code-server.log
```

If the relay answers inside the container but not from the host, the problem is
the publish: stop another flavor that already holds the port (previous section),
or use `YOLO_DSH_PORT` to move it. If you set `YOLO_BIND_ADDRESS=127.0.0.1`
deliberately, tunnel in instead of exposing the port:

```bash
ssh -L 8080:127.0.0.1:8080 user@airgapped-host
```

Starting `dsh web` by hand inside a terminal cannot work from the host: it binds
loopback on purpose. Use the compose `deepseek` service. See
[07-WEB-IDE.md](07-WEB-IDE.md).

## gdb, strace, or ptrace fails

**Symptom.** In the base image, `gdb` or `strace` reports "command not found"; in
any image, a debugger or profiler fails with `ptrace: Operation not permitted`,
`ptrace(PTRACE_TRACEME) = -1 EPERM`, or a tool that reads another process's memory
fails immediately.

**Cause.** Two separate restrictions:

- The base image does not install `gdb`, `strace`, or `valgrind` at all. They ship
  in the `cpp` and `reverse` flavors.
- Seccomp profiles. `config/seccomp-base.json` (base) denies `ptrace`,
  `process_vm_readv`, and `process_vm_writev` with EPERM.
  `config/seccomp-toolchain.json` (cpp and reverse) allows exactly those three —
  they are the only difference between the two profiles. gdb needs `ptrace`, and
  gcc LTO plus debugger-driven unpacking need the `process_vm_*` calls.

**Fix.** Use the flavor that carries the toolchain:

```bash
CONTAINER=cpp ./bin/run.sh
docker compose -f compose.cpp.yaml run --rm agent

# Inside that flavor:
gdb --batch -ex run -ex bt ./your-binary
strace -f ./your-binary
```

Confirm which profile a container got:

```bash
docker ps --format '{{.Names}}' | grep yolo-agent
docker inspect --format '{{.Name}} {{json .HostConfig.SecurityOpt}}' \
  $(docker ps -q --filter name=yolo-agent-cpp)
```

Do not work around this with `--security-opt seccomp=unconfined`: the denylist is
the containment model, and everything else in it — `mount`, module loading,
`bpf`, `perf_event_open`, and thirty-odd more syscalls — stays denied in every
profile. See [10-SECURITY.md](10-SECURITY.md).

## pip install cannot find a package

**Symptom.** `pip install <package>` fails with a retry loop ending in "Could not
find a version that satisfies the requirement", even for a package you know
exists.

**Cause.** There is no package index at runtime. The environment is complete as
shipped, and it is a single Python 3.11 venv at `/opt/pyenv`
(`VIRTUAL_ENV=/opt/pyenv`, first on `PATH`). The build installs it with
`--only-binary=:all:`, so a pin with no cp311 wheel fails the build by design
rather than compiling from source on the offline host.

**Fix.** Add the package to the build, then rebuild on a networked machine:

```bash
# All three images:
$EDITOR docker/requirements-common.txt
# Reverse image only (layered onto the same venv, not a second environment):
$EDITOR docker/requirements-reverse.txt

python3 -m pip index versions <package>     # on a networked machine, to pick a pin
docker buildx bake base                     # rebuild + smoke suite
docker run --rm yolo-agent:2.0.0 python3 -m pip show <package>
```

Pin an exact version. A floating requirement cannot be resolved later, and the
`--only-binary` rule means a source-only package fails the build — which is the
intended outcome, because it would fail far worse on the air-gapped host.

Packages that already ship report `Requirement already satisfied`, so a runtime
`pip install` can look like it worked when it only found what was baked in. Check
what is really there:

```bash
pip list | wc -l
grep -i '^<package>==' /opt/PYTHON-MANIFEST.txt
```

See [04-PYTHON.md](04-PYTHON.md) and
[11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md).

## The build fails at a smoke test

**Symptom.** `docker buildx bake` stops inside a `RUN` step whose output ends in a
failing `test`, `grep`, `jq`, or `curl` line, with a command trace because the
suites run under `set -euxo pipefail`.

**Cause.** The per-image smoke suites are the build gate, by design: a pin, a
package, or a generated config drifted, and the failure surfaces at build time
instead of on the air-gapped host. `docker buildx bake` with no arguments builds
the `test` target of all three images; `docker buildx bake images` builds the
shippable `runtime` images and runs no gate at all.

**Fix.** Re-run just the failing gate with readable output, then fix the pin in
the Dockerfile and `PINS.md` together:

```bash
docker buildx bake --progress=plain 2>&1 | tee /tmp/bake.log
docker buildx bake cpp-test --progress=plain      # base-test | cpp-test | reverse-test
```

What each gate asserts, so you can read the failure:

| Suite | Checks |
|---|---|
| `smoke-common.sh` (all images) | uid 10001 and user `agent`; `/workspace`, `/home/agent`, `/tmp` writable and `/usr`, `/opt` not; zero setuid files; `opencode`/`pi`/`dsh` versions against the pinned ARGs; `goose`, `aider`, `prime-agent`, `openhands` absent; code-server and ttyd versions plus ≥15 extensions; node v22 and Python 3.11; the common tool set; one venv with `VIRTUAL_ENV=/opt/pyenv` and imports from the common package set; `configure-agents.sh` output asserted with `jq` (opencode permission/model/limit, pi trust/telemetry/thinking, dsh settings); no `DEEPSEEK_API_KEY`; both git modes (`~/.git-credentials` mode 600, SSH key with `Port 2222`, key mode 600); HTTP from code-server, ttyd, and the dsh relay on 3081 |
| `smoke-cpp.sh` | the compiler tool set including `x86_64-w64-mingw32-*`; `CCACHE_DIR` writable; a real ELF64 built by g++ and by clang, and a real PE32+ built by mingw; the cross binary must not link `libstdc++`; CMake end to end for both toolchain files, with `ctest` on the native build; `cpp-build.sh both`; `gdb --batch -ex run` |
| `smoke-reverse.sh` | tool set (`pycdc pycdas jadx ghidra-headless r2 gdb java binwalk …`); Java 21 from `/opt/java`; the reverse Python packages in the **same** venv; a real PyInstaller archive built, extracted with `pyinstxtractor-ng`, and disassembled with `pycdas`; `decompyle3`; `.pyc` disassembly; `readelf`/`objdump`/`r2`/`yara` on a native binary; `lief`/`angr` loading a binary; `ghidra-headless` resolving Java |

Common readings:

- A version assertion fails: the installed CLI and the pinned ARG disagree — bump
  the ARG in the Dockerfile **and** the entry in `PINS.md`, then rebuild.
- An installer's checksum verification fails: the upstream asset changed or was
  re-tagged. Re-verify before updating the hash; the hash is the supply chain (see
  [11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md)).
- A Python import assertion fails: a package is missing from `/opt/pyenv` — fix
  `docker/requirements-*.txt`, or the pin no longer has a cp311 wheel.
- `test "$(stat -c %a ~/.git-credentials)" = 600` fails: `configure-git.sh` lost
  its `umask 077` / `chmod`. That is a security property, not a style issue.
- The 3081 HTTP check fails: the Harness relay did not come up; the suite prints
  `/tmp/dsh-web.log` on failure.
- `gdb` attach fails in `smoke-cpp.sh`: `config/seccomp-toolchain.json` lost
  `ptrace` from its allow list.
- "cross binary links libstdc++ dynamically": the mingw toolchain file stopped
  linking statically, and the target Windows host has no mingw runtime DLLs.

The `test` targets are never published, and `images` skips the gate — do not
release from an ungated build. Every download happens during the build, so build
on a networked machine. See [02-QUICKSTART.md](02-QUICKSTART.md).

## A cross-compiled Windows binary will not run

**Symptom.** `cpp-build.sh . windows` succeeds and produces `build-win/probe.exe`,
but running it fails with `cannot execute binary file: Exec format error` (or
"Permission denied").

**Cause.** That is expected. The `cpp` flavor cross-compiles to 64-bit Windows
PE32+ with mingw-w64 (`x86_64-w64-mingw32-*`), and the image has **no Wine** and
no Windows: it can produce a PE binary but never execute one. `smoke-cpp.sh`
asserts the file format and does not run the artifact.

**Fix.** Confirm the format, then run it on the machine it was built for — copy it
out through the `/workspace` mount:

```bash
file build-win/probe.exe                                  # PE32+ executable (console) x86-64
x86_64-w64-mingw32-objdump -p build-win/probe.exe | grep 'DLL Name'
```

Link statically (`-static`), which is what the smoke suite enforces: an `.exe`
that links `libstdc++` dynamically fails the build gate, because the Windows host
will not have the mingw runtime DLLs. `cpp-build.sh <dir> [linux|windows|both]`
writes the Linux build to `build-linux/` and the Windows build to `build-win/`.
See [05-CPP.md](05-CPP.md).

## Ghidra fails to start

**Symptom.** `ghidra-headless` exits immediately: a Java version complaint,
`JAVA_HOME` unresolved, a permission error on a project directory, or
`OutOfMemoryError` partway into analysis.

**Cause.** Three independent requirements:

- **Java 21.** Ghidra 12 needs it, Debian 12 ships 17, so the image carries
  Temurin at `/opt/java` and sets `JAVA_HOME=/opt/java`. If `java` resolves to a
  different JDK, Ghidra refuses to launch.
- **A writable user directory.** `GHIDRA_USER_DIR` defaults to `$HOME/.ghidra`
  inside the home volume. The container's root filesystem is read-only, so
  pointing it at `/opt/...` (or at a read-only mount) breaks project creation.
- **Heap.** Ghidra's JVM default can exceed the container's memory limit (12g for
  the reverse flavor, set with `YOLO_MEM`).

**Fix.**

```bash
java -version                      # expect 21.x
echo "$JAVA_HOME"                  # /opt/java
echo "$GHIDRA_USER_DIR"            # default: $HOME/.ghidra

# Prove the user directory is writable, and move it to the mount if you prefer.
mkdir -p /home/agent/.ghidra
touch /home/agent/.ghidra/.probe && rm /home/agent/.ghidra/.probe

# Cap the heap (must fit inside YOLO_MEM).
JAVA_OPTS=-Xmx4g ghidra-headless
```

Set `GHIDRA_USER_DIR` and `JAVA_OPTS` in `config/reverse.env` to make them
permanent for the container. Large projects are better off on the workspace mount
(`GHIDRA_USER_DIR=/workspace/.ghidra`) than in the home volume. See
[06-REVERSE-ENGINEERING.md](06-REVERSE-ENGINEERING.md).

## Read-only file system

**Symptom.** `mkdir: cannot create directory '/opt/anything': Read-only file
system`, or a tool that wants to write next to its own installation fails.

**Cause.** Every flavor runs with a read-only root filesystem (`read_only: true`
in compose, `--read-only` in the launchers). Only these paths are writable:

| Path | What it is | Survives container replacement |
|---|---|---|
| `/workspace` | the one host folder you mounted | yes, it is your host directory |
| `/home/agent` | the flavor's named volume | yes |
| `/tmp`, `/run`, `/dev/shm` | tmpfs mounts, size-capped | no |

`/opt`, `/usr`, and the rest of the image are immutable at runtime.

**Fix.** Write to a writable path:

```bash
touch /workspace/probe      # ok
touch /home/agent/probe     # ok
touch /tmp/probe            # ok
touch /opt/probe            # Read-only file system
```

Anything that must exist in the image has to be installed at build time; see
[pip install cannot find a package](#pip-install-cannot-find-a-package). `/tmp` is
tmpfs: it is cleared when the container stops, so never leave work there.

## Permission denied writing to the workspace

**Symptom.** The agent cannot write in `/workspace`, `git` refuses to operate in a
mounted repository, or files you created on the host are not writable inside the
container (and files the agent created are owned by a number instead of your
user).

**Cause.** The container runs as **uid 10001, gid 10001** (user `agent`) and
Docker does not remap that unless the daemon has `userns-remap` enabled. Files the
agent writes into the mount are owned by 10001 on the host; a host directory owned
by another user — root, or your desktop account — is not writable by the agent.

**Fix.** Look at the numeric owner, then give uid 10001 access:

```bash
ls -ln /path/to/workspace                  # on the host: 10001 is the agent

sudo chown -R 10001:10001 /path/to/workspace
# Or keep the host ownership and grant write access:
sudo chmod -R o+rwX /path/to/workspace
```

If git complains about `detected dubious ownership in repository at '/workspace'`
because the directory belongs to another uid, either fix the ownership as above or
tell git to trust that path:

```bash
git config --global --add safe.directory /workspace
```

Remember what this mount is: everything under it is fully writable by an agent
that never asks permission. Point `YOLO_WORKSPACE` at a scratch directory — see
[10-SECURITY.md](10-SECURITY.md).

## Find out what is actually in an image

**Symptom.** You need to know whether a tool, package, or extension is really in
the image you loaded, before blaming the configuration.

**Cause.** Each image is self-contained and they differ: `gdb`, `strace`,
`valgrind`, the mingw cross compiler, and the JDK are not in the base image.

**Fix.** Run a command in the image itself, and read the baked manifests:

```bash
docker images | grep yolo-agent

# A one-off command in the image. A bare run applies no seccomp profile, no
# read-only flag, and no env file: use it to inspect content, not to reproduce
# the hardened runtime.
docker run --rm yolo-agent:2.0.0 sh -c 'command -v gdb strace valgrind || echo "not in this flavor"'
docker run --rm yolo-agent:2.0.0 cat /opt/PYTHON-MANIFEST.txt
docker run --rm yolo-agent:2.0.0 cat /opt/yolo/EXTENSIONS-MANIFEST.txt
docker run --rm yolo-agent-reverse-engineering:2.0.0 /opt/java/bin/java -version
docker run --rm yolo-agent:2.0.0 ls /opt/yolo/docs

# Reproduce a real runtime failure instead: this applies uid 10001, the read-only
# rootfs, cap_drop ALL, the flavor's seccomp profile, and the flavor's env file.
docker compose run --rm -T agent sh -c 'command -v gdb || echo "gdb is not in the base image"'
```

Useful places to look: `/opt/PYTHON-MANIFEST.txt` (exact `pip freeze` of the baked
venv), `/opt/yolo/EXTENSIONS-MANIFEST.txt` (code-server extension versions),
`/opt/yolo/docs/` (these documents, inside the image), and the
`config/<flavor>.env.example` template. Offline bundles additionally ship
`IMAGE-INSPECT.json` and `SOURCE-COMMIT.txt`. See
[11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md).

## Full reset of one flavor

**Symptom.** You want a clean home volume — a half-configured agent, a stale
endpoint, a login loop, or a volume left over from an earlier version.

**Cause.** Agent state, credentials, and caches persist in the flavor's named
volume, which is exactly why they survive container replacement. A stale volume is
not refreshed by rebuilding the image.

**Fix.** Stop the flavor's containers, then remove only that flavor's volume
(`base` shown; substitute `cpp` or `reverse`):

```bash
docker compose down                                  # stop this flavor's services
docker rm -f yolo-agent-base yolo-agent-base-server  # launchers remove on exit, servers do not

docker volume ls | grep yolo-agent
docker volume rm yolo-agent-base-home-v1
```

| Flavor | Volume |
|---|---|
| base | `yolo-agent-base-home-v1` |
| cpp | `yolo-agent-cpp-home-v1` |
| reverse | `yolo-agent-reverse-home-v1` |

This deletes agent sessions and configs, git credentials and SSH keys, the C++
ccache, and Ghidra user state. `/workspace` is untouched. If you overrode
`YOLO_HOME_VOLUME`, remove that name instead.

The next launch rebuilds what it can from the env file: git is configured
immediately, and the agents are configured on first launch. Nothing needs to be
re-downloaded — it all came from the image. See
[03-AGENTS.md](03-AGENTS.md) for what persists where.
