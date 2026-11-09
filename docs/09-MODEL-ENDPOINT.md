# 09 — The model endpoint

All agents use SEC09, the lab's vLLM server at `192.168.1.101:8000`.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `VLLM_BASE_URL` | `http://192.168.1.101:8000/v1` | OpenAI-style base URL. Claude Code gets the same host without `/v1`. |
| `VLLM_MODEL` | empty | model id; empty = the first model SEC09 serves |
| `VLLM_API_KEY` | `local` | `local` = send `yolo-<person>` (for usage per person); anything else is sent as is |
| `VLLM_REASONING_EFFORT` | `xhigh` | `off`, `low`, `medium`, `xhigh` for reasoning models |
| `VLLM_CONTEXT` | empty | context window in tokens; empty = `max_model_len` from `/v1/models`, else 131072 |
| `VLLM_VISION_MODELS` | `auto` | models that accept images: `auto` (all) or a space-separated list |

Where to set them, later wins:

1. `/etc/yolo/defaults.env` in the image (the defaults above).
2. `fleet.env` in the fleet repo — for everyone.
3. `people/<name>.env` in the fleet repo — for one person.
4. The person's `.env` next to `compose.yaml`.

An empty value in `.env` does not override. After a change: `yolo sync` (fleet
repo) or `docker compose restart` (`.env`). Values with spaces need quotes in
the fleet files (`GIT_NAME="YOLO Agent"`): they are read by bash.

## Model discovery

`yolo configure` calls `GET $VLLM_BASE_URL/models`, caches the answer in
`~/.yolo/models.json`, and writes every served model into each agent's config,
with the chosen one as default. The output limit is a quarter of the context,
between 4096 and 32768 tokens. If SEC09 does not answer, the cached list is used
and the agents are still configured.

```bash
yolo models     # what SEC09 serves; ★ = the default
yolo status     # endpoint, model, reachability
```

## Changing the model for everyone

Put `VLLM_MODEL=<id>` in the fleet repo's `fleet.env` and push. Each container
picks it up on its next start or `yolo sync`. For one person, use
`people/<name>.env`.

## Through the lab monitor

The monitor (`compose.lab.yaml`, port 4000) is a proxy for SEC09 that records
every request. To have a person's usage show up there:

```
VLLM_BASE_URL=http://<lab-host>:4000/v1
```

in their `.env` or in `fleet.env` for everyone. The proxy passes OpenAI and
Anthropic requests through unchanged (streaming included), can map aliases to
real model ids, and adds the aliases to `/v1/models`. See
[14-LAB.md](14-LAB.md).

## Requirements on the vLLM side

- `/v1/chat/completions` for most agents, `/v1/messages` for Claude Code,
  `/v1/responses` for Codex.
- A tool-calling parser enabled for the served model, or agents cannot run
  tools.
- If vLLM was started with `--api-key`, set `VLLM_API_KEY` to it (and
  `UPSTREAM_API_KEY` in the lab `.env` for the monitor).
