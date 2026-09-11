# 11 — Pins and integrity

[../PINS.md](../PINS.md) is the authoritative version table: every component, its
version, where it came from, and whether its hash is official or trust-on-first-use.
This document explains the model behind that table — what the build actually
enforces, what it does not, how to audit an image after the fact, and how to bump
a pin without weakening anything.

Related: [10-SECURITY.md](10-SECURITY.md) (containment), [04-PYTHON.md](04-PYTHON.md)
(the single environment), [13-COMMAND-REFERENCE.md](13-COMMAND-REFERENCE.md)
(inspection commands).

## Why the pins are the supply chain

Each image is built **once**, on a networked machine, then exported and carried to
a host with no internet. Three consequences follow, and they shape everything
below:

- **Nothing can be fetched on the offline host.** There is no npm, pip, apt, or
  Open VSX route at runtime. Whatever is not in the image cannot be added later.
- **Nothing can be repaired on the offline host.** If an artifact was wrong when
  it was baked in, the rebuilt image is the only fix, and rebuilding needs the
  networked machine.
- **Nothing can be re-verified on the offline host** against upstream, because
  upstream is unreachable. The only hashes available there are the ones shipped
  alongside the image.

So a pin is not a version preference. It is the entire supply-chain control: the
build either reproduces exactly the artifact that was reviewed, or it fails. A
pin that is wrong, stale, or edited to silence an error ships silently and is
discovered only when the tool misbehaves — or never.

## The three verification mechanisms

Every downloaded artifact is checked with `sha256sum -c` under
`set -euo pipefail`, so a mismatch is a build failure, not a warning. What
differs is the *provenance* of the hash being checked against.

| # | Mechanism | Applies to | Enforced by | Provenance of the expected hash |
|---|---|---|---|---|
| a | Official upstream `SHA256SUMS` | pi, ttyd | checksum file downloaded from the same release at build time | published by the upstream project |
| b | TOFU-pinned sha256 | opencode, code-server; also Temurin JDK, jadx, Ghidra, pycdc, radare2 | sha256 embedded as a build `ARG` and compared at build time | recorded by this project from the first verified download |
| c | Transitive npm integrity lock | DeepSeek Harness (`dsh`) | `pnpm install --frozen-lockfile` with a committed lockfile | `integrity:` hashes from the npm registry, one per package |

### (a) Official upstream `SHA256SUMS` — pi and ttyd

Both projects publish a `SHA256SUMS` file next to their release assets, and the
installer downloads it from the same release tag as the artifact:

```bash
# install-agents.sh — pi
curl -fsSL -o /tmp/pi.SHA256SUMS \
  "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/SHA256SUMS"
grep "pi-linux-x64.tar.gz" /tmp/pi.SHA256SUMS | (cd /tmp && sha256sum -c -)

# install-web-ide.sh — ttyd
curl -fsSL -o /tmp/ttyd.SHA256SUMS \
  "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/SHA256SUMS"
grep "ttyd.x86_64" /tmp/ttyd.SHA256SUMS | (cd /tmp && sha256sum -c -)
```

The difference between the two matters:

- **pi** falls back to its pinned `PI_SHA256` ARG if the checksum asset cannot be
  downloaded. Official verification is preferred; the pin keeps the build
  verifiable if upstream ever removes the file.
- **ttyd** has no fallback. If the `SHA256SUMS` asset disappears, the build fails.
  That is deliberate: there is no pinned alternative, and inventing one at that
  point would be exactly the kind of unverified value this model exists to avoid.

Because the expected hash comes from upstream at build time, this mechanism also
catches a **re-tagged or replaced release asset**: the tag would still match, the
hash would not.

### (b) TOFU-pinned sha256 — opencode and code-server

Neither project publishes checksums for its release tarball. For these, the hash
was recorded from the first verified download and is now a build `ARG`:

| Artifact | Version | Pinned sha256 (full) | Verified against |
|---|---|---|---|
| opencode | 1.18.30 | `55007246858165496ff85ba1c2b648f7421e8e2013bf4189a680c9ff8e699d17` | `OPENCODE_SHA256` ARG, always |
| code-server | 4.137.0 | `9303165b7fd43532091922f77e2f119ff2fa109c6b6f1c3c966fb02f3d6d9c8b` | `CODE_SERVER_SHA256` ARG, always |
| pi (fallback only) | 0.85.1 | `494e498f47d74d21f40b3386f6a5e921a3d49531a169cab55bbdaca0ea1fe25a` | used only when the official `SHA256SUMS` is unavailable |
| Node base image | 22 (bookworm-slim) | `sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5` | image reference digest, not a download check |

