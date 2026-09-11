# 08 — Git: push to your Gitea server

The host has no internet, so there is no github.com to push to. Point the
container at a Gitea server on your LAN instead: every image ships `git` and
`openssh-client`, and `/opt/yolo/configure-git.sh` writes the identity and the
credentials for you.

Two modes, both driven by the flavor's env file:

| Mode | Env file needs | Credential used |
|---|---|---|
| token (default) | `GITEA_HOST`, `GITEA_USER`, `GITEA_TOKEN` | `~/.git-credentials` (HTTP basic via `credential.helper store`) |
| SSH | `GITEA_HOST`, `GIT_SSH=1`, optional `GITEA_SSH_PORT`, `GITEA_SSH_HOST` | `~/.ssh/id_ed25519` |

The env file is the source of truth: edit it, relaunch, and the next launch
applies the change. Optional in both modes: `GIT_NAME` and `GIT_EMAIL`
(defaults `Agent` / `agent@gitea.local`).

## Which env file

Git settings live in the flavor's env file, and each flavor has its own home
volume — configuring one does not configure the others:

| Flavor | Env file | Home volume |
|---|---|---|
| base | `config/base.env` | `yolo-agent-base-home-v1` |
| cpp | `config/cpp.env` | `yolo-agent-cpp-home-v1` |
| reverse | `config/reverse.env` | `yolo-agent-reverse-home-v1` |

Start from the matching `config/<flavor>.env.example`. Real env files are
gitignored (`config/*.env`), and `.dockerignore` keeps the whole `config/`
directory except the two seccomp profiles out of the build context, so a token
is never committed and never baked into an image.

## What gets written, and where

Everything lands in the home volume at `/home/agent`. Nothing is written to
`/workspace`, and nothing is baked into the image.

| Path | Mode | Written by | Contents |
|---|---|---|---|
| `~/.gitconfig` | private (`umask 077`) | every run | global `user.name` / `user.email` |
| `~/.git-credentials` | 600 | token mode | `http://<user>:<token>@<host>` |
| `~/.ssh` | 700 | SSH mode | key directory |
| `~/.ssh/id_ed25519` | 600 | SSH mode | private key, no passphrase |
| `~/.ssh/id_ed25519.pub` | — | SSH mode | public key to paste into Gitea |
| `~/.ssh/config` | 600 | SSH mode | `Host gitea` alias (host, port, user, key) |

## When it runs

`~/.bashrc` runs `/opt/yolo/configure-git.sh` on every interactive launch when
`GITEA_HOST` is set, so the env file is re-applied each time — a new token or a
switch between token and SSH mode takes effect on the next launch:

```
>> yolo-agent: configuring git for server4:3000 ...
git (token mode) configured for http://agent@server4:3000
```

The script is idempotent and safe to re-run by hand. Inside a container started
with the flavor's env file, the values are already in the environment:

```bash
/opt/yolo/configure-git.sh          # re-apply from the current environment
git config --global --list          # identity + credential.helper
```

It exits 1 in two cases: `GITEA_HOST` is unset (usage message), or token mode was
selected without `GITEA_TOKEN`. Inside `~/.bashrc` that failure is non-fatal
(`|| true`), so a misconfigured token shows only as an `ERROR:` line during
launch and the shell still opens.

A one-off command (`docker compose run --rm agent <cmd>`) does not source
`~/.bashrc`; run the script explicitly there.

## Token mode

1. In Gitea, create a dedicated user for the agent (for example `agent`). A
   separate account keeps commit attribution and auditing clean. Put it in an
   org team with **Write** on only the repositories it should touch — Gitea repo
   permissions are read/write/admin, and team scoping is what keeps the agent
   out of repo and org deletion.
2. As that user, open **Settings → Applications → Generate New Token** and scope
   it to **`write:repository`**. Do not use an admin or full-scope token.
3. Put the values in the flavor's env file:

```bash
# config/base.env (or cpp.env / reverse.env)
GITEA_HOST=server4:3000
GITEA_USER=agent
GITEA_TOKEN=<token>
#GIT_NAME=Agent
#GIT_EMAIL=agent@gitea.local
```

4. Relaunch the container. `GITEA_HOST` may include the port, and a pasted
   `http://` / `https://` prefix is tolerated and stripped.
5. Verify with a clone. The stored credential matches on scheme + host, so use
   the same spelling of the host that you put in `GITEA_HOST`:

```bash
git clone http://agent@server4:3000/agent/myproject.git   # no password prompt
cd myproject && echo first >> README.md
git commit -am "first commit"
git push
```

For a repository that does not exist yet, create it in the Gitea web UI first,
then push to it from `/workspace`:

```bash
cd /workspace/myproject
git init -b main
git add -A && git commit -m "initial import"
git remote add origin http://agent@server4:3000/agent/myproject.git
git push -u origin main
```

Do not put the token in the remote URL (`http://agent:<token>@server4:...`):
that writes the secret into `.git/config` inside the workspace mount in plain
text. The stored credential exists so you never have to.

