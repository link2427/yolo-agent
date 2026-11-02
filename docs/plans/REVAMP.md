# Plan: yolo-agent 3.0 revamp

Status: **proposed, not built.** Written 2026-11-02 against `v2.0.0` (`060eab5`).

Working name 3.0 because it changes the container contract: one image instead of
three, T3 Code instead of code-server, and compose instead of launchers.

---

## 1. Constraints (confirmed by the operator)

| Constraint | Value | Consequence |
| --- | --- | --- |
| Network | Air gapped, no internet. LAN allowed by firewall rule. | No build on the target host. No package install without a mirror. |
| Transfer budget | **~4 GB per trip** onto the network | Drive this design. Not a disk limit. |
| Storage | 4 TB drive, WSL 2 / Docker, many separate images affordable | Fat image is fine. |
| Fleet | 3 containers now, 5 people eventually. Each machine eventually its own host. | One image, N compose projects. |
| Phones | Not used. | No T3 Connect, no relay, no mobile surface. |
| Client | Browsers on the LAN. | Zero-install client tier. |
| Host resources | One host now, 224 GB DDR5 | Room for 3-5 containers at sane limits. |
| File system | **Must use the WSL 2 filesystem, not the Windows 9p mount** | Named volumes only. |

The 9p constraint is the one that silently wrecks performance. `/mnt/c` is
drvfs/9p and is dramatically slower than ext4 inside the VHDX. See section 7.

---

## 2. Measured findings that drive the design

All numbers from the published `2.0.0` manifests on ghcr, layer by layer.

### 2.1 Three images share almost nothing

| Image | Compressed | Layers |
| --- | --- | --- |
| `yolo-agent` (base) | 828.2 MiB | — |
| `yolo-agent-cpp` | 1470.5 MiB | 26 |
| `yolo-agent-reverse-engineering` | 1719.2 MiB | 26 |

**cpp and reverse share 2 layers, 27 MiB.** Every base layer is rebuilt per
image, so the base is paid three times. The `buildx bake` targets do not share a
parent, which is why the sharing is near zero despite identical content.

Consequence: "keep it modular through separate images" costs ~3x the base, and
every *new* toolchain costs a full new bundle (~1.5 GB) rather than a delta.

### 2.2 A 100 MiB layer of duplicated binaries

`Dockerfile` runs `chown -R root:root /opt/opencode /opt/pi ...` **after**
copying those trees in. A recursive chown rewrites every file, so the whole tree
lands in a second layer.

Verified: `opt/opencode/opencode` is 184,825,984 bytes with sha256
`87bd160e053af86b5b409daabf71f8dc05bbc3a2a3a5f563f36011cdf706a999` in **both**
the COPY layer and the chown layer. 224 files duplicated.

- 100.5 MiB compressed, **285 MiB uncompressed**, in every image.
- Fix: `COPY --chown=root:root` and delete the `chown -R`.

### 2.3 Base image is not pullable anonymously

`ghcr.io/link2427/yolo-agent:2.0.0` returns 403 with an empty anonymous token,
while `-cpp` and `-reverse` return 200. The base package appears to be set
private. Unconfirmed via API — the available PAT lacks `read:packages`.
Needs a manual check in the package settings.

### 2.4 Transfer arithmetic

With the chown duplication removed, base is **748 MiB** compressed.

| Scenario | Transfer | On disk (~2.83x) |
| --- | --- | --- |
| Today, 3 self-contained bundles | 4017 MiB | ~11 GiB |
| **One image, all toolchains** | **2278 MiB** | ~6.3 GiB |
| base + cpp only | 1411 MiB | ~3.9 GiB |
| base + reverse only | 1615 MiB | ~4.5 GiB |

One image is **43% less to carry** than today's three, and fits the 4 GB budget
in a single trip. On disk it is 6.3 GiB for the whole fleet, because Docker
stores the layers once and shares them across every container (`read_only`
containers add no writable copy).

