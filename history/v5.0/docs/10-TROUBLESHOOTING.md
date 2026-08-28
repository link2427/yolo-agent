# 10 — Troubleshooting

## General

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `ERROR: yolo.env missing` | Launcher can't find the env file | `cp yolo.env.example yolo.env` next to the launchers |
| `ERROR: docker not found` | Wrong machine / docker not installed | Install Docker Engine or Docker Desktop on the destination host |
| Agent says "no models" / connection refused | Endpoint unreachable | `curl $VLLM_BASE_URL/models` from the host; check IP/port/path (`/v1`); if `server4`-style hostnames don't resolve inside the container, add `--add-host` (see 06) |
| Agents not auto-configured | `VLLM_BASE_URL`/`VLLM_MODEL` missing from yolo.env | Add both, relaunch; or run `/opt/yolo/configure-agents.sh` by hand |
| Model id unknown | Wrong model string | `curl $VLLM_BASE_URL/models` and use an exact served id |
| Extension install fails in-code-server | Runtime has no open-vsx.org egress (by design) | Install at build time; extensions already ship pre-installed (see 05) |
| Push to Gitea prompts for password | Credentials not configured | Check `GITEA_*` in yolo.env; verify `~/.git-credentials` exists (token mode) or key added to Gitea (SSH mode); relaunch so `configure-git.sh` re-runs |
| Ports 8080/7681 already in use | Another service | `docker rm -f yolo-server`, free the ports, relaunch; or edit the `-p` mapping in `run-yolo-server.sh` |
| Container exits immediately (interactive) | Exit code from the shell | That's normal for `--rm` interactive mode; run `./run-yolo.sh` again |
| Skills missing | Stale home volume | Use a fresh `yolo-home-v5` volume, or run `/opt/yolo/make-skill-farm.sh` (rebuilds the symlink farm from `/opt/skills`) |

## Upgrading from an older version

- v1→v5 volumes are intentionally **not** reused: each release uses a new
  volume name (`yolo-home-v5` for 5.0). Old volumes can be removed:
  `docker volume rm yolo-home-v4` (etc.).
- A stale volume will not receive newly baked content (skills, prime-agent
  kernel, configs). Either start fresh (recommended) or run
  `/opt/yolo/configure-agents.sh` + `/opt/yolo/make-skill-farm.sh` to refresh
  what can be refreshed (the prime-agent kernel venv is baked into the home
  and needs a fresh volume).

## Prime-agent

| Symptom | Fix |
|---------|-----|
| `prime-agent` starts but no kernel | Check `~/.prime/agent/kernel-venv/bin/python -c "import ipykernel, rlm"`; if missing, the volume predates v3 — use a fresh `yolo-home-v5` |
| Headless run wants network | Use `--offline` for non-provider startup operations |
| Autonomous mode off | Interactive mode is prompt-less by design; use `prime-agent --autonomous "task"` for bounded self-driving |

## Web IDE

| Symptom | Fix |
|---------|-----|
| `docker logs -f yolo-server` shows restart loop | Check `/tmp/code-server.log` / `/tmp/ttyd.log` inside the container; usually a port conflict or missing HOME writability (volume) |
| Code-server slow first open | First open after a fresh volume copies baked extensions; subsequent opens are fast |
| ttyd opens but session gone | The tmux session was killed (container restarted). Work on disk persists in the volume; `tmux attach -t yolo` after reopening if the session still exists |

## Docker host quirks

- **Linux + no DNS for `server4`**: add `--add-host` mappings (see 06).
- **Model on the host itself** (not another machine): Docker Desktop resolves
  `host.docker.internal`; Linux needs
  `--add-host host.docker.internal:host-gateway` (commented in the launchers).
- **Memory**: if the builder or runtime OOMs, raise `YOLO_MEM` and/or
  `YOLO_CPUS` in the launcher.
