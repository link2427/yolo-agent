# Security posture for YOLO-mode agents

The threat model: the agent is **trusted inside its own workspace** (it must
run arbitrary commands to do its job) but must **not** reach the host, other
containers, or persist anything in the image. Containment is the goal —
this does **not** protect the workspace itself, and a kernel/containerd
0-day is always the residual risk. Keep the destination engine patched.

**YOLO-mode note:** agents never ask permission (opencode `"permission":
"allow"`, goose `GOOSE_MODE: auto`, aider `yes-always: true`, pi and
prime-agent have no permission-prompt system by design). That is safe *only
because* the container boundary below is the real sandbox — never run these
configs with a permissive runtime.

## Layer A — host / Docker runtime (destination machine)

These cannot be baked into the image; they are the actual security boundary.

1. **Never** give the container the Docker socket, host paths (except the
   `/workspace` bind), `--privileged`, or host PID/IPC/network namespaces.
   The Docker socket is *the* escape: an agent with it can start a privileged
   container and own the host.
2. **User namespaces / rootless**:
   - **Linux Docker Engine**: run **rootless Docker**, or enable
     `userns-remap`, so container root maps to an unprivileged host user.
   - **Docker Desktop (macOS/Windows)**: the engine already runs inside an
     isolated Linux VM as a non-root process on your OS — that VM *is* the
     boundary. Rootless adds little there; keep the engine updated and
     **never mount the Docker socket**.
3. `--cap-drop ALL`, `--security-opt no-new-privileges`, strict seccomp
   (ship: `seccomp-yolo.json`), non-root user (uid 10001, baked in).
4. Resource limits (in `bin/run.sh`): `--memory`, `--cpus`,
   `--pids-limit 512`, `--ulimit` nofile/nproc.
5. **Read-only rootfs** with writable tmpfs/volumes only for `/tmp`, `/run`,
   `/dev/shm`, `/workspace`, `/home/agent`. The skills library lives in
   `/opt/skills` — root-owned, read-only, tamper-evident.
6. **Egress-only networking**: the container needs outbound HTTPS to the
   model server on your LAN — nothing inbound. Default bridge reaches the
   LAN; for strict egress-only, put it on a dedicated network and firewall
   it (iptables). Docker has no one-flag "egress only".
7. **Secrets at runtime only** — the image tar travels on a disc, so no API
   keys or tokens may ever be baked in. `yolo.env` is passed at launch only.

## Layer B — baked into the image

- Non-root `agent` user (uid 10001); **no sudo**, **no setuid/setgid
  binaries** (stripped in the build); read-only rootfs is the runtime default.
- Declared `VOLUME`s (`/workspace`, `/home/agent`, `/tmp`) keep those paths
  writable even if the operator forgets tmpfs/bind flags.
- Offline/telemetry defaults for pi (`PI_OFFLINE`, `PI_SKIP_VERSION_CHECK`,
  `PI_TELEMETRY`); umask 077; per-agent config dirs `chmod 700`.
- Agent versions + skill repos pinned with sha256 verification; builds fail
  on mismatch ([PINS.md](PINS.md)). prime-agent's kernel runtime is
  bootstrapped during the build and verified (uv + Python 3.11 +
  `prime-agent-runtime`) — no first-run downloads.
- prime-agent telemetry disabled (`telemetry.enabled: false` baked + env).
- **prime-agent kernel caveat:** its persistent Python kernel executes
  model-generated Python with the agent's user permissions. It lives in
  `~/.prime/agent/kernel-venv` (inside the volume-populated home) — it is
  user-space process isolation for lifecycle/recovery, **not** a security
  sandbox. The container boundary is what contains it; skills and prompts
  are third-party content — vet before relying on them.
- YOLO permission configs are baked *in addition to* the runtime lockdown —
  if the destination host ever runs the container without the Layer A flags,
  the agent is still a non-root user with dropped caps and no setuid tools.

## Skills supply chain

- Only repos with permissive licenses ship (MIT / Apache-2.0).
  Excluded on purpose: `hesreallyhim/awesome-claude-code` (CC BY-NC-ND),
  `vercel-labs/agent-skills` (no license), and Anthropic's `docx/pdf/pptx/
  xlsx` skills (source-available, not open source — pruned at install).
- Every repo is pinned to an exact commit and its codeload tarball is
  sha256-verified during the build.
- The farm is a set of symlinks into the read-only `/opt/skills` tree — **30
  curated coding skills are linked by default** (tiny session-start context);
  the other ~890 are unloaded in the image and available via
  `skill-use.sh` / the library zip. Agents can read skills but never modify
  them, and a compromised agent cannot plant a malicious skill that survives
  a container restart (rootfs is read-only; `/home/agent` skills are symlinks
  to `/opt/skills`).
- ~1000 skills loaded on demand: opencode/pi load full SKILL.md only when
  the skill matches; goose injects names+descriptions at session start.

## Verification after `docker load`

```bash
docker run --rm --read-only --tmpfs /tmp --user 10001:10001 --entrypoint sh yolo-agent:1.2.1 -c \
  'id; command -v sudo || echo "no sudo"; find / -xdev -perm /6000 2>/dev/null | wc -l; \
   ls ~/.agents/skills | wc -l; jq -r .permission ~/.config/opencode/opencode.json'
# expect: uid=10001(agent) ... / no sudo / 0 / >400 / allow
```

The image's `--target test` stage already runs these checks at build time.

## Browser access (server mode) — deliberate exposure tradeoff

`bin/run-server.sh` (or `docker compose up -d`) exposes **code-server
(:8080)**, **ttyd (:7681)**, and **OpenHands (:3000)** with no
application-level authentication. This is deliberate: the build targets an
air-gapped internal network, so host publishing defaults to `0.0.0.0`. A
web UI that can execute commands **as the agent user** is a
remote-code-execution surface, so keep these ports off any internet-facing
host. The container lockdown (non-root, cap-drop, seccomp, read-only
rootfs) still applies to everything the web UI can do.

Everything the browser needs is **baked at build time** — extensions are
pre-installed from Open VSX (the locked runtime has no open-vsx.org egress),
and code-server's update check is disabled, so the server never phones home.
Installed extension versions: `/opt/yolo/EXTENSIONS-MANIFEST.txt`.

The DeepSeek Harness UI (:3080) and the OpenHands UI (:3000) are equally
sensitive because they can run agent tools against the mounted workspace.
They default to the internal network bind, like the other browsers. The
container-side DeepSeek relay exists only to bridge upstream Harness's
loopback socket to Docker publishing; it is not authentication. Never
expose any of these to an untrusted network.

## Git credentials

`configure-git.sh` writes auth into the **volume**, not the image: token mode
stores `~/.git-credentials` (mode 600; plaintext token over air-gapped HTTP is
the user's call — it never touches the disc tar). SSH mode keeps a
passphrase-less ed25519 keypair in `~/.ssh` (mode 600). Scope the Gitea agent
user (org team Write on chosen repos, token limited to `write:repository`) so
a compromised agent can push but not delete repos or touch other projects —
Gitea repo permissions are read/write/admin, so that team scoping is the
closest practical guardrail.

## Residual risks (honest list)

- A kernel/containerd/Docker-engine 0-day can still escape the sandbox; keep
  the host patched and don't run this on multi-tenant shared hosts.
- The agent is trusted with everything inside `/workspace` and `/home/agent`.
- The model server on your LAN receives everything the agent reads — treat
  that network path as trusted.
- Skills are third-party content: even loved repos can contain instructions
  that are subtly wrong or unsafe. They load on demand and run with the
  agent's full workspace access — vet a skill before relying on it.