Replacing code-server also *reduces* size: code-server 222.2 MiB + extensions
64.7 MiB + ttyd 0.7 MiB out (~288 MiB), T3 Code CLI 117.4 MiB in.

---

## 3. Target architecture

### 3.1 One image, modular by build stage

```
Dockerfile
  base      agents (opencode, pi), Python 3.11, Node 22, T3 Code, core tools
  cpp       base + C/C++ toolchain + mingw-w64
  reverse   base + decompilers, JVM tools, binary analysis
```

Toolchains are accumulated in the single image rather than split. Profiles then
select *behaviour*, not image, which is what makes them cheap.

### 3.2 One compose file, two services

```yaml
services:
  agent:      # interactive shell, on demand
  t3:         # control surface on :3773, the default
```

### 3.3 Per-person isolation via compose projects

One service definition, N instances. The `-p` flag gives separate networks,
volumes and container names for free.

```bash
docker compose --env-file people/alice.env -p alice up -d
docker compose --env-file people/bob.env   -p bob   up -d
```

`people/<name>.env`:

```bash
T3_PORT=3773
PERSON_WORKSPACE=/srv/yolo/alice
VLLM_BASE_URL=http://192.168.1.101:8000/v1
VLLM_MODEL=qwen3.8-27b
GITEA_HOST=192.168.1.27:3000
GIT_NAME=YOLO Agent
GIT_EMAIL=yoloagent@gmail.com
```

Offboarding is `docker compose -p alice down -v`, which also destroys that
person's T3 state, and is the only per-person revocation the old design could
not offer (`auth: none`).

### 3.4 What gets deleted

| Removed | Lines removed |
| --- | --- |
| `compose.base.yaml`, `compose.cpp.yaml`, `compose.reverse.yaml` | 3 files |
| `bin/run.sh`, `run-server.sh` | 2 files |
| `bin/run.ps1`, `run-server.ps1` | 2 files |
| `Dockerfile.cpp`, `Dockerfile.reverse` | 2 files |
| code-server + 19 VS Code extensions | ~289 MiB |
| ttyd | 0.7 MiB |
| DeepSeek Harness (`dsh`) | 48 MiB |

Replaced by one `compose.yaml` and two `Dockerfile` stages.

---

## 4. T3 Code integration

`pingdotgg/t3code`, MIT, v0.1.6. Verified by running it in a sandbox: `t3
--version` works with **no Node installed** (161 MiB Node SEA binary),
`t3 serve` ran migrations and served HTTP 200.

### 4.1 Why it earns the slot

The decisive argument is not the UI. It is access control:

> `code-server` listens on `0.0.0.0:8080` with `auth: none`. Anyone who can
> reach those ports has the container. — `docs/10-SECURITY.md`

For five engineers on one LAN, that means every colleague can reach every
other colleague's IDE and terminal with no credential. T3 ships pairing tokens
and revocable sessions (`t3 auth session revoke`), which is a real access model
instead of relying on trust.

It also replaces three things with one: code-server (222 MiB), 19 extensions
(64.7 MiB), ttyd (0.7 MiB). Its terminal has server-side scrollback that
persists across devices, so agents and humans share the session.

### 4.2 Air-gap configuration

```bash
T3CODE_TELEMETRY_ENABLED=false
```

Plus a managed policy at `/etc/t3code/policy.json`:

```json
{
  "limits": {
    "clients": ["local-browser", "remote"],
    "providers": { "installedOnly": true, "allowedDrivers": ["opencode", "pi"] },
    "telemetry": false,
    "connect": false
  },
  "updates": { "mode": "off", "allowNightly": false }
}
```

**`remote` is required.** `local-browser` means "only browsers on this machine",
which would reject every cross-VM client. `remote` means "reachable from the
LAN", which is exactly the topology. This was initially specified wrong in
review; the policy would have rejected every client.

