# 01 — Overview

yolo-agent is a container that gives one person a complete agent workstation on
an air-gapped network: coding agents, VS Code in the browser, a browser
terminal and a file manager. The agents use the lab's vLLM server (SEC09) and
Gitea. Nothing needs the internet once the images are loaded.

## Tiers

One image, built from one `Dockerfile`, in three tiers. Each tier contains the
one before it.

| Tag | For | Adds |
|---|---|---|
| `yolo-agent:3.0.0-core` | most work | seven agents, the web pages, Python 3.11, Node 22, git, common CLI tools |
| `yolo-agent:3.0.0-cpp` | C, C++, Fortran | gcc/g++/gfortran 12, clang 14, cmake, ninja, gdb, valgrind, mingw-w64 cross compilers for 64-bit Windows |
| `yolo-agent:3.0.0-full` | reverse engineering | Ghidra headless, jadx, radare2, pycdc, pyinstxtractor-ng, pydumpck, binwalk, yara, Java 21 |

## One person, one folder

```
~/yolo/alice/
  compose.yaml        the services (same file for everyone)
  .env                tier, ports, person name, Gitea token, overrides
  config/seccomp.json
  workspace/          alice's files, mounted at /workspace
```

`docker compose up -d` in that folder starts five services from the same image.
They share `/workspace` and a home volume (`alice_home`, mounted at
`/home/agent`) that holds settings, agent history and the Gitea token.

| Service | Port | What |
|---|---|---|
| home | 8000 | start page |
| code | 8080 | VS Code (code-server) with the Kilo Code panel |
| chat | 4096 | opencode web: an agent in the browser |
| term | 7681 | browser terminal (tmux) |
| files | 8081 | File Browser for `/workspace` |
| shell | — | `docker compose run --rm shell` for a one-off shell |

## What happens at start

Every service starts through `/opt/yolo/bin/entrypoint`, which runs
`yolo configure`:

1. Load settings: `/etc/yolo/defaults.env`, then the fleet repo, then the
   person's file in the fleet repo, then `~/.yolo/secrets.env`, then the
   container's environment (the `.env`). Later wins.
2. Pull the fleet and skills repos from Gitea, if there is a token.
3. Ask SEC09 which models it serves (`/v1/models`) and pick the model.
4. Write each agent's config, the Kilo Code config, VS Code settings, git
   settings and the agent instructions (`~/.yolo/AGENTS.md`).
5. Link the enabled skills into each agent's skills folder.

If SEC09 is down, the last known model list is used. Configure never stops a
service from starting.

## Lab services

`compose.lab.yaml` runs once per lab, from the core tier:

- **monitor** (`:4000`) — a proxy for `/v1/*` and a dashboard for SEC09.
- **bot** (`:9000`) — the always-on agent: pull request reviews, `@yolo`
  mentions, scheduled jobs.

See [14-LAB.md](14-LAB.md).

## Hardening

Every person's container runs as uid 10001 with a read-only root filesystem,
no capabilities, `no-new-privileges`, a seccomp profile and resource limits.
The pages have no login. See [10-SECURITY.md](10-SECURITY.md).

## Repository layout

```
Dockerfile                  all three tiers and their test stages
docker-bake.hcl             build matrix (core, cpp, full and *-test)
compose.yaml                one person's services
compose.lab.yaml            monitor and bot
.env.example, lab.env.example
config/seccomp.json
docker/install/             build-time installers
docker/rootfs/              files copied into the image (/opt/yolo, /etc/yolo, home)
docker/skills/              house skills and skill packs
docker/tests/               smoke tests and the stub model server
scripts/install.sh          host helper: load, new, lab, upgrade
scripts/package-offline.sh  builds the release files
tools/gpu-exporter.py       optional, runs on SEC09
```

## History

- 2.0.0 split the old monolith into three images with three agents.
- 3.0.0 made them tiers of one image, moved to compose only, added five agents,
  the web pages, the fleet repo, skills, the monitor and the bot.