**TOFU = trust on first use.** The hash is only as trustworthy as that first
download: if the artifact had already been tampered with when the pin was
recorded, the pin freezes the tampered bytes. What TOFU does buy is
**byte-stability from then on** — a re-tagged asset, a replaced binary, or a
man-in-the-middle on a later build all produce a different hash and fail the
build. It does not buy provenance, and it is not the same claim as mechanism (a).
[../PINS.md](../PINS.md) marks each one explicitly.

The single-artifact downloads in the reverse image are the same class of pin:
Temurin JDK 21 (`ce79869e…faee94`), jadx 1.5.6 (`545ea2be9c…30e8974`), Ghidra
12.1.3 (`93a5d11a9a…5081fd54`), the pycdc source tarball at commit `b4289760`
(`d7d8c53d37…c9941bf31`), and radare2 6.2.2 (`09234e4139…63b1ad`). radare2 is the
one worth noting: its value was taken from the hash the release itself publishes
in `checksums.txt`, but the build verifies against the pinned `ARG` — it does not
re-fetch that file, so a later change to the release's own checksum list would not
be noticed until someone re-pins.

### (c) A full transitive npm lock — DeepSeek Harness

`dsh` is the one component with a dependency graph too large to pin by hand, so it
is pinned by a committed lockfile instead:

```
docker/deepseek-harness/package.json      -> "@deepseek-ai/dsh": "0.1.5-rc.1", pnpm@11.7.0
docker/deepseek-harness/pnpm-lock.yaml    -> lockfileVersion 9.0, 561 integrity: hashes
```

The installer (`docker/install/install-deepseek-harness.sh`) enforces three things
before it trusts the result:

```bash
# 1. the lockfile must pin exactly the version this build intends
locked_version="$(sed -n '/^[[:space:]]*specifier:/ { ... }' "$lock_root/pnpm-lock.yaml")"
[[ "$locked_version" == "$DSH_VERSION" ]] || exit 1

# 2. install strictly from the lock, no scripts, production tree only
corepack prepare pnpm@11.7.0 --activate
pnpm --dir /opt/deepseek-harness install --prod --frozen-lockfile --ignore-scripts

# 3. the installed package must really be that version, then run it
node -p "require('/opt/deepseek-harness/node_modules/@deepseek-ai/dsh/package.json').version"
dsh --version | grep -Fx "$DSH_VERSION"
dsh --profile headless --dump-default-config
```

`--frozen-lockfile` is what makes the lock authoritative: pnpm refuses to resolve
anything new, and every one of the 561 packages is checked against the `integrity:`
hash recorded for it. `--ignore-scripts` means no dependency can execute code
during install. If a package in the graph ever changed content, the install fails.

## What the build gate enforces

Pinning is only half the model; the other half is a smoke suite that runs inside
the image during the build, as the `test` target of each Dockerfile. CI runs it on
every push and pull request (`docker buildx bake <flavor>-test`).

| Suite | Runs in | Asserts |
|---|---|---|
| `docker/tests/smoke-common.sh` | all three | uid 10001 and user `agent`; writable `/workspace`, `/home/agent`, `/tmp`; read-only `/usr`, `/opt`; zero setuid files; `opencode`, `pi`, and `dsh` versions (exact strings, from the same ARGs as the build); removed agents absent (`goose`, `aider`, `prime-agent`, `openhands`) and no leftover interpreter directories; code-server and ttyd versions; ≥15 extensions; node v22; Python 3.11 with the common imports; `VIRTUAL_ENV=/opt/pyenv`; `configure-agents.sh` output asserted with `jq`; `configure-git.sh` in both token and SSH mode with mode-600 secrets; HTTP responses from code-server `:8080`, ttyd `:7681`, and the DSH relay `:3081` |
| `docker/tests/smoke-cpp.sh` | cpp | the compiler and build tools exist; a real ELF64 and a real PE32+ are produced and the PE is checked for a static libstdc++ link; CMake configures, builds, and runs a test suite for linux and cross-builds for Windows; `cpp-build.sh` produces both artifacts; `gdb` attaches (proving `ptrace` works under the toolchain seccomp profile) |
| `docker/tests/smoke-reverse.sh` | reverse | every tool on PATH; Java 21; the reverse Python packages import in the one venv; a genuine PyInstaller archive is built, extracted without execution, and its bytecode disassembled; `uncompyle6` runs; a `.pyc` round trip; radare2, LIEF, and angr load a real binary; `ghidra-headless` resolves Java and starts |

