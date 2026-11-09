# shellcheck shell=bash
#
# Load yolo settings into the environment. Sourced by the entrypoint, login
# shells, the agent wrappers and every yolo command. Later files win:
#
#   /etc/yolo/defaults.env                       lab defaults (in the image)
#   ~/.yolo/fleet/fleet.env                      fleet repo, everyone
#   ~/.yolo/fleet/people/$YOLO_PERSON.env        fleet repo, this person
#   ~/.yolo/secrets.env                          yolo login (Gitea token)
#
# and anything set explicitly beats all of them: compose `environment:` and
# .env, `docker run -e`, or `export X=...` / `X=... yolo configure` in a shell.
# "Explicit" means a non-empty variable whose value differs from what this file set the
# last time it ran (YOLO_ENV_APPLIED records that), so re-sourcing is stable
# and a fleet change still reaches values that came from files.

: "${HOME:=/home/agent}"

declare -A __yolo_applied=()
if [[ -n "${YOLO_ENV_APPLIED:-}" ]]; then
  eval "__yolo_applied=( ${YOLO_ENV_APPLIED} )" 2>/dev/null || __yolo_applied=()
fi

__yolo_keep=""
while IFS= read -r __yolo_n; do
  case "$__yolo_n" in YOLO_ENV_APPLIED|_|SHLVL|PWD|OLDPWD) continue ;; esac
  [[ "$__yolo_n" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
  # An empty value (GITEA_TOKEN= in .env) is "not set", so files still apply.
  [[ -n "${!__yolo_n}" ]] || continue
  if [[ -z "${__yolo_applied[$__yolo_n]+x}"|| "${__yolo_applied[$__yolo_n]}" != "${!__yolo_n}" ]]; then
    __yolo_keep+="$(declare -p "$__yolo_n" 2>/dev/null)"$'\n'
  fi
done < <(compgen -e)

set -a
for __yolo_f in /etc/yolo/defaults.env "$HOME/.yolo/fleet/fleet.env" \
  "${YOLO_PERSON:+$HOME/.yolo/fleet/people/${YOLO_PERSON}.env}" "$HOME/.yolo/secrets.env"; do
  if [[ -n "$__yolo_f" && -r "$__yolo_f" ]]; then
    # shellcheck disable=SC1090
    . "$__yolo_f" || echo "yolo: error in $__yolo_f" >&2
  fi
done
set +a
eval "$__yolo_keep" 2>/dev/null || true

# Remember what the files produced, so the next run can tell an explicit
# override from a value that merely came from a file.
YOLO_ENV_APPLIED=""
while IFS= read -r __yolo_n; do
  case "$__yolo_n" in YOLO_ENV_APPLIED|_|SHLVL|PWD|OLDPWD) continue ;; esac
  [[ "$__yolo_n" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
  [[ "$__yolo_keep" == *"declare -x $__yolo_n="* ]] && continue
  YOLO_ENV_APPLIED+="[$__yolo_n]=$(printf '%q' "${!__yolo_n}") "
done < <(compgen -e)
export YOLO_ENV_APPLIED
unset __yolo_keep __yolo_n __yolo_f __yolo_applied
