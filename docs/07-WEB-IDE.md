# 07 — Web IDE, terminal, and the Harness UI

Every image ships the same three browser surfaces, all started by scripts inside
the container and published by Docker on the host:

| Surface | Container port | Host port | Host env var | Started by |
|---|---|---|---|---|
| code-server (VS Code in the browser) | 8080 | 8080 | `YOLO_CODE_PORT` | `/opt/yolo/server-start.sh` |
| ttyd + tmux (browser terminal) | 7681 | 7681 | `YOLO_TERMINAL_PORT` | `/opt/yolo/server-start.sh` |
| DeepSeek Harness UI | 3081 (relayed from loopback 3080) | 3080 | `YOLO_DSH_PORT` | `/opt/yolo/deepseek-web-start.sh` |

```bash
./bin/run-server.sh                       # base: IDE + terminal (detached)
docker compose up -d                      # base: IDE + terminal + Harness UI
docker compose up -d deepseek             # Harness UI only
docker compose -f compose.cpp.yaml up -d  # C/C++ flavor, same three surfaces
```

`bin/run-server.sh` (and `bin\run-server.ps1`) publish only code-server and
ttyd. The DeepSeek Harness UI is a separate compose service so you can restart
the agent UI without dropping your editor session; see
[02-QUICKSTART.md](02-QUICKSTART.md) for the launcher matrix.

There is **no authentication on any of the three surfaces**. Read
"No authentication: the risk" below before you publish them anywhere.

## Publishing and restricting ports

Docker Compose does the publishing, and it resolves `${...}` on the **host**
before any container starts, from your shell environment or a repo-root `.env`
file:

```bash
# loopback only — reach it through an SSH tunnel
YOLO_BIND_ADDRESS=127.0.0.1 docker compose up -d

# move the host ports (useful when two flavors run on one host)
YOLO_CODE_PORT=9080 YOLO_TERMINAL_PORT=9681 YOLO_DSH_PORT=3081 docker compose up -d

# the same variables work for the launchers
YOLO_BIND_ADDRESS=127.0.0.1 ./bin/run-server.sh
```

The default is `0.0.0.0` for all three: the design target is an air-gapped LAN,
so the ports are reachable from the network unless you say otherwise.

Two details that catch people out:

- Putting `YOLO_BIND_ADDRESS` or `YOLO_*_PORT` in `config/<flavor>.env` does not
  move the published port. That file is attached with `env_file:`, which injects
  environment variables *into the container*; the `ports:` mapping was already
  resolved on the host. Put these in the shell (or a repo-root `.env`, which
  Compose reads automatically).
- Only the host side moves. Inside the container, code-server and ttyd bind
  `0.0.0.0` (see `server-start.sh`) and the Harness relay listens on 3081; with
  `YOLO_BIND_ADDRESS=127.0.0.1` nothing outside the Docker host can reach them,
  but another container on the same Docker network still can.

## code-server

- 4.137.0, standalone tarball at `/opt/code-server`, run as uid 10001 in the
  container. The supervisor starts it as
  `code-server --bind-addr 0.0.0.0:8080 --auth none --disable-telemetry`.
- `~/.config/code-server/config.yaml` mirrors that (`bind-addr: 0.0.0.0:8080`,
  `auth: none`, `cert: false`, telemetry and update check disabled). The CLI
  flags in `server-start.sh` win, so editing the YAML alone does not change how
  the supervised process binds.
- `~/.local/share/code-server/User/settings.json` is the operator profile:
  GitHub Dark Default theme, Material icons, format-on-save, autosave after a
  delay, no startup editor, workspace trust disabled, bash as the integrated
  terminal, Python interpreter `/opt/pyenv/bin/python3` with the bundled Jedi
  language server, `clangd.path` `/usr/bin/clangd`, CMake generator Ninja with
  `configureOnOpen: false`, and `C_Cpp.intelliSenseEngine: disabled` (clangd is
  the C/C++ engine here).
- Open `http://<host>:8080` and you land in `/workspace`. It is full VS Code —
  editor, integrated terminal, source control, extension panel. Everything runs
  as the agent user inside the container, so the IDE can do anything the agents
  can, including running them from its own terminal.

### Bundled extensions (19, installed at build time)

Extensions come from Open VSX during `docker build` and are baked into the
image, all listed in `/opt/yolo/EXTENSIONS-MANIFEST.txt`. The runtime container
has no open-vsx.org egress, so the Extensions panel cannot install anything new
— to add one, edit `docker/install/install-web-ide.sh` and rebuild
([11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md)).

