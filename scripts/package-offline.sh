#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <version> <full|headless> <image-ref> [output-dir]" >&2
  exit 2
}

[[ $# -ge 3 && $# -le 4 ]] || usage

version="$1"
profile="$2"
image_ref="$3"
output_dir="${4:-dist}"

case "$version" in
  ''|*[!0-9A-Za-z._-]*) echo "invalid version: $version" >&2; exit 2 ;;
esac

case "$profile" in
  full)
    local_image="yolo-agent:$version"
    archive="yolo-agent_${version}_full.docker.tar"
    ;;
  headless)
    local_image="yolo-agent:${version}-headless"
    archive="yolo-agent_${version}_headless.docker.tar"
    ;;
  *) usage ;;
esac

for tool in docker zip sha256sum git; do
  command -v "$tool" >/dev/null || {
    echo "required tool not found: $tool" >&2
    exit 1
  }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
bundle_name="yolo-agent-${version}-${profile}-offline"
staging="$output_dir/$bundle_name"
zip_path="$output_dir/${bundle_name}.zip"
zip_checksum="${zip_path}.sha256"

rm -rf "${staging:?}"
rm -f "$zip_path" "$zip_checksum"
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
yolo-agent $version ($profile) offline bundle

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
   Full profile:
     docker compose run --rm agent
     docker compose --profile server up -d server
   Headless profile:
     YOLO_IMAGE=$local_image docker compose run --rm agent

No registry or internet connection is required after docker load completes.
EOF

echo "creating $zip_path (ZIP64 store mode; Docker layers are already compressed)"
(
  cd "$output_dir"
  zip -0 -q -r "$(basename "$zip_path")" "$bundle_name"
  sha256sum "$(basename "$zip_path")" > "$(basename "$zip_checksum")"
)

rm -rf "${staging:?}"
echo "$zip_path"
echo "$zip_checksum"
