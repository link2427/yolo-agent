# 12 — Troubleshooting

Start with:

```bash
yolo doctor      # in the container: endpoint, model, token, workspace, agents, configs
```

and, on the host, in the person's folder:

```bash
docker compose ps
docker compose logs --tail 50 <service>     # home, code, chat, term, files
```

## The agents have no model, or "cannot connect"

**Check.** `yolo status` shows the endpoint and whether it is up. `yolo models`
lists what SEC09 serves.

**Causes and fixes.**

- SEC09 is down or unreachable from this machine:
  `curl http://192.168.1.101:8000/v1/models`. Agents keep the last known model
  list, but requests fail until it is back.
- `VLLM_BASE_URL` points somewhere else: check the person's `.env` and the fleet
  repo (`~/.yolo/fleet/fleet.env`, `~/.yolo/fleet/people/<name>.env`).
- `VLLM_MODEL` names a model SEC09 no longer serves: `yolo doctor` says
  "configured model is served ✗". Clear it or fix it, then `yolo configure`.
- vLLM needs an API key: set `VLLM_API_KEY`.

After any change, `yolo configure` rewrites every agent's config.

## I edited an agent's config and it changed back

The configs are rewritten from settings on every start (see
[03-AGENTS.md](03-AGENTS.md)). Put the change in `.env` or the fleet repo
instead. Settings you change in VS Code itself are kept.

## A setting in the fleet repo does not apply

- The container needs a Gitea token to pull the fleet repo: `yolo status` shows
  "fleet repo: no token" otherwise. Run `yolo login`.
- Pull now: `yolo sync`.
- The person's `.env` wins over the fleet repo. Remove the line from `.env`.
- Values with spaces need quotes in the fleet files (`GIT_NAME="Team Bot"`).

## git asks for a password, or push is refused

- No token: `yolo login`, then `yolo status` should say "git ready as <user>".
- The token lacks repository write access: make a new one with the right scopes.
- The repository is protected: push a branch and open a pull request
  (`yolo-gitea pr-create`).

## A page does not open

- Wrong port: the person's ports are in their `.env` (`YOLO_PORT_*`).
- Port already used by someone else on the machine: give each person their own
  block with `install.sh new <name> --ports N`, or edit `.env` and
  `docker compose up -d`.
- The service is restarting: `docker compose logs <service>`.
- `YOLO_BIND=127.0.0.1` in `.env` makes the pages local to that machine only.

## Kilo Code panel shows "Could not register service worker"

Browsers allow service workers only on `https://` or `http://localhost`. Open VS
Code as `http://localhost:<port>` on the machine running the container. See
[07-WEB-IDE.md](07-WEB-IDE.md).

## A VS Code notification about downloading or the internet

3.0 removed every extension that did this in 2.x
([07-WEB-IDE.md](07-WEB-IDE.md)). If one appears, the person probably installed
an extension themselves: Extensions view → uninstall it. Note which extension
it was so it can be listed in the docs.

## Everything is slow

The person's folder is under `/mnt/c` (the Windows drive). Move it to the WSL
disk (`~/yolo/<name>`); `yolo doctor` warns about this.

## Permission denied writing to the workspace

The container runs as uid 10001. The workspace folder must be writable by it.
`install.sh new` sets this up; for a folder made by hand:

```bash
sudo setfacl -m u:10001:rwX,u:$(id -u):rwX -d -m u:10001:rwX,u:$(id -u):rwX workspace
# or, without ACL support:
chmod 0777 workspace
```

## Read-only file system

Every service runs with a read-only root filesystem. Writable paths:

| Path | What | Kept when the container is replaced |
|---|---|---|
| `/workspace` | the person's folder on the host | yes |
| `/home/agent` | the home volume (`<folder>_home`) | yes |
| `/tmp`, `/run`, `/dev/shm` | tmpfs | no |

Install what you need at build time, or use `pip install --target
/workspace/.pylibs` for a one-off ([04-PYTHON.md](04-PYTHON.md)).

## pip install or npm install fails

There is no internet. Use what is installed (`yolo tools`, `pip list`). To add a
package for everyone, add it to `docker/requirements-common.txt` and build a new
release.

## gdb, strace or ptrace fails

Debuggers are only in the cpp and full tiers. `config/seccomp.json` allows
`ptrace`; if the person's folder has an old seccomp file, run
`install.sh upgrade <name>`.

## A cross-compiled Windows binary will not run

Expected: there is no Wine. The container builds 64-bit Windows PE files but
cannot run them. Copy the `.exe` out (Files page, VS Code download, or the
workspace folder) and run it on Windows. It is statically linked, so it needs no
DLLs. See [05-CPP.md](05-CPP.md).

## Ghidra fails to start

- `java -version` must say 21 and `JAVA_HOME` must be `/opt/java`.
- `GHIDRA_USER_DIR` must be writable (default `$HOME/.ghidra`).
- Heap: set `JAVA_OPTS=-Xmx8g` in the person's `.env`, within `YOLO_MEM`.

## The Crush agent sometimes prints nothing

With a very fast reply Crush can drop its output in `crush run`. Run it again or
use the interactive `crush`.

## The build fails at a smoke test

The smoke tests run with no network and print the failing command (`set -x`).
Common causes: a pin bumped in one place but not the other, an agent changing its
config format (the round-trip check catches it), an upstream asset replaced
under the same version (hash mismatch). See
[11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md).

## Look inside an image

```bash
docker run --rm -it --entrypoint bash yolo-agent:3.0.0-full
cat /opt/agents/VERSIONS.txt
```

A bare `docker run` skips the read-only flag, seccomp and the `.env`. To
reproduce a real problem, use `docker compose run --rm shell` in the person's
folder.

## Full reset of one person

Their files in `workspace/` are kept; settings, agent history and the stored
token are deleted:

```bash
cd ~/yolo/alice
docker compose down
docker volume rm alice_home
docker compose up -d
```
