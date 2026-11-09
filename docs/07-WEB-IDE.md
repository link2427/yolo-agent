# 07 — The browser pages

Every person's container serves five pages. Ports are the defaults; a person's
`.env` can change them (see [02-QUICKSTART.md](02-QUICKSTART.md)).

| Page | Port | Program | Notes |
|---|---|---|---|
| Start | 8000 | `yolo serve home` | buttons for everything below; shows the model, whether SEC09 and Gitea answer, the agents |
| VS Code | 8080 | code-server 4.137.0 | opens `/workspace`; Kilo Code panel |
| Chat | 4096 | `opencode web` | the opencode agent in the browser; runs in the container with the same tools as the terminal |
| Terminal | 7681 | ttyd 1.7.7 + tmux | one tmux session (`main`); closing the tab keeps it running |
| Files | 8081 | File Browser 2.63.23 | upload, download, zip; root is `/workspace` |

There is no login on any page. Each service is its own compose service, so a
crash in one does not take down the others; compose restarts it.

## VS Code

- Settings come from `/opt/yolo/vscode/settings.json` in the image and are
  merged into the person's settings on each start. Settings the person changed
  are kept; yolo-managed keys are refreshed.
- Extensions in the image are linked into the home volume
  (`~/.local/share/code-server/extensions`), not copied. Extensions a person
  installs from a VSIX file stay.
- Terminals are login shells, so all `yolo` settings and agents are there.
- VS Code's built-in Copilot chat is turned off (`chat.disableAIFeatures`).

### Extensions

YAML, TOML, ShellCheck, EditorConfig, Prettier, Git Graph, Kilo Code, and
themes (GitHub, Dracula, Catppuccin, Material icons). The cpp and full tiers
add clangd, CMake Tools and CMake. The full list is in [PINS.md](../PINS.md).

### Kilo Code

The Kilo icon in the left bar opens an agent panel. It runs Kilo's bundled
`kilo` program (an opencode fork) inside the container. `yolo configure` writes
`~/.config/kilo/kilo.json` from the opencode config and selects the SEC09 model
in VS Code settings, so it works on first open. The first time, Kilo asks you to
choose between "review first" and "high autonomy"; either works.

Kilo may also show "Move your opencode configuration". That is harmless; close
it. The config it needs is already in `~/.config/kilo`.

Cline is not included: its provider settings live in VS Code's secret storage
and cannot be filled in ahead of time, so every person would have to configure
it by hand.

## The "internet error" in VS Code (fixed in 3.0)

In 2.x, people kept seeing an error notification in VS Code. 3.0 tested every
2.x extension in a code-server on a network with no internet:

| Extension | What it did offline | 3.0 |
|---|---|---|
| `vadimcn.vscode-lldb` (CodeLLDB) | **The error people saw.** Open VSX serves a 94 KB stub; on first start it downloads the real debugger from github.com and fails: "Platform package installation failed: Error: getaddrinfo EAI_AGAIN github.com" | removed (use `gdb` in a terminal) |
| `ms-python.python` | tries to install its companion extensions from open-vsx.org | removed |
| `eamodio.gitlens` | calls GitKraken's servers on start | removed (Git Graph and the built-in Source Control remain) |
| `llvm-vs-code-extensions.vscode-clangd` | offers to download clangd when it is not installed (the 2.x base image) | only in the cpp and full tiers, where clangd exists |
| `ms-vscode.cmake-tools` | "It is recommended to reconfigure after upgrading to a new kits definition" on first start | automatic kit scan turned off |

With the 3.0 set, a fresh code-server on a network with no internet shows no
notifications.

Other offline settings in the image: telemetry off, update checks off,
extension recommendations off, JSON/YAML/TOML schema downloads off, git
autofetch off, GitHub authentication off.

## Browser requirements

VS Code panels such as Kilo Code use service workers, which browsers allow only
on `https://` or `http://localhost`. Open VS Code as `http://localhost:8080` on
the machine that runs the container. From another machine over plain
`http://<ip>:8080`, the editor works but panels can fail with "Could not
register service worker". The Chat page (`:4096`) has no such limit.
