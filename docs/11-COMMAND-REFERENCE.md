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
| Start DeepSeek Harness UI | `docker compose up -d deepseek` |
| Run a DeepSeek Harness task | `dsh --profile headless "task"` |
| Inspect DeepSeek Harness config | `dsh --profile headless --dump-config` |
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

(ttyd wraps `tmux new -A -s yolo-agent` — closing the browser tab is equivalent to
detaching.)

## Docker ops (destination host)

| Task | Command |
|------|---------|
| Interactive run | `./bin/run.sh` (from the directory to expose as `/workspace`) |
| Run one command | `./bin/run.sh opencode` |
| Server mode | `./bin/run-server.sh` |
| Server logs | `docker logs -f yolo-agent-server` |
| Stop / restart / remove server | `docker stop yolo-agent-server` · `docker restart yolo-agent-server` · `docker rm -f yolo-agent-server` |
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
| DeepSeek Harness | `http://<host>:3080` |

## Inside the image

| Path | What |
|------|------|
| `/workspace` | The mounted working directory (agents work here) |
| `/home/agent` | Home (volume `yolo-agent-home-v1`): configs, skills farm, git creds, sessions |
| `/opt/skills` | Read-only skills library (root-owned) |
| `/opt/yolo` | Runtime configurators, supervisor, docs, and seccomp profile |
| `/opt/code-server` | code-server install |
| `/opt/aider-venv` | aider's isolated Python venv |
| `/opt/deepseek-harness` | Locked DeepSeek Harness npm installation |
| `~/.dsh` | Persistent DeepSeek Harness profiles, settings, and sessions |
| `/opt/prime…` → `~/.prime/agent/kernel-venv` | prime-agent's Python kernel |
| `/tmp/code-server.log`, `/tmp/ttyd.log` | Web server logs |
