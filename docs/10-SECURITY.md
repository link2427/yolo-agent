# 10 — Security

## Threat model

The agents are **trusted inside their own container** — they must run arbitrary
commands to do their job — but must **not** reach the host, other containers, or
the LAN beyond the model endpoint. Containment is the goal, not sandboxing the
agent from its own workspace.

This is a deliberate trade: yolo-agent runs with no permission prompts, which is
what makes it useful for unattended work. Everything below exists to make sure
that "no prompts" does not also mean "no boundary".

## The boundary that actually matters: `/workspace`

The container is given exactly one host folder. Whatever is mounted there is
fully readable, writable, and deletable by the agent. That mount is the real
security boundary of this system — the container hardening protects the *host*,
not the mounted folder.

Therefore:

- Point `YOLO_WORKSPACE` at a scratch or disposable directory.
- Do not mount a folder containing credentials, personal documents, or
  irreplaceable data.
- Keep a backup that the container cannot reach. A read-only bind mount or a
  separate copy outside the mount is enough.
- Remember that an agent can `rm -rf /workspace/*` and that it will do so if
  asked to.

Git history inside the workspace is not a backup if the agent can also rewrite
it, or if the whole directory is removed.

## Container hardening

Every image's launcher applies the same posture (see `compose*.yaml` and
`bin/run*.sh|ps1`):

| Control | Setting | Effect |
|---|---|---|
| User | `--user 10001:10001` | unprivileged uid; no root inside |
| Root filesystem | `--read-only` | `/`, `/usr`, `/opt` cannot be modified at runtime |
| Writable paths | `/workspace`, `/home/agent`, `/tmp`, `/run`, `/dev/shm` | only these; `/tmp` and `/run` are tmpfs |
| Capabilities | `--cap-drop ALL` | no `CAP_SYS_ADMIN`, `CAP_NET_RAW`, etc. |
| Privilege escalation | `no-new-privileges:true` | setuid binaries cannot gain privilege |
| Syscalls | seccomp denylist | see below |
| Docker socket | **not mounted** | the container cannot control Docker or the host |
| Namespaces | default (no `--privileged`, no host PID/NET) | isolated from host processes and interfaces |
| Resources | `mem_limit`, `cpus`, `pids_limit`, `ulimit` | limits runaway builds and fork bombs |
| Entrypoint | `tini` | reaps zombies; correct signal handling |
| setuid binaries | none | the build strips the setuid/setgid bits from the whole image |

### The seccomp profiles

There are two, and the difference between them is small and deliberate:

**`config/seccomp-base.json`** — used by `yolo-agent`. Denies 35 syscalls,
including `ptrace`, `process_vm_readv`, `process_vm_writev`, `mount`, `bpf`,
`init_module`, `kexec_load`, `settimeofday`, `keyctl`, and friends.

**`config/seccomp-toolchain.json`** — used by `yolo-agent-cpp` and
`yolo-agent-reverse-engineering`. Identical **except** that `ptrace`,
`process_vm_readv`, and `process_vm_writev` are *not* denied.

Why the exception exists: `gdb` cannot attach to a process without `ptrace`, and
gcc's link-time optimization uses `process_vm_readv`/`writev` to pass data
between compiler processes. Denying them makes the C++ container unable to debug
and its builds flaky. Every privileged syscall stays denied in both profiles —
the exception is narrow and specific.

Consequence to be aware of: in the cpp and reverse images, a process inside the
container can inspect other processes inside the same container. That is already
true of anything running as the same uid, so it does not widen the boundary —
but it does mean the toolchain images are slightly less restrictive internally
than the base image. If you do not need a debugger, use the base image.

Verify the difference yourself:

```bash
python3 -c "
import json
b=json.load(open('config/seccomp-base.json'));t=json.load(open('config/seccomp-toolchain.json'))
nb={n for s in b['syscalls'] for n in s['names']};nt={n for s in t['syscalls'] for n in s['names']}
print('allowed only in toolchain:', sorted(nb-nt))"
```

## Secrets

- `VLLM_API_KEY` and Gitea credentials are supplied **only** through the env
  file and the runtime environment. Nothing secret is baked into an image.
