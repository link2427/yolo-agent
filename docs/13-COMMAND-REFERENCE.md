# 13 — Command reference

## On the host: `install.sh`

From the unpacked kit (`yolo-agent-3.0.0/install.sh`). Folders go in
`~/yolo` (`YOLO_HOME` to change).

| Command | Does |
|---|---|
| `install.sh load [dir]` | check `SHA256SUMS` and `docker load` the images in `dir` |
| `install.sh new <name> [--tier core\|cpp\|full] [--ports N] [--token T] [--no-start]` | make `~/yolo/<name>` and start it |
| `install.sh lab` | make `~/yolo/lab` for the monitor and bot |
| `install.sh upgrade <name>\|--all` | move folders to this kit's version and restart them |

## On the host: compose

In a person's folder (`~/yolo/<name>`):

```bash
docker compose up -d                 # start all five services
docker compose down                  # stop (workspace and home volume kept)
docker compose restart               # after editing .env
docker compose run --rm shell        # one-off shell
docker compose exec code bash -l     # shell in a running service
docker compose logs -f chat          # follow a service's log
```

In `~/yolo/lab`:

```bash
docker compose up -d
docker compose exec bot yolo bot hook team/project      # or org:team
docker compose logs -f monitor
```

## In the container: `yolo`

| Command | Does |
|---|---|
| `yolo` / `yolo status` | version, tier, model server, model, Gitea, git, fleet, skills, agents |
| `yolo doctor` | status plus checks, each with a fix |
| `yolo models` | models SEC09 serves; ★ = the default |
| `yolo agents` | installed agents, versions, how to start them |
| `yolo tools` | compilers and tools in this tier |
| `yolo login [token]` | check a Gitea token and store it in the home volume |
| `yolo sync` | pull the fleet and skills repos, then reconfigure |
| `yolo configure` | rewrite every agent's config (runs on every start) |
| `yolo skills ...` | `list`, `search <text>`, `show <name>`, `enable <name\|pack:NAME> [--project]`, `disable`, `packs`, `apply` |
| `yolo serve <service>` | run one service in the foreground: `home code chat term files bot gateway` (compose uses this) |
| `yolo bot hook <owner/repo\|org:NAME>` | install the bot's webhook in Gitea (lab bot only) |
| `yolo bot run <owner/repo> <n>` | review one pull request now (lab bot only) |

## Agents

| Command | Agent |
|---|---|
| `claude` | Claude Code |
| `opencode` | opencode (`opencode web` is the Chat page) |
| `qwen` | Qwen Code |
| `pi` | pi |
| `crush` | Crush |
| `goose session` | Goose |
| `codex` | Codex (experimental) |

Without a prompt: `opencode run "..."`, `claude -p "..."`, `qwen -p "..."`,
`pi -p "..."`, `crush run -q "..."`, `goose run -t "..." --no-session`,
`codex exec "..."`.

## Gitea: `yolo-gitea`

```bash
yolo-gitea whoami
yolo-gitea pr-list    <owner/repo> [open|closed|all]
yolo-gitea pr-view    <owner/repo> <n>
yolo-gitea pr-diff    <owner/repo> <n>
yolo-gitea pr-create  <owner/repo> <head> <base> <title> [body-file]
yolo-gitea comment    <owner/repo> <n> <body-file|->
yolo-gitea review     <owner/repo> <n> <COMMENT|APPROVE|REQUEST_CHANGES> <body-file|->
yolo-gitea api        <METHOD> <path> [json-body-file]
```

## Settings

Set in the person's `.env`, or in the fleet repo (`fleet.env`,
`people/<name>.env`). See [09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md) and
[14-LAB.md](14-LAB.md).

