# yolo-agent profile
umask 077
export EDITOR=vim

# Auto-configure every agent when VLLM_BASE_URL/VLLM_MODEL are set in yolo.env
# but the endpoint configs haven't been written yet. Edit yolo.env on the host,
# launch, and everything is ready — no manual step.
if [[ -n "${VLLM_BASE_URL:-}" ]] && [[ -n "${VLLM_MODEL:-}" ]] \
   && ! grep -q '"provider"' "$HOME/.config/opencode/opencode.json" 2>/dev/null; then
  echo ">> yolo-agent: configuring agents for $VLLM_BASE_URL ..."
  /opt/yolo/configure-agents.sh
fi

# Auto-configure git for Gitea when GITEA_HOST is set in yolo.env.
# Re-runs each launch: yolo.env is the source of truth, so changing the token
# or switching token<->SSH mode applies on the next launch.
if [[ -n "${GITEA_HOST:-}" ]]; then
  echo ">> yolo-agent: configuring git for $GITEA_HOST ..."
  /opt/yolo/configure-git.sh || true
fi

if [[ -t 0 ]]; then
  echo
  echo "yolo-agent — opencode | pi | goose | aider | prime-agent | dsh | OpenHands"
  echo "  docs:   /opt/yolo/README.md   security: /opt/yolo/SECURITY.md"
  echo "  config: VLLM_BASE_URL/VLLM_MODEL in yolo.env -> auto-configured on launch"
  echo "  web:    code-server :8080 | terminal :7681 | OpenHands :3000 | DeepSeek Harness :3080"
  echo
fi
