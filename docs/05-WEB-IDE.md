# 05 — Browser access (code-server + ttyd + OpenHands)

`bin/run-server.sh` (or `docker compose up -d`) starts the container detached
with three web endpoints. They have no application-level authentication by
design, because this build targets an air-gapped internal network; ports are
bound to `0.0.0.0` by default. Set `YOLO_BIND_ADDRESS=127.0.0.1` to bind
host-loopback instead.

| Service | URL | What it is |
|---------|-----|------------|
| code-server | `http://<host>:8080` | Full VS Code in the browser |
| ttyd | `http://<host>:7681` | Browser terminal (wraps tmux) |
| OpenHands | `http://<host>:3000` | OpenHands CLI browser UI (`openhands web`) |

## code-server

- Version 4.135.0 (standalone binary at `/opt/code-server`), runs as the
  agent user.
- Config: `~/.config/code-server/config.yaml` (bind 0.0.0.0:8080, `auth: none`,
  telemetry + update-check disabled — it never phones home).
- User settings: `~/.local/share/code-server/User/settings.json` (GitHub Dark
  theme, Material icons, format-on-save, Jedi Python LS, workspace trust off).

### Pre-installed extensions (15, from Open VSX — all offline)

- Language tooling: Python (Jedi LS — Pylance is MS-marketplace-only and
  can't ship offline), YAML, TOML, ESLint, Prettier, shellcheck,
  EditorConfig
- Themes/icons: GitHub, One Dark, Dracula, Catppuccin, Material Icons
- Utilities: GitLens, Git Graph, Code Spell Checker

Installed versions: `/opt/yolo/EXTENSIONS-MANIFEST.txt` inside the image.
Adding extensions at runtime requires open-vsx.org egress (not available in
the locked container) — install at build time instead, or open the registry in
the network rules.

## ttyd + tmux (terminal persistence)

ttyd serves a terminal that wraps **tmux** (`tmux new -A -s yolo-agent`), so:

- Close the browser tab → the tmux session **survives**; reopen the page to
  reattach.
- Multiple tabs attach to the same session (like screen sharing).
- Start other sessions from inside: `tmux new -s work`, `tmux attach -t work`.

## OpenHands

OpenHands 1.16.0 is the current CLI, installed via pip into a uv-managed
Python 3.12 venv. `openhands web` serves the browser UI on port 3000 with no
Docker socket. `openhands serve` (the full GUI) is not used here because it
needs Docker. The UI is pointed at the same local vLLM endpoint as the other
agents (see `configure-openhands.sh`; driven by VLLM_* in yolo.env).
Conversations and settings persist under `~/.openhands`.

## Ops

```bash
docker logs -f yolo-agent-server        # logs (also /tmp/code-server.log, /tmp/ttyd.log, /tmp/openhands.log)
docker stop yolo-agent-server           # stop
docker restart yolo-agent-server        # restart (--restart unless-stopped handles reboots)
docker rm -f yolo-agent-server          # remove
```

All services auto-respawn if they crash (supervisor: `/opt/yolo/server-start.sh`).

## DeepSeek Harness UI

DeepSeek Harness is a separate Compose service so its lifecycle does not
affect code-server, terminal, or OpenHands sessions:

```bash
docker compose up -d deepseek
docker compose logs -f deepseek
```

Open `http://<host>:3080` (override the host port with `DSH_WEB_PORT`).
Upstream DeepSeek Harness intentionally binds only inside container loopback;
`deepseek-web-start.sh` relays that listener to Docker without patching the
Harness. It is an agent UI (a remote-code-execution surface) — keep it on the
internal network.
