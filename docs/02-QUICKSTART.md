# 02 — Quick start

## What you need

- Windows with WSL 2 and Docker Desktop (WSL integration on), or a Linux host
  with Docker Engine and the compose plugin.
- The release files: `yolo-agent-3.0.0-images.tar.zst` (or its `.part-NN`
  files), `yolo-agent-3.0.0-kit.zip`, and `SHA256SUMS`.

Do everything below in a WSL terminal, in your Linux home directory. Keep the
folders on the WSL disk (`~/...`), never under `/mnt/c`: the Windows mount is
many times slower and agents will feel broken.

## 1. Load the release

```bash
mkdir -p ~/yolo-release && cd ~/yolo-release
# copy the release files here (Explorer: \\wsl.localhost\<distro>\home\<you>\yolo-release)
unzip yolo-agent-3.0.0-kit.zip
./yolo-agent-3.0.0/install.sh load .
```

`load` checks every file against `SHA256SUMS`, then loads the three tiers. It
takes a few minutes. Afterwards `docker image ls yolo-agent` shows
`3.0.0-core`, `3.0.0-cpp` and `3.0.0-full`. Remove tiers nobody on this machine
uses with `docker image rm`.

## 2. Make a person's folder

```bash
./yolo-agent-3.0.0/install.sh new alice
```

This makes `~/yolo/alice`, writes its `.env`, and starts it. Options:

| Option | Meaning |
|---|---|
| `--tier core\|cpp\|full` | image tier (default `full`) |
| `--ports 9000` | use ports 9000–9004 instead of the defaults; needed for a second person on the same machine |
| `--token <token>` | the person's Gitea token (or run `yolo login` later) |
| `--no-start` | write the folder only |

Default ports: start page 8000, VS Code 8080, Chat 4096, Terminal 7681,
Files 8081. With `--ports N`: start page N, VS Code N+1, Chat N+2, Terminal
N+3, Files N+4.

## 3. Open it

Open `http://localhost:8000`. The start page links to everything and shows
whether SEC09 and Gitea are reachable.

In the Terminal page or a VS Code terminal:

```bash
yolo login        # paste your Gitea token once; stored in the home volume
yolo doctor       # checks the model server, token, workspace, agents
claude            # or: opencode, qwen, pi, crush, goose session, codex
```

## Getting files in and out

Pick whichever is easiest:

- **Files page** (`:8081`): drag files in, download files or whole folders as a
  zip.
- **VS Code**: drag files onto the Explorer to upload; right-click → Download.
- **Windows Explorer**: the workspace is a normal folder at
  `\\wsl.localhost\<distro>\home\<you>\yolo\alice\workspace`. `install.sh new`
  gives both you and the container user (uid 10001) write access to it.
- **git**: push to Gitea from the container and pull elsewhere.

## Everyday commands

Run these in the person's folder (`cd ~/yolo/alice`):

```bash
docker compose up -d          # start
docker compose down           # stop (files and settings are kept)
docker compose restart        # restart after editing .env
docker compose run --rm shell # a one-off shell
docker compose logs -f code   # logs of one service
```

## Upgrading to a new release

Load the new release, then:

```bash
./yolo-agent-3.1.0/install.sh upgrade --all     # or: upgrade alice
```

This replaces `compose.yaml` and `config/seccomp.json`, updates `YOLO_IMAGE` in
each `.env` (keeping the tier), and restarts. Workspaces, home volumes and
`.env` settings are kept.

## Lab services

Whoever runs the lab sets up the monitor and bot once:

```bash
./yolo-agent-3.0.0/install.sh lab     # makes ~/yolo/lab; edit its .env, then docker compose up -d
```

See [14-LAB.md](14-LAB.md).