| Group | Extensions |
|---|---|
| Language tooling (7) | `ms-python.python` (bundled Jedi LS — Pylance is Marketplace-only), `redhat.vscode-yaml`, `tamasfe.even-better-toml`, `dbaeumer.vscode-eslint`, `timonwong.shellcheck`, `editorconfig.editorconfig`, `esbenp.prettier-vscode` |
| C/C++ (4) | `llvm-vs-code-extensions.vscode-clangd`, `ms-vscode.cmake-tools`, `twxs.cmake`, `vadimcn.vscode-lldb` |
| Themes and icons (5) | `github.github-vscode-theme`, `mskelton.one-dark-theme`, `dracula-theme.theme-dracula`, `Catppuccin.catppuccin-vsc`, `PKief.material-icon-theme` |
| Utilities (3) | `eamodio.gitlens`, `mhutchie.git-graph`, `streetsidesoftware.code-spell-checker` |

The four C/C++ extensions are installed in **every** image on purpose, so the
editor looks the same everywhere — but the tools they drive (`clangd`, `cmake`,
`ninja`, `lldb`, the compilers) exist only in `yolo-agent-cpp`. In the base and
reverse-engineering images those extensions are inert; see
[05-CPP.md](05-CPP.md).

## ttyd + tmux: terminal persistence

The supervisor runs:

```bash
ttyd -p 7681 -t titleFixed=yolo-agent -W tmux new -A -s yolo-agent /bin/bash -l
```

What that gives you:

- **Closing the browser tab does not kill the session.** ttyd detaches; the tmux
  server keeps the shell and its scrollback alive.
- Reopen `http://<host>:7681` and you are back in the same session, same working
  directory, with an agent you left running still alive.
- Reattach from anywhere inside the container — including the code-server
  terminal: `tmux attach -t yolo-agent`. Start a second one with
  `tmux new -s work`.
- `-W` makes the terminal writable (input enabled), and `bash -l` means
  `~/.bashrc` runs: the agent auto-configuration hook, the flavor banner, and —
  on the reverse-engineering flavor — `JAVA_HOME`/`PATH` from
  `/opt/yolo/toolchain-env.sh`.
- Sessions survive a ttyd crash (the supervisor restarts it within about five
  seconds, logging to `/tmp/ttyd.log`) but **not** a container restart: the
  processes and `/tmp` are gone, so a fresh session is created. Long-running
  work should live in `/workspace`, not in a tmux pane.

Both supervised processes are restarted on exit by `/opt/yolo/server-start.sh`,
which logs to `/tmp/code-server.log` and `/tmp/ttyd.log` (tmpfs — readable only
while the container is up).

## The DeepSeek Harness UI and the loopback relay

DeepSeek Harness deliberately listens on container loopback only
(`127.0.0.1:3080`), and this image does not patch that upstream safety check.
That alone is not publishable: a Docker port mapping forwards to the
container's network address, where nothing is listening, so a published
`3080:3080` mapping would have nothing to connect to.

`/opt/yolo/deepseek-web-start.sh` therefore runs two processes side by side —
the Harness on loopback, and a `socat` relay on a second container port:

```bash
dsh web --host 127.0.0.1 --port "${DSH_INTERNAL_PORT:-3080}" &   # the real UI
socat TCP-LISTEN:"${DSH_RELAY_PORT:-3081}",fork,reuseaddr \
      TCP:127.0.0.1:"${DSH_INTERNAL_PORT:-3080}" &               # the relay
```

Compose then publishes the relay port:

```yaml
deepseek:
  command: /opt/yolo/deepseek-web-start.sh
  ports:
    - ${YOLO_BIND_ADDRESS:-0.0.0.0}:${YOLO_DSH_PORT:-3080}:3081
```

So the path is: host `:3080` → container `:3081` (socat) → container
`127.0.0.1:3080` (`dsh web`). Consequences:

- **The relay is a bridge, not a security layer.** It does not authenticate
  anything and does not restrict what the harness can do. Anything that can
  reach the published port reaches an agent UI that runs tools against
  `/workspace`.
- The script waits on both children and traps `EXIT`/`INT`/`TERM` to kill both,
  so stopping the service does not leave an orphaned `socat` holding the port.
- Both ports are overridable with `DSH_INTERNAL_PORT` and `DSH_RELAY_PORT`
  inside the container, but the relay port must match the compose mapping.
- `DSH_HOME=/home/agent/.dsh` is baked into the image, so the UI reads exactly
  the config written by `configure-agents.sh` — see
  [03-AGENTS.md](03-AGENTS.md). Do not set `DEEPSEEK_API_KEY`.
- Running `dsh web` by hand inside a shell (`docker compose run --rm agent`)
  binds container loopback and is therefore *not* reachable from the host. Use
  the compose `deepseek` service, or run
  `/opt/yolo/deepseek-web-start.sh` in a container that publishes 3081.

