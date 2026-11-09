#!/usr/bin/env bash
#
# Build the baked skills library at /opt/yolo/skills/library.
#
#   * yolo house skills from docker/skills/ (this repo)
#   * the open-licensed skills from github.com/anthropics/skills at a pinned
#     commit. Only skills whose LICENSE.txt is Apache-2.0 are taken; anything
#     else is skipped so the image only redistributes what it may.
#
# Nothing here is enabled for anyone: `yolo skills enable` links skills into the
# folders the agents read. The library itself is just files on disk.
set -euo pipefail

SKILLS_COMMIT="${SKILLS_COMMIT:?}"
LIB=/opt/yolo/skills/library
mkdir -p "$LIB"

cp -a /tmp/yolo-skills/. "$LIB/"
mv "$LIB/packs.json" /opt/yolo/skills/packs.json

curl -fsSL --retry 4 -o /tmp/skills.tgz \
  "https://codeload.github.com/anthropics/skills/tar.gz/${SKILLS_COMMIT}"
mkdir -p /tmp/skills-src
tar -xzf /tmp/skills.tgz -C /tmp/skills-src --strip-components=1 --no-same-owner

taken=() skipped=()
for dir in /tmp/skills-src/skills/*/; do
  name="$(basename "$dir")"
  [[ -f "$dir/SKILL.md" ]] || continue
  if [[ -f "$dir/LICENSE.txt" ]] && grep -q 'Apache License' "$dir/LICENSE.txt"; then
    if [[ -e "$LIB/$name" ]]; then
      skipped+=("$name(name taken by a house skill)")
      continue
    fi
    cp -a "$dir" "$LIB/$name"
    taken+=("$name")
  else
    skipped+=("$name(licence)")
  fi
done

{
  echo "# skills library, built $(date -u +%F)"
  echo "# anthropics/skills @ ${SKILLS_COMMIT}"
  for d in "$LIB"/*/; do
    n="$(basename "$d")"
    # description: may be one line or a YAML block scalar (> or |-).
    desc="$(awk '/^description:/{sub(/^description:[ 	]*/,""); if ($0 ~ /^[>|][-+]?$/) {blk=1; next} print; exit}
                 blk && /^[ 	]/{sub(/^[ 	]+/,""); printf "%s ", $0; next} blk{exit}' "$d/SKILL.md"             | tr -d '"' | cut -c1-140)"
    printf '%s\t%s\n' "$n" "$desc"
  done
} > /opt/yolo/skills/INDEX.tsv

chown -R root:root /opt/yolo/skills
chmod -R a+rX /opt/yolo/skills
rm -rf /tmp/skills.tgz /tmp/skills-src
echo ">> skills taken from anthropics/skills: ${taken[*]}"
echo ">> skipped: ${skipped[*]:-none}"
echo ">> library: $(ls "$LIB" | wc -l) skills"
