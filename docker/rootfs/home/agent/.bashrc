# yolo-agent profile
umask 077
export EDITOR=vim

# Flavor-specific environment (JAVA_HOME/PATH for the reverse-engineering image).
if [[ -r /opt/yolo/toolchain-env.sh ]]; then
  # shellcheck source=/dev/null
  . /opt/yolo/toolchain-env.sh
fi

# Python: /opt/pyenv (Python 3.11) is already first on PATH and VIRTUAL_ENV is
# baked into the image, so `python3` is the environment with all the packages.
# The system interpreter at /usr/bin/python3 is the same 3.11 build.

# Auto-configure the agents when VLLM_BASE_URL/VLLM_MODEL are set in the env
# file but the endpoint configs have not been written yet. Edit the env file on
# the host, launch, and everything is ready — no manual step.
if [[ -n "${VLLM_BASE_URL:-}" ]] && [[ -n "${VLLM_MODEL:-}" ]] \
   && ! grep -q '"provider"' "$HOME/.config/opencode/opencode.json" 2>/dev/null; then
  echo ">> yolo-agent: configuring agents for $VLLM_BASE_URL ..."
  /opt/yolo/configure-agents.sh
fi

# Auto-configure git for Gitea when GITEA_HOST is set. Re-runs each launch:
# the env file is the source of truth, so changing the token or switching
# token<->SSH mode applies on the next launch.
if [[ -n "${GITEA_HOST:-}" ]]; then
  echo ">> yolo-agent: configuring git for $GITEA_HOST ..."
  /opt/yolo/configure-git.sh || true
fi

if [[ -t 0 ]]; then
  echo
  echo "yolo-agent — opencode | pi | dsh"
  case "${YOLO_FLAVOR:-base}" in
    cpp)
      echo "  c++:    cmake + ninja + clang + gcc; mingw-w64 cross -> 64-bit Windows PE"
      echo "          helper: cpp-build.sh <dir> [linux|windows|both]"
      ;;
    reverse)
      echo "  reverse: pyinstxtractor-ng | pycdc/pycdas | jadx | radare2 | ghidra-headless"
      echo "          guide:  /opt/yolo/docs/06-REVERSE-ENGINEERING.md"
      ;;
  esac
  echo "  python: $(python3 --version 2>&1) at /opt/pyenv"
  echo "  docs:   /opt/yolo/docs/00-INDEX.md   security: /opt/yolo/docs/10-SECURITY.md"
  echo "  config: VLLM_BASE_URL/VLLM_MODEL in the env file -> auto-configured on launch"
  echo "  web:    code-server :8080 | terminal :7681 | DeepSeek Harness :3080"
  echo
fi
