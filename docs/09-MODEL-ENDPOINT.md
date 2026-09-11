# 09 — Model endpoint

Every agent in every image talks to **one** OpenAI-compatible endpoint. Set two
variables and the agent configs are written for you on first launch.

## Configure

Copy the env template for your flavor and edit it:

```bash
cp config/base.env.example config/base.env          # base
cp config/cpp.env.example config/cpp.env            # C/C++
cp config/reverse.env.example config/reverse.env    # reverse engineering
```

The values that matter:

| Variable | Meaning | Example |
|---|---|---|
| `VLLM_BASE_URL` | OpenAI-compatible base URL, including `/v1` | `http://192.168.1.50:8000/v1` |
| `VLLM_MODEL` | exact model id the server serves | `Qwen/Qwen3.8-27B` |
| `VLLM_CONTEXT` | context window in tokens; must match the server's `--max-model-len` | `262144` |
| `VLLM_REASONING_EFFORT` | `off`, `low`, `medium`, or `xhigh` | `xhigh` |
| `VLLM_API_KEY` | key, if your server requires one | `local` |

Confirm the endpoint answers before you debug the container:

```bash
curl "$VLLM_BASE_URL/models"
```

Take the model id from that response — it must match `VLLM_MODEL` exactly,
including any `owner/` prefix.

## What gets written, and when

`/opt/yolo/configure-agents.sh` writes all three agent configs. `~/.bashrc` runs
it automatically on an interactive launch when **both** `VLLM_BASE_URL` and
`VLLM_MODEL` are set **and** the opencode config does not yet have a `provider`
key. So the normal flow is: edit the env file, start the container, done.

To re-run it manually after changing the env file:

```bash
/opt/yolo/configure-agents.sh
```

It is idempotent and safe to re-run. The files it writes:

| Agent | File | Key settings |
|---|---|---|
| opencode | `~/.config/opencode/opencode.json` | `"permission": "allow"`, a custom `vllm` provider, `enabled_providers: ["vllm"]`, model limits and reasoning variants |
| pi | `~/.pi/agent/settings.json` + `~/.pi/agent/models.json` | `defaultProjectTrust: "always"`, telemetry off, `qwen-chat-template` thinking format, context window |
| DeepSeek Harness | `~/.dsh/settings.yaml` | custom `vllm` provider, reasoning effort map, empty DeepSeek cloud provider |

All three are written with mode `600`.

## Reasoning effort

`VLLM_REASONING_EFFORT` accepts:

| Value | Behavior |
|---|---|
| `xhigh` | default; maximum reasoning. `high` is accepted as an alias |
| `medium` | balanced |
| `low` | minimal reasoning |
| `off` | thinking disabled (instruct mode) |

It is wired into every agent: opencode gets a default plus per-level variants,
pi gets `defaultThinkingLevel` and an in-session `/effort` command, and DeepSeek
Harness gets a `reasoningEfforts` map.

Change it per session rather than rebuilding:

- **pi** — `/effort` inside the session
- **opencode** — cycle the model variant in-session

An unrecognized value logs a warning and falls back to `xhigh` rather than
failing.

## Context window

`VLLM_CONTEXT` is worth setting explicitly. Agent catalogs often assume 128k for
Qwen-class model ids even when the server was started with a much larger
`--max-model-len`, which makes the agent truncate or compact far too early.

Set it to the value the server was actually started with. A mismatch is not
detected automatically — the agent will simply behave as though the smaller or
larger window is real. When it is set, all three agents receive it
(opencode `limit.context`, pi `contextWindow`, DeepSeek Harness
`contextWindow`). When it is unset, each agent falls back to its catalog
default.

## LM Studio instead of vLLM

LM Studio's OpenAI-compatible server works the same way. Comment out the
`VLLM_*` lines and set:

```bash
LM_STUDIO_BASE_URL=http://192.168.1.50:1234/v1
LM_STUDIO_MODEL=your-loaded-model-id
```

opencode then uses an `lmstudio` provider instead of `vllm`. `VLLM_API_KEY` and
the other variables keep working as documented.

## Do not set cloud keys

Leave `DEEPSEEK_API_KEY` and `OPENAI_API_KEY` unset:

- The host has no internet, so a cloud call cannot succeed anyway.
- Setting them puts cloud models back into the agent pickers, which is
  confusing when the only reachable models are local.

`configure-dsh.sh` writes `llm-deepseek` with an empty model list on purpose.

## Troubleshooting

**Agents start but cannot reach a model.** Check that the env file for *your
flavor* is populated — the three flavors use separate env files and separate
home volumes, so configuring `config/base.env` does nothing for
`compose.cpp.yaml`. Then verify the config was actually written:

```bash
jq -e '.provider.vllm' ~/.config/opencode/opencode.json
```

**The config was regenerated but nothing changed.** `configure-agents.sh` only
runs automatically when the opencode config lacks a `provider` key. Run it by
hand, or delete the flavor's home volume to start clean.

**The endpoint is unreachable from inside the container.** Confirm the host name
resolves (use an IP if DNS is not available in the container) and that the model
server binds an address the container can reach — `127.0.0.1` on the host is not
reachable from inside a container.
