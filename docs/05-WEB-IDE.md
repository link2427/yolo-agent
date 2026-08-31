# 05 — Browser access (code-server + ttyd)

`bin/run-server.sh` starts the container detached with two web endpoints.
They have no application-level authentication but are published to localhost
by default. See 08 before changing `YOLO_BIND_ADDRESS`:

| Service | URL | What it is |
|---------|-----|------------|
| code-server | `http://<host>:8080` | Full VS Code in the browser |
| ttyd | `http://<host>:7681` | Browser terminal (wraps tmux) |

## code-server

- Version 4.117.0 (standalone binary at `/opt/code-server`), runs as the
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

## Ops

```bash
docker logs -f yolo-agent-server        # logs (also /tmp/code-server.log, /tmp/ttyd.log in-container)
docker stop yolo-agent-server           # stop
docker restart yolo-agent-server        # restart (--restart unless-stopped handles reboots)
docker rm -f yolo-agent-server          # remove
```

Both services auto-respawn if they crash (supervisor: `/opt/yolo/server-start.sh`).

## DeepSeek Harness UI

DeepSeek Harness is a separate opt-in Compose service so its lifecycle does
not affect code-server or terminal sessions:

```bash
docker compose --profile deepseek up -d deepseek
docker compose logs -f deepseek
```

Open `http://127.0.0.1:3080` (override the host port with `DSH_WEB_PORT`).
Upstream DeepSeek Harness intentionally binds only inside container loopback;
`deepseek-web-start.sh` relays that listener to Docker without patching the
Harness. Docker still publishes it to host loopback by default. Do not set
`YOLO_BIND_ADDRESS=0.0.0.0` unless an authenticated reverse proxy or trusted
network boundary protects it: an agent UI is a remote-code-execution surface.
