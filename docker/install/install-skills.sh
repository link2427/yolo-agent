#!/usr/bin/env bash
#
# Install the curated skills library into /opt/skills (read-only in the image).
#
# Policy:
#   * Only repos people actually use (star counts + skills.sh install counts).
#   * Only license-safe (MIT / Apache-2.0) redistributable content.
#   * Every tarball is pinned to an exact commit and sha256-verified; the build
#     fails on mismatch. See PINS.md.
#   * anthropics/skills docx, pdf, pptx, xlsx are "source-available, not open
#     source" — they are pruned here, not redistributed.
#
set -euo pipefail

SKILLS_ROOT="${SKILLS_ROOT:-/opt/skills}"
mkdir -p "$SKILLS_ROOT"

verify_sha256() { echo "$1  $2" | sha256sum -c - >/dev/null; }

# name|owner/repo|commit|tarball-sha256 (codeload tarball of the commit)
SKILLS=(
  "mattpocock-skills|mattpocock/skills|2ab958093e83e0ec752e6c1c5932da465bf23e0c|80e06b58bde4b3423637b8bf83044473249fd6606e6cb36296fbfde4468dd202"
  "obra-superpowers|obra/superpowers|44c9b2d6e889982ac18c27d05a19fefe335194e1|412d988824cb2a555a167c111ef990a602ee8069c5833eb7ec48c06539ca0c14"
  "anthropics-skills|anthropics/skills|b29e7cf65e5cb78a5ac33d582270551bc74a14eb|c3832f49600230dc30ccecb770bea6887dab5341632652f0e56b1c41278d474c"
  "wshobson-agents|wshobson/agents|c4b82b0ad771190355eb8e204b1329732a18449a|ada3f8e177be3b522e63b77f14fac4bc95b0b1e6e73e9342028dba55004a2bb3"
  "microsoft-azure-skills|microsoft/azure-skills|ff47e4e6caad94ac07b7778658bd3603ae376ffa|e1e03d6e3d9fc2d6f3b664b8e811cd6f073e0fe0d5945df995adc75c6f7dbdbf"
  "supabase-agent-skills|supabase/agent-skills|1207767388a0ffb55f21fb4e6988fee96942431d|0bc734b1697de896b27d2ad2010c64abb5bf5bf11e8eb6f30ebf42cb379e055a"
  "prisma-skills|prisma/skills|808913c1dac11dc425631c2454f7fcb2d5ade5ca|e47af844dbd736c03f7e37686a1b62376437e1167c251f1a0ab82b4f461d721c"
  "planning-with-files|OthmanAdi/planning-with-files|ad1b6927e88359764a4f33720a46ae04e55ab120|32786564fc8f93c740707f0714204a08fe82d015dbec39cb6c2de70fc0f47b47"
  "affaan-ECC|affaan-m/ECC|2665d48ae604b585d0bafb69c3a8e8dca9a15be5|c7f4e4148101bc58a5a7fbb9c957703e79a9b08fe204988e8d96af7fe9221124"
  "alireza-claude-skills|alirezarezvani/claude-skills|aa8d778811a557a2c28ccadda4cf3d0bd028a4cc|ac8bdd2d6b7383e9d844e65dc153e07968cfca807e7651877d4c8b199dadab77"
)

: > "$SKILLS_ROOT/SKILLS-MANIFEST.txt"

for entry in "${SKILLS[@]}"; do
  IFS='|' read -r name repo commit sha <<< "$entry"
  echo ">> skills: $name @ ${commit:0:12}"
  curl -fsSL --max-time 600 -o "/tmp/$name.tgz" \
    "https://codeload.github.com/$repo/tar.gz/$commit"
  verify_sha256 "$sha" "/tmp/$name.tgz"
  rm -rf "$SKILLS_ROOT/$name"
  mkdir -p "$SKILLS_ROOT/$name"
  tar -xzf "/tmp/$name.tgz" -C "$SKILLS_ROOT/$name" --strip-components=1
  rm -f "/tmp/$name.tgz"
  echo "$name|$repo|$commit|$sha" >> "$SKILLS_ROOT/SKILLS-MANIFEST.txt"
done

# anthropics/skills: doc skills are source-available, not open source — prune.
for s in docx pdf pptx xlsx; do
  rm -rf "$SKILLS_ROOT/anthropics-skills/skills/$s"
done

echo ">> install-skills.sh: done -> $SKILLS_ROOT ($(find "$SKILLS_ROOT" -name SKILL.md -type f | wc -l) SKILL.md files)"
