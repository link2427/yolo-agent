#!/usr/bin/env bash
#
# Point opencode, pi, and DeepSeek Harness at an OpenAI-compatible local
# endpoint (vLLM by default; LM Studio alternative), always in YOLO mode — no
# permission prompts ever. Idempotent, and safe to re-run on a reused home
# volume.
#
# Required env:
#   VLLM_BASE_URL=http://<host>:<port>/v1     (vLLM default; or LM_STUDIO_BASE_URL=...)
#   VLLM_MODEL=<model id served by the endpoint>
# Optional env:
#   VLLM_API_KEY=<key>                        (most local servers need none)
#   VLLM_REASONING_EFFORT=xhigh               (off|low|medium|xhigh; Qwen3.8)
#   VLLM_CONTEXT=<tokens>                     (must match vLLM --max-model-len)
#   LM_STUDIO_MODEL=...                       (only with LM_STUDIO_BASE_URL)
#
# YOLO settings baked here (never ask permission):
#   opencode  "permission": "allow"        auto-approve every tool
#   pi        no permission system; defaultProjectTrust "always" silences the
#             trust prompt
#   dsh       harness runs non-interactively against the local endpoint
#
# Secrets policy: the only secret is VLLM_API_KEY. opencode reads it from the
# environment ({env:VLLM_API_KEY}); pi reads it from models.json (mode 600).
#
set -euo pipefail
umask 077
: "${HOME:=/home/agent}"

LM_STUDIO_BASE_URL="${LM_STUDIO_BASE_URL:-}"
VLLM_BASE_URL="${VLLM_BASE_URL:-}"

if [[ -n "$LM_STUDIO_BASE_URL" ]]; then
  BASE_URL="$LM_STUDIO_BASE_URL"
  OC_PROVIDER="lmstudio"
  MODEL="${LM_STUDIO_MODEL:-${VLLM_MODEL:-}}"
elif [[ -n "$VLLM_BASE_URL" ]]; then
  BASE_URL="$VLLM_BASE_URL"
  OC_PROVIDER="vllm"
  MODEL="${VLLM_MODEL:-}"
else
  echo "usage: VLLM_BASE_URL=... VLLM_MODEL=... [VLLM_API_KEY=...] $(basename "$0")" >&2
  echo "   or: LM_STUDIO_BASE_URL=... [LM_STUDIO_MODEL=...] $(basename "$0")" >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"
[[ -n "$MODEL" ]] || { echo "ERROR: set VLLM_MODEL (or LM_STUDIO_MODEL) to the model id served by $BASE_URL" >&2; exit 1; }
API_KEY="${VLLM_API_KEY:-local}"

# Qwen3.8-27B official reasoning_effort values: xhigh (default), medium, low.
# `off` is not a Qwen effort level; it sets enable_thinking=false (instruct mode).
# `high` is accepted as an alias for xhigh.
VLLM_REASONING_EFFORT="${VLLM_REASONING_EFFORT:-xhigh}"
case "$VLLM_REASONING_EFFORT" in
  high) VLLM_REASONING_EFFORT="xhigh" ;;
  off|low|medium|xhigh) ;;
  *) echo "WARN: VLLM_REASONING_EFFORT='$VLLM_REASONING_EFFORT' is not off|low|medium|xhigh; using xhigh" >&2
     VLLM_REASONING_EFFORT="xhigh" ;;
esac

# --- context window override -------------------------------------------------
# If VLLM_CONTEXT is set (e.g. 262144 for a 256k model), every agent config
# gets an explicit context window. Must match what the vLLM server was started
# with (--max-model-len). Without it, agents use their built-in catalog
# defaults, which are often 128k for Qwen-class ids.
VLLM_CONTEXT="${VLLM_CONTEXT:-}"
case "$VLLM_CONTEXT" in
  ""|[0-9]*) ;;
  *) echo "WARN: VLLM_CONTEXT='$VLLM_CONTEXT' is not numeric; ignoring" >&2; VLLM_CONTEXT="" ;;
esac

