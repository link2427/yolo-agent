# 06 — Git: push to your Gitea server

The container ships with git + openssh-client and a configurator
(`/opt/yolo/configure-git.sh`) that wires credentials automatically from
`yolo.env`. **Both token and SSH modes are supported**; pick per deployment.

## Setup — token mode (default, simplest)

```bash
# yolo.env
GITEA_HOST=server4:3000
GITEA_USER=agent
GITEA_TOKEN=<token>
# optional: GIT_NAME / GIT_EMAIL (defaults: Agent / agent@gitea.local)
```

On launch this:

1. Sets git identity (global gitconfig — used by all agents **and**
   code-server's Git UI).
2. Writes `http://<user>:<token>@<host>` to `~/.git-credentials`
   (mode 600, in the home volume — **never** in the image).
3. Sets `credential.helper store`, so plain clones push without prompts:

```bash
git clone http://agent@server4:3000/agent/myproject.git
cd myproject && echo x >> README.md && git commit -am x && git push   # no prompt
```

## Setup — SSH mode (agent's own keypair)

```bash
# yolo.env
GITEA_HOST=server4:3000
GIT_SSH=1
GITEA_SSH_PORT=2222        # Gitea's ssh port (often not 22)
```

On first launch the container generates `~/.ssh/id_ed25519` (no passphrase,
mode 600) and **prints the public key** — paste it into the agent user's Gitea
account (Settings → SSH / GPG Keys). Then:

```bash
git clone ssh://git@server4:2222/agent/myproject.git   # or git@gitea:agent/repo.git
```

Host-key verification is `accept-new` (auto-accepts the first connection —
fine on the air-gapped LAN).

## Behavior notes

- `configure-git.sh` re-runs **every launch** when `GITEA_HOST` is set, so
  `yolo.env` is the source of truth: change the token (or switch token ↔ SSH)
  and the next launch applies it.
- Secrets live only in the home volume — the disc tar stays clean.

## Recommended Gitea-side setup (least privilege)

Create a dedicated **agent** user (it makes commit history and auditing
clean), then:

1. Put the agent in an **org team** with **Write** access on only the repos it
   should touch. Gitea repo permissions are read/write/admin — team scoping is
   the practical way to keep the agent from admin actions (no repo/org
   deletion).
2. For token mode, generate the token scoped to **`write:repository`** only
   (Settings → Applications → Generate New Token), not admin or full scope.

## DNS

If `server4` doesn't resolve inside the container, set `GITEA_HOST_IP` in
`yolo.env` and uncomment `--add-host server4:$GITEA_HOST_IP` in
`run-yolo.sh` / `run-yolo-server.sh`.
