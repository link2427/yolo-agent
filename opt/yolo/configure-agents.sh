#!/usr/bin/env bash
#
# Point opencode, pi, goose and aider at an OpenAI-compatible local endpoint
# (vLLM by default; LM Studio alternative), always in YOLO mode — no
# permission prompts ever — and refresh the skills farm. Idempotent.
#
# Required env:
#   VLLM_BASE_URL=http://<host>:<port>/v1     (vLLM default; or LM_STUDIO_BASE_URL=...)
#   VLLM_MODEL=<model id served by the endpoint>
# Optional env:
#   VLLM_API_KEY=<key>                        (most local servers need none)
#   LM_STUDIO_MODEL=...                       (only with LM_STUDIO_BASE_URL)
#
# YOLO settings baked here (never ask permission):
#   opencode   "permission": "allow"          (auto-approve every tool)
#   pi         no permission system; defaultProjectTrust "always" silences trust prompts
#   goose      GOOSE_MODE: auto                 (fully autonomous)
#   aider      yes-always: true                 (always say yes)
#   prime-agent  no permission-prompt system (pi lineage); autonomous headless
#                mode via --autonomous; telemetry disabled
#   (all of the above are also the baked image defaults — see /opt/yolo)
#
# Secrets policy: the only secret is VLLM_API_KEY. opencode reads it from the
# environment ({env:VLLM_API_KEY}); pi from models.json (mode 600); goose and
# aider from OPENAI_API_KEY env (goose ignores keys in its config file).
#
set -euo pipefail
umask 077
: "${HOME:=/home/agent}"

LM_STUDIO_BASE_URL="${LM_STUDIO_BASE_URL:-}"
VLLM_BASE_URL="${VLLM_BASE_URL:-}"

if [[ -n "$LM_STUDIO_BASE_URL" ]]; then
  BASE_URL="$LM_STUDIO_BASE_URL"
  OC_PROVIDER="lm-studio"
  MODEL="${LM_STUDIO_MODEL:-${VLLM_MODEL:-}}"
elif [[ -n "$VLLM_BASE_URL" ]]; then
  BASE_URL="$VLLM_BASE_URL"
  OC_PROVIDER="openai"
  MODEL="${VLLM_MODEL:-}"
else
  echo "usage: VLLM_BASE_URL=... VLLM_MODEL=... [VLLM_API_KEY=...] $(basename "$0")" >&2
  echo "   or: LM_STUDIO_BASE_URL=... [LM_STUDIO_MODEL=...] $(basename "$0")" >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"
[[ -n "$MODEL" ]] || { echo "ERROR: set VLLM_MODEL (or LM_STUDIO_MODEL) to the model id served by $BASE_URL" >&2; exit 1; }
API_KEY="${VLLM_API_KEY:-local}"

OPENAI_HOST="$BASE_URL"
case "$OPENAI_HOST" in
  */v1/chat/completions) OPENAI_HOST="${OPENAI_HOST%/v1/chat/completions}" ;;
  */v1)                  OPENAI_HOST="${OPENAI_HOST%/v1}" ;;
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
MODEL_ENTRY_JSON="{ \"id\": \"$MODEL\", \"name\": \"$MODEL\""
LIMIT_JSON=""
if [[ -n "$VLLM_CONTEXT" ]]; then
  MODEL_ENTRY_JSON+=", \"contextWindow\": $VLLM_CONTEXT, \"maxTokens\": 32768"
  LIMIT_JSON="\"limit\": { \"context\": $VLLM_CONTEXT, \"output\": 32768 }"
fi
MODEL_ENTRY_JSON+=" }"

mkdir -p "$HOME/.config/opencode" "$HOME/.pi/agent" "$HOME/.config/goose" "$HOME/.prime/agent"
chmod 700 "$HOME/.config/opencode" "$HOME/.pi/agent" "$HOME/.config/goose" "$HOME/.prime/agent"

# --- opencode: YOLO + endpoint ----------------------------------------------
cat > "$HOME/.config/opencode/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "permission": "allow",
  "model": "$MODEL",
  "provider": {
    "$OC_PROVIDER": {
      "options": {
        "baseURL": "$BASE_URL",
        "apiKey": "{env:VLLM_API_KEY}"
      },
      "models": {
        "$MODEL": { $LIMIT_JSON }
      }
    }
  }
}
EOF

# --- pi: never trust-prompt, telemetry off, endpoint -------------------------
cat > "$HOME/.pi/agent/settings.json" <<EOF
{
  "defaultProjectTrust": "always",
  "enableInstallTelemetry": false
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
        "supportsReasoningEffort": false
      },
      "models": [
        $MODEL_ENTRY_JSON
      ]
    }
  }
}
EOF

