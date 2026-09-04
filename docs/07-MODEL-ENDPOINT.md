# 07 — Model endpoint (vLLM / LM Studio)

Every agent talks to one OpenAI-compatible endpoint, configured in two lines
of `yolo.env`:

```bash
VLLM_BASE_URL=http://192.168.1.50:8000/v1   # your server + /v1 path
VLLM_MODEL=Qwen/Qwen3.8-27B                 # model id served by that endpoint
VLLM_REASONING_EFFORT=xhigh                 # off | low | medium | xhigh
```

On launch, `/opt/yolo/configure-agents.sh` writes each agent's config:

| Agent | Config written |
|-------|----------------|
| opencode | `~/.config/opencode/opencode.json` (custom `vllm` provider only) |
| pi | `~/.pi/agent/models.json` (provider `vllm`, `api: openai-completions`) |
| goose | custom provider `vllm` only (`custom_providers/vllm.json`) |
| aider | `~/.aider.conf.yml` (`model`, `openai-api-base`, reasoning extra_body) |
| prime-agent | `~/.prime/agent/models.json` (same schema as pi) |
| OpenHands | `~/.openhands/agent_settings.json` (same VLLM_* values) |

## Auth

- Most local vLLM / LM Studio servers need no key. Leave
  `VLLM_API_KEY=local`. Do not set `OPENAI_API_KEY`; that unlocks OpenAI's
  cloud catalog in pi and prime-agent.
- If the server requires a token: set it in `VLLM_API_KEY` only. Never bake
  keys into the image.

## LM Studio alternative

```bash
# comment the VLLM_* lines, uncomment:
LM_STUDIO_BASE_URL=http://192.168.1.50:1234/v1
LM_STUDIO_MODEL=your-loaded-model-id
```

## Find your model ids

```bash
curl http://192.168.1.50:8000/v1/models   # list served model ids
```

## Compatibility

The configurator sets `supportsDeveloperRole: false` so local vLLM / SGLang /
LM Studio servers get a `system` prompt instead of the `developer` role.

Qwen3.8 thinking is on by default. `supportsReasoningEffort` is true, and
pi/prime-agent use `thinkingFormat: qwen-chat-template` so vLLM receives
`chat_template_kwargs.enable_thinking` plus `reasoning_effort`.

## Reasoning effort

```bash
VLLM_REASONING_EFFORT=xhigh   # off | low | medium | xhigh
```

Qwen3.8-27B official `reasoning_effort` values are `xhigh` (default), `medium`,
and `low`. Thinking is on by default. `off` is instruct mode
(`enable_thinking: false`), not a Qwen effort string.

| Agent | How to change level |
|-------|---------------------|
| opencode | variants `low` / `medium` / `xhigh` (cycle with `variant_cycle`) |
| pi / prime-agent | `/effort` or `--thinking <level>` |
| goose | `OPENAI_REASONING_EFFORT` in goose config |
| aider | `reasoning-effort` plus vLLM `extra_body` |
| OpenHands | `llm.reasoning_effort` in agent_settings.json |

Confirm the served model id with `curl $VLLM_BASE_URL/models`.

## Context window (128k → 256k)

Agents' built-in model catalogs (models.dev / litellm) often default
Qwen-class ids to **128k** even when your vLLM server serves more. Override in
one place:

```bash
VLLM_CONTEXT=262144   # yolo.env — must match vLLM's --max-model-len
```

The configurator then writes the explicit window into every agent:
opencode (`limit.context`), pi & prime-agent (`contextWindow` + `maxTokens`),
goose (custom `vllm` provider with `context_limit`; if it doesn't auto-select,
`goose session start --provider vllm`), aider (`model-metadata-file` with
`context_window`). Leave `VLLM_CONTEXT` empty to use catalog defaults.

## Reconfigure any time

`yolo.env` is re-read each launch, so editing it and relaunching re-applies
everywhere. You can also run the configurator by hand inside the container:
`/opt/yolo/configure-agents.sh` (idempotent).
