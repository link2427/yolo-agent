# 03 — The five coding agents

All agents are pre-configured for an OpenAI-compatible endpoint (vLLM / LM
Studio) and to **never ask permission**. Configs are generated automatically on
launch by `/opt/yolo/configure-agents.sh` from `yolo.env`, and can be
regenerated any time:

```bash
VLLM_BASE_URL=http://<host>:8000/v1 VLLM_MODEL=<model> /opt/yolo/configure-agents.sh
```

## opencode 1.18.13

- Standalone binary; config `~/.config/opencode/opencode.json`
- YOLO: `"permission": "allow"` — auto-approves every tool
- Run: `opencode` → `/models` to select the model; `/help` in-session
- Sessions: resume with `opencode --continue` (or `/sessions`)
- Skills: reads `~/.agents/skills/` (auto)

## pi 0.83.0

- Standalone binary (earendil-works); configs `~/.pi/agent/settings.json` +
  `~/.pi/agent/models.json`
- YOLO: no permission-prompt system by design (container is the sandbox);
  `defaultProjectTrust: always` silences even the trust prompt; telemetry off
  (`PI_OFFLINE=1` etc. baked)
- Run: `pi --model vllm/<model>` or `pi` then `/model`
- Sessions: `pi agents` / `pi attach <id>` / `pi --resume <id>`

## goose 1.45.0

- Standalone binary; config `~/.config/goose/config.yaml`
- YOLO: `GOOSE_MODE: auto` (fully autonomous); provider `openai` pointed at
  your endpoint via `OPENAI_HOST`/`GOOSE_MODEL`
- Run: `goose`
- Skills: `goose skills list`; reads `~/.agents/skills/` (auto)
- Note: goose ignores API keys in its config file — pass `OPENAI_API_KEY` via
  `yolo.env` if your endpoint requires auth.

## aider 0.86.2

- Isolated venv (`/opt/aider-venv`); config `~/.aider.conf.yml`
- YOLO: `yes-always: true` (never asks before edits/commits)
- Run: `aider` (works in a git repo; auto-commits)
- Reads `OPENAI_API_KEY` from the environment if your endpoint requires auth.
- No skills support (markdown skills are not loaded by aider).

## prime-agent 0.7.2

- Prime Intellect agent (pi lineage); configs `~/.prime/agent/models.json` +
  `~/.prime/agent/settings.json` (telemetry off)
- **Kernel**: persistent IPython runtime, pre-bootstrapped at build time —
  uv → Python 3.11 → `~/.prime/agent/kernel-venv` (ipykernel +
  `prime-agent-runtime` (rlm) + dill + requests/httpx/pyyaml/tomli/dotenv/
  pandas/numpy/scipy/bs4/lxml/pydantic/tyro). No first-run downloads.
- YOLO: no permission-prompt system; headless autonomous runs use
  `prime-agent --autonomous [--autonomous-gate …] --offline "task"`
- Sessions/daemon: `prime-agent agents` / `prime-agent attach <agent>` /
  `prime-agent --resume <path|id>` / `prime-agent status`
- Skills: reads `~/.agents/skills/` (auto), plus its built-in skills
  (`prime-intellect`, `skill-creator`, `websearch`).

## Git identity for commits

All agents commit through the system git, so the global gitconfig set by
`configure-git.sh` (see 06) controls attribution: `Agent <agent@gitea.local>`
by default, overridable with `GIT_NAME`/`GIT_EMAIL` in `yolo.env`.

## Persistence model

| Layer | Survives tab close | Survives container restart |
|-------|--------------------|----------------------------|
| Raw terminal | No (use tmux, see 05/11) | No (restart with `--restart` in server mode) |
| Agent session transcripts (in `~/…` home volume) | Yes | Yes |
| Workspace files (`/workspace` bind mount) | Yes | Yes |