Two properties of that gate are worth stating plainly:

- **A hash mismatch fails the build.** Every verification is `sha256sum -c` in a
  `set -euo pipefail` script; a non-zero exit stops the layer, the image is never
  produced, and nothing is published.
- **A version drift fails the build.** The suites compare the installed CLI
  versions against the same `ARG`s the installer used. That is why the Dockerfile
  `ARG` and the [../PINS.md](../PINS.md) row have to move together: if they drift,
  either the build fails or the table stops describing what ships.

The suite is a gate, not a proof. It detects the failures that matter for shipping
(wrong version, missing tool, broken config, port that does not serve) and it is
not a substitute for reading the version table.

## `--only-binary=:all:` for pip

The Python environment is installed with an explicit refusal to build from source:

```bash
"$VENV/bin/python" -m pip install --no-cache-dir --disable-pip-version-check \
  --index-url "$PIP_INDEX" --only-binary=:all: -r "$f"
```

Every pin in `docker/requirements-common.txt` and
`docker/requirements-reverse.txt` was verified to publish a CPython 3.11
linux/amd64 wheel (or a universal `py3` wheel). `--only-binary=:all:` turns that
verification into a build-time rule:

- If a pin has **no cp311 wheel**, the build **fails immediately**. It does not
  fall back to compiling an sdist, which would pull in a compiler, a network fetch
  of build dependencies, and a result that depends on the builder's toolchain — a
  package that could never be reproduced or audited later.
- It also prevents a silently *different* artifact. A wheel and an sdist of the
  same version are not the same thing, and only one of them was reviewed.

The check for a candidate pin, before adding it:

```bash
pip download --only-binary=:all: --python-version 3.11 -d /tmp/x <pkg>==<ver>
```

Then `pip list --format=freeze` is recorded into `/opt/PYTHON-MANIFEST.txt` inside
the image, which is the resolved set an operator can audit.

## The Node base image

Node 22 is taken from the official image **by manifest digest**, not by tag:

```dockerfile
ARG NODE_IMAGE=node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5
```

The digest is the linux/amd64 manifest, so `node:22-bookworm-slim` moving forward
cannot change what this build consumes. Only two paths are copied out of it into
the Debian runtime stage — `/usr/local/bin/node` and
`/usr/local/lib/node_modules` — and `npm`, `npx`, and `corepack` are then
symlinked from the copied tree, with `node --version` and `npm --version` asserted
in the same layer.

Why not use the Node image as the runtime base: it brings its own OS userland and
its own Python. This project's promise is **one** Debian 12 userland and **one**
Python 3.11 environment per image, and Debian's system `python3` is 3.11 while the
Node image's is not. Copying `/usr/local` gets the runtime without inheriting a
second distribution.

## What is not pinned

Be honest about the gaps; they are the reason the audit trail below exists.

- **apt packages are not hash-pinned.** `gcc`, `clang`, `cmake`, `mingw-w64`,
  `gdb`, `binwalk`, and the rest come from the Debian 12 archives at build time.
  Exact versions are whatever the archive served that day. Two builds of the same
  commit weeks apart can therefore differ in those packages. This is the one place
  where the build is not byte-reproducible, and no smoke assertion can detect it.
- **pip installs are exact versions over TLS, without `--hash=` values.** A pin
  names the version; pip does not compare a hash recorded in the requirements
  file. What catches a problem instead is the build gate's import and version
  assertions plus the recorded manifest.
- **`IMAGE-INSPECT.json` and the manifests describe what shipped, not what was
  intended.** They are the compensating control: read them when you need to
  certify an image.

If you need stronger guarantees than that, build all three images from one commit
in a single session, keep the bundles, and treat `SOURCE-COMMIT.txt` plus
`IMAGE-INSPECT.json` as the record of that build.

