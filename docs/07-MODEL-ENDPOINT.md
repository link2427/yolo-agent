# 07 — Model endpoint (vLLM / LM Studio)

Every agent talks to one OpenAI-compatible endpoint, configured in two lines
of `yolo.env`:

```bash
VLLM_BASE_URL=http://192.168.1.50:8000/v1   # your server + /v1 path
VLLM_MODEL=Qwen/Qwen3-Coder-30B-AWQ         # model id served by that endpoint
```

On launch, `/opt/yolo/configure-agents.sh` writes each agent's config:

| Agent | Config written |
|-------|----------------|
| opencode | `~/.config/opencode/opencode.json` (provider + model + `permission: allow`) |
| pi | `~/.pi/agent/models.json` (provider `vllm`, `api: openai-completions`) |
| goose | `~/.config/goose/config.yaml` (`OPENAI_HOST` derived from the URL) |
| aider | `~/.aider.conf.yml` (`model`, `openai-api-base`) |
| prime-agent | `~/.prime/agent/models.json` (same schema as pi) |

## Auth

- Most local vLLM / LM Studio servers need no key. Leave
  `VLLM_API_KEY=local` (safe placeholder) and `OPENAI_API_KEY=local`.
- If the server requires a token: set the real value in `VLLM_API_KEY`
  (opencode/pi/prime-agent read it) and `OPENAI_API_KEY` (goose/aider read
  it). Never bake keys into the image.

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

The configurator sets `supportsDeveloperRole: false` and
`supportsReasoningEffort: false` for the local provider — the safe defaults
for vLLM / SGLang / LM Studio (many don't understand the `developer` role).

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
