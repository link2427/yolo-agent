# Plan: offline package mirror (pip / npm / shadcn)

Status: **proposed, not built.** Nothing in this document ships in 2.x. It exists
so the design is not re-derived later, and so the three blockers below are not
discovered for the first time on the air-gapped host.

Goal: agents inside the air gap can `pip install` and `npm install` real
packages, and can scaffold shadcn/Tailwind UIs, without internet. The same
mirror serves the Windows and macOS machines that humans use.

---

## 1. Blockers that must be solved first

These are properties of the current image, not of the mirror. A working mirror
does not fix any of them.

### 1.1 `pip install` cannot work at all

`compose.yaml` sets `read_only: true`, so `/opt/pyenv` is read-only. `pip
install --user` also fails, because pip refuses `--user` inside a virtual
environment and `/opt/pyenv` is one:

```
ERROR: Can not perform a '--user' install in a virtual environment.
```

**Resolution (chosen): one global interpreter, writable prefix.**

Drop `read_only: true` and give pip a writable prefix on a persistent volume:

```bash
# build time
python3 -m pip install --prefix=/opt/pylocal <baseline packages>

# runtime env
PYTHONPATH=/opt/pylocal/lib/python3.11/site-packages
PATH=/opt/pylocal/bin:$PATH
```

`/opt/pylocal` is a named volume. Packages installed by an agent are then global
to that container and survive restarts. This matches how a coding agent is
actually used: install once, available in every project.

Trade-offs accepted with this choice:

- Image immutability is lost. Anything written outside the volumes lands in the
  container's writable layer. It dies with the container, and the shipped
  `docker export` tar is built from the image, not a running container, so the
  bundle stays clean.
- Two containers sharing one `/opt/pylocal` volume can conflict on versions.
  Acceptable here; it is the same trade the current `$HOME` volume already makes.

Rejected alternative: per-project venvs with `--system-site-packages`. It works,
but isolates packages per project, which is the opposite of what an agent wants,
and it requires the agent to remember to activate a venv.

### 1.2 shadcn does not come from npm

The `shadcn` npm package (v4.23.0) is only the CLI. Components are fetched as
JSON/TSX from `https://ui.shadcn.com/r/index.json`. A complete npm mirror still
leaves `shadcn add button` failing offline.

Verified against the CLI source: it hardcodes `https://ui.shadcn.com/r` and reads
only `SHADCN_TEMPLATE_DIR`, `SHADCN_GITHUB_URL`, and `NODE_ENV`. **There is no
registry environment variable and no global config file.** The only supported
override is per project, via `components.json`:

```json
{
  "registries": {
    "@local": { "url": "http://<mirror>/shadcn/{name}" }
  }
}
```

Options, in order of preference:

1. **Per-project `registries` (recommended).** The agent writes it once when
   scaffolding a project. Explicit, supported, survives CLI updates.
2. **Hosts-file redirect.** Add `0.0.0.0 ui.shadcn.com` plus an endpoint
   answering as that host. Truly transparent for every project, but it is a
   permanent kludge and needs a certificate nobody will maintain.
3. **Wrapper shim** on `PATH` that injects the registry. Fragile; depends on CLI
   internals. Not recommended.

### 1.3 npm needs a registry mirror, not a directory of tarballs

`registry.npmjs.org/-/all` refuses bulk listing (returns 61 bytes), so a mirror
cannot be built by enumerating the registry. It must be produced by a
pull-through proxy that fills itself, or seeded from a published snapshot.

---

## 2. Architecture: run a proxy, do not stuff a volume

A volume full of tarballs is not an installable index; its metadata would have
to be hand-maintained. Run a real proxy that answers as a registry.

```
INTERNET HOST (build / burn time)
  Nexus or Verdaccio or devpi
    proxy repositories -> pypi.org, registry.npmjs.org, ui.shadcn.com
         |
         |  burn: export blob store + config
         v
  ==================== air gap ====================
         |
AIR-GAP HOST
  same container, cache volume mounted, serving the LAN
         |
   +-----+------+---------+
   |            |         |
 alice        bob      carol        dev containers
   +  the Windows / macOS machines that humans use
```

`packages` runs as its own compose project, with a fixed name so the URL is
stable:

