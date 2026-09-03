# 01 — Overview

yolo-agent is a persistent Linux/amd64 development environment for running
autonomous coding agents against local or cloud model endpoints. Agents can do
anything permitted inside /workspace and /home/agent, while the host-facing
runtime drops capabilities, blocks privilege escalation, uses a read-only root
filesystem, and never mounts the Docker socket.

## The runtime

The image is a single always-on browser runtime: every agent harness plus
code-server, ttyd/tmux, OpenHands, DeepSeek Harness, and the complete skills
library. There is no separate headless variant — this build targets an
air-gapped internal network, so every web surface is exposed by default.

## Pinned components

| Component | Version |
| --- | --- |
| opencode | 1.18.27 |
| goose | 1.48.0 |
| pi | 0.84.4 |
| aider | 0.86.2 |
| Prime Agent | 0.9.1 |
| DeepSeek Harness | 0.1.1-rc.2 (developer preview) |
| OpenHands | 0.62.0 (full web UI, `RUNTIME=local`) |
| code-server | 4.135.0 |
| ttyd | 1.7.7 |
| Node | 22, Debian Bookworm slim, image digest pinned |
| Python | 3.11 (system) + 3.13 (OpenHands venv, uv-managed) |

## Version lineage

- 5.0 survives only as documents and export metadata in history/v5.0.
- 6.0 is the exact recovered source at tag archive-yolo-dev-6.0-recovered.
- 1.0 begins the reorganized source-first build with Docker Bake, Compose,
  CI, and tagged GHCR releases.
- 1.2 drops the headless profile and adds OpenHands.

See CHANGELOG.md and history/README.md for the recovery boundary.
