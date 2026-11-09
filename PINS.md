# Version pins & integrity

Everything is pinned. The build fails on a hash mismatch, and `--only-binary`
is enforced for Python so a pin with no cp311 wheel fails at build time rather
than on the offline host.

The images are built once, on a networked machine, and then carried to a lab
with no internet. Nothing can be re-verified or repaired there, so the pins are
the supply chain. All pins are `ARG`s at the top of the `Dockerfile`.

## Tiers

One `Dockerfile`, three tags: `yolo-agent:3.0.0-core`, `-cpp`, `-full`. Each
tier contains the one below it.

## Agents

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| opencode | 1.18.30 | `github.com/anomalyco/opencode` release tarball | sha256 pinned `5500724685…699d17` |
| pi | 0.85.1 | `github.com/earendil-works/pi` release tarball | sha256 pinned `494e498f47…1fe25a` |
| Crush | 0.100.0 | `github.com/charmbracelet/crush` release tarball | sha256 pinned `122d4afe0e…cd7a152` |
| Goose | 1.57.0 | `github.com/aaif-goose/goose` release tarball | sha256 pinned `10eb96cb6a…df98e3` |
| Codex | 0.167.0 | `github.com/openai/codex` release tarball (musl) | sha256 pinned `9d64836106…da251a` |
| Qwen Code | 0.27.0 | npm `@qwen-code/qwen-code` | exact version; npm registry integrity hashes |
| Claude Code | 2.1.319 | npm `@anthropic-ai/claude-code` (native linux-x64 binary) | exact version; npm registry integrity hashes |

Every binary must run and print its pinned version at build time
(`/opt/agents/VERSIONS.txt`), and the smoke test makes each agent complete a
request against a stub model server with no network.

## Web surfaces

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| code-server | 4.137.0 | `github.com/coder/code-server` standalone tarball | sha256 pinned `9303165b7f…d6d9c8b` |
| ttyd | 1.7.7 | `github.com/tsl0922/ttyd` release binary | sha256 checked against the release's own `SHA256SUMS` |
| File Browser | 2.63.23 | `github.com/filebrowser/filebrowser` release tarball | sha256 pinned `b14db2bb80…909e88` |

## VS Code extensions

Installed from Open VSX at build time into `/opt/vscode-extensions`; the exact
versions are recorded in `/opt/yolo/manifests/vscode-extensions.txt`.

| Extension | Notes |
|---|---|
| `redhat.vscode-yaml` | schema store download turned off |
| `tamasfe.even-better-toml` | schema download turned off |
| `timonwong.shellcheck` | uses `/usr/bin/shellcheck` |
| `editorconfig.editorconfig` | |
| `esbenp.prettier-vscode` | |
| `llvm-vs-code-extensions.vscode-clangd` | cpp and full tiers only |
| `ms-vscode.cmake-tools` | cpp and full tiers only; automatic kit scan off |
| `twxs.cmake` | cpp and full tiers only |
| `mhutchie.git-graph` | |
| `kilocode.Kilo-Code` | agent panel, configured for SEC09 |
| `github.github-vscode-theme`, `dracula-theme.theme-dracula`, `Catppuccin.catppuccin-vsc`, `PKief.material-icon-theme` | themes and icons |

Removed in 3.0 because they reach for the internet: `vadimcn.vscode-lldb`,
`ms-python.python`, `eamodio.gitlens`. Also dropped: `dbaeumer.vscode-eslint`,
`streetsidesoftware.code-spell-checker`, `mskelton.one-dark-theme`, and Cline
(`saoudrizwan.claude-dev`, which cannot be pre-configured). See
[docs/07-WEB-IDE.md](docs/07-WEB-IDE.md).

## Skills

| Item | Pin |
|---|---|
| `anthropics/skills` | commit `2c5958ecac7cee2b583967a2c4981d0f4a75c579`; only skills whose `LICENSE.txt` is the Apache License are copied in |
| house skills | `docker/skills/` in this repository |

## Base OS and runtimes

| Component | Version | Source | Integrity |
|-----------|---------|--------|-----------|
| Debian base | 12 (bookworm), slim | `debian:bookworm-slim` | distro-managed |
| Python | **3.11** | Debian bookworm `python3` | distro-managed; the project targets exactly one interpreter version |
| Node | 22 | `node:22-bookworm-slim` | linux/amd64 manifest digest pinned: `sha256:83f487e0…7767a7e5`; only `/usr/local` is copied forward |
| cmake / ninja / gcc / g++ / gfortran / liblapack / libblas / clang / lld / lldb / gdb / make / pkg-config / ccache / nasm / valgrind / lcov / gcovr / autotools | Debian 12 | apt | distro-managed |
| mingw-w64 cross toolchain | 10.0.0-3 (`gcc`/`g++`/`gfortran-mingw-w64-x86-64` 12.2.0) | apt | distro-managed; Debian's POSIX threading model is the default |
| Temurin JDK | 21.0.12.1+1 | Adoptium GitHub release | sha256 `ce79869e13…faee94`; required because Ghidra ≥ 12 needs Java 21 and Debian 12 ships only OpenJDK 17 |