## Auditing what actually shipped

| Artifact | Where | Contains |
|---|---|---|
| `/opt/PYTHON-MANIFEST.txt` | in every image | `pip list --format=freeze` for the single `/opt/pyenv` environment |
| `/opt/yolo/EXTENSIONS-MANIFEST.txt` | in every image | `code-server --list-extensions --show-versions`; 19 declared extensions plus their dependency closure (21 entries) |
| `/opt/deepseek-harness/package.json` + `pnpm-lock.yaml` | in every image | the pinned `dsh` version and the 561-hash lock |
| `IMAGE-INSPECT.json` | in each offline bundle | full `docker image inspect` output for the saved tag |
| `SOURCE-COMMIT.txt` | in each offline bundle | the git commit (`$GITHUB_SHA` in CI) the bundle was built from |
| `SHA256SUMS` | in each offline bundle | sha256 of the image archive inside that bundle |
| `<bundle>.zip.sha256` | beside each bundle | sha256 of the ZIP itself |
| `VERSION`, `PINS.md` | in each offline bundle | the release version and the version table as of that build |

```bash
# From the image
docker run --rm yolo-agent:2.0.0 cat /opt/PYTHON-MANIFEST.txt
docker run --rm yolo-agent:2.0.0 cat /opt/yolo/EXTENSIONS-MANIFEST.txt
docker run --rm yolo-agent-reverse-engineering:2.0.0 sh -c \
  'python3 -c "import xdis, angr, numpy; print(numpy.__version__, xdis.__version__)"'

# From an unpacked offline bundle
cd yolo-agent-base-2.0.0-offline
sha256sum -c SHA256SUMS
cat SOURCE-COMMIT.txt
jq '.[0].Config.Labels' IMAGE-INSPECT.json
```

The `.zip.sha256` sidecar stores the bare filename, so verify it from the
directory that holds the ZIP: `sha256sum -c yolo-agent-base-2.0.0-offline.zip.sha256`.
Bundles that exceeded GitHub's 2 GiB asset limit ship as `.part-NN` files with a
`.parts.sha256` and `.REASSEMBLE.txt`; verify the parts first, reassemble, then
verify the ZIP. See [02-QUICKSTART.md](02-QUICKSTART.md).

## Packages pinned below their latest release

This project targets exactly one interpreter, Python 3.11, because that is
Debian 12's system Python (see [04-PYTHON.md](04-PYTHON.md)). Several packages have
since moved to requiring 3.12 or newer, so they are held at their last
3.11-compatible release on purpose — not because they are untested:

| Package | Pinned here | Latest release | Why it is held back |
|---|---|---|---|
| numpy | 2.4.6 | 2.5.3 | numpy 2.5 requires Python ≥ 3.12 |
| angr | 9.2.213 | 9.3.4 | angr 9.3 requires Python ≥ 3.12 |
| xdis | 6.3.0 | 6.3.0 | not behind latest — held at exactly 6.3.0 because `pyinstxtractor-ng` requires `xdis==6.3.0` |

A "why is this old?" question about any of these rows has the same answer: a newer
release would break the single-environment rule, and splitting the environment to
get it would cost more than the upgrade is worth.

### Deliberately not installed: uncompyle6

`uncompyle6` is **not** in the reverse image, and cannot be added to it:

- `pyinstxtractor-ng` requires `xdis==6.3.0` exactly.
- `decompyle3` requires `xdis<6.3`, and `uncompyle6` requires `xdis<6.2.0`.
- All three land on the same shared dependency in the same environment.

`pyinstxtractor-ng` is the non-negotiable one: without it a PyInstaller `.exe`
cannot be unpacked at all, which is the first step of the workflow the image
exists for. So `xdis==6.3.0` wins, and:

- **`decompyle3` is not installed.** `xdis<6.3` is genuinely unsatisfiable
  against `xdis==6.3.0`; pip fails the install with `ResolutionImpossible`
  rather than downgrading silently, which is how this was found.
- **`uncompyle6` is installed transitively via `pydumpck`**, which declares
  `uncompyle6>=3.9.0`. pip installed it without re-checking its own `xdis`
  ceiling, so `smoke-reverse.sh` runs its CLI at build time — that execution,
  not the resolver, is the evidence it works here. Being transitive it is
  best-effort: if a future `pydumpck` drops it, it must be pinned explicitly.
