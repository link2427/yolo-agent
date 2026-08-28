# 08 — Security

The threat model: agents are **trusted inside their own workspace** (they must
run arbitrary commands) but must **not** reach the host, other containers, or
persist anything in the image. Containment is the goal. This does **not**
protect the workspace itself, and a kernel/containerd 0-day is always the
residual risk — keep the destination engine patched.

## Layer A — host / runtime (destination machine; the real boundary)

These are applied by `bin/run.sh` / `bin/run-server.sh` and cannot be baked
in:

1. **Never** give the container the Docker socket, host paths (except the
   `/workspace` bind), `--privileged`, or host PID/IPC/network namespaces.
   The Docker socket is *the* escape — an agent with it can start a privileged
   container.
2. **User namespaces / rootless**:
   - Linux Docker Engine: run **rootless Docker** or enable `userns-remap`
     so container root maps to an unprivileged host user.
   - Docker Desktop (macOS/Windows): the engine already runs in an isolated
     Linux VM as a non-root process on your OS — that VM is the boundary;
     keep the engine updated and never mount the Docker socket.
3. `--cap-drop ALL`, `--security-opt no-new-privileges`, strict seccomp
   (`seccomp-yolo.json`), non-root user (uid 10001, baked).
4. Resource limits: `--memory` (8g), `--cpus` (4), `--pids-limit` (512
   interactive / 2048 server — kills fork bombs), `--ulimit` nofile/nproc.
5. **Read-only rootfs** with writable tmpfs/volumes only for `/tmp`, `/run`,
   `/dev/shm`, `/workspace`, `/home/agent`.
6. **Egress-only networking**: outbound HTTPS to the model server on the LAN;
   nothing inbound (except the explicit web-IDE ports in server mode).
7. **Secrets at runtime only** — the tar travels on a disc, so no API keys or
   tokens may be baked in. `yolo.env` is passed at launch only.

## Layer B — baked into the image

- Non-root `agent` user (uid 10001); **no sudo**, **no setuid/setgid
  binaries** (stripped in the build); read-only rootfs default.
- `VOLUME`s (`/workspace`, `/home/agent`, `/tmp`) stay writable even if the
  operator forgets the tmpfs/bind flags.
- Offline/telemetry defaults for pi (`PI_OFFLINE`, `PI_SKIP_VERSION_CHECK`,
  `PI_TELEMETRY`) and prime-agent (`PRIME_AGENT_TELEMETRY=0`); umask 077;
  per-agent config dirs `chmod 700`.
- YOLO permission configs (opencode `allow`, goose `auto`, aider
  `yes-always`) are safe **only because** the container boundary is the real
  sandbox — never run these configs with a permissive runtime.

## Seccomp profile

Default-allow with a deny-list of container-breakout / host-tampering
syscalls: `mount`, `umount2`, `pivot_root`, `chroot`, `ptrace`,
`process_vm_readv/writev`, `kexec_load`, `kexec_file_load`,
`open_by_handle_at`, `name_to_handle_at`, `keyctl`, `add_key`, `request_key`,
`bpf`, `perf_event_open`, `reboot`, `swapon`, `swapoff`, `settimeofday`,
`clock_settime`, module syscalls, `acct`, `quotactl`, `fanotify_init`,
`vhangup`, `sethostname`, `setdomainname`, `iopl`, `ioperm`,
`lookup_dcookie`, `nfsservctl`. Network syscalls stay allowed (agents must
reach the model server).

## prime-agent kernel — important caveat

Its persistent IPython kernel executes model-generated Python with the
agent's user permissions. That's user-space process isolation for
lifecycle/recovery — **not** a security sandbox. The container boundary
contains it; nothing else does.

## Browser exposure tradeoff (server mode)

`bin/run-server.sh` exposes code-server (:8080) and ttyd (:7681) with
**no application-level authentication**. Host publishing defaults to
`127.0.0.1`; anyone who can reach ports deliberately exposed with
`YOLO_BIND_ADDRESS=0.0.0.0` gets a VS Code instance that can run commands
**as the agent user**. On shared or internet-reachable networks, keep the
localhost binding and use an authenticated reverse proxy or SSH tunnel.

## Git credentials

Stored in the home volume only: `~/.git-credentials` (token, mode 600) or
`~/.ssh/` (keypair, mode 600). Never in the image. Scope the Gitea agent user
(see 06) so a compromised agent can push but not delete repos.

## Skills

Third-party instructions executed with full workspace access — vet before
relying on them. They live in read-only `/opt/skills` (symlinked), so a
compromised agent can't plant a malicious skill that survives a restart.

## Verification after load

```bash
docker run --rm --read-only --tmpfs /tmp --user 10001:10001 --entrypoint sh yolo-agent:1.0.0 -c \
  'id; command -v sudo || echo "no sudo"; find / -xdev -perm /6000 2>/dev/null | wc -l; \
   ls ~/.agents/skills | wc -l; jq -r .permission ~/.config/opencode/opencode.json'
# expect: uid=10001(agent) ... / no sudo / 0 / 924 / allow
```
