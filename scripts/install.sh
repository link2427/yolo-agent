#!/usr/bin/env bash
#
# yolo-agent host helper. Run it in WSL (or any Linux host with Docker).
#
#   install.sh load [dir]                 verify SHA256SUMS and load the images
#                                         from dir (default: the current folder)
#   install.sh new <name> [options]       make ~/yolo/<name> and start it
#       --tier core|cpp|full              image tier (default full)
#       --ports N                         first host port; the five services get
#                                         N..N+4 (default: 8000 8080 4096 7681 8081)
#       --token TOKEN                     the person's Gitea token
#       --no-start                        write the folder, do not start it
#   install.sh lab                        make ~/yolo/lab (monitor + bot) from
#                                         compose.lab.yaml
#   install.sh upgrade <name>|--all       point folders at this kit's version
#                                         and restart them
#
# Each person gets one folder: compose.yaml, .env, config/seccomp.json and
# workspace/ (their files; also reachable from Windows at
# \\wsl.localhost\<distro>\home\<you>\yolo\<name>\workspace).
set -euo pipefail

kit="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="$(cat "$kit/VERSION")"
base="${YOLO_HOME:-$HOME/yolo}"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

need_docker() {
  command -v docker >/dev/null || die "docker not found. Install Docker Desktop (WSL integration on) or Docker Engine."
  docker info >/dev/null 2>&1 || die "docker is not running, or this user cannot reach it."
  docker compose version >/dev/null 2>&1 || die "docker compose v2 is required."
}

cmd_load() {
  local dir="${1:-.}"
  need_docker
  cd "$dir"
  [[ -f SHA256SUMS ]] || die "no SHA256SUMS in $dir"
  say "verifying checksums"
  local present
  present="$(awk '{print $2}' SHA256SUMS | while read -r f; do [[ -f "$f" ]] && echo "$f"; done)"
  grep -F -f <(printf '%s\n' "$present") SHA256SUMS | sha256sum -c - || die "checksum mismatch: copy the files again"
  local archive="yolo-agent-${version}-images.tar.zst" parts
  if [[ -f "$archive" ]]; then parts=("$archive"); else mapfile -t parts < <(ls "$archive".part-* 2>/dev/null | sort); fi
  [[ ${#parts[@]} -gt 0 ]] || die "no $archive or $archive.part-* in $dir"
  say "loading images (a few minutes)"
  if command -v zstd >/dev/null; then
    cat "${parts[@]}" | zstd -dc --long=27 | docker load
  else
    cat "${parts[@]}" | docker load
  fi
  docker image ls --filter "reference=yolo-agent:${version}-*"
}

# Give both the container user (10001) and you full access to a folder, now
# and for files created later, so the agent and Windows Explorer can both edit.
share_folder() {
  local d="$1" me; me="$(id -u)"
  mkdir -p "$d"
  if command -v setfacl >/dev/null && setfacl -m "u:10001:rwX,u:${me}:rwX" -d -m "u:10001:rwX,u:${me}:rwX" "$d" 2>/dev/null; then
    return 0
  fi
  if sudo -n true 2>/dev/null && sudo setfacl -m "u:10001:rwX,u:${me}:rwX" -d -m "u:10001:rwX,u:${me}:rwX" "$d" 2>/dev/null; then
    return 0
  fi
  echo "note: setfacl unavailable (sudo apt install acl); making $d world-writable instead" >&2
  chmod 0777 "$d"
}

cmd_new() {
  local name="${1:-}"; shift || true
  [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "usage: install.sh new <name>   (lowercase letters, digits, - and _)"
  local tier=full ports="" token="" start=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tier) tier="$2"; shift 2 ;;
      --ports) ports="$2"; shift 2 ;;
      --token) token="$2"; shift 2 ;;
      --no-start) start=0; shift ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ "$tier" =~ ^(core|cpp|full)$ ]] || die "--tier must be core, cpp or full"
  local d="$base/$name"
  [[ -e "$d/compose.yaml" ]] && die "$d already exists (use: install.sh upgrade $name)"
  mkdir -p "$d/config"
  cp "$kit/compose.yaml" "$d/compose.yaml"
  cp "$kit/config/seccomp.json" "$d/config/seccomp.json"
  local home=8000 code=8080 chat=4096 term=7681 files=8081
  if [[ -n "$ports" ]]; then
    [[ "$ports" =~ ^[0-9]+$ ]] || die "--ports takes a number"
    home=$ports code=$((ports + 1)) chat=$((ports + 2)) term=$((ports + 3)) files=$((ports + 4))
  fi
  sed -e "s|^YOLO_IMAGE=.*|YOLO_IMAGE=yolo-agent:${version}-${tier}|" \
      -e "s|^YOLO_PERSON=.*|YOLO_PERSON=${name}|" \
      -e "s|^YOLO_PORT_HOME=.*|YOLO_PORT_HOME=${home}|" \
      -e "s|^YOLO_PORT_CODE=.*|YOLO_PORT_CODE=${code}|" \
      -e "s|^YOLO_PORT_CHAT=.*|YOLO_PORT_CHAT=${chat}|" \
      -e "s|^YOLO_PORT_TERM=.*|YOLO_PORT_TERM=${term}|" \
      -e "s|^YOLO_PORT_FILES=.*|YOLO_PORT_FILES=${files}|" \
      -e "s|^GITEA_TOKEN=.*|GITEA_TOKEN=${token}|" \
      "$kit/.env.example" > "$d/.env"
  chmod 0600 "$d/.env"
  share_folder "$d/workspace"
  say "made $d"
  if [[ $start == 1 ]]; then
    need_docker
    (cd "$d" && docker compose up -d)
    say "open http://localhost:${home}  (start page with links to everything)"
  else
    echo "start it with: cd $d && docker compose up -d"
  fi
}