- Gitea credentials are written to `/home/agent/.git-credentials` with mode
  `600`; SSH keys to `/home/agent/.ssh` with mode `600`. Both live in the named
  home volume, never in the repository and never in the image archive.
- **This is what makes an exported image archive safe to hand around.** Anyone
  who `docker load`s the archive gets the tooling, not your tokens.
- `umask 077` is set in the image profile, so files created inside the container
  are private by default.
- Do not set `DEEPSEEK_API_KEY` or `OPENAI_API_KEY`: they are unnecessary here
  (the endpoint is local) and would put cloud models back into the agent
  pickers.

The offline bundles deliberately ship `config/*.env.example`, never a populated
`config/<flavor>.env`.

## The browser surfaces

code-server listens on `0.0.0.0:8080` with `auth: none`. ttyd gives a shell on
`0.0.0.0:7681`. DeepSeek Harness is relayed to `0.0.0.0:3080`. **Anyone who can
reach those ports has your container.**

That is intentional for an air-gapped LAN where the alternative is no browser
access at all, but it is the single most likely way this setup gets compromised
on a shared network. Mitigations, in order of preference:

1. Bind to host loopback and tunnel:
   ```bash
   YOLO_BIND_ADDRESS=127.0.0.1 docker compose up -d
   ssh -L 8080:127.0.0.1:8080 -L 7681:127.0.0.1:7681 user@yolo-host
   ```
2. Restrict with the host firewall to specific source addresses.
3. Run the browser surfaces only when you need them
   (`docker compose up -d` / `docker compose down`).

There is no built-in authentication. The container's own security controls do
not protect a port you published to the LAN.

## Supply chain

- Every component is version-pinned; the build fails on a hash mismatch. Official
  upstream checksums are used where the project publishes them, and the
  distinction between "verified against upstream checksums" and "pinned on first
  verified download (TOFU)" is recorded in [../PINS.md](../PINS.md).
- Python installs use `--only-binary=:all:`, so nothing compiles from an
  unpinned source tree at build time.
- The Node base image is pinned by manifest digest, and only `/usr/local` is
  copied out of it.
- The build gate is a per-image smoke suite: a drifted pin fails the build
  rather than shipping.

See [11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md) for the operator-facing version
of this.

### The reverse-engineering image is different

`pycdc`, `jadx`, `Ghidra`, and `radare2` parse **hostile, potentially
malformed** input by design — that is their job. A parsing bug in any of them is
a genuine memory-safety risk, and no container setting changes that.

What contains it: they run as uid 10001, with no capabilities, no network route,
and only `/workspace` and the home volume writable. A successful exploit gets
the attacker the workspace and the agent's session state — not the host, not
your LAN. This is why the decompilation toolchain lives in its own image instead
of being folded into the base: you only run it when you actually need it, and a
compromise there does not also hand over your normal development container.

Treat files you did not create as untrusted.

## What this does *not* protect against

Be honest about the limits:

- **A malicious agent with legitimate tool access.** An agent told to "clean up
  the workspace" will delete files. YOLO mode has no confirmation step.
- **Data exfiltration via the model endpoint.** The agent can send anything it
  can read to whatever endpoint `VLLM_BASE_URL` points at. Keep that endpoint on
  your own network, and remember the agent can also `curl` other LAN hosts.
- **Host kernel vulnerabilities.** Container isolation is strong but is not a
  virtual machine. A kernel exploit escapes it.
- **Anything reachable from the LAN.** The container has network access to your
  internal network — the model endpoint requires it. It is air-gapped from the
  *internet*, not from your other machines.
- **The published browser ports.** See above.

## Recommended operating practice

1. Mount a scratch directory, not your real work.
2. Keep secrets out of `/workspace`.
3. Bind browser ports to loopback unless you are certain of the network.
4. Use a dedicated Gitea identity with a narrowly scoped token for the agent,
   not your personal account.
5. Read [../SECURITY.md](../SECURITY.md) and [../PINS.md](../PINS.md) before
   changing pins or exposing ports.
6. Rebuild and re-export from source rather than pulling an image you cannot
   verify.
