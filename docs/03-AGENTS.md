# 03 — The coding agents

All agents are pre-configured for an OpenAI-compatible endpoint (vLLM / LM
Studio) and to **never ask permission**. Configs are generated automatically on
launch by `/opt/yolo/configure-agents.sh` from `yolo.env`, and can be
regenerated any time:

```bash
VLLM_BASE_URL=http://<host>:8000/v1 VLLM_MODEL=<model> /opt/yolo/configure-agents.sh
```

## opencode 1.18.27

- Standalone binary; config `~/.config/opencode/opencode.json`
- YOLO: `"permission": "allow"` — auto-approves every tool
- Run: `opencode` → `/models` to select the model; `/help` in-session
- Reasoning: Qwen3.8 variants `low` / `medium` / `high` (default from
  `VLLM_REASONING_EFFORT`); cycle with `variant_cycle`
- Sessions: resume with `opencode --continue` (or `/sessions`)
- Skills: reads `~/.agents/skills/` (auto)

## pi 0.84.4

- Standalone binary (earendil-works); configs `~/.pi/agent/settings.json` +
  `~/.pi/agent/models.json`
- YOLO: no permission-prompt system by design (container is the sandbox);
  `defaultProjectTrust: always` silences even the trust prompt; telemetry off
  (`PI_OFFLINE=1` etc. baked)
- Run: `pi --model vllm/<model>` or `pi` then `/model`
- Reasoning: `/effort` or `--thinking off|low|medium|high` (vLLM Qwen
  chat-template thinking)
- Sessions: `pi agents` / `pi attach <id>` / `pi --resume <id>`

## goose 1.48.0

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

## prime-agent 0.9.1

- Prime Intellect agent (pi lineage); configs `~/.prime/agent/models.json` +
  `~/.prime/agent/settings.json` (telemetry off)
- **Kernel**: persistent Python runtime, pre-bootstrapped at build time —
  uv → Python 3.11 → `~/.prime/agent/kernel-venv` (`prime-agent-runtime`
  (rlm) + dill + requests/httpx/pyyaml/tomli/dotenv/pandas/numpy/scipy/
  bs4/lxml/pydantic/tyro). No first-run downloads.
- Reasoning: `/effort` or `--thinking off|low|medium|high` (same Qwen
  thinking config as pi)
- YOLO: no permission-prompt system; headless autonomous runs use
  `prime-agent --autonomous [--autonomous-gate …] --offline "task"`
- Sessions/daemon: `prime-agent agents` / `prime-agent attach <agent>` /
  `prime-agent --resume <path|id>` / `prime-agent status`
- Skills: reads `~/.agents/skills/` (auto), plus its built-in skills
  (`prime-intellect`, `skill-creator`, `websearch`).

## DeepSeek Harness 0.1.1-rc.2

- Official DeepSeek plugin-based agent harness, currently an upstream
  developer preview; binary: `dsh`.
- Runtime state, profiles, settings, and session logs persist under
  `~/.dsh` (`DSH_HOME`) in the existing agent-home volume.
- Browser UI: `docker compose up -d deepseek`, then open
  `http://<host>:3080`.
- Headless task: `dsh --profile headless "inspect this repository"`.
- Direct UI process inside a terminal: `dsh web` (upstream binds container
  loopback; use the Compose `deepseek` service to publish it on the host).
- Reads `DEEPSEEK_API_KEY` from the runtime environment. Put the key only in
  ignored `config/yolo.env`; it is never baked into an image or archive.
- The Harness can read/edit/run anything available to uid 10001 inside the
  container, but receives no Docker socket, capabilities, sudo, or host root.

## OpenHands 1.16.0

- Browser UI at `http://<host>:3000` via `openhands web` (no Docker socket)
  inside the container. Installed as pip `openhands` in a uv-managed Python
  3.12 venv at `/opt/openhands`.
- Configured by `configure-openhands.sh` into `~/.openhands/agent_settings.json`
  from the same VLLM_* values in yolo.env; conversations and settings persist
  under `~/.openhands`.
- Started by the server supervisor (`/opt/yolo/server-start.sh`); see 05.

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