cmd_lab() {
  local d="$base/lab"
  [[ -e "$d/compose.yaml" ]] && die "$d already exists"
  mkdir -p "$d"
  cp "$kit/compose.lab.yaml" "$d/compose.yaml"
  sed -e "s|^YOLO_IMAGE=.*|YOLO_IMAGE=yolo-agent:${version}-core|" "$kit/lab.env.example" > "$d/.env"
  chmod 0600 "$d/.env"
  say "made $d — edit $d/.env (BOT_GITEA_TOKEN, BOT_PUBLIC_URL), then: cd $d && docker compose up -d"
}

cmd_upgrade() {
  need_docker
  local targets=()
  if [[ "${1:-}" == --all ]]; then
    for f in "$base"/*/compose.yaml; do targets+=("$(dirname "$f")"); done
  else
    [[ -n "${1:-}" ]] || die "usage: install.sh upgrade <name>|--all"
    targets=("$base/$1")
  fi
  for d in "${targets[@]}"; do
    [[ -f "$d/.env" ]] || { echo "skip $d (no .env)"; continue; }
    if [[ "$(basename "$d")" == lab ]]; then cp "$kit/compose.lab.yaml" "$d/compose.yaml"
    else cp "$kit/compose.yaml" "$d/compose.yaml"; mkdir -p "$d/config"; cp "$kit/config/seccomp.json" "$d/config/"; fi
    sed -i -E "s|^YOLO_IMAGE=yolo-agent:[^-]+-(core|cpp|full)$|YOLO_IMAGE=yolo-agent:${version}-\\1|" "$d/.env"
    say "upgrading $d → $(grep ^YOLO_IMAGE= "$d/.env" | cut -d= -f2)"
    (cd "$d" && docker compose up -d --remove-orphans)
  done
}

case "${1:-}" in
  load) shift; cmd_load "$@" ;;
  new) shift; cmd_new "$@" ;;
  lab) shift; cmd_lab "$@" ;;
  upgrade) shift; cmd_upgrade "$@" ;;
  -h|--help|help|"") usage 0 ;;
  *) usage 2 ;;
esac
