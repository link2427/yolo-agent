# 03 — Agents

Seven terminal agents, plus two in the browser. All of them talk to SEC09, all
of them run without permission prompts, and all of them are reconfigured from
the same settings every time the container starts. Pick whichever you like;
they share the same files in `/workspace`.

| Command | Agent | API it uses |
|---|---|---|
| `claude` | Claude Code 2.1.319 | Anthropic Messages (`/v1/messages`, which vLLM serves) |
| `opencode` | opencode 1.18.30 (also the Chat page) | OpenAI chat completions |
| `qwen` | Qwen Code 0.27.0 | OpenAI chat completions |
| `pi` | pi 0.85.1 | OpenAI chat completions |
| `crush` | Crush 0.100.0 | OpenAI chat completions |
| `goose session` | Goose 1.57.0 | OpenAI chat completions |
| `codex` | Codex 0.167.0 — experimental | OpenAI Responses (`/v1/responses`); works only if SEC09's vLLM serves it |

In the browser: **Chat** (`:4096`) is opencode's web UI, the full agent with
the same tools as the terminal version. **Kilo Code** is the agent panel in VS
Code (the Kilo icon in the left bar). See [07-WEB-IDE.md](07-WEB-IDE.md).

`yolo agents` lists them with versions.

## Running one without a prompt

Useful in scripts and for the bot:

```bash
opencode run "explain src/main.c"
claude -p "add a unit test for parse()"
qwen -p "..."
pi -p "..."
crush run -q "..."
goose run -t "..." --no-session
codex exec "..."
```

## How they are configured

`yolo configure` runs on every container start (and by hand). It reads the
settings (see [09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md)), asks SEC09 which
models it serves, and writes:

| Agent | Files |
|---|---|
| opencode | `~/.config/opencode/opencode.json` (provider `vllm`, `permission: allow`, context and output limits, reasoning variants) |
| Claude Code | `~/.claude/settings.json` (`ANTHROPIC_BASE_URL`, model for every role, `bypassPermissions`, context window), `~/.claude.json` (onboarding done, `/workspace` trusted) |
| Qwen Code | `~/.qwen/settings.json` (OpenAI provider, `approvalMode: yolo`, no usage statistics) |
| pi | `~/.pi/agent/settings.json`, `~/.pi/agent/models.json` |
| Crush | `~/.config/crush/crush.json` (OpenAI-compatible provider, tools allowed, no metrics) |
| Goose | `~/.config/goose/config.yaml` (OpenAI provider, `GOOSE_MODE: auto`, developer extension) |
| Codex | `~/.codex/config.toml` (provider `vllm`, `wire_api = responses`, `approval_policy = never`, full access) |
| Kilo Code | `~/.config/kilo/kilo.json` (a copy of the opencode config) and VS Code settings |

Each command in `/opt/yolo/bin` is a small wrapper that loads
`~/.yolo/env/<agent>.env` (keys and base URLs) and then runs the real binary
from `/opt/agents`. **These files are rewritten on every start**: change
settings in `.env` or the fleet repo, not in the files.

The API key each agent sends is `yolo-<person>` (from `YOLO_PERSON`), unless
`VLLM_API_KEY` is set to something other than `local`. vLLM ignores it; the lab
monitor uses it to show usage per person.

## Instructions

Every agent reads the same instructions, `~/.yolo/AGENTS.md`, built from:

1. `/opt/yolo/AGENTS.md` in the image: the lab facts (no internet, where files
   go, how to open pull requests).
2. `AGENTS.md` in the fleet repo, for everyone.
3. `people/<name>.md` in the fleet repo, for one person.

It is linked as `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.qwen/QWEN.md`,
`~/.pi/agent/AGENTS.md`, `~/.config/goose/.goosehints`,
`~/.config/opencode/AGENTS.md` and `~/.config/kilo/AGENTS.md`. Project-level
`AGENTS.md` / `CLAUDE.md` files in a repository work as usual.

## Skills

Skills are folders with a `SKILL.md` that teach an agent a task. The image has a
library, but only enabled skills are visible to agents, so they do not get
cluttered.

```bash
yolo skills                 # the library; ★ = enabled for you
yolo skills search pdf
yolo skills enable pdf      # linked into every agent's skills folder
yolo skills enable pack:cpp
yolo skills disable pdf
yolo skills enable pdf --project   # copy into this repo instead, for everyone on it
```

Enabled by default: `yolo-airgap`, `yolo-gitea`, `skill-creator`. The fleet
repo can add more for everyone or one person. Packs: `core`, `cpp`, `reverse`,
`web`, `docs`, `tools` (`yolo skills packs`). See [14-LAB.md](14-LAB.md).

## YOLO mode

No agent asks before running a command or editing a file. That is the point of
the container, and it is why the container is locked down
([10-SECURITY.md](10-SECURITY.md)). Commit your work to git often.

## Offline switches

The image sets each agent's switches for update checks, telemetry, model-list
downloads and similar (`/etc/yolo/defaults.env`). `compose.yaml` also maps a few
known telemetry hosts to `0.0.0.0` so any call that slips through fails at once
instead of waiting for a timeout.
