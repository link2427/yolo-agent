# yolo-agent shell profile. Settings, agent config and git are handled by the
# entrypoint and /etc/profile.d/yolo.sh; this file only sets up the prompt.
[[ $- == *i* ]] || return
umask 022
export EDITOR=vim
HISTSIZE=50000
HISTFILESIZE=100000
shopt -s histappend checkwinsize
PS1='\[\e[38;5;209m\]yolo\[\e[0m\]:\[\e[1m\]\w\[\e[0m\]\$ '
alias ll='ls -lah --color=auto' ls='ls --color=auto' grep='grep --color=auto'

if [[ -z "${YOLO_GREETED:-}" ]]; then
  export YOLO_GREETED=1
  echo
  echo -e "\e[1myolo-agent ${YOLO_VERSION:-}\e[0m  (${YOLO_TIER:-?} tier)   model: $(jq -r '.model // "?"' ~/.yolo/state.json 2>/dev/null)"
  echo "  agents:  claude  opencode  qwen  pi  crush  goose  codex"
  echo "  help:    yolo status   yolo doctor   yolo skills   yolo tools"
  [[ "${YOLO_TIER:-}" != core ]] && echo "  build:   cpp-build <dir> linux|windows|both"
  echo
fi
