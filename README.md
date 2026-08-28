# yolo-dev — locked-down local coding agents, ready to go

A Linux/amd64 container with **opencode, pi, goose, aider** — all preconfigured
for an OpenAI-compatible **local** model endpoint (vLLM by default, LM Studio
alternative), **never asking permission** (YOLO mode), with a **~100 MB curated
skills library** preloaded (30 curated coding skills active by default; the full 920-skill library ships in the image and as a separate zip). No cloud API keys, no models baked in.

Built for YOLO-mode agent work in a **locked-down** runtime: non-root user,
read-only rootfs, all capabilities dropped, strict seccomp, no-new-privileges,
resource limits. See [SECURITY.md](SECURITY.md).

## Contents

| Tool | Version | Role |
|------|---------|------|
| opencode | 1.18.13 | Terminal coding agent — `permission: "allow"` baked in |
| pi | 0.83.0 | Terminal coding agent — no permission system; trust prompts silenced |
| goose | 1.45.0 | Terminal coding agent — `GOOSE_MODE: auto` baked in |
| aider | 0.86.2 | Git-pairing agent — `yes-always: true` baked in |
| prime-agent | 0.7.2 | Prime Intellect agent — IPython kernel runtime pre-bootstrapped, telemetry off |
| code-server | 4.117.0 | VS Code in the browser (:8080) + 15-extension pack (themes, Python/JS/YAML/TOML, git) |
| ttyd | 1.7.7 | Browser terminal (:7681), tmux-backed — sessions survive tab closes |
| skills | 30 active + 920-library | agentskills.io skills in `~/.agents/skills/` (full library at `/opt/skills` + zip export) |
| node / python / git / build-essential / curl / jq / ripgrep / tmux / vim / tini | 22 / 3.11 / … | Dev toolkit |

**YOLO out of the box:** every agent ships with permissions never asked —
opencode auto-approves all tools, goose runs fully autonomous, aider always
says yes, pi and prime-agent never prompt (pi lineage). The container
boundary is the sandbox. prime-agent's headless YOLO runs use
`prime-agent --autonomous [--autonomous-gate …]`.

**prime-agent kernel:** pre-installed at build time — uv, Python 3.11 and the
IPython kernel venv (`~/.prime/agent/kernel-venv`, with ipykernel + the
`prime-agent-runtime` rlm packages) are verified before the image is exported.
No first-run download; works offline. It executes model-generated Python with
the agent's user permissions — user-space isolation, **not** a security
sandbox (see SECURITY.md).

**Skills:** 30 curated coding skills are symlinked by default (tiny agent
context); the full 920-skill library stays read-only at `/opt/skills` and is
shipped separately as `yolo-dev-6.0-skill-library.zip`. All from the most-loved
real collections (star counts + skills.sh install leaderboard), MIT/Apache-2.0,
pinned + sha256-verified — see [PINS.md](PINS.md). No hand-rolled skills.
Activate more with `/opt/yolo/skill-use.sh <name>` (browse
`~/.agents/SKILLS-LIBRARY.txt`).

## Build (this workspace)

```bash
container-build yolo-dev:2.0 . --target test      # validate
container-build yolo-dev:2.0 . --target runtime --reproducible   # export
```

## Git: push to your Gitea server (v5)

Set the `GITEA_*` vars in `yolo.env` — git is configured automatically on
launch (identity, credentials). Two modes:

```bash
# token mode (default)
GITEA_HOST=server4:3000
GITEA_USER=agent
GITEA_TOKEN=<token scoped to write:repository>

# …or ssh mode
GIT_SSH=1
GITEA_SSH_PORT=2222        # Gitea's ssh port (often not 22)
```

- **Token mode** writes `~/.git-credentials` (mode 600, in the volume — never
the image) + `credential.helper store`; `git clone http://agent@server4:3000/…`
pushes without prompts, for CLI agents *and* code-server's Git UI.
- **SSH mode** generates an ed25519 keypair on first launch and prints the
public key — paste it into the agent user's Gitea account.
- Identity defaults to `Agent <agent@gitea.local>`; override with `GIT_NAME` /
`GIT_EMAIL`. Re-run happens every launch, so `yolo.env` is the source of truth
(change the token → next launch applies it).

**Gitea side (recommended):** create a dedicated **agent** user; for
least-privilege, put it in an org team with **Write** on the repos it should
touch (Gitea repo perms are read/write/admin — no admin), and scope the token
to `write:repository` only.