A policy that cannot be parsed or enforced makes the server refuse to start,
which is the fail-closed behaviour wanted here.

### 4.3 The three `t3.codes` hosts

The bundle references `app.t3.codes`, `relay.t3.codes`, `ingest.t3.codes`. On a
network with no internet these blackhole. Depending on the resolver they can
hang for seconds rather than fail fast. Blackhole them in the image:

```
RUN printf '0.0.0.0 ingest.t3.codes\n0.0.0.0 relay.t3.codes\n0.0.0.0 app.t3.codes\n' >> /etc/hosts
```

Belt and braces alongside the policy, and it does not depend on the policy being
correct.

### 4.4 OPEN: headless Chrome

T3 downloads a headless Chrome (~120 MB) at runtime on first browser tab or HTML
render, into the T3 home. `t3 browser setup` exists but is `sudo`+apt for
libraries; the Chrome binary itself has no documented pre-seed.

This is the one unresolved air-gap blocker. It works for chat and terminal, then
fails the first time an agent renders or browses. Must be tested in a real build
before any documentation promises browser or HTML preview. Options if it cannot
be seeded: disable browser/HTML features by policy, or bake the download at build
time and point T3 at it.

---

## 5. BLOCKER: T3 never runs `.bashrc`

Both config generators are invoked **only** from `~/.bashrc`:

```bash
# ~/.bashrc
[[ -n "${VLLM_BASE_URL:-}" ]] && ... && /opt/yolo/configure-agents.sh
[[ -n "${GITEA_HOST:-}" ]]            && /opt/yolo/configure-git.sh
```

T3 spawns `opencode` and `pi` as children of the T3 server: no login shell, no
bash, no `.bashrc`. Under T3:

- `configure-agents.sh` never runs, so opencode has no provider block and
  **T3 shows zero models**
- `configure-git.sh` never runs, so there is **no git identity and no Gitea
  credential**

The entire "launch and it just works" behaviour dies the moment T3 replaces
code-server. Fix: call both from the service entrypoint, and keep the `.bashrc`
hooks so an interactive shell also configures itself.

```bash
# t3 entrypoint
/opt/yolo/configure-agents.sh
/opt/yolo/configure-git.sh
exec t3 serve --host 0.0.0.0 --port 3773 --lan
```

Both scripts are already idempotent, so double invocation is safe. Note
`configure-git.sh` exits non-zero without a token, and `.bashrc` currently
swallows that with `|| true`; the entrypoint must decide deliberately whether a
missing token is fatal.

---

## 6. Harness compatibility with T3

| Provider | Usable offline with vLLM | Notes |
| --- | --- | --- |
| **opencode** | yes | needs >= 1.14.19; already YOLO-configured for vLLM |
| **pi** | yes | needs >= 0.80.5; `models.json` already points at vLLM |
| claudeAgent | conditional | needs Anthropic, or a Bedrock/gateway base URL |
| codex | conditional | ChatGPT login or `base_url` via `config.toml` |
| cursor, grok, antigravity, muse | no | SaaS auth |
| acpRegistry | no | registry lookup |
| `dsh` | no | not a T3 provider — **cut** |

Two viable harnesses, both already in the image and both already aimed at SEC09.
No new binaries needed for T3 support.

Pinning to vLLM uses pi's `--provider`/`--model` launch args (T3 rejects launch
args that change execution mode or select a session, but model selection is
allowed).

---

## 7. WSL 2 storage

| Path | Performance |
| --- | --- |
| `/mnt/c/...` (Windows) | **slow**, 9p/drvfs over the VM boundary |
| `\\wsl$\distro\...` | faster, still a boundary |
| **named Docker volume** | **native ext4 in the VHDX** |

Rule: **named volumes only, never a Windows bind mount.**

`/workspace` does not need to be a host folder, because Gitea is on the LAN.
Each person clones into the volume from inside the container:

