# 03 — The agents

Every image ships exactly three agents: **opencode**, **pi**, and **DeepSeek
Harness** (`dsh`). All three are pre-wired for YOLO mode — no permission
prompts, ever — against the OpenAI-compatible endpoint you configure in the
flavor's env file. No cloud provider is configured in any of them.

Nothing here is hand-maintained. `/opt/yolo/configure-agents.sh` writes all
three configs from the same `VLLM_*` values, and `~/.bashrc` runs it
automatically on the first launch after you set them. Endpoint variables are in
[09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md); getting a shell inside the
container is in [02-QUICKSTART.md](02-QUICKSTART.md).

## Launching each agent

```bash
# host: interactive shell, /workspace = your project directory
docker compose run --rm agent
```

Then, inside the container:

```bash
opencode                                  # then /models to pick the served model
pi --model vllm/Qwen/Qwen3.8-27B          # or: pi, then /model
dsh web                                   # browser UI — publish it via compose, see 07-WEB-IDE.md
dsh --profile headless "inspect this repository"
```

`opencode` and `pi` are standalone binaries under `/opt/opencode` and `/opt/pi`
with symlinks in `/usr/local/bin`. `dsh` is the pnpm bin shim for
`/opt/deepseek-harness`.

## The three agents

| Agent | Command | Version | Config file | YOLO mechanism |
|---|---|---|---|---|
| opencode | `opencode` | 1.18.30 | `~/.config/opencode/opencode.json` | `"permission": "allow"` |
| pi | `pi` | 0.85.1 | `~/.pi/agent/settings.json` + `models.json` | no permission system; `defaultProjectTrust: "always"` |
| DeepSeek Harness | `dsh` / `dsh web` | 0.1.5-rc.1 | `~/.dsh/settings.yaml` | no prompt gate in this wiring; runs non-interactively against the local endpoint |

### opencode

`~/.config/opencode/opencode.json`:

- `"permission": "allow"` — every tool call is approved automatically; there is
  no confirmation step at which to deny one.
- `enabled_providers: ["vllm"]` — the provider list is narrowed to your
  endpoint, so the model picker (`/models`) shows only what your server serves.
- `model` and `small_model` are both `vllm/<VLLM_MODEL>`.
- The provider block uses `@ai-sdk/openai-compatible` with `baseURL` from
  `VLLM_BASE_URL` and `apiKey: "{env:VLLM_API_KEY}"` — the key is read from the
  environment, never written to disk.
- `autoupdate: false` and `share: "disabled"` — no update checks and no session
  upload (there is no internet route anyway).

### pi

Two files, both mode 600:

`~/.pi/agent/settings.json`

- `defaultProjectTrust: "always"` — suppresses the per-project trust prompt,
  which is the only prompt pi has.
- `enableInstallTelemetry: false`; the image also bakes `PI_OFFLINE=1`,
  `PI_SKIP_VERSION_CHECK=1`, and `PI_TELEMETRY=0`.
- `defaultProvider: "vllm"`, `defaultModel`, `defaultThinkingLevel` from
  `VLLM_REASONING_EFFORT`.

`~/.pi/agent/models.json`

- `providers.vllm` — `baseUrl`, `api: "openai-completions"`, `authHeader: true`,
  and the API key inline (which is why the file is 600 and lives only in the
  home volume).
- `compat` — `supportsDeveloperRole: false`, `supportsReasoningEffort: true`,
  `thinkingFormat: "qwen-chat-template"`.
- One model entry with `reasoning: true`, the `thinkingLevelMap`, and
  `contextWindow` / `maxTokens` when `VLLM_CONTEXT` is set.

pi has no permission system at all: there is nothing to auto-approve, no
approval dialog, and no sandbox flag. The container is the sandbox.

### DeepSeek Harness (`dsh`)

`DSH_HOME=/home/agent/.dsh` is baked into every image, so the config is
`~/.dsh/settings.yaml` and harness state and session logs persist in the same
volume.

```yaml
llm-deepseek:
  thinking: disabled
  models: []          # the cloud catalog stays empty on purpose
llm-pi-ai:
  providers:
    vllm:             # your local endpoint, OpenAI-compatible
```

- `providers.vllm` carries `baseURL`, `api: "openai-completions"`,
  `apiKeyEnv: VLLM_API_KEY`, `reasoning` from `VLLM_REASONING_EFFORT`, a
  `compat` block (`supportsDeveloperRole: false`,
  `thinkingFormat: qwen-chat-template`, `maxTokensField: max_tokens`), the model
  id, an optional `contextWindow`, and the `reasoningEfforts` map.
