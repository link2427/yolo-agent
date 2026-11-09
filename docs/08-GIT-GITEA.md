# 08 — Git and Gitea

Gitea is at `192.168.1.27:3000` (`GITEA_HOST`, `GITEA_PROTOCOL=http`). Commits
are made as "YOLO Agent" <yoloagent@gmail.com> unless `GIT_NAME` / `GIT_EMAIL`
are set in `.env` or the fleet repo.

## Give the container your token

Each person uses their own Gitea token. Make one in Gitea: avatar → Settings →
Applications → Generate token, with repository read/write, issue read/write and
user read.

Either:

```bash
yolo login            # in the container; paste the token
```

which checks the token with Gitea and stores it in `~/.yolo/secrets.env`
(mode 600, in the home volume), or put `GITEA_TOKEN=...` in the person's `.env`
(or pass `--token` to `install.sh new`). `yolo status` shows "git ready as
<user>" when it works.

The token is never in an image, a compose file or this repository.

## What configure sets up

On every start, with a token:

- `~/.git-credentials` (mode 600) with `http://<user>:<token>@192.168.1.27:3000`
  and `credential.helper store`, so clone, pull and push never prompt. The user
  name is asked from Gitea (`/api/v1/user`) unless `GITEA_USER` is set.
- `user.name`, `user.email`, `init.defaultBranch main`, `pull.ff only`,
  `safe.directory *`.
- The fleet repo (`yolo/fleet`) and skills repo (`yolo/skills`) are pulled into
  `~/.yolo/` when they exist and the token can read them.

```bash
git clone http://192.168.1.27:3000/team/project.git
```

## Pull requests from the shell: `yolo-gitea`

A small helper over the Gitea API, using the stored token. The agents know it
through the `yolo-gitea` skill.

```bash
yolo-gitea whoami
yolo-gitea pr-list    team/project [open|closed|all]
yolo-gitea pr-view    team/project 12
yolo-gitea pr-diff    team/project 12
yolo-gitea pr-create  team/project my-branch main "Fix the parser" body.md
yolo-gitea comment    team/project 12 comment.md        # or - for stdin
yolo-gitea review     team/project 12 COMMENT review.md # or APPROVE, REQUEST_CHANGES
yolo-gitea api        GET /repos/team/project
```

Agents are told to open pull requests rather than push to `main`.

## The bot

The lab bot reviews pull requests automatically and answers comments that
mention `@yolo`. It has its own Gitea account. See [14-LAB.md](14-LAB.md).

## File ownership

The container runs as uid 10001. Files it writes in `/workspace` are owned by
10001 on the host. `install.sh new` gives both 10001 and your WSL user access to
the workspace folder through default ACLs, so either side can edit. If `setfacl`
is missing (`sudo apt install acl`), it makes the folder world-writable instead.
