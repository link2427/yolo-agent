# 11 — Command reference

## Agents

| Task | Command |
|------|---------|
| Start opencode | `opencode` → `/models` to pick the model |
| Resume an opencode session | `opencode --continue` |
| Start pi | `pi --model vllm/<model>` (or `pi` → `/model`) |
| List / attach / resume pi sessions | `pi agents` · `pi attach <id>` · `pi --resume <id>` |
| Start goose | `goose` |
| List goose skills | `goose skills list` |
| Start aider (in a git repo) | `aider` |
| Start prime-agent | `prime-agent` |
| prime-agent headless YOLO | `prime-agent --autonomous --offline "task"` |
| prime-agent sessions | `prime-agent agents` · `prime-agent attach <id>` · `prime-agent --resume <id>` · `prime-agent status` |

## Configuration (auto-run on launch, manual anytime)

| Task | Command |
|------|---------|
| Reconfigure all agents for the endpoint | `VLLM_BASE_URL=… VLLM_MODEL=… /opt/yolo/configure-agents.sh` |
| Reconfigure git for Gitea | `GITEA_HOST=… [GITEA_TOKEN=…|GIT_SSH=1] /opt/yolo/configure-git.sh` |
| Rebuild the skills farm | `/opt/yolo/make-skill-farm.sh` |
| List baked extension versions | `cat /opt/yolo/EXTENSIONS-MANIFEST.txt` |

## Terminal persistence (tmux)

| Task | Command |
|------|---------|
| New session | `tmux new -s work` |
| Detach (keep running) | `Ctrl-b d` |
| Reattach | `tmux attach -t work` |
| List sessions | `tmux ls` |
| Kill a session | `tmux kill-session -t work` |

(ttyd wraps `tmux new -A -s yolo` — closing the browser tab is equivalent to
detaching.)

## Docker ops (destination host)

| Task | Command |
|------|---------|
| Interactive run | `./run-yolo.sh` (from the directory to expose as `/workspace`) |
| Run one command | `./run-yolo.sh opencode` |
| Server mode | `./run-yolo-server.sh` |
| Server logs | `docker logs -f yolo-server` |
| Stop / restart / remove server | `docker stop yolo-server` · `docker restart yolo-server` · `docker rm -f yolo-server` |
| Verify lockdown | see 08 "Verification after load" |

## Git (inside the container)

| Task | Command |
|------|---------|
| Clone (token mode) | `git clone http://agent@server4:3000/agent/repo.git` |
| Clone (ssh mode) | `git clone ssh://git@server4:2222/agent/repo.git` |
| Identity | `git config --global user.name` / `user.email` (set by configure-git) |
| Where the token lives | `~/.git-credentials` (mode 600, volume) |
| Regenerate SSH key + print pubkey | `rm -rf ~/.ssh && GITEA_HOST=… GIT_SSH=1 /opt/yolo/configure-git.sh` |

## Web

| Endpoint | URL |
|----------|-----|
| code-server (VS Code) | `http://<host>:8080` |
| ttyd (terminal) | `http://<host>:7681` |

## Inside the image

| Path | What |
|------|------|
| `/workspace` | The mounted working directory (agents work here) |
| `/home/agent` | Home (volume `yolo-home-v5`): configs, skills farm, git creds, sessions |
| `/opt/skills` | Read-only skills library (root-owned) |
| `/opt/yolo` | Launchers, configurators, docs, seccomp profile |
| `/opt/code-server` | code-server install |
| `/opt/aider-venv` | aider's isolated Python venv |
| `/opt/prime…` → `~/.prime/agent/kernel-venv` | prime-agent's IPython kernel |
| `/tmp/code-server.log`, `/tmp/ttyd.log` | Web server logs |