- **`pycdc` / `pycdas`**, built from source in the reverse image, handle arbitrary
  Python bytecode versions. That is the real fallback for bytecode the Python-side
  decompilers cannot read.

`docker/requirements-reverse.txt` carries the same explanation next to the pins,
and [06-REVERSE-ENGINEERING.md](06-REVERSE-ENGINEERING.md) covers the workflow.

## Bumping a pin safely

Do these in order. The first two steps are what keep a bump reviewable; the last
three are what keep it shippable.

1. **Determine the integrity story for the new artifact.** If upstream publishes a
   `SHA256SUMS` for that release, the mechanism stays (a) and the `ARG` becomes a
   fallback. If it does not, you are creating a new TOFU pin: download the
   artifact once, from the official release, over TLS, and record its
   `sha256sum`. Never take a hash from a third-party mirror, a blog, or a search
   result.
2. **Update every copy of the version together, in one commit:**
   - the `ARG` in each Dockerfile that carries it — the three Dockerfiles repeat
     the shared `ARG`s (`OPENCODE_VERSION`/`OPENCODE_SHA256`, `PI_VERSION`/
     `PI_SHA256`, `DSH_VERSION`, `CODE_SERVER_VERSION`/`CODE_SERVER_SHA256`,
     `TTYD_VERSION`), so a bump that touches only one file silently splits the
     images;
   - the matching `:-` default in `docker/install/*.sh` (`install-agents.sh`,
     `install-web-ide.sh`, `install-deepseek-harness.sh`), which is what the
     scripts use when run standalone;
   - the matching row in [../PINS.md](../PINS.md). The table is the register of
     what ships — a bump that leaves it behind is the failure mode this document
     exists to prevent.
3. **For `dsh`, regenerate the lock rather than editing versions:** put the new
   version in `docker/deepseek-harness/package.json`, then
   `corepack prepare pnpm@11.7.0 --activate && pnpm --dir docker/deepseek-harness install --lockfile-only`
   and confirm the lockfile's `specifier` equals the new `DSH_VERSION`. The build
   compares those two and refuses to proceed if they disagree.
4. **For a Python pin, prove the wheel exists before committing:**
   `pip download --only-binary=:all: --python-version 3.11 -d /tmp/x <pkg>==<ver>`,
   then update the row in [../PINS.md](../PINS.md) if the version moved.
5. **Rebuild through the test target, not the runtime target:**

   ```bash
   docker buildx bake base-test      # or cpp-test, reverse-test; no args = all three
   ```

   A pin change is exactly the case the smoke suite exists for: it asserts the
   installed version against the new `ARG`, so a bump that does not actually take
   effect fails here instead of on the offline host.
6. **Confirm the suite passed, then produce the shippable images and bundles:**

   ```bash
   docker buildx bake images
   ./scripts/package-offline.sh <version> base:<tag> cpp:<tag> reverse:<tag> -- dist
   ```

7. **Never edit a hash to make a build pass.** A `sha256sum -c` failure means the
   bytes you downloaded are not the bytes that were pinned. Re-download,
   re-verify the version and the source URL, and treat a changed release asset as
   an incident until proven otherwise — a replaced asset under an unchanged tag is
   precisely what the pins are there to catch.

## Trust boundary: the reverse-engineering toolchain

`pycdc`, `jadx`, `Ghidra`, and `radare2` parse **hostile, potentially malformed**
input. That is their function, and it makes them the most exposed components in the
repository: a parsing bug in any of them is a genuine memory-safety risk, and no
container setting changes that.

What contains it:

- they run as uid **10001**, unprivileged, with **all capabilities dropped**,
  `no-new-privileges`, and a **read-only root filesystem**;
- the runtime container has **no internet route**, so a successful exploit has no
  egress of its own;
- only `/workspace` (the mount you chose) and `/home/agent` (the volume) are
  writable, plus tmpfs at `/tmp`, `/run`, and `/dev/shm`;
- the toolchain seccomp profile allows `ptrace` for the debugger and denies every
  privileged syscall — see [10-SECURITY.md](10-SECURITY.md).

That is why the decompilation stack lives in its own image rather than in the base
one: you run it only when you need it, and a compromise there does not also hand
over your normal development container. Treat every file you did not create as
untrusted input.