- `llm-deepseek` is deliberately `thinking: disabled` with `models: []`.
  **Do not set `DEEPSEEK_API_KEY`** — a cloud key puts DeepSeek models back in
  the picker, and the host has no internet route to use them on.
- The harness binds container loopback only; publishing it is covered in
  [07-WEB-IDE.md](07-WEB-IDE.md).
- `configure-dsh.sh` can be run standalone and only needs `VLLM_BASE_URL` and
  `VLLM_MODEL` in the environment.

## YOLO mode: what it actually means per agent

| Agent | What is disabled |
|---|---|
| opencode | `"permission": "allow"` auto-approves every tool call. |
| pi | No permission subsystem exists; `defaultProjectTrust: "always"` also silences the trust prompt. |
| dsh | No prompt gate in this configuration; the harness runs non-interactively against the local endpoint. |

Three things are worth being explicit about:

1. YOLO applies to *tool* decisions only. All three still run as uid 10001 in a
   container with a read-only root filesystem, all capabilities dropped, and
   `no-new-privileges`, so writes land in `/workspace`, `/home/agent`, and the
   tmpfs mounts — and nowhere else.
2. There is no undo. An agent that deletes `/workspace` is doing exactly what
   you configured it to be able to do, so point the mount at scratch data. See
   [10-SECURITY.md](10-SECURITY.md).
3. Agent configs and secrets live in the home volume. The session data, API
   key, git token, and SSH key are all readable by anything the agent runs.

## Reasoning effort and context window

Both are driven from the env file and written into all three configs:

| Variable | Meaning |
|---|---|
| `VLLM_REASONING_EFFORT` | `off`, `low`, `medium`, or `xhigh`. `high` is accepted as an alias for `xhigh`; anything else warns and falls back to `xhigh`. |
| `VLLM_CONTEXT` | Token count the agents should assume. Must match what your vLLM server was started with (`--max-model-len`). |

How each agent receives them:

| Agent | Effort | Context |
|---|---|---|
| opencode | `options.reasoningEffort` on the model entry, plus `variants.low` / `variants.medium` / `variants.xhigh` to switch in-session | `limit.context` + `limit.output` (32768), and `contextWindow` / `maxTokens` (32768) on the model entry |
| pi | `defaultThinkingLevel`, plus the model entry's `thinkingLevelMap` (`off`/`low`/`medium`/`xhigh`); switch with `/effort` | `contextWindow` + `maxTokens` (32768) on the model entry |
| dsh | `reasoning:` on the provider, plus the `reasoningEfforts` map | `contextWindow` on the model entry |

Notes:

