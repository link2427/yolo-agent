# Changelog

## 2.0.0 - 2026-09-11

The modular overhaul. The repository now builds **three** independent images
instead of one monolith, and the agent surface is deliberately much smaller.

### Added

- `yolo-agent-cpp` (`Dockerfile.cpp`) — an offline C/C++ toolchain: gcc, g++,
  clang 14 (+clangd), lld, lldb, gdb, make, ninja, cmake, pkg-config, ccache,
  nasm, strace, ltrace, valgrind, lcov, gcovr, doxygen, graphviz and autotools,
  plus the **mingw-w64 cross toolchain** that produces 64-bit Windows PE
  binaries (`x86_64-w64-mingw32-gcc/g++`). Includes two CMake toolchain files,
  a `cpp-build.sh` helper, and a smoke test that compiles and asserts on both an
  ELF64 and a PE32+ binary.
- `yolo-agent-reverse-engineering` (`Dockerfile.reverse`) — pycdc/pycdas (built
  from source), pyinstxtractor-ng, decompyle3, pydumpck, xdis, jadx 1.5.6,
  Ghidra 12.1.3 headless on Temurin JDK 21, radare2 6.2.2, gdb, angr, capstone,
  unicorn, lief, pefile, pyelftools, binwalk, foremost, and yara. Its smoke test
  builds a real PyInstaller archive, extracts it, and disassembles the result.
- `config/seccomp-toolchain.json` — a second seccomp profile for the toolchain
  images. It is identical to the base profile except that `ptrace`,
  `process_vm_readv`, and `process_vm_writev` are allowed, which is what makes
  `gdb` and gcc LTO work. Every privileged syscall stays denied.
- Per-image compose files (`compose.yaml`, `compose.cpp.yaml`,
  `compose.reverse.yaml`) and per-flavor env templates, home volumes, and
  launcher targets.
- One offline bundle per image, with `scripts/package-offline.sh` generalized
  from a single image to `name:tag` specs.

### Changed

- **Build graph** — `docker buildx bake` now builds and smoke-tests all three
  images; `docker buildx bake {base,cpp,reverse}` builds one.
- **Base image** — moved from `node:22-bookworm-slim` to `debian:bookworm-slim`
  with the Node runtime copied in from the official image. This gives a clean
  Debian userland whose system interpreter is exactly Python 3.11, which is the
  single interpreter version the project now targets.
- **Python** — collapsed into **one** environment per image at `/opt/pyenv`
  (Python 3.11, first on `PATH`, `VIRTUAL_ENV` preset). The reverse image
  extends that same venv instead of creating a second one.
- **Pins refreshed** — opencode 1.18.30, pi 0.85.1, DeepSeek Harness
  0.1.5-rc.1 (with a regenerated 561-package pnpm lock), code-server 4.137.0.
- **Node base digest** re-pinned; VS Code extension pack grown from 15 to 19 to
  include the C/C++ set in every image.
- Documentation restructured for three containers (13 documents under `docs/`).

### Removed

- **OpenHands** entirely — it never worked reliably in this container. Gone from
  the Dockerfile, compose, launchers, docs, and the offline bundles.
- **prime-agent** and its Python kernel runtime (the `~/.prime` venv, `uv`, and
  the second interpreter it dragged in).
- **goose** and **aider** — their config surface and their venvs.
- **The skills library** (`install-skills.sh`, `make-skill-farm.sh`,
  `skill-use.sh`, `CURATED-SKILLS.txt`, and the 147 MB `/opt/skills` tree). This
  was the single largest weight cut and is what makes one complete shared Python
  environment affordable. Agents author skills in `/workspace` instead.
- **The DeepSeek Harness wrapper script** — 0.1.5-rc.1 no longer imports Node
  internals, and the `dsh --version` check in the installer is what proves the
  shim runs.
- `config/yolo.env.example` and `config/seccomp-yolo.json`, replaced by
  per-flavor templates and two named seccomp profiles.

### Known limitations

- The C++ image has **no Wine**, so Windows binaries can be cross-compiled but
  not executed inside the container. CMake test execution is guarded with
  `if(NOT CMAKE_CROSSCOMPILING)`.
