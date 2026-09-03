# 10 — Troubleshooting

## General

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `ERROR: yolo.env missing` | Launcher can't find the env file | `cp config/yolo.env.example config/yolo.env` from the repository root |
| `ERROR: docker not found` | Wrong machine / docker not installed | Install Docker Engine or Docker Desktop on the destination host |
| Agent says "no models" / connection refused | Endpoint unreachable | `curl $VLLM_BASE_URL/models` from the host; check IP/port/path (`/v1`); if `server4`-style hostnames don't resolve inside the container, add `--add-host` (see 06) |
| Agents not auto-configured | `VLLM_BASE_URL`/`VLLM_MODEL` missing from yolo.env | Add both, relaunch; or run `/opt/yolo/configure-agents.sh` by hand |
| Model id unknown | Wrong model string | `curl $VLLM_BASE_URL/models` and use an exact served id |
| Extension install fails in-code-server | Runtime has no open-vsx.org egress (by design) | Install at build time; extensions already ship pre-installed (see 05) |
| Push to Gitea prompts for password | Credentials not configured | Check `GITEA_*` in yolo.env; verify `~/.git-credentials` exists (token mode) or key added to Gitea (SSH mode); relaunch so `configure-git.sh` re-runs |
| Ports 8080/7681/3080 already in use | Another service | Stop the conflicting service, or set `YOLO_CODE_PORT`, `YOLO_TERMINAL_PORT`, or `DSH_WEB_PORT` |
| Container exits immediately (interactive) | Exit code from the shell | That's normal for `--rm` interactive mode; run `./bin/run.sh` again |
| Skills missing | Stale home volume | Use a fresh `yolo-agent-home-v1` volume, or run `/opt/yolo/make-skill-farm.sh` (rebuilds the symlink farm from `/opt/skills`) |

## Upgrading from an older version

- The 1.x release line uses `yolo-agent-home-v1`. Back it up before removing
  it; `docker volume rm yolo-agent-home-v1` permanently deletes agent
  sessions and home-directory state.
- A stale volume will not receive newly baked content (skills, prime-agent
  kernel, configs). Either start fresh (recommended) or run
  `/opt/yolo/configure-agents.sh` + `/opt/yolo/make-skill-farm.sh` to refresh
  what can be refreshed (the prime-agent kernel venv is baked into the home
  and needs a fresh volume).

## Prime-agent

| Symptom | Fix |
|---------|-----|
| `prime-agent` starts but no kernel | Check `~/.prime/agent/kernel-venv/bin/python -c "import rlm, dill, numpy"`; if missing, back up the volume and retry with a fresh `yolo-agent-home-v1` |
| Headless run wants network | Use `--offline` for non-provider startup operations |
| Autonomous mode off | Interactive mode is prompt-less by design; use `prime-agent --autonomous "task"` for bounded self-driving |

## DeepSeek Harness

| Symptom | Fix |
|---------|-----|
| UI cannot reach a model | Put `DEEPSEEK_API_KEY` in ignored `config/yolo.env`, recreate only the `deepseek` Compose service, and select the DeepSeek model in Harness settings |
| Browser cannot reach port 3080 | Run `docker compose up -d deepseek`, then inspect `docker compose logs deepseek`; override a conflict with `DSH_WEB_PORT` |
| `--expose-internals is required for HMR service` | Use the image's `/usr/local/bin/dsh` wrapper. Do not invoke the package's `lib/bin.js` directly unless using `node --expose-internals`; this is an upstream rc.2 loader bug |
| Sessions disappeared | Confirm the service still mounts `yolo-agent-home-v1:/home/agent`; Harness persists under `~/.dsh` |

## Web IDE

| Symptom | Fix |
|---------|-----|
| `docker logs -f yolo-agent-server` shows restart loop | Check `/tmp/code-server.log` / `/tmp/ttyd.log` inside the container; usually a port conflict or missing HOME writability (volume) |
| Code-server slow first open | First open after a fresh volume copies baked extensions; subsequent opens are fast |
| ttyd opens but session gone | The tmux session was killed (container restarted). Work on disk persists in the volume; `tmux attach -t yolo` after reopening if the session still exists |

## Docker host quirks

- **Linux + no DNS for `server4`**: add `--add-host` mappings (see 06).
- **Model on the host itself** (not another machine): Docker Desktop resolves
  `host.docker.internal`; Linux needs
  `--add-host host.docker.internal:host-gateway` (commented in the launchers).
- **Memory**: if the builder or runtime OOMs, raise `YOLO_MEM` and/or
  `YOLO_CPUS` in the launcher.