- `off` is not a Qwen effort level. It is passed down as thinking disabled
  (vLLM's `enable_thinking=false`, i.e. instruct mode).
- Leave `VLLM_CONTEXT` unset and each agent falls back to its built-in catalog
  default — often 128k for Qwen-class model ids, even when your server serves
  more.
- Setting `VLLM_CONTEXT` higher than the server's `--max-model-len` does not
  make the server accept more; it only makes agents send requests that fail.

## Changing the model later

Edit the values on the host, then regenerate. A one-shot container already has
the flavor's env file attached, so the script reads `VLLM_*` straight from the
environment:

```bash
# host: point config/base.env (or cpp/reverse) at the new endpoint/model
docker compose run --rm agent /opt/yolo/configure-agents.sh
```

Or from inside an interactive shell:

```bash
/opt/yolo/configure-agents.sh            # idempotent; re-reads the container env
```

Per-agent shortcuts, if you only need a session-level change:

```bash
opencode                                 # /models
pi --model vllm/<model-id>               # or /model in-session
```

Two behaviours to know:

- The automatic run in `~/.bashrc` only fires when
  `~/.config/opencode/opencode.json` **has no `"provider"` key**. After the
  first successful configuration the file has one, so editing the env file
  alone does not rewrite anything — you must re-run the script as above.
- With the LM Studio alternative (`LM_STUDIO_BASE_URL` / `LM_STUDIO_MODEL`),
  opencode's provider id becomes `lmstudio` while the pi and dsh provider stays
  named `vllm` pointing at the LM Studio URL. The env file is in
  [09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md).

## Config generation and the baked defaults

`~/.bashrc`, on every launch:

```bash
# runs only if the endpoint is configured AND the opencode config has no provider yet
if [[ -n "${VLLM_BASE_URL:-}" ]] && [[ -n "${VLLM_MODEL:-}" ]] \
   && ! grep -q '"provider"' "$HOME/.config/opencode/opencode.json" 2>/dev/null; then
  /opt/yolo/configure-agents.sh
fi
```

That is the whole "first launch just works" story: copy the env template, launch,
and all three agents are pointed at your endpoint.

The files under `docker/rootfs/home/agent/` are only image defaults:

- `.config/opencode/opencode.json` — schema plus `"permission": "allow"`, no
  provider block.
- `.pi/agent/settings.json` — `defaultProjectTrust` and
  `enableInstallTelemetry` only.

They are the reason the auto-run triggers on the first launch, and they are not
what the agents use afterwards: `configure-agents.sh` overwrites both in the
volume, plus writes `models.json` and `~/.dsh/settings.yaml`. If you find an
endpoint value that differs from your env file, the config was written earlier
and the generator was not re-run.

## Config file locations

`~` is `/home/agent` — the named home volume, not a host directory.

| Path | Written by | Holds |
|---|---|---|
| `/opt/yolo/configure-agents.sh` | image (read-only) | generator for all three agents |
| `/opt/yolo/configure-dsh.sh` | image (read-only) | DeepSeek Harness config only |
| `~/.config/opencode/opencode.json` | `configure-agents.sh` | provider, model, `permission: allow`, no autoupdate/share |
| `~/.pi/agent/settings.json` | `configure-agents.sh` | trust, telemetry, default provider/model/thinking level |
| `~/.pi/agent/models.json` | `configure-agents.sh` | vLLM endpoint, API key (mode 600), model entry |
| `~/.dsh/settings.yaml` | `configure-dsh.sh` | harness provider, model, context, effort; cloud catalog empty |
| `~/.bashrc` | image | the auto-run hook above, `umask 077`, flavor env |
| `~/.gitconfig`, `~/.git-credentials`, `~/.ssh/` | `configure-git.sh` | commit identity and Gitea auth — see [08-GIT-GITEA.md](08-GIT-GITEA.md) |

Verify the wiring from inside the container:

```bash
jq -e '.permission, .model' ~/.config/opencode/opencode.json
jq -e '.defaultProjectTrust, .defaultThinkingLevel' ~/.pi/agent/settings.json
grep -E 'baseURL|^ +- id:|contextWindow' ~/.dsh/settings.yaml
```

## Where sessions and state persist

| What | Where | Survives container replacement |
|---|---|---|
| Agent configs, sessions, harness state | `/home/agent` (named volume) | Yes, as long as the volume name is unchanged |
| `dsh` profiles and session logs | `/home/agent/.dsh` (`DSH_HOME`) | Yes — same volume |
| Project files | `/workspace` (the single host mount) | Yes — it is your folder |
| Running processes, tmux sessions, `/tmp` logs | container / tmpfs | No |
| Anything written outside `/workspace` and `/home/agent` | read-only rootfs | No — the write fails |

Each flavor has its own volume, so configuring one does not configure the
others:

| Flavor | Volume | Env file |
|---|---|---|
| base | `yolo-agent-base-home-v1` | `config/base.env` |
| cpp | `yolo-agent-cpp-home-v1` | `config/cpp.env` |
| reverse | `yolo-agent-reverse-home-v1` | `config/reverse.env` |

`YOLO_HOME_VOLUME` overrides the name — set it explicitly if you want a fresh
home (agents re-configure on first launch) or want two containers to share one
configured home. Volume layout is in [01-OVERVIEW.md](01-OVERVIEW.md).

## Removed in 2.0

**goose, aider, prime-agent, and OpenHands are gone and must not be described as
present.** They were removed because:

- OpenHands never worked reliably in this container.
- The other three tripled the Python surface — separate venvs and runtimes per
  agent — for no capability that opencode, pi, and DeepSeek Harness lack.

The 147 MB skills library was dropped as well; agents now author skills in
`/workspace` instead of loading a curated set from the image.

The build gate enforces the removals: the smoke suite fails if a `goose`,
`aider`, `prime-agent`, or `openhands` binary reappears, and asserts that
`/opt/openhands`, `/opt/aider-venv`, and `~/.prime` do not exist. Any document
that still lists them is stale — see [11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md)
for what actually ships.

## Next

- [07-WEB-IDE.md](07-WEB-IDE.md) — code-server, ttyd/tmux, and the Harness UI
- [09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md) — the endpoint variables in full
- [12-TROUBLESHOOTING.md](12-TROUBLESHOOTING.md) — when an agent will not start
