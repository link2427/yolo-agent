# 10 — Security

## Threat model

The agents are **trusted inside their own container** — they must run arbitrary
commands to do their job — but must **not** reach the host or other containers. On the lab network they
reach SEC09 and Gitea, which they need. Containment is the goal, not sandboxing the
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

- Each person's `workspace/` folder holds only their work. `YOLO_WORKSPACE` in
  `.env` can point it elsewhere; never at a folder with irreplaceable data.
- Do not mount a folder containing credentials, personal documents, or
  irreplaceable data.
- Keep a backup that the container cannot reach. A read-only bind mount or a
  separate copy outside the mount is enough.
- Remember that an agent can `rm -rf /workspace/*` and that it will do so if
  asked to.

Git history inside the workspace is not a backup if the agent can also rewrite
it, or if the whole directory is removed.

## Container hardening

Every service in `compose.yaml` has the same posture:

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
| Resources | `mem_limit`, `cpus`, `pids_limit` | limits runaway builds and fork bombs |
| Entrypoint | `tini` | reaps zombies; correct signal handling |
| setuid binaries | none | the build strips the setuid/setgid bits from the whole image |

### The seccomp profile

`config/seccomp.json` is used by every service in `compose.yaml`, in every
tier. It denies the privileged syscalls (`mount`, `bpf`, `init_module`,
`kexec_load`, `settimeofday`, `keyctl` and others) and allows `ptrace`,
`process_vm_readv` and `process_vm_writev`.

Why those three are allowed: `gdb` cannot attach to a process without `ptrace`,
and gcc's link-time optimization uses `process_vm_readv`/`writev`. In 2.x the
base image denied them; in 3.0 there is one profile, because the tiers are one
image. A process can inspect other processes of the same user in the same
container, which anything running as that uid can already affect.

The lab services in `compose.lab.yaml` use Docker's default seccomp profile.

## Secrets

- No token is baked into an image or committed to the repository. That is what
  makes the release archive safe to hand around.
- A person's Gitea token comes from their `.env` (`GITEA_TOKEN`, mode 600 as
  written by `install.sh`) or from `yolo login`, which stores it in
  `~/.yolo/secrets.env` (mode 600) in the home volume. git reads it from
  `~/.git-credentials` (mode 600).
- The bot's token is only in the lab `.env` (`BOT_GITEA_TOKEN`).
- The fleet repo must never contain tokens: everyone with access to it can read
  it, and every container pulls it.
- The key agents send to vLLM (`yolo-<person>`) is an identifier for the
  monitor, not a secret.

## The browser pages

Start page `:8000`, VS Code `:8080`, Chat `:4096`, Terminal `:7681`, Files
`:8081`, and the lab monitor `:4000` and bot `:9000`, all listen on every
address with no login. **Anyone who can reach those ports has that container.**

That is intentional for an air-gapped lab. Mitigations if you need them:

1. `YOLO_BIND=127.0.0.1` in a person's `.env` keeps their pages to the machine
   they run on.
2. Restrict with the host firewall to specific source addresses.
3. Stop a person's services when not in use (`docker compose down`).

## Supply chain

- Every component is version-pinned; the build fails on a hash mismatch. Official
  upstream checksums are used where the project publishes them, and the
  distinction between "verified against upstream checksums" and "pinned on first
  verified download (TOFU)" is recorded in [../PINS.md](../PINS.md).
- Python installs use `--only-binary=:all:`, so nothing compiles from an
  unpinned source tree at build time.
- The Node base image is pinned by manifest digest, and only `/usr/local` is
  copied out of it.
- The build gate is a smoke suite per tier, run with no network: a drifted pin
  fails the build rather than shipping.

See [11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md) for the operator-facing version
of this.

### The reverse-engineering tools (full tier) are different

`pycdc`, `jadx`, `Ghidra`, and `radare2` parse **hostile, potentially
malformed** input by design — that is their job. A parsing bug in any of them is
a genuine memory-safety risk, and no container setting changes that.

What contains it: they run as uid 10001, with no capabilities, no network route,
and only `/workspace` and the home volume writable. A successful exploit gets
the attacker the workspace and the agent's session state — not the host, not
your lab network. This is why the decompilation tools are only in the `full` tier: give it only
to people who need it.

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
4. Give the bot its own Gitea account with only the access it needs.
5. Read [../SECURITY.md](../SECURITY.md) and [../PINS.md](../PINS.md) before
   changing pins or exposing ports.
6. Rebuild and re-export from source rather than pulling an image you cannot
   verify.
