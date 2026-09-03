#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <version> <image-ref> [output-dir]" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage

version="$1"
image_ref="$2"
output_dir="${3:-dist}"

case "$version" in
  ''|*[!0-9A-Za-z._-]*) echo "invalid version: $version" >&2; exit 2 ;;
esac

local_image="yolo-agent:$version"
archive="yolo-agent_${version}.docker.tar"

for tool in docker zip sha256sum git stat split; do
  command -v "$tool" >/dev/null || {
    echo "required tool not found: $tool" >&2
    exit 1
  }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
bundle_name="yolo-agent-${version}-offline"
staging="$output_dir/$bundle_name"
zip_path="$output_dir/${bundle_name}.zip"
zip_checksum="${zip_path}.sha256"

rm -rf "${staging:?}"
rm -f "$zip_path" "$zip_checksum" "${zip_path}.part-"* \
  "${zip_path}.parts.sha256" "${zip_path}.REASSEMBLE.txt"
mkdir -p "$staging/bin" "$staging/config" "$staging/docs"

echo "pulling $image_ref"
docker pull "$image_ref"
docker tag "$image_ref" "$local_image"

echo "saving $local_image as $archive"
docker save --output "$staging/$archive" "$local_image"

cp "$repo_root"/bin/* "$staging/bin/"
cp "$repo_root/config/seccomp-yolo.json" "$staging/config/"
cp "$repo_root/config/yolo.env.example" "$staging/config/"
cp -R "$repo_root"/docs/. "$staging/docs/"
cp "$repo_root/compose.yaml" "$staging/"
cp "$repo_root/README.md" "$staging/"
cp "$repo_root/SECURITY.md" "$staging/"
cp "$repo_root/PINS.md" "$staging/"
cp "$repo_root/VERSION" "$staging/"

source_commit="${GITHUB_SHA:-$(git -C "$repo_root" rev-parse HEAD)}"
printf '%s\n' "$source_commit" > "$staging/SOURCE-COMMIT.txt"
docker image inspect "$local_image" > "$staging/IMAGE-INSPECT.json"

(
  cd "$staging"
  sha256sum "$archive" > SHA256SUMS
)

cat > "$staging/LOAD-OFFLINE.txt" <<EOF
yolo-agent $version offline bundle

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
     cp config/yolo.env.example config/yolo.env
   Windows PowerShell:
     Copy-Item config\\yolo.env.example config\\yolo.env

4. Run it:
   Local image tag: $local_image
     docker compose run --rm agent     # interactive shell
     docker compose up -d              # code-server, ttyd, OpenHands, DeepSeek Harness

No registry or internet connection is required after docker load completes.
EOF

echo "creating $zip_path (ZIP64, maximum compression)"
(
  cd "$output_dir"
  zip -9 -q -r "$(basename "$zip_path")" "$bundle_name"
  sha256sum "$(basename "$zip_path")" > "$(basename "$zip_checksum")"
)

rm -rf "${staging:?}"

# GitHub release assets must be strictly smaller than 2 GiB. Normally maximum
# ZIP compression keeps the bundle below that limit. If a future image grows
# beyond it, emit deterministic 1900 MiB parts plus whole/part checksums and
# reassembly instructions instead of failing after the expensive image build.
github_asset_limit=2147483648
zip_size="$(stat -c '%s' "$zip_path")"
if (( zip_size >= github_asset_limit )); then
  echo "$zip_path is $zip_size bytes; splitting for GitHub release assets"
  split -b 1900m -d -a 2 "$zip_path" "${zip_path}.part-"
  (
    cd "$output_dir"
    sha256sum "$(basename "$zip_path")".part-* > "$(basename "$zip_path").parts.sha256"
  )
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