```bash
docker compose exec t3 git clone http://192.168.1.27:3000/alice/project.git /workspace/project
```

That keeps 9p out of the hot path entirely, at the cost of "point it at a folder
on my desktop", which is the slow thing being escaped. Importing existing code
is `docker cp`, or push to Gitea first.

---

## 8. Resource limits

Current defaults are **8 GB RAM and 4 CPUs per container**:

```yaml
mem_limit: ${YOLO_MEM:-8g}
cpus: ${YOLO_CPUS:-4}
```

| Containers | At current defaults | At 4 GB / 2 CPU |
| --- | --- | --- |
| 3 | 24 GB / 12 cores | 12 GB / 6 cores |
| 5 | 40 GB / 20 cores | 20 GB / 10 cores |

The host has 224 GB DDR5, so both fit today. A coding agent mostly waits on the
model endpoint, so 4 GB / 2 CPU is the sane starting point, raised if builds
OOM. Note that OOM during a build presents as flaky agent behaviour, which is
easy to misdiagnose.

---

## 9. Open questions

1. **Headless Chrome** — section 4.4. Needs a real build to test.
2. **`dsh` removal** — agreed to cut. Confirm nothing depends on it.
3. **Gitea attribution** — see section 10.
4. **Proxy for packages** — see `PACKAGE-MIRROR.md`, not part of this revamp.
5. Whether `t3` or `agent` is the default profile.
6. Whether the base image private-visibility bug (2.3) is fixed before or after.
7. **Image input** — see `AGENT-VERSIONS.md` section 7. Root cause found: pi
   defaults `input` to `["text"]` and `configure-agents.sh` never sets it, so
   images never reach the model. Also verify T3 passes attachments through, and
   check `--limit-mm-per-prompt` on SEC09.

---

## 10. Git identity with one shared credential

Requested defaults:

```
GIT_NAME  = YOLO Agent
GIT_EMAIL = yoloagent@gmail.com
```

The intent is that YOLO Agent co-authors and the container's user is the author.
That needs two distinct things, and one credential cannot provide both:

- **Author** is set per commit by `user.name`/`user.email`. Distinct per person
  if each has their own env file.
- **Co-author** is a commit-message trailer (`Co-authored-by: YOLO Agent
  <yoloagent@gmail.com>`), conventionally added by the committer or the agent,
  not by config.
- **Attribution in Gitea** comes from the credential, not from gitconfig. One
  shared token means every push is recorded as the token's user.

So with a single shared token:

| Requirement | Result |
| --- | --- |
| Per-person author | works via `GIT_NAME`/`GIT_EMAIL` per env file |
| YOLO Agent co-authors | works if the trailer is added |
| Per-person attribution in Gitea | **does not work** — all pushes are one user |

Options: (a) accept it, since "it doesn't matter if they just co-author";
(b) one Gitea user and token per person, which `GITEA_USER` already supports as
a single knob. Decide at burn time; the token is not in the repo.

Also: the token is passed as a container environment variable and is therefore
visible in `docker inspect`. This is not a regression, since the current design
already stores it in `.git-credentials` in the volume, but `people/*.env` must be
`chmod 600` and must never be committed.

---

## 11. Acceptance criteria

1. One `docker load` of a single archive (<= 4 GB) serves the whole fleet.
2. `docker compose -p alice up -d` yields a working T3 UI on `http://<host>:<port>`.
3. A browser with no client software connects and pairs.
4. `opencode` and `pi` both appear in T3 with models from SEC09.
5. Git pushes to Gitea work with no manual configuration step.
6. `pip install` / `npm install` state survives container restart (named volume).
7. No container writes to a 9p path.
8. Every image keeps passing the existing smoke suite, which must be extended to
   cover the T3 path (see `AGENT-VERSIONS.md` section 5).
9. `dsh` is gone from the image and from `PINS.md`.
