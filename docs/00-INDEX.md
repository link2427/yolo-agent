# yolo-agent 2.x documentation

Three containers, one repository. Each image is independently buildable and
independently shippable to an air-gapped host.

| Document | Purpose |
| --- | --- |
| [01-OVERVIEW.md](01-OVERVIEW.md) | The three images, what is in each, and the one-mount model |
| [02-QUICKSTART.md](02-QUICKSTART.md) | Build, load offline, configure, and run |
| [03-AGENTS.md](03-AGENTS.md) | opencode, pi, and DeepSeek Harness: commands, config, persistence |
| [04-PYTHON.md](04-PYTHON.md) | The single Python 3.11 environment and its packages |
| [05-CPP.md](05-CPP.md) | The C/C++ toolchain and 64-bit Windows cross-compilation |
| [06-REVERSE-ENGINEERING.md](06-REVERSE-ENGINEERING.md) | Decompiling Python `.exe` files and analysing native binaries |
| [07-WEB-IDE.md](07-WEB-IDE.md) | code-server, ttyd/tmux, and the DeepSeek Harness web UI |
| [08-GIT-GITEA.md](08-GIT-GITEA.md) | Git identity, token and SSH modes for an air-gapped Gitea |
| [09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md) | Pointing every agent at a local OpenAI-compatible endpoint |
| [10-SECURITY.md](10-SECURITY.md) | Containment model, seccomp profiles, and their limits |
| [11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md) | Versions, hashes, and the verification model |
| [12-TROUBLESHOOTING.md](12-TROUBLESHOOTING.md) | Symptom, cause, and fix for common failures |
| [13-COMMAND-REFERENCE.md](13-COMMAND-REFERENCE.md) | Operator command cheat sheet |

These docs are copied into every image at `/opt/yolo/docs`, so an agent inside
the container can read them without the repository. The authoritative copy is
always the repository, and [PINS.md](../PINS.md) is the file that defines what
actually ships.

Historical 5.0 documentation is kept separately under `history/v5.0/docs`.

Tagged releases attach one offline ZIP bundle per image containing
Docker-loadable archives, launchers, configuration templates, and checksums.