# --- prime-agent: endpoint + telemetry off (pi-lineage models.json schema) ---
cat > "$HOME/.prime/agent/models.json" <<EOF
{
  "providers": {
    "vllm": {
      "baseUrl": "$BASE_URL",
      "api": "openai-completions",
      "apiKey": "$API_KEY",
      "authHeader": true,
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        $MODEL_ENTRY_JSON
      ]
    }
  }
}
EOF
cat > "$HOME/.prime/agent/settings.json" <<EOF
{
  "telemetry": {
    "enabled": false
  }
}
EOF

# --- goose: autonomous mode + endpoint (key stays in env) --------------------
# With VLLM_CONTEXT set, a custom provider file carries the real context
# window (goose's built-in catalog defaults Qwen-class ids to 128k).
GOOSE_PROVIDER_NAME="openai"
if [[ -n "$VLLM_CONTEXT" ]]; then
  GOOSE_PROVIDER_NAME="vllm"
  mkdir -p "$HOME/.config/goose/custom_providers"
  cat > "$HOME/.config/goose/custom_providers/vllm.json" <<EOF
{
  "name": "vllm",
  "engine": "openai",
  "display_name": "vLLM (local)",
  "description": "Local vLLM endpoint with explicit context window",
  "api_key_env": "OPENAI_API_KEY",
  "base_url": "$BASE_URL/chat/completions",
  "models": [
    { "name": "$MODEL", "context_limit": $VLLM_CONTEXT }
  ],
  "supports_streaming": true,
  "requires_auth": false
}
EOF
fi
cat > "$HOME/.config/goose/config.yaml" <<EOF
GOOSE_MODE: auto
GOOSE_PROVIDER: $GOOSE_PROVIDER_NAME
GOOSE_MODEL: $MODEL
OPENAI_HOST: $OPENAI_HOST
EOF

# --- aider: always yes + endpoint (key from OPENAI_API_KEY env) --------------
# Context window override via a model metadata file (aider's catalog also
# defaults Qwen-class ids to 128k).
AIDER_METADATA_LINE=""
if [[ -n "$VLLM_CONTEXT" ]]; then
  AIDER_METADATA_LINE="model-metadata-file: $HOME/.aider-model-metadata.json"
  cat > "$HOME/.aider-model-metadata.json" <<EOF
{
  "$MODEL": {
    "context_window": $VLLM_CONTEXT,
    "max_tokens": 32768
  }
}
EOF
fi
cat > "$HOME/.aider.conf.yml" <<EOF
yes-always: true
model: $MODEL
openai-api-base: $BASE_URL
no-show-model-warnings: true
$AIDER_METADATA_LINE
EOF

chmod 600 "$HOME/.aider.conf.yml" "$HOME/.config/goose/config.yaml" "$HOME/.prime/agent/models.json" "$HOME/.prime/agent/settings.json" \
  "$HOME/.pi/agent/models.json" "$HOME/.pi/agent/settings.json"
[[ -n "$VLLM_CONTEXT" ]] && chmod 600 "$HOME/.aider-model-metadata.json" "$HOME/.config/goose/custom_providers/vllm.json"

# --- skills farm refresh (idempotent; also fixes reused home volumes) --------
/opt/yolo/make-skill-farm.sh

echo "Configured all agents for $BASE_URL (model: $MODEL) — YOLO mode, no permission prompts"
echo "  opencode -> ~/.config/opencode/opencode.json   (run: opencode, then /models)"
echo "  pi       -> ~/.pi/agent/{settings,models}.json (run: pi --model vllm/$MODEL)"
echo "  goose    -> ~/.config/goose/config.yaml        (run: goose)"
echo "  aider    -> ~/.aider.conf.yml                  (run: aider)"
echo "  prime-agent -> ~/.prime/agent/{models,settings}.json (run: prime-agent)"
echo "  skills   -> ~/.agents/skills ($(find "$HOME/.agents/skills" -maxdepth 1 -mindepth 1 | wc -l) skills)"
if [[ -n "$VLLM_CONTEXT" ]]; then
  echo "  context  -> $VLLM_CONTEXT tokens (must match vLLM --max-model-len)"
  echo "  goose    -> uses the custom 'vllm' provider; if it doesn't auto-select,"
  echo "             run: goose session start --provider vllm"
fi
echo "Note: if your endpoint requires auth, export OPENAI_API_KEY=... (goose/aider)"
echo "and set VLLM_API_KEY in yolo.env (opencode/pi)."