The mingw-w64 cross compiler is pinned to the **POSIX threading variant** via
`update-alternatives`. Both variants are installed and Debian's default is
win32, which silently breaks `<mutex>` and `std::thread` while still accepting
`-pthread`; the toolchain installer and the C++ smoke suite both assert the
posix variant is the one resolved.

Note: Debian 12 provides clang/lld/lldb **14**. A newer LLVM would have to be
vendored and would cost several hundred MB; the distro version is what
"lightweight and offline" allows here.

## Python 3.11 environment (`/opt/pyenv`)

One environment, one interpreter version, in every tier:

| File | Used by | Contents |
|------|---------|----------|
| `docker/requirements-common.txt` | all three tiers | ~45 general-purpose packages (HTTP, CLI, data, testing, linting, IPython) |
| `docker/requirements-reverse.txt` | full tier only | layered onto the **same** venv — decompilers and binary-analysis bindings |

The full tier therefore has exactly one environment containing both sets; it
does not create a second venv.

### Packages pinned below their latest release on purpose

These current releases require Python ≥ 3.12, and this project targets one 3.11
environment, so each is pinned to its last 3.11-compatible release:

| Package | Pinned | Latest | Why |
|---------|--------|--------|-----|
| numpy | 2.4.6 | 2.5.3 | 2.5 requires ≥ 3.12 |
| xdis | 6.3.0 | 6.3.0 | held at 6.3.0 because `pyinstxtractor-ng` requires exactly this |

### The pydumpck / uncompyle6 / xdis conflict

`uncompyle6` and `decompyle3` both declare an upper bound on `xdis`
(`<6.3` and `<6.2.0` respectively, per their wheel metadata), while
`pyinstxtractor-ng` requires `xdis==6.3.0` exactly. **pip treats transitive
constraints as hard**, so no combination of pins resolves:

- `decompyle3` is simply not installed — `xdis<6.3` cannot meet `xdis==6.3.0`.
- `pydumpck` requires `uncompyle6`, so pydumpck cannot be resolved normally
  either. Both are installed from
  `docker/requirements-reverse-nodeps.txt` with `--no-deps`.
- Their dependencies are pinned explicitly in `requirements-reverse.txt`
  (`pyinstaller`, `sgtpyutils`, `tinyaes`, `spark-parser`, and `click` from the
  common set), so nothing in the environment is actually unpinned — only the
  resolution edge from pydumpck/uncompyle6 to its dependencies is skipped.
- `uncompyle6` running against `xdis 6.3.0` is unverified by its metadata. The
  reverse smoke suite runs its CLI during the build, and that execution is the
  only real evidence it works.

Extraction is the capability the full tier exists for, so `xdis` wins. The
alternative — dropping `pyinstxtractor-ng` to satisfy the decompilers — would
remove the ability to unpack a PyInstaller `.exe` at all.

## Reverse-engineering toolchain

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| pycdc / pycdas | commit `b4289760` (2026-04-07) | `github.com/zrax/pycdc` source tarball | sha256 `d7d8c53d37…c9941bf31`; built from source with cmake+ninja at image build |
| jadx | 1.5.6 | `github.com/skylot/jadx` release zip | sha256 `545ea2be9c…30e8974` |
| Ghidra | 12.1.3 (build 20260817) | NSA GitHub release zip | sha256 `93a5d11a9a…5081fd54`; headless launcher only |
| radare2 | 6.2.2 | official release `.deb` | sha256 `09234e4139…63b1ad`, taken from the release's own `checksums.txt` |
| gdb, binutils-multiarch, elfutils, strace, ltrace, binwalk, foremost, yara, xxd, hexedit, p7zip, cabextract | Debian 12 | apt | distro-managed |

Trust boundary: `pycdc`, `jadx`, `Ghidra`, and `radare2` are third-party
analysis tools that parse **hostile input**. They run as uid 10001 inside the
container with no network and no capabilities, which is the containment this
project relies on — but a parsing bug in any of them is a genuine risk, which is
why they are only in the `full` tier.

## Offline release

| Item | Detail |
|------|--------|
| Images | `yolo-agent-<v>-images.tar.zst`: one `docker save` of all three tiers, zstd level 19. Layers the tiers share are stored once. |
| Asset limit | split into 1900 MiB parts (`.part-00`, `.part-01`, ...) when larger than GitHub's 2 GiB limit |
| Kit | `yolo-agent-<v>-kit.zip`: compose files, env templates, `config/seccomp.json`, docs, `install.sh`, `tools/gpu-exporter.py` |
| Verification | `SHA256SUMS` covers every file; `install.sh load` checks it before loading |

## Audit trail

- `/opt/yolo/manifests/python.txt` — exact `pip freeze` output.
- `/opt/yolo/manifests/vscode-extensions.txt` — code-server extension versions.
- `/opt/agents/VERSIONS.txt` — agent versions, checked at build.
- `/opt/yolo/skills/INDEX.tsv` — every skill in the library and where it came from.
- `SOURCE-COMMIT.txt` in the kit — the git commit the release was built from.
