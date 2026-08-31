# 01 — Overview

yolo-agent is a persistent Linux/amd64 development environment for running
autonomous coding agents against local or cloud model endpoints. Agents can do
anything permitted inside /workspace and /home/agent, while the host-facing
runtime drops capabilities, blocks privilege escalation, uses a read-only root
filesystem, and never mounts the Docker socket.

## Profiles

| Profile | Includes | Intended use |
| --- | --- | --- |
| Full | Six agents, code-server, ttyd/tmux, complete skills library | Persistent browser development box |
| Headless | Six agents and core developer tools | CI, terminals, and smaller transfers |

Both profiles use uid 10001 and the same persistent home-volume layout.

## Pinned components

| Component | Version |
| --- | --- |
| opencode | 1.18.13 |
| goose | 1.45.0 |
| pi | 0.83.0 |
| aider | 0.86.2 |
| Prime Agent | 0.7.2 |
| DeepSeek Harness | 0.1.1-rc.2 (developer preview) |
| code-server (full) | 4.117.0 |
| ttyd (full) | 1.7.7 |
| Node | 22, Debian Bookworm slim, image digest pinned |
| Python | 3.11 |

## Version lineage

- 5.0 survives only as documents and export metadata in history/v5.0.
- 6.0 is the exact recovered source at tag archive-yolo-dev-6.0-recovered.
- 1.0 begins the reorganized source-first build with full/headless profiles,
  Docker Bake, Compose, CI, and tagged GHCR releases.

See CHANGELOG.md and history/README.md for the recovery boundary.
