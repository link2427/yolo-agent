# 01 — Overview

**yolo-dev:5.0** is a locked-down Linux/amd64 container for running local
coding agents in "YOLO mode" — autonomous, never asking permission — against
an OpenAI-compatible model endpoint on your air-gapped network (vLLM by
default, LM Studio alternative). It ships ready to go: agents, models-free
skills library, browser IDE, and git push to your Gitea server.

## Design goals

1. **Ready to go** — agents, configs, YOLO permissions, skills, and the
   prime-agent kernel are all pre-baked and auto-configured from `yolo.env`.
2. **No cloud, no keys in the image** — the tar travels on a disc, so every
   secret (API key, git token) is injected at runtime via `yolo.env` / the
   home volume, never baked in.
3. **Locked down** — non-root user, no sudo, no setuid, read-only rootfs,
   all capabilities dropped, strict seccomp, resource limits. The container
   boundary is the sandbox; agents are trusted inside `/workspace`.
4. **Small enough for one disc** — ~1.7 GB docker-loadable tar (4 GiB disc
   budget).

## What's inside

| Component | Version | Notes |
|-----------|---------|-------|
| opencode | 1.18.13 | Terminal coding agent; `permission: allow` baked in |
| pi | 0.83.0 | Terminal coding agent; no permission system; trust prompts silenced |
| goose | 1.45.0 | Terminal coding agent; `GOOSE_MODE: auto` baked in |
| aider | 0.86.2 | Git-pairing agent; `yes-always: true` baked in |
| prime-agent | 0.7.2 | Prime Intellect agent; IPython kernel pre-bootstrapped; telemetry off |
| code-server | 4.117.0 | VS Code in the browser (:8080) + 15-extension pack |
| ttyd | 1.7.7 | Browser terminal (:7681), tmux-backed |
| Skills library | 30 active + 920 library | 10 loved repos, MIT/Apache-2.0, pinned + hash-verified; full library also shipped as zip |
| node / npm | 22 | Runtime + dev tooling |
| python | 3.11 | apt python + pip/venv, plus prime-agent's uv-managed 3.11 kernel |
| git / openssh-client / build-essential / curl / jq / ripgrep / fd / shellcheck / tmux / vim / tini / … | Debian bookworm | Dev toolkit |

## Version lineage

- **v1** — base: opencode + pi + goose + aider, vLLM config, lockdown, 655 MB
- **v2** — + ~100 MB skills library (924 skills), YOLO permissions baked
- **v6** — 30 curated coding skills active by default (kills the ~120k-token
  skill context); full 920-skill library kept in-image + as a separate zip
- **v3** — + prime-agent with pre-bootstrapped IPython kernel runtime
- **v4** — + browser access: code-server + ttyd/tmux (LAN, no auth)
- **v5** — + git auth for Gitea (token & SSH modes via `yolo.env`)

## Artifact

- Image tag: `yolo-dev:5.0`
- Archive: `yolo-dev_5.0.docker.tar` (~1.7 GB)
- SHA-256: `3ad5d7f8bce19c983244ea8adbdfb7d76baa4bb2a24bf35a5f807f81d56e8d99`
- Platform: linux/amd64 (Debian 12 bookworm base)
