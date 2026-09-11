# Security posture for YOLO-mode agents

The threat model: the agent is **trusted inside its own container** — it must run
arbitrary commands to do its job — but must **not** reach the host, other
containers, or your LAN beyond the model endpoint. Containment is the goal, not
sandboxing the agent from its own workspace.

Full detail, including the seccomp profiles and their limits, is in
[docs/10-SECURITY.md](docs/10-SECURITY.md). This file is the short version.

## Hardening applied to every image

| Control | Setting |
|---|---|
| Unprivileged user | uid/gid `10001`, baked in; no root inside the container |
| Root filesystem | read-only (`--read-only`); only `/workspace`, `/home/agent`, and tmpfs are writable |
| Capabilities | all dropped (`--cap-drop ALL`) |
| Privilege escalation | `no-new-privileges:true` |
| Syscalls | seccomp denylist (`config/seccomp-base.json`) |
| setuid/setgid binaries | none — stripped from the whole image at build time |
| Docker socket | **never mounted** |
| Resources | memory, CPU, and PID limits; `nofile`/`nproc` ulimits |
| Init | `tini` for signal handling and zombie reaping |

The `yolo-agent-cpp` and `yolo-agent-reverse-engineering` images use
`config/seccomp-toolchain.json`, which differs from the base profile in exactly
three syscalls: `ptrace`, `process_vm_readv`, and `process_vm_writev` are
allowed so that `gdb` and gcc's LTO can work. Every privileged syscall (`mount`,
`bpf`, `init_module`, `kexec_load`, …) stays denied in both profiles.

## YOLO mode is the point

Every agent is configured to never ask permission:

| Agent | Setting |
|---|---|
| opencode | `"permission": "allow"` — every tool auto-approved |
| pi | `defaultProjectTrust: "always"`; pi has no permission system by design |
| DeepSeek Harness | runs against the local endpoint; the DeepSeek cloud provider is left empty |

This is safe *only* because of the container boundary, and it means the mount
you hand the container is the real security boundary. Point `/workspace` at a
scratch directory. An agent asked to clean up will delete files, and there is no
confirmation step to save you.

## Secrets never enter an image

- `VLLM_API_KEY` and Gitea credentials are passed at launch only.
- Gitea credentials live in `~/.git-credentials` (mode `600`) and SSH keys in
  `~/.ssh` (mode `600`), both inside the named `/home/agent` volume.
- Nothing secret is baked into an image, which is what makes an exported image
  archive safe to hand around.
- `umask 077` means files created inside the container are private by default.
- Do not set `DEEPSEEK_API_KEY` or `OPENAI_API_KEY`: they are unnecessary here
  and would put cloud models back into the agent pickers.

## The browser surfaces have no authentication

code-server (`:8080`), ttyd (`:7681`), and the DeepSeek Harness UI (`:3080`) all
bind `0.0.0.0` with no auth by default, because this build targets an air-gapped
internal network. Anyone who can reach those ports gets a shell in your
container.

Bind them to loopback unless you are certain about the network:

```bash
YOLO_BIND_ADDRESS=127.0.0.1 docker compose up -d
```

There is no built-in password. The container's hardening does not protect a port
you published.

## Supply chain integrity

Every component is version-pinned and the build fails on a hash mismatch.
Official upstream checksums are used where the project publishes them; the rest
are pinned from the first verified download, and [PINS.md](PINS.md) records
which is which. Python installs are `--only-binary=:all:`, so nothing compiles
from an unpinned source tree. Every image is smoke-tested at build time, so a
pin that drifts fails the build rather than shipping.

## The reverse-engineering image deserves separate thought

`pycdc`, `jadx`, `Ghidra`, and `radare2` parse hostile input by design. A
parsing bug in any of them is a real risk that no container setting removes.
They run as uid 10001 with no capabilities, no network route, and only
`/workspace` and the home volume writable — so a compromise gets the workspace
and session state, not the host. This is why that toolchain lives in its own
image: you run it only when you need it, and a compromise there does not also
hand over your normal development container.

Treat files you did not create as untrusted.

## What this does not protect against

- A malicious or careless agent with legitimate tool access.
- Exfiltration through the model endpoint, or by `curl` to another LAN host.
- Host kernel exploits — container isolation is not a virtual machine.
- Reachability from your internal network, which the model endpoint requires.
- The published browser ports, if you bind them to `0.0.0.0`.

## Reporting

This is a personal air-gapped toolchain, not a product with a security team. If
you find a containment bug, open an issue describing the escape and the
configuration it needs.
