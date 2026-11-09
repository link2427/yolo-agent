# shellcheck shell=sh
# yolo-agent: login shells (docker compose exec, ttyd, code-server terminals).
# Debian's /etc/profile resets PATH, so put the image's PATH back first, then
# load lab defaults, fleet settings and secrets.
__yolo_path=/opt/yolo/bin:/opt/pyenv/bin
[ -d /opt/java/bin ] && __yolo_path="$__yolo_path:/opt/java/bin"
case ":$PATH:" in
  *:/opt/yolo/bin:*) ;;
  *) PATH="$__yolo_path:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" ;;
esac
export PATH
unset __yolo_path
if [ -n "${BASH_VERSION:-}" ] && [ -r /opt/yolo/lib/env.sh ]; then
  . /opt/yolo/lib/env.sh
fi