## SSH mode

1. Set SSH mode in the flavor's env file. `GITEA_SSH_PORT` is Gitea's SSH port,
   which is often not 22; `GITEA_SSH_HOST` overrides the host name and defaults
   to `GITEA_HOST` without the port:

```bash
GITEA_HOST=server4:3000
GIT_SSH=1
GITEA_SSH_PORT=2222
#GITEA_SSH_HOST=server4
```

2. Relaunch. On the first launch the container generates an ed25519 keypair in
   `~/.ssh` and prints the public key:

```
git (SSH mode): new ed25519 keypair created.
Add this PUBLIC key to the Gitea agent user (Settings -> SSH / GPG Keys):
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... agent@gitea.local
```

   The keypair is generated only when `~/.ssh/id_ed25519` does not exist yet;
   later launches rewrite `~/.ssh/config` and print the clone URL instead.

3. Paste that public key into the agent user's Gitea account
   (**Settings → SSH / GPG Keys → Add Key**).
4. Clone using the URL the script prints, or the `gitea` alias from
   `~/.ssh/config`:

```bash
git clone ssh://git@server4:2222/agent/myproject.git
git clone git@gitea:agent/myproject.git        # Host gitea alias
```

Host-key checking is `StrictHostKeyChecking accept-new`: the first connection to
an unknown host is accepted, later key changes are rejected. That is why there is
no fingerprint prompt, and it is reasonable on the air-gapped LAN.

Switching back to token mode is just editing the env file and relaunching. The
leftover `~/.git-credentials` and `~/.ssh` files are harmless — an SSH URL never
consults the credential helper. Remove them inside the container if you want a
clean state:

```bash
rm -f ~/.git-credentials
```

## Git identity

`GIT_NAME` / `GIT_EMAIL` are written to the **global** gitconfig on every run,
so every agent — and code-server's Git UI — commits as the same identity:

```bash
git config --global user.name
git config --global user.email
```

The default is `Agent <agent@gitea.local>`; set `GIT_EMAIL` to a real address if
your Gitea instance validates one. This is attribution only, not a credential.

## DNS for an internal host name

The container resolves names through Docker's embedded DNS, which does not know
your LAN's internal zones. Check what the container can see:

```bash
getent hosts server4                    # inside the container
python3 -c "import socket; print(socket.gethostbyname('server4'))"
```

`GITEA_HOST_IP` handles this. `configure-git.sh` maps the host name to the
address when the name does not already resolve:

```bash
GITEA_HOST=server4:3000
GITEA_HOST_IP=192.168.1.20
```

`/etc/hosts` is root-owned and the container runs as uid 10001, so that write
usually fails — in which case the script says so and tells you the two working
alternatives:

```bash
# 1. Use the address directly (works in both modes).
GITEA_HOST=192.168.1.20:3000            # token mode also accepts the IP
GITEA_SSH_HOST=192.168.1.20             # SSH mode: only if GITEA_HOST is a name

# 2. Inject the mapping at launch instead.
docker run --add-host server4:192.168.1.20 ...
```

Whichever spelling you choose, use it consistently: the credential store matches
on scheme + host, so credentials saved for `server4:3000` are not offered to
`192.168.1.20:3000`.

## Secrets

- The token and the private key exist **only** in the `$HOME` volume, at mode
  600, written under `umask 077`. They are never copied into the image.
- `.dockerignore` allowlists only the two seccomp profiles from `config/`, so an
  env file cannot reach the build context even by accident.
- The build's smoke suite exercises both git modes with a throwaway token inside
  the `test` stage, which is never published; shipped images come from the
  `runtime` stage (`docker buildx bake images`).
- That combination is what makes the exported archive safe to hand around: the
  archive carries the wiring, not your credentials. See
  [10-SECURITY.md](10-SECURITY.md).

Files the agent creates inside the container are private to uid 10001 by default
(`~/.bashrc` sets `umask 077`). Files it creates under `/workspace` appear in
your host directory owned by uid 10001 — that is the mount you chose to expose.

## Troubleshooting

- Push still prompts for a password: the credential is not in the volume for the
  flavor you actually launched. Check `GITEA_*` in that flavor's env file and
  relaunch, or run `/opt/yolo/configure-git.sh` inside the container.
- `Permission denied (publickey)` in SSH mode: the public key is not registered
  on the Gitea user the clone authenticates as. Re-read `~/.ssh/id_ed25519.pub`
  (or re-run the script) and add the key in Gitea.
- Host name does not resolve: see the DNS section above.
- Everything else: [12-TROUBLESHOOTING.md](12-TROUBLESHOOTING.md).

## Related

- [02-QUICKSTART.md](02-QUICKSTART.md) — building, loading, and running a flavor
- [09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md) — the same env-file pattern for the model endpoint
- [10-SECURITY.md](10-SECURITY.md) — what the container can reach, and what the archive contains
