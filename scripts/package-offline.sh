#!/usr/bin/env bash
#
# Package a release for the air-gapped lab.
#
#   package-offline.sh <version> <image-prefix> [-- <output-dir>]
#
#   image-prefix   where the tiers are, e.g. ghcr.io/link2427/yolo-agent or
#                  localhost:5000/yolo-agent; <prefix>:<version>-core|cpp|full
#
# Output (all in <output-dir>, default dist/):
#
#   yolo-agent-<v>-images.tar.zst[.part-NN]   all three tiers in one docker
#                                             archive; layers the tiers share
#                                             are stored once. Split into
#                                             1900 MiB parts when larger than
#                                             GitHub's 2 GiB asset limit.
#   yolo-agent-<v>-kit.zip                    compose files, env templates,
#                                             seccomp profile, docs, install.sh,
#                                             tools (a few hundred KB)
#   SHA256SUMS                                every file above
#
# The images are saved under their plain local names (yolo-agent:<v>-core ...),
# which is what compose.yaml refers to.
set -euo pipefail

usage() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -ge 2 ]] || usage
version="$1" prefix="$2"; shift 2
out=dist
if [[ "${1:-}" == -- ]]; then out="${2:-dist}"; fi
case "$version" in ''|*[!0-9A-Za-z._-]*) echo "invalid version: $version" >&2; exit 2 ;; esac
for t in docker zstd zip sha256sum split git; do
  command -v "$t" >/dev/null || { echo "required tool not found: $t" >&2; exit 1; }
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
tiers=(core cpp full)

echo "=== images"
local_tags=()
for t in "${tiers[@]}"; do
  src="${prefix}:${version}-${t}" dst="yolo-agent:${version}-${t}"
  docker image inspect "$src" >/dev/null 2>&1 || docker pull "$src"
  docker tag "$src" "$dst"
  local_tags+=("$dst")
  printf '  %-28s %s\n' "$dst" "$(docker image inspect -f '{{.Id}}' "$dst")"
done

archive="yolo-agent-${version}-images.tar.zst"
rm -f "$out/$archive" "$out/$archive".part-*
echo "=== docker save ${local_tags[*]} | zstd → $archive"
# Long-distance matching finds the layers the tiers share; level 19 is slow to
# write but decompresses as fast as level 3. The stream goes straight into
# 1900 MiB parts (GitHub's asset limit is 2 GiB), so the archive never exists
# twice on disk; a single part is renamed to the plain archive name.
docker save "${local_tags[@]}" | zstd -T0 -19 --long=27 -q -c | split -b 1900m -d -a 2 - "$out/$archive.part-"
mapfile -t image_files < <(cd "$out" && ls "$archive".part-*)
if (( ${#image_files[@]} == 1 )); then
  mv "$out/${image_files[0]}" "$out/$archive"
  image_files=("$archive")
fi
size="$(cat "${image_files[@]/#/$out/}" | wc -c)"
echo "    $(numfmt --to=iec "$size") in ${#image_files[@]} file(s)"

echo "=== kit"
kit="yolo-agent-${version}"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$kit/config" "$stage/$kit/tools"
cp "$root/compose.yaml" "$root/compose.lab.yaml" "$root/.env.example" "$root/lab.env.example" \
   "$root/README.md" "$root/CHANGELOG.md" "$root/PINS.md" "$root/SECURITY.md" "$root/VERSION" "$stage/$kit/"
cp "$root/config/seccomp.json" "$stage/$kit/config/"
cp "$root/tools/gpu-exporter.py" "$stage/$kit/tools/"
cp "$root/scripts/install.sh" "$stage/$kit/install.sh"
chmod 0755 "$stage/$kit/install.sh"
cp -R "$root/docs" "$stage/$kit/docs"
rm -rf "$stage/$kit/docs/plans"
git -C "$root" rev-parse HEAD > "$stage/$kit/SOURCE-COMMIT.txt" 2>/dev/null || echo unknown > "$stage/$kit/SOURCE-COMMIT.txt"
{
  echo "yolo-agent ${version} — offline install"
  echo
  echo "Copy these files into one folder on the WSL side (e.g. ~/yolo-release):"
  for f in "${image_files[@]}"; do echo "  $f"; done
  echo "  yolo-agent-${version}-kit.zip"
  echo "  SHA256SUMS"
  echo
  echo "Then, in WSL:"
  echo "  cd ~/yolo-release && unzip yolo-agent-${version}-kit.zip"
  echo "  ./yolo-agent-${version}/install.sh load .      # verify checksums, load the images"
  echo "  ./yolo-agent-${version}/install.sh new alice   # make ~/yolo/alice and start it"
  echo
  echo "docs/02-QUICKSTART.md has the details."
} > "$stage/$kit/INSTALL.txt"
cp "$stage/$kit/INSTALL.txt" "$out/INSTALL-${version}.txt"
rm -f "$out/$kit-kit.zip"
( cd "$stage" && zip -9 -q -r "$out/$kit-kit.zip" "$kit" )

( cd "$out" && sha256sum "${image_files[@]}" "$kit-kit.zip" "INSTALL-${version}.txt" > SHA256SUMS )
echo "=== $out"
( cd "$out" && ls -l "${image_files[@]}" "$kit-kit.zip" SHA256SUMS "INSTALL-${version}.txt" )