## No authentication: the risk

State it plainly: **none of these surfaces has a login.** code-server runs with
`auth: none`, ttyd hands out a raw shell, and the Harness UI drives an agent.
Anyone who can open the port gets, as uid 10001:

- read/write on `/workspace` and on `/home/agent`;
- the ability to run any binary in the image, including the three agents in YOLO
  mode;
- the git credentials and SSH key in the home volume
  ([08-GIT-GITEA.md](08-GIT-GITEA.md));
- whatever the model endpoint exposes, since the agents reach it from inside the
  container.

The container's lockdown — read-only rootfs, `cap_drop: ALL`,
`no-new-privileges`, seccomp denylist, no Docker socket, no sudo — bounds the
blast radius to the container and the one mount. It does not protect the
workspace, the volume, or the LAN, and it is not a substitute for network
controls ([10-SECURITY.md](10-SECURITY.md)).

Mitigations, strongest first:

```bash
# 1. Bind host-loopback, then tunnel from your workstation.
YOLO_BIND_ADDRESS=127.0.0.1 docker compose up -d

ssh -N \
  -L 8080:127.0.0.1:8080 \
  -L 7681:127.0.0.1:7681 \
  -L 3080:127.0.0.1:3080 \
  user@air-gapped-host
# then browse to http://127.0.0.1:8080, http://127.0.0.1:7681, http://127.0.0.1:3080
```

- **Firewall the host.** Restrict the three ports to the machines that need
  them. Do this on the Docker host — the container has no capabilities and
  cannot manage firewall rules.
- **Never expose them to an untrusted network or the internet.** There is no TLS
  either (`cert: false`), so anything you put in front of them must terminate
  TLS *and* add authentication. If you add a reverse proxy, keep the backends
  bound to host loopback so the proxy is the only way in.
- **Treat `/workspace` as scratch.** The workspace mount is the real security
  boundary of the whole project ([01-OVERVIEW.md](01-OVERVIEW.md)).

## Across the three flavors

| | base | cpp | reverse |
|---|---|---|---|
| code-server + ttyd + extensions | yes | yes | yes |
| Harness UI (compose `deepseek` service) | yes | yes | yes |
| Default host ports | 8080 / 7681 / 3080 | 8080 / 7681 / 3080 | 8080 / 7681 / 3080 |
| Compose file | `compose.yaml` | `compose.cpp.yaml` | `compose.reverse.yaml` |
| Home volume (IDE state, extensions dir, open files) | `yolo-agent-base-home-v1` | `yolo-agent-cpp-home-v1` | `yolo-agent-reverse-home-v1` |
| C/C++ toolchain present (`clangd`, `cmake`, `ninja`, compilers) | no | yes | no |
| Terminal environment | base | base | adds `JAVA_HOME`, `/opt/java/bin`, `GHIDRA_USER_DIR` |

- The browser stack itself is identical in all three images — same code-server
  and ttyd builds, same 19 extensions, same `server-start.sh`, same ports. Only
  the toolchain on top differs.
- Each flavor has its own compose file, env file, and home volume, so IDE state
  and agent config are separate: configuring the base container does not affect
  the C++ one.
- Because the defaults collide, run one flavor at a time, or move the host ports
  for the second:

  ```bash
  YOLO_CODE_PORT=9080 YOLO_TERMINAL_PORT=9681 YOLO_DSH_PORT=3081 \
    docker compose -f compose.cpp.yaml up -d
  ```
- The reverse-engineering flavor adds `JAVA_HOME`/`PATH` (Ghidra and jadx need
  Java) through `~/.bashrc` → `/opt/yolo/toolchain-env.sh`, which is exactly
  what a ttyd session or a code-server terminal inherits. See
  [06-REVERSE-ENGINEERING.md](06-REVERSE-ENGINEERING.md) and
  [05-CPP.md](05-CPP.md).
- The base image's smoke suite starts code-server, ttyd, and the relayed Harness
  UI and requires all three to answer HTTP, so a broken surface fails
  `docker buildx bake` rather than the offline host
  ([02-QUICKSTART.md](02-QUICKSTART.md)).

## Operations

```bash
# server-mode launcher (bin/run-server.sh): container name is yolo-agent-<flavor>-server
docker logs -f yolo-agent-base-server
docker rm -f yolo-agent-base-server

# compose services
docker compose ps
docker compose logs -f server deepseek
docker compose restart deepseek
```

## Next

- [03-AGENTS.md](03-AGENTS.md) — what you run inside these terminals
- [10-SECURITY.md](10-SECURITY.md) — containment and exposure tradeoffs
- [12-TROUBLESHOOTING.md](12-TROUBLESHOOTING.md) — a surface that will not load
