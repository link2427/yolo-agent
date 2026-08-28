#!/usr/bin/env bash
#
# Build the ~/.agents/skills symlink farm from the read-only /opt/skills tree.
# One farm covers all skill-capable agents: opencode, pi, goose and
# prime-agent all auto-discover ~/.agents/skills/<name>/SKILL.md.
#
# DEFAULT: curated mode — only the skills listed in /opt/yolo/CURATED-SKILLS.txt
# are linked (30 coding-focused skills). This keeps the skills that agents
# load at session start (goose injects names+descriptions) tiny.
#
# ALL mode (link the whole library, more than 900 skills): SKILL_FARM=all
# Custom list: SKILL_FARM_FILE=/path/to/list.txt
#
# The complete library stays in /opt/skills (read-only, root-owned) and is
# indexed to ~/.agents/SKILLS-LIBRARY.txt (name<TAB>repo). Activate individual
# skills with /opt/yolo/skill-use.sh <name>.
#
# Idempotent and safe to re-run (e.g. from configure-agents.sh), so a reused
# home volume still gets the farm. Logs to ~/.agents/.skills.log.
#
set -euo pipefail
: "${HOME:=/home/agent}"
SKILLS_ROOT="${SKILLS_ROOT:-/opt/skills}"
FARM="$HOME/.agents/skills"
LOG="$HOME/.agents/.skills.log"
CURATED_FILE="${CURATED_FILE:-/opt/yolo/CURATED-SKILLS.txt}"
LIBRARY_INDEX="$HOME/.agents/SKILLS-LIBRARY.txt"

mkdir -p "$FARM" "$HOME/.agents"
: > "$LOG"
: > "$LIBRARY_INDEX"

# Most-loved first; on name collision the earlier repo wins.
REPO_ORDER=(
  mattpocock-skills
  obra-superpowers
  anthropics-skills
  wshobson-agents
  microsoft-azure-skills
  supabase-agent-skills
  prisma-skills
  planning-with-files
  affaan-ECC
  alireza-claude-skills
)

# Pass 1: collect every unique skill (frontmatter name, first-wins) and write
# the library index. Strips quotes from quoted frontmatter names ("x" -> x).
declare -A NAME_DIR
order=()
total=0
for repo in "${REPO_ORDER[@]}"; do
  dir="$SKILLS_ROOT/$repo"
  [[ -d "$dir" ]] || continue
  while IFS= read -r f; do
    [[ -r "$f" ]] || continue
    total=$((total + 1))
    name=$(awk '/^---/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); gsub(/[[:space:]]+$/,""); gsub(/^"|"$/,""); print; exit}' "$f")
    [[ -z "$name" ]] && name="$(basename "$(dirname "$f")")"
    case "$name" in ""|README|TEMPLATE|*/*|.*) continue ;; esac
    if [[ -z "${NAME_DIR[$name]+x}" ]]; then
      NAME_DIR["$name"]="$(dirname "$f")"
      order+=("$name")
    fi
  done < <(find "$dir" -name SKILL.md -type f | sort)
done

for name in "${order[@]}"; do
  d="${NAME_DIR[$name]}"
  repo=$(echo "$d" | sed -E "s#^$SKILLS_ROOT/([^/]+)/.*#\1#")
  printf '%s\t%s\n' "$name" "$repo" >> "$LIBRARY_INDEX"
done

# Pass 2: decide which names to link.
if [[ "${SKILL_FARM:-curated}" == "all" ]]; then
  targets=("${order[@]}")
else
  curated_file="${SKILL_FARM_FILE:-$CURATED_FILE}"
  targets=()
  if [[ -f "$curated_file" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(echo "$line" | tr -d '[:space:]')"
      [[ -n "$line" ]] || continue
      targets+=("$line")
    done < "$curated_file"
  else
    echo "warning: curated list not found ($curated_file); nothing linked" >> "$LOG"
  fi
fi

linked=0; skipped=0
for name in "${targets[@]}"; do
  d="${NAME_DIR[$name]:-}"
  if [[ -z "$d" ]]; then
    echo "warning: curated skill not in library: $name" >> "$LOG"
    skipped=$((skipped + 1))
    continue
  fi
  if [[ -L "$FARM/$name" || -e "$FARM/$name" ]]; then
    echo "exists: $name" >> "$LOG"
    skipped=$((skipped + 1))
    continue
  fi
  ln -s "$d" "$FARM/$name"
  linked=$((linked + 1))
done

echo "skill farm: $linked linked ($total in library, ${#targets[@]} requested, $skipped skipped/exists) -> $FARM"
