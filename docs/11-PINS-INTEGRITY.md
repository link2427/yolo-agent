# 11 — Pins and integrity

The images are built once, on a networked machine, and carried to a lab with no
internet. Nothing can be re-downloaded or repaired there. So every input is
pinned, every download is checked, and every tier is tested before it ships.
[../PINS.md](../PINS.md) is the register of what ships; this page explains how
the build enforces it.

## Where the pins live

All versions and hashes are `ARG`s at the top of the `Dockerfile` (one file for
all three tiers, so a bump cannot split them). The installers in
`docker/install/` require those values and fail if one is missing.

## How downloads are verified

| Mechanism | Used for |
|---|---|
| sha256 pinned in the `Dockerfile` (`sha256sum -c` at build) | opencode, pi, Crush, Goose, Codex, code-server, File Browser, Ghidra, jadx, radare2, pycdc, Temurin JDK |
| the release's own `SHA256SUMS` | ttyd |
| npm registry integrity, exact version | Qwen Code, Claude Code |
| pinned git commit of a tarball | `anthropics/skills` |
| manifest digest | the Node 22 base image (`node:22-bookworm-slim@sha256:83f487e0…`) |
| Debian archive signatures | apt packages |

A hash mismatch fails the build. Never edit a hash to make a build pass: a
mismatch means the bytes changed under an unchanged version, which is exactly
what the pins are there to catch.

## `--only-binary=:all:` for pip

The Python environment refuses to build from source. Every pin in
`docker/requirements-*.txt` has a CPython 3.11 linux/amd64 wheel (or a `py3`
wheel); a pin without one fails the build instead of compiling an unreviewed
sdist. Check a candidate before adding it:

```bash
pip download --only-binary=:all: --python-version 3.11 -d /tmp/x <pkg>==<ver>
```

## The Node base image

Node 22 comes from the official image by digest. Only `/usr/local/bin/node` and
`/usr/local/lib/node_modules` are copied into the Debian runtime, so there is one
Debian 12 userland and one Python 3.11.

## What the build gate checks

Each tier has a test stage (`core-test`, `cpp-test`, `full-test`) that runs the
smoke suites **with no network** (`RUN --network=none`):

- `docker/tests/smoke-core.sh` (all tiers): uid 10001; read-only `/usr`, `/opt`,
  `/etc`; no setuid files; Node 22, Python 3.11 and the common imports; every
  agent prints its pinned version; `yolo configure` against a stub model server
  (`docker/tests/stub-llm.py`), with each agent's config file checked; every
  agent, and Kilo Code's `kilo`, completes a real request through its generated
  config, sending the person's key and the right model; configure still works
  when the model server is down; skills enable and disable; `yolo status`,
  `agents`, `tools`; the start page, code-server, ttyd, File Browser and opencode
  web answer HTTP; the lab gateway proxies `/v1/models` and serves the dashboard;
  the bot module loads.
- `docker/tests/smoke-cpp.sh` (cpp, full): compilers present; the mingw-w64
  cross compilers are the POSIX variants; C++20 native ELF and Windows PE builds;
  Fortran with LAPACK, mixed C++/Fortran, a static Fortran PE with no DLL
  dependency; both CMake toolchain files; `cpp-build`.
- `docker/tests/smoke-reverse.sh` (full): Java 21, the reverse Python packages,
  a real PyInstaller archive built, extracted and disassembled, jadx, Ghidra
  headless, radare2.

`install-agents.sh` also runs every agent binary at build time and records the
versions in `/opt/agents/VERSIONS.txt`.

## What is not pinned

- **apt packages** are not hash-pinned. Compilers and tools come from the Debian
  12 archive on the day of the build. Two builds weeks apart can differ there.
- **pip** installs exact versions without `--hash=` values. The smoke tests and
  the recorded manifest are the compensating control.
- **npm dependencies** of Qwen Code and Claude Code are resolved at build time
  from the exact top-level versions.

For a build you need to certify, keep the release files together with
`SOURCE-COMMIT.txt` from the kit.

## Auditing what shipped

```bash
# inside any container
cat /opt/agents/VERSIONS.txt
cat /opt/yolo/manifests/python.txt
cat /opt/yolo/manifests/vscode-extensions.txt
cat /opt/yolo/skills/INDEX.tsv

# on the host
docker image inspect yolo-agent:3.0.0-full --format '{{json .Config.Labels}}'
```

## Packages pinned below their latest release

Python is 3.11 (Debian 12's system Python). Packages that now need 3.12 are held
at their last 3.11 release; see [../PINS.md](../PINS.md) for the list and the
`xdis` / `pyinstxtractor-ng` / `uncompyle6` conflict.

## Bumping a pin

1. Find the integrity story for the new artifact. If upstream publishes
   checksums, use them. Otherwise download once from the official release and
   record its `sha256sum`. Never take a hash from a mirror or a search result.
2. Change the `ARG`s in the `Dockerfile` and the row in [../PINS.md](../PINS.md)
   in one commit.
3. For a Python pin, prove the cp311 wheel exists (above).
4. Build through the tests:

   ```bash
   docker buildx bake            # core-test, cpp-test, full-test
   ```

5. Then the images and the release:

   ```bash
   docker buildx bake images
   ./scripts/package-offline.sh <version> <image-prefix> -- dist
   ```

The release workflow (`.github/workflows/release.yml`) does steps 4 and 5 for a
`v*` tag and publishes nothing unless every tier passes.

## Trust boundary: the reverse-engineering tools

`pycdc`, `jadx`, Ghidra and radare2 parse hostile input. A verified hash proves
you got the upstream release, not that the release is free of parsing bugs. See
[10-SECURITY.md](10-SECURITY.md).