| Variable | Default | |
|---|---|---|
| `YOLO_IMAGE` | `yolo-agent:3.0.0-full` | tier |
| `YOLO_PERSON` | empty | person name: fleet files, usage in the monitor |
| `YOLO_PORT_HOME` / `CODE` / `CHAT` / `TERM` / `FILES` | 8000 / 8080 / 4096 / 7681 / 8081 | host ports |
| `YOLO_BIND` | `0.0.0.0` | host address the ports listen on |
| `YOLO_WORKSPACE` | `./workspace` | host folder mounted at `/workspace` |
| `YOLO_MEM`, `YOLO_CPUS`, `YOLO_TMP_SIZE` | `12g`, `6`, `4g` | limits per service |
| `GITEA_TOKEN` | empty | the person's token (or `yolo login`) |
| `VLLM_BASE_URL`, `VLLM_MODEL`, `VLLM_API_KEY`, `VLLM_REASONING_EFFORT`, `VLLM_CONTEXT`, `VLLM_VISION_MODELS` | SEC09 | model endpoint |
| `GITEA_HOST`, `GITEA_PROTOCOL`, `GITEA_USER` | `192.168.1.27:3000`, `http`, from token | Gitea |
| `GIT_NAME`, `GIT_EMAIL` | `YOLO Agent`, `yoloagent@gmail.com` | commit identity |
| `YOLO_FLEET_REPO`, `YOLO_SKILLS_REPO` | `yolo/fleet`, `yolo/skills` | repos pulled at start |
| `YOLO_DEFAULT_SKILLS` | `yolo-airgap yolo-gitea skill-creator` | skills on for everyone |
| `YOLO_SKIP_CONFIGURE` | empty | `1` = start without running `yolo configure` |

## C++ helper (cpp and full tiers)

```bash
cpp-build <source-dir> [linux|windows|both] [extra cmake args...]

cpp-build .                                   # both targets, Release
cpp-build . windows                           # 64-bit Windows PE only
cpp-build . linux -DBUILD_TESTS=ON
CMAKE_BUILD_TYPE=Debug YOLO_BUILD_JOBS=8 cpp-build . both
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

## Reverse-engineering tools (full tier)

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
| `python3` | `/opt/pyenv/bin/python3` | the single 3.11 environment, with `capstone`, `unicorn`, `lief`, `pefile`, `pyelftools`, `xdis` |

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

## Build and release (networked machine)

```bash
docker buildx bake                  # core-test, cpp-test, full-test
docker buildx bake images           # yolo-agent:<v>-core|cpp|full
docker buildx bake core             # one tier
./scripts/package-offline.sh 3.0.0 ghcr.io/link2427/yolo-agent -- dist
```

`package-offline.sh` writes `yolo-agent-<v>-images.tar.zst` (or `.part-NN`
files), `yolo-agent-<v>-kit.zip`, `INSTALL-<v>.txt` and `SHA256SUMS`. Pushing a
`v*` tag runs the same through `.github/workflows/release.yml`.

## Paths inside the image

| Path | Contents |
|---|---|
| `/workspace` | the person's folder |
| `/home/agent` | home volume: agent configs and history, `~/.yolo/` (state, secrets, fleet, skills), `.git-credentials`, ccache |
| `/opt/yolo/bin` | `yolo`, `yolo-gitea`, `cpp-build`, agent wrappers, `entrypoint` |
| `/opt/yolo/lib` | `configure.py`, `status.py`, `skills.py`, `home.py`, `bot.py`, `env.sh`, `serve.sh` |
| `/opt/yolo/lab` | `gateway.py` and the monitor dashboard |
| `/opt/yolo/skills` | the skill library, `packs.json`, `INDEX.tsv` |
| `/opt/yolo/manifests` | `python.txt`, `vscode-extensions.txt` |
| `/opt/yolo/docs` | these docs |
| `/opt/agents` | agent binaries and `VERSIONS.txt` |
| `/opt/vscode-extensions` | VS Code extensions (linked into the home volume) |
| `/opt/code-server` | code-server |
| `/opt/pyenv` | the Python 3.11 environment |
| `/etc/yolo/defaults.env` | lab defaults |
| `/opt/java`, `/opt/jadx`, `/opt/ghidra` | full tier |
