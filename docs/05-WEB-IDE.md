# 05 — Browser access (code-server + ttyd)

`run-yolo-server.sh` starts the container detached with two web endpoints,
exposed on the LAN **without authentication** (air-gapped network only — see
08):

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

ttyd serves a terminal that wraps **tmux** (`tmux new -A -s yolo`), so:

- Close the browser tab → the tmux session **survives**; reopen the page to
  reattach.
- Multiple tabs attach to the same session (like screen sharing).
- Start other sessions from inside: `tmux new -s work`, `tmux attach -t work`.

## Ops

```bash
docker logs -f yolo-server        # logs (also /tmp/code-server.log, /tmp/ttyd.log in-container)
docker stop yolo-server           # stop
docker restart yolo-server        # restart (--restart unless-stopped handles reboots)
docker rm -f yolo-server          # remove
```

Both services auto-respawn if they crash (supervisor: `/opt/yolo/server-start.sh`).
