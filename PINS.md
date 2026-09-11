# Version pins & integrity

Everything is pinned. The build fails on a hash mismatch, and `--only-binary`
is enforced for Python so a pin with no cp311 wheel fails at build time rather
than on the offline host.

**Why this matters here:** the images are built once, on a networked machine,
and then shipped to a host with no internet. Nothing in this repository can be
re-verified or repaired after export — so the pins *are* the supply chain.

## Images

| Image | Dockerfile | Adds |
|-------|-----------|------|
| `yolo-agent` | `Dockerfile` | base: agents, browser IDE, Python 3.11 |
| `yolo-agent-cpp` | `Dockerfile.cpp` | C/C++ toolchain + mingw-w64 Windows cross compiler |
| `yolo-agent-reverse-engineering` | `Dockerfile.reverse` | decompilers, JVM tools, binary analysis |

## Agents

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| opencode | 1.18.30 | `github.com/anomalyco/opencode` release tarball | sha256 TOFU¹ `5500724685…699d17` |
| pi | 0.85.1 | `github.com/earendil-works/pi` release tarball | sha256 **vs official release SHA256SUMS**² `494e498f47…1fe25a` |
| DeepSeek Harness (`dsh`) | 0.1.5-rc.1 | npm `@deepseek-ai/dsh` | exact top-level version plus a complete transitive integrity lock in `docker/deepseek-harness/pnpm-lock.yaml` (561 packages, every `integrity:` hash recorded); pnpm 11.7.0; CLI version and config boot verified at build |

¹ **TOFU** = trust-on-first-use. The project publishes no checksums for its
release tarball, so the hash was recorded from the first verified download. A
mismatch fails the build, which is what catches a re-tagged or tampered asset.

² pi and ttyd publish an official `SHA256SUMS` in each release; the build
verifies against that file and only falls back to the pinned TOFU hash if the
asset is missing.

### Removed in 2.0

goose, aider, prime-agent, and OpenHands were removed. OpenHands never worked
reliably in this container, and the other three tripled the Python surface for
no capability the remaining agents lack. Their pins are gone from this file on
purpose — an entry here means "this ships in an image".

## Web IDE

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| code-server | 4.137.0 | `github.com/coder/code-server` standalone tarball | sha256 TOFU¹ `9303165b7f…d6d9c8b` |
| ttyd | 1.7.7 | `github.com/tsl0922/ttyd` release binary | sha256 **vs official release SHA256SUMS**² (verified at build) |
| VS Code extension pack | 19 extensions | Open VSX, installed at build time | versions recorded in `/opt/yolo/EXTENSIONS-MANIFEST.txt` inside the image |

The C/C++ extension set (`clangd`, `cmake-tools`, `cmake`, `lldb`) is installed
in **every** image so IntelliSense works in the base container too; only
`yolo-agent-cpp` ships the compilers themselves.

## Base OS and runtimes

| Component | Version | Source | Integrity |
|-----------|---------|--------|-----------|
| Debian base | 12 (bookworm), slim | `debian:bookworm-slim` | distro-managed |
| Python | **3.11** | Debian bookworm `python3` | distro-managed; the project targets exactly one interpreter version |
| Node | 22 | `node:22-bookworm-slim` | linux/amd64 manifest digest pinned: `sha256:83f487e0…7767a7e5`; only `/usr/local` is copied forward |
| cmake / ninja / gcc / g++ / clang / lld / lldb / gdb / make / pkg-config / ccache / nasm / valgrind / lcov / gcovr / autotools | Debian 12 | apt | distro-managed |
| mingw-w64 cross toolchain | 10.0.0-3 (`gcc-mingw-w64-x86-64` 12.2.0) | apt | distro-managed; Debian's POSIX threading model is the default |
| Temurin JDK | 21.0.12.1+1 | Adoptium GitHub release | sha256 `ce79869e13…faee94`; required because Ghidra ≥ 12 needs Java 21 and Debian 12 ships only OpenJDK 17 |

Note: Debian 12 provides clang/lld/lldb **14**. A newer LLVM would have to be
vendored and would cost several hundred MB; the distro version is what
"lightweight and offline" allows here.

## Python 3.11 environment (`/opt/pyenv`)

One environment, one interpreter version, per image:

| File | Used by | Contents |
|------|---------|----------|
| `docker/requirements-common.txt` | all three images | ~45 general-purpose packages (HTTP, CLI, data, testing, linting, IPython) |
| `docker/requirements-reverse.txt` | reverse image only | layered onto the **same** venv — decompilers and binary-analysis bindings |

The reverse image therefore has exactly one environment containing both sets; it
does not create a second venv.

### Packages pinned below their latest release on purpose

These current releases require Python ≥ 3.12, and this project targets one 3.11
environment, so each is pinned to its last 3.11-compatible release:

| Package | Pinned | Latest | Why |
|---------|--------|--------|-----|
| numpy | 2.4.6 | 2.5.3 | 2.5 requires ≥ 3.12 |
| angr | 9.2.213 | 9.3.4 | 9.3 requires ≥ 3.12 |
| xdis | 6.3.0 | 6.3.0 | held at 6.3.0 because `pyinstxtractor-ng` requires exactly this |

### Deliberately not installed: uncompyle6

`uncompyle6` requires `xdis<6.2.0`, while `pyinstxtractor-ng` requires
`xdis==6.3.0` exactly. The two cannot coexist in one environment, and
`pyinstxtractor-ng` is the non-negotiable one (it is how a PyInstaller `.exe`
is unpacked at all). `decompyle3` is kept and is verified to run at build time.
For bytecode the Python decompilers cannot handle, **pycdc** (C++, built from
source in the reverse image) is the fallback and covers arbitrary versions.

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
why a dedicated image exists rather than folding them into the base.

## Offline packaging

| Item | Detail |
|------|--------|
| Bundles | one ZIP per image: `yolo-agent-<flavor>-<version>-offline.zip` |
| Asset limit | GitHub release assets must be < 2 GiB; `scripts/package-offline.sh` splits into 1900 MiB parts with checksums and reassembly instructions if a bundle exceeds it |
| Verification | `SHA256SUMS` inside the bundle for the image archive, plus a `.zip.sha256` sidecar for the ZIP itself |

## Audit trail

- `/opt/PYTHON-MANIFEST.txt` — exact `pip freeze` output baked into the image.
- `/opt/yolo/EXTENSIONS-MANIFEST.txt` — code-server extension versions.
- `IMAGE-INSPECT.json` — `docker image inspect` output in each offline bundle.
- `SOURCE-COMMIT.txt` — the git commit each bundle was built from.
- `docker/deepseek-harness/pnpm-lock.yaml` — full transitive npm lock.