- Debian 12 ships clang/lld/lldb **14**; a newer LLVM would have to be vendored.
- `uncompyle6` is deliberately absent because it requires `xdis<6.2.0` while
  `pyinstxtractor-ng` requires `xdis==6.3.0` exactly. pycdc covers arbitrary
  bytecode versions as the fallback.
- `numpy` (2.4.6) and `angr` (9.2.213) are pinned below their latest releases,
  which now require Python ≥ 3.12.

## 1.2.2 - 2026-09-04

- Qwen3.8-27B reasoning effort matches the model card: `xhigh` (default),
  `medium`, and `low`. `off` turns thinking off (`enable_thinking: false`).
  `high` is accepted as an alias for `xhigh`. Default model id is
  `Qwen/Qwen3.8-27B`.
- Model selectors are local vLLM only. OpenCode uses a custom `vllm`
  provider with `enabled_providers`. Goose uses only the custom vLLM
  provider. pi/prime-agent default to vLLM; do not set `OPENAI_API_KEY`
  or their cloud catalogs appear. DeepSeek Harness writes
  `~/.dsh/settings.yaml` for the same vLLM route; do not set
  `DEEPSEEK_API_KEY`.

## 1.2.1 - 2026-09-04

- Default vLLM model is Qwen3.8-27B (`VLLM_MODEL` in yolo.env).
- Qwen reasoning effort is configured for every agent: opencode variants
  (low/medium/high), pi and prime-agent (`qwen-chat-template` + `/effort`),
  goose, aider, and OpenHands. Override with `VLLM_REASONING_EFFORT`
  (`off` | `low` | `medium` | `high`, default `high`).

## 1.2.0 - 2026-09-03

- Removed the headless profile; the image is now a single always-on browser
  runtime (code-server, ttyd, OpenHands, and DeepSeek Harness all exposed).
  `docker compose up -d` starts those browser services; the interactive
  shell remains `docker compose run --rm agent`.
- Added the current OpenHands CLI (1.16.0) web interface on port 3000, no
  Docker socket, pointed at the same vLLM endpoint as the other agents.
- Bumped agent harnesses to current releases: opencode 1.18.27, goose 1.48.0,
  pi 0.84.4, prime-agent 0.9.1, code-server 4.135.0. aider, ttyd, and
  DeepSeek Harness remain at their current versions.
- Collapsed the offline release bundle to a single full bundle.

## 1.1.0 - 2026-08-30

- Added the official DeepSeek Harness (`dsh`) developer preview, pinned through
  a committed pnpm lockfile and verified during the image build.
- Added persistent headless and browser workflows; Harness state lives in the
  existing agent-home volume and `DEEPSEEK_API_KEY` stays runtime-only.
- Added an opt-in Compose browser service on host-loopback port 3080 without
  patching DeepSeek Harness's upstream loopback-only safety policy.
- Added image smoke tests for the Harness CLI and runtime environment.
- Compressed offline bundles and added automatic multipart fallback for
  GitHub's 2 GiB release-asset limit.

## 1.0.0 - 2026-08-28

- Renamed the project from `yolo-dev` to `yolo-agent`.
- Split the image into independently cached toolchain, skills, and web-IDE stages.
- Added `headless` and `full` runtime profiles plus matching smoke-test stages.
- Added Docker Bake, Compose, and GitHub Actions build/release workflows.
- Added downloadable full and headless offline ZIP bundles for disc transfer.
- Pinned the Linux/amd64 Node base image by digest.
- Separated host launchers, runtime rootfs, security policy, and image installers.
- Preserved the exact recovered 6.0 source as `archive-yolo-dev-6.0-recovered`.
- Preserved the surviving 5.0 documents and build metadata as a partial snapshot.

## Imported yolo-dev 6.0 source - 2026-08-18

Exact source tree recovered from the `lavender-lark-43` Longhorn backup.
This is the first complete source state available in Git history.

## Imported yolo-dev 5.0 evidence

Only exported documentation, a build log, manifest, and archive checksum
survived. See `history/v5.0/README.md`; no complete source tree is claimed.