```bash
docker compose -p packages up -d
```

Per-person projects (`-p alice`, `-p bob`) then point at it. People stay
isolated from each other's workspaces but share one package cache, which is the
point.

| | Proxy | Volume of tarballs |
| --- | --- | --- |
| pip/npm see a real index | yes | no |
| cache shared by N containers | yes | no |
| add packages later without a re-burn | copy blobs | re-burn |
| metadata | generated | hand-maintained |

The sharing row matters more than it looks. With per-container `~/.cache/pip`
and `~/.npm`, a package fetched for one person benefits nobody else; five
containers fetch five copies. A LAN proxy serves all of them.

---

## 3. Sizing (measured)

Wheel sizes from the PyPI JSON API, current releases, cp311.

| Metric | Value |
| --- | --- |
| median wheel | 4.6 MiB |
| mean wheel | 44.4 MiB (torch 461, tensorflow 269 dominate) |
| 90th percentile | 11.2 MiB |

| Python 3.11 mirror | Linux only | + Windows wheels |
| --- | --- | --- |
| ~300 packages | ~1.3 GiB | ~1.7 GiB |
| ~800 packages | ~3.6 GiB | ~5 GiB |
| ~2000 packages | ~9 GiB | ~12 GiB |

Windows wheels add roughly 30% on the same package set. Torch shows the
asymmetry: 514 MiB Linux against 120 MiB Windows. Windows wheels matter because
the human-facing machines need them, even though nothing inside the container
does.

| npm mirror | Size |
| --- | --- |
| curated, latest-only | ~10-20 GB |
| all versions (full) | ~40-60 GB |

**Python is cheap; npm is the bulk.** A useful dual-platform Python mirror is
about 5 GB. Hoarding 500 GB of PyPI would be roughly 40x oversized, and mostly
abandoned versions nobody installs.

Practical total: **~20 GB**, which fits the bulk HDD in one burn and does not
need 4 GB chunking.

### 3.1 Seeding command

Cap by dependency-closure size, not by top-level package count; transitive
dependencies dominate.

```bash
pip download \
  --dest /srv/mirror/pypi \
  --only-binary=:all: \
  --python-version 3.11 \
  --implementation cp \
  --abi cp311 \
  --platform manylinux2014_x86_64 \
  --platform win_amd64 \
  -r seed-requirements.txt
```

---

## 4. Making it the default, automatically

| Tool | Mechanism | Scope |
| --- | --- | --- |
| pip | `/etc/pip.conf` (`index-url`, `trusted-host`) or `PIP_INDEX_URL` | machine-wide |
| npm | `/etc/npmrc` (`registry=`) or `npm config set registry --location=global` | machine-wide |
| shadcn | `components.json` -> `registries` | **per project only** |

```ini
# /etc/pip.conf
[global]
index-url = http://<mirror>:8081/repository/pypi-proxy/simple
trusted-host = <mirror>
```

```ini
# /etc/npmrc
registry=http://<mirror>:8081/repository/npm-proxy/
```

Both files are baked into the agent image. Outside the container, the same two
settings apply per machine.

**No network routing change is required.** The mirror is an ordinary HTTP
service on the LAN. If a machine can already reach Gitea and the vLLM endpoint,
it can reach a mirror on the same subnet. IT involvement is only needed if the
mirror is placed on a different network segment.

---

## 5. Open questions

- Which proxy: Nexus (one service for pip + npm + shadcn, heavier) or Verdaccio
  plus devpi (lighter, two services). Not decided.
- Whether the mirror should also serve `apt` for adjacent tooling. Out of scope
  for now.
- Whether the air-gap host needs the mirror to be HA. Single host today.
- shadcn option 1 versus option 2 from section 1.2.

## 6. Acceptance criteria

1. `pip install <pkg>` succeeds in a fresh container with no internet.
2. `pip install <pkg> --platform win_amd64` resolves from the mirror.
3. `npm install` succeeds, including a package with transitive native deps.
4. `npx shadcn@latest add button` succeeds, or fails with a documented,
   actionable error naming the local registry.
5. Installing a package in one container does not require a second container to
   re-download it.
6. Adding a new package to the mirror does not require rebuilding the agent
   image.
