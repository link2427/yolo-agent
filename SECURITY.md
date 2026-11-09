# Security posture for YOLO-mode agents

The threat model: the agent is **trusted inside its own container** — it must run
arbitrary commands to do its job — but must **not** reach the host or other
containers. On the lab network it can reach SEC09 and Gitea, which it needs.
Containment is the goal, not sandboxing the agent from its own workspace.

Full detail is in [docs/10-SECURITY.md](docs/10-SECURITY.md). This file is the
short version.

## Hardening applied to every person's container

| Control | Setting (`compose.yaml`) |
|---|---|
| Unprivileged user | uid/gid `10001`; no root inside the container |
| Root filesystem | read-only; only `/workspace`, `/home/agent` and tmpfs mounts are writable |
| Capabilities | all dropped |
| Privilege escalation | `no-new-privileges:true` |
| Syscalls | seccomp denylist (`config/seccomp.json`) |
| setuid/setgid binaries | none — stripped at build time and checked by the smoke test |
| Docker socket | never mounted |
| Resources | memory, CPU and PID limits per service |
| Init | `tini` for signal handling and zombie reaping |

`config/seccomp.json` denies the privileged syscalls (`mount`, `bpf`,
`init_module`, `kexec_load`, ...) and allows `ptrace`, `process_vm_readv` and
`process_vm_writev` so that `gdb` and gcc LTO work in the cpp and full tiers.
The lab services in `compose.lab.yaml` use Docker's default seccomp profile.

## YOLO mode is the point

Every agent is configured to never ask permission: opencode and Kilo Code
(`permission: allow`), Claude Code (`bypassPermissions`), Qwen Code
(`approvalMode: yolo`), Codex (`approval_policy = never`), Goose (`GOOSE_MODE:
auto`), Crush (tools allowed), pi (no permission system).

This is safe *only* because of the container boundary, and it means the
workspace folder you hand the container is the real security boundary. An agent
asked to clean up will delete files, and there is no confirmation step.

## Secrets never enter an image

- No token is baked into an image or committed to this repository.
- The person's Gitea token comes from their `.env` (`GITEA_TOKEN`) or from
  `yolo login`, which stores it in `~/.yolo/secrets.env` (mode `600`) in the home
  volume. git uses it through `~/.git-credentials` (mode `600`).
- The bot's token is in the lab's `.env` (`BOT_GITEA_TOKEN`) only.
- `install.sh` writes each `.env` with mode `600`.
- The agents send a per-person key (`yolo-<person>`) to vLLM, so the monitor can
  attribute usage. It is an identifier, not a secret.

## The browser pages have no authentication

The start page (`:8000`), VS Code (`:8080`), Chat (`:4096`), Terminal (`:7681`)
and Files (`:8081`), and the lab's monitor (`:4000`) and bot (`:9000`), have no
login. This is deliberate: the lab is air-gapped. Anyone who can reach those
ports gets a shell in that person's container.

To keep a container to its own machine, set `YOLO_BIND=127.0.0.1` in its `.env`.

## Supply chain integrity

Every component is version-pinned and the build fails on a hash mismatch.
[PINS.md](PINS.md) records each pin. Python installs are
`--only-binary=:all:`. Every tier is smoke-tested at build time with no network,
so a pin that drifts fails the build rather than shipping.

## The reverse-engineering tools deserve separate thought

`pycdc`, `jadx`, Ghidra and radare2 (full tier) parse hostile input by design. A
parsing bug in any of them is a real risk that no container setting removes.
They run as uid 10001 with no capabilities and only `/workspace` and the home
volume writable — so a compromise gets the workspace and session state, not the
host. Use the core or cpp tier for people who do not need them.

Treat files you did not create as untrusted.

## What this does not protect against

- A malicious or careless agent with legitimate tool access.
- Exfiltration through the model endpoint, or by `curl` to another lab host.
- Host kernel exploits — container isolation is not a virtual machine.
- Anyone on the lab network opening another person's pages.

## Reporting

This is an internal air-gapped toolchain, not a product with a security team. If
you find a containment bug, open an issue describing the escape and the
configuration it needs.
