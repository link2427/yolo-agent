# yolo-dev:6.0 — Documentation Bundle

Complete operator documentation for the `yolo-dev:6.0` container image
(locked-down local coding agents, browser IDE, Gitea push support, curated
30-skill default + 920-skill library).

| Doc | What it covers |
|-----|----------------|
| [01-OVERVIEW.md](01-OVERVIEW.md) | What the container is, contents, versions, design goals |
| [02-QUICKSTART.md](02-QUICKSTART.md) | Fastest path: load → configure → run (interactive & server) |
| [03-AGENTS.md](03-AGENTS.md) | The five coding agents: configs, run commands, YOLO mode, persistence |
| [04-SKILLS.md](04-SKILLS.md) | The 924 preloaded skills: sources, discovery, adding/trimming |
| [05-WEB-IDE.md](05-WEB-IDE.md) | code-server + ttyd browser access, extensions, terminal persistence |
| [06-GIT-GITEA.md](06-GIT-GITEA.md) | Pushing to your Gitea server: token & SSH modes, server-side setup |
| [07-MODEL-ENDPOINT.md](07-MODEL-ENDPOINT.md) | vLLM / LM Studio endpoint configuration via `yolo.env` |
| [08-SECURITY.md](08-SECURITY.md) | Layered lockdown, launcher flags, seccomp, exposure tradeoffs |
| [09-PINS-INTEGRITY.md](09-PINS-INTEGRITY.md) | Every pinned version, checksum, and supply-chain note |
| [10-TROUBLESHOOTING.md](10-TROUBLESHOOTING.md) | Common problems and fixes |
| [11-COMMAND-REFERENCE.md](11-COMMAND-REFERENCE.md) | Cheat sheet: agents, tmux, docker ops, git |

Reference files that ship with the image/launcher:

- `yolo.env.example` — copy to `yolo.env` and edit (endpoint, git, auth)
- `run-yolo.sh` — interactive launcher (all lockdown flags)
- `run-yolo-server.sh` — detached server launcher (code-server + ttyd)
- `seccomp-yolo.json` — strict seccomp profile used by both launchers
- `SHA256SUMS` — integrity of the docker archive
- `LOAD-IN-SCIF.txt` — exact `docker load` command

Inside the image, the same docs live at `/opt/yolo/docs/`.
