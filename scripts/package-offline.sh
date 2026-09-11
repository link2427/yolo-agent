#!/usr/bin/env bash
#
# Package one or more built images into ready-to-burn offline ZIP bundles.
#
#   package-offline.sh <version> <name:tag> [<name:tag> ...] [-- <output-dir>]
#
# Each bundle contains the image archive, host launchers, the compose file for
# that container, its seccomp profile, its env template, documentation, exact
# load instructions, the source commit, image metadata, and checksums. The ZIP
# gets its own .sha256 sidecar.
#
# GitHub release assets must be strictly smaller than 2 GiB. Maximum ZIP
# compression normally keeps a bundle under that limit; if a bundle still
# exceeds it, deterministic 1900 MiB parts plus checksums and reassembly
# instructions are emitted instead, so a release never fails after an expensive
# image build.
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: package-offline.sh <version> <name:tag> [<name:tag> ...] [-- <output-dir>]

  name  base | cpp | reverse   (selects compose file, seccomp profile, env template)
  tag   local image tag to save, e.g. yolo-agent-cpp:2.0.0
EOF
  exit 2
}

[[ $# -ge 2 ]] || usage

version="$1"; shift
images=()
output_dir="dist"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; output_dir="${1:-dist}"; break ;;
    *) images+=("$1"); shift ;;
  esac
done

[[ ${#images[@]} -ge 1 ]] || usage
case "$version" in
  ''|*[!0-9A-Za-z._-]*) echo "invalid version: $version" >&2; exit 2 ;;
esac

for tool in docker zip sha256sum git stat split; do
  command -v "$tool" >/dev/null || { echo "required tool not found: $tool" >&2; exit 1; }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
source_commit="${GITHUB_SHA:-$(git -C "$repo_root" rev-parse HEAD)}"

github_asset_limit=2147483648

package_one() { # $1 = name:tag
  local spec="$1" name tag
  name="${spec%%:*}"
  tag="${spec#*:}"

  local compose seccomp env_template flavor
  case "$name" in
    base)
      compose="compose.yaml";             seccomp="seccomp-base.json"
      env_template="base.env.example";    flavor="base" ;;
    cpp)
      compose="compose.cpp.yaml";         seccomp="seccomp-toolchain.json"
      env_template="cpp.env.example";     flavor="cpp" ;;
    reverse)
      compose="compose.reverse.yaml";     seccomp="seccomp-toolchain.json"
      env_template="reverse.env.example"; flavor="reverse" ;;
    *)
      echo "ERROR: unknown image name '$name' (expected base, cpp, or reverse)" >&2
      return 1 ;;
  esac

  for f in "$repo_root/config/$seccomp" "$repo_root/config/$env_template" "$repo_root/$compose"; do
    [[ -f "$f" ]] || { echo "ERROR: missing bundle input: $f" >&2; return 1; }
  done

  local bundle_name="yolo-agent-${flavor}-${version}-offline"
  local staging="$output_dir/$bundle_name"
  local archive="yolo-agent-${flavor}_${version}.docker.tar"
  local zip_path="$output_dir/${bundle_name}.zip"
  local zip_checksum="${zip_path}.sha256"

  echo "=== packaging $name ($tag) -> ${bundle_name}.zip"
  rm -rf "${staging:?}"
  rm -f "$zip_path" "$zip_checksum" "${zip_path}.part-"* \
    "${zip_path}.parts.sha256" "${zip_path}.REASSEMBLE.txt"
  mkdir -p "$staging/bin" "$staging/config" "$staging/docs"

  docker pull "$tag" 2>/dev/null || true
  docker image inspect "$tag" >/dev/null
  echo "saving $tag as $archive"
  docker save --output "$staging/$archive" "$tag"

  cp "$repo_root"/bin/* "$staging/bin/"
  cp "$repo_root/config/$seccomp" "$staging/config/"
  cp "$repo_root/config/$env_template" "$staging/config/"
  cp -R "$repo_root"/docs/. "$staging/docs/"
  cp "$repo_root/$compose" "$staging/"
  cp "$repo_root/README.md" "$repo_root/SECURITY.md" "$repo_root/PINS.md" "$staging/"
  cp "$repo_root/VERSION" "$staging/"
  printf '%s\n' "$source_commit" > "$staging/SOURCE-COMMIT.txt"
  docker image inspect "$tag" > "$staging/IMAGE-INSPECT.json"
  ( cd "$staging" && sha256sum "$archive" > SHA256SUMS )

  cat > "$staging/LOAD-OFFLINE.txt" <<EOF
yolo-agent ${flavor} ${version} — offline bundle

1. Verify the Docker archive:
   Linux/macOS/WSL:
     sha256sum -c SHA256SUMS
   Windows PowerShell:
     (Get-FileHash -Algorithm SHA256 .\\$archive).Hash
     Compare it with the hash printed in SHA256SUMS.

2. Load the image:
     docker load --input $archive

3. Configure runtime values:
   Linux/macOS/WSL:
     cp config/$env_template config/$flavor.env
   Windows PowerShell:
     Copy-Item config\\$env_template config\\$flavor.env

4. Run it (local image tag: $tag):
     docker compose run --rm agent     # interactive shell
     docker compose up -d              # code-server, ttyd, DeepSeek Harness

   The compose file in this bundle already refers to $tag.

No registry and no internet connection are required after docker load completes.
EOF

  echo "creating $zip_path (ZIP64, maximum compression)"
  ( cd "$output_dir" && zip -9 -q -r "$(basename "$zip_path")" "$bundle_name" )
  ( cd "$output_dir" && sha256sum "$(basename "$zip_path")" > "$(basename "$zip_checksum")" )
  rm -rf "${staging:?}"

  local zip_size
  zip_size="$(stat -c '%s' "$zip_path")"
  if (( zip_size >= github_asset_limit )); then
    echo "$zip_path is $zip_size bytes; splitting for GitHub release assets"
    split -b 1900m -d -a 2 "$zip_path" "${zip_path}.part-"
    ( cd "$output_dir" && sha256sum "$(basename "$zip_path")".part-* > "$(basename "$zip_path").parts.sha256" )
    cat > "${zip_path}.REASSEMBLE.txt" <<EOF
This offline ZIP exceeded GitHub's 2 GiB per-asset limit.
Download every $(basename "$zip_path").part-* file plus both checksum files.

Linux/macOS/WSL:
  sha256sum -c $(basename "$zip_path").parts.sha256
  cat $(basename "$zip_path").part-* > $(basename "$zip_path")
  sha256sum -c $(basename "$zip_checksum")

Windows PowerShell:
  \$parts = Get-ChildItem '$(basename "$zip_path").part-*' | Sort-Object Name
  \$out = [IO.File]::Create('$(basename "$zip_path")')
  try { foreach (\$part in \$parts) { \$in = \$part.OpenRead(); try { \$in.CopyTo(\$out) } finally { \$in.Dispose() } } } finally { \$out.Dispose() }
  (Get-FileHash -Algorithm SHA256 '$(basename "$zip_path")').Hash
  Compare that hash with $(basename "$zip_checksum").
EOF
    rm -f "$zip_path"
    printf '%s\n' "${zip_path}.part-"* "${zip_path}.parts.sha256" \
      "${zip_path}.REASSEMBLE.txt" "$zip_checksum"
  else
    echo "$zip_path ($zip_size bytes)"
    echo "$zip_checksum"
  fi
}

for spec in "${images[@]}"; do
  package_one "$spec"
done

echo "=== packaged ${#images[@]} bundle(s) into $output_dir"