If `server4` doesn't resolve inside the container, set `GITEA_HOST_IP` in
yolo.env and uncomment `--add-host server4:$GITEA_HOST_IP` in the launchers.

## Browser access (server mode)

```bash
./run-yolo-server.sh        # detached: code-server :8080 + ttyd+tmux :7681 on the LAN
docker logs -f yolo-server
```

- **code-server** → `http://<host>:8080` — full VS Code in the browser with a
  pre-installed extension pack (GitHub/One Dark/Dracula/Catppuccin themes,
  Material icons, Python (Jedi LS), YAML, TOML, ESLint, Prettier,
  shellcheck, EditorConfig, GitLens, Git Graph, Code Spell Checker; markdown
  is built into VS Code). Installed
  versions are recorded in `/opt/yolo/EXTENSIONS-MANIFEST.txt` inside the image.
- **ttyd** → `http://<host>:7681` — browser terminal wrapping tmux: close the
  tab and the session survives; reopen to reattach. `tmux attach -t yolo` from
  anywhere.
- **Persistence**: agent transcripts/sessions live in the `yolo-home-v4` volume,
  so work survives tab closes *and* container restarts (`--restart unless-stopped`).
- **Security**: LAN-only, no auth — intended for an **air-gapped** network; see
  SECURITY.md for the exposure tradeoff.

## Run (destination Docker host)

```bash
cp yolo.env.example yolo.env   # point at your vLLM / LM Studio server
./run-yolo.sh                  # shell as uid 10001 in /workspace
```

**vLLM endpoint = two lines, auto-applied.** Edit `yolo.env`, launch — the
container auto-runs `configure-agents.sh` on first shell if it sees
`VLLM_BASE_URL` + `VLLM_MODEL`, wiring opencode, pi, goose, aider and
prime-agent to your endpoint (vLLM or LM Studio, key optional). No manual
config steps; change `yolo.env` any time and relaunch.

`run-yolo.sh` mounts your current directory as `/workspace`, a **fresh**
`yolo-home-v2` volume as `/home/agent`, and applies the full lockdown. The
baked skills + YOLO configs land in `/home/agent` on first run of the new
volume. Upgrading from v1? The volume name changed on purpose — the old
`yolo-home` volume won't have skills/configs; either start fresh or just run
the configurator once (it refreshes everything):

```bash
VLLM_BASE_URL=http://192.168.1.50:8000/v1 VLLM_MODEL=Qwen/Qwen3-Coder-30B-AWQ \
  /opt/yolo/configure-agents.sh
```

This writes all agent configs (endpoint + YOLO permissions) and rebuilds the
skills farm. Then:

```bash
opencode                    # /models to select your model
pi --model vllm/<model>     # or /model inside pi
prime-agent                 # model from ~/.prime/agent/models.json
prime-agent --autonomous --offline "task"   # headless YOLO run
goose                       # model set in config
aider                       # model set in config
```

Skills are auto-discovered from `~/.agents/skills/` by opencode, pi, goose
and prime-agent (aider has no skills support). 30 are active by default;
browse the 920-skill library with `cat ~/.agents/SKILLS-LIBRARY.txt` and add
with `/opt/yolo/skill-use.sh <name>`.

## Files

```
Dockerfile                     base → agents → skills → runtime → test
scripts/install-agents.sh      pinned, hash-verified agent installs (opencode/pi/goose/aider)
scripts/install-prime-agent.sh pinned, SHA256SUMS-verified prime-agent + kernel bootstrap
scripts/install-web-ide.sh   code-server + ttyd + Open VSX extension pack (all baked)
scripts/install-skills.sh      pinned, hash-verified skills library (10 repos)
scripts/make-skill-farm.sh     dedupes SKILL.md → ~/.agents/skills symlink farm
opt/home/                      baked YOLO defaults (opencode/pi/goose/aider)
opt/yolo/configure-agents.sh   endpoint + YOLO configs + farm refresh
opt/yolo/run-yolo.sh           interactive launcher (lockdown flags)
opt/yolo/run-yolo-server.sh    server launcher: code-server :8080 + ttyd :7681
opt/yolo/server-start.sh       web supervisor (respawns code-server/ttyd)
opt/yolo/seccomp-yolo.json     strict seccomp profile
yolo.env.example               endpoint + auth env template
README.md / SECURITY.md / PINS.md
docs/                      full operator documentation (12 MD files; also baked at /opt/yolo/docs in the image)
```
