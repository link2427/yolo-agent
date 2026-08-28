#!/usr/bin/env bash
#
# skill-use.sh — activate one skill from the /opt/skills library into the
# default farm (~/.agents/skills). The library (924 skills) is always present
# but only 30 are linked by default, to keep agent context small.
#
#   skill-use.sh <skill-name>
#   browse first:  cat ~/.agents/SKILLS-LIBRARY.txt   (name<TAB>repo)
#
set -euo pipefail
: "${HOME:=/home/agent}"
SKILLS_ROOT="${SKILLS_ROOT:-/opt/skills}"
FARM="$HOME/.agents/skills"

name="${1:-}"
[[ -n "$name" ]] || {
  echo "usage: skill-use.sh <skill-name>   (browse: cat ~/.agents/SKILLS-LIBRARY.txt)" >&2
  exit 1
}

mkdir -p "$FARM"
if [[ -e "$FARM/$name" ]]; then
  echo "already active: $FARM/$name"
  exit 0
fi

found=""
while IFS= read -r f; do
  n=$(awk '/^---/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); gsub(/[[:space:]]+$/,""); gsub(/^"|"$/,""); print; exit}' "$f")
  [[ -z "$n" ]] && n="$(basename "$(dirname "$f")")"
  if [[ "$n" == "$name" ]]; then
    found="$(dirname "$f")"
    break
  fi
done < <(find "$SKILLS_ROOT" -name SKILL.md -type f)

[[ -n "$found" ]] || {
  echo "skill '$name' not found in the library — see ~/.agents/SKILLS-LIBRARY.txt" >&2
  exit 1
}

ln -s "$found" "$FARM/$name"
echo "activated: $FARM/$name"
echo "agents will pick it up on their next session start."