MODEL_ENTRY_JSON="{ \"id\": \"$MODEL\", \"name\": \"$MODEL\", \"reasoning\": true, \"thinkingLevelMap\": { \"off\": \"off\", \"minimal\": null, \"low\": \"low\", \"medium\": \"medium\", \"high\": \"xhigh\", \"xhigh\": \"xhigh\", \"max\": null }"
LIMIT_JSON=""
if [[ -n "$VLLM_CONTEXT" ]]; then
  MODEL_ENTRY_JSON+=", \"contextWindow\": $VLLM_CONTEXT, \"maxTokens\": 32768"
  LIMIT_JSON="\"limit\": { \"context\": $VLLM_CONTEXT, \"output\": 32768 },"
fi
MODEL_ENTRY_JSON+=" }"
OC_MODEL_JSON="${LIMIT_JSON}
          \"reasoning\": true,
          \"options\": {
            \"reasoningEffort\": \"$VLLM_REASONING_EFFORT\"
          },
          \"variants\": {
            \"low\": { \"reasoningEffort\": \"low\" },
            \"medium\": { \"reasoningEffort\": \"medium\" },
            \"xhigh\": { \"reasoningEffort\": \"xhigh\" }
          }"

mkdir -p "$HOME/.config/opencode" "$HOME/.pi/agent" "$HOME/.dsh"
chmod 700 "$HOME/.config/opencode" "$HOME/.pi/agent" "$HOME/.dsh"

# --- opencode: YOLO + endpoint ----------------------------------------------
cat > "$HOME/.config/opencode/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "permission": "allow",
  "autoupdate": false,
  "share": "disabled",
  "enabled_providers": ["$OC_PROVIDER"],
  "model": "$OC_PROVIDER/$MODEL",
  "small_model": "$OC_PROVIDER/$MODEL",
  "provider": {
    "$OC_PROVIDER": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "vLLM (local)",
      "options": {
        "baseURL": "$BASE_URL",
        "apiKey": "{env:VLLM_API_KEY}"
      },
      "models": {
        "$MODEL": {
          $OC_MODEL_JSON
        }
      }
    }
  }
}
EOF

# --- pi: never trust-prompt, telemetry off, endpoint -------------------------
PI_THINKING="$VLLM_REASONING_EFFORT"
cat > "$HOME/.pi/agent/settings.json" <<EOF
{
  "defaultProjectTrust": "always",
  "enableInstallTelemetry": false,
  "defaultProvider": "vllm",
  "defaultModel": "$MODEL",
  "defaultThinkingLevel": "$PI_THINKING"
}
EOF
cat > "$HOME/.pi/agent/models.json" <<EOF
{
  "providers": {
    "vllm": {
      "baseUrl": "$BASE_URL",
      "api": "openai-completions",
      "apiKey": "$API_KEY",
      "authHeader": true,
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": true,
        "thinkingFormat": "qwen-chat-template"
      },
      "models": [
        $MODEL_ENTRY_JSON
      ]
    }
  }
}
EOF

# --- DeepSeek Harness: same endpoint, local only -----------------------------
# Do NOT set DEEPSEEK_API_KEY: that would put DeepSeek cloud models back in the
# picker, and there is no internet on the host anyway.
/opt/yolo/configure-dsh.sh

chmod 600 "$HOME/.pi/agent/models.json" "$HOME/.pi/agent/settings.json" "$HOME/.dsh/settings.yaml"

echo "Configured agents for $BASE_URL (model: $MODEL) — YOLO mode, no permission prompts"
echo "  opencode -> ~/.config/opencode/opencode.json   (run: opencode, then /models)"
echo "  pi       -> ~/.pi/agent/{settings,models}.json (run: pi --model vllm/$MODEL)"
echo "  dsh      -> ~/.dsh/settings.yaml               (run: dsh web)"
echo "  python   -> /opt/pyenv ($(python3 --version 2>&1))"
echo "  reasoning -> $VLLM_REASONING_EFFORT (Qwen3.8: off|low|medium|xhigh; pi /effort)"
if [[ -n "$VLLM_CONTEXT" ]]; then
  echo "  context  -> $VLLM_CONTEXT tokens (must match vLLM --max-model-len)"
fi
echo "Note: if your endpoint requires auth, set VLLM_API_KEY in the env file."
