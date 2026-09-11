#!/usr/bin/env bash
#
# cpp-build.sh — build a CMake project for Linux, for 64-bit Windows, or both,
# into separate build directories so the two never fight over cache state.
#
#   cpp-build.sh <source-dir> [linux|windows|both] [extra cmake args...]
#
# Examples:
#   cpp-build.sh .                 # both targets, Release
#   cpp-build.sh . windows         # 64-bit Windows PE only
#   cpp-build.sh . linux -DBUILD_TESTS=ON
#
# Output:
#   <src>/build-linux/   ELF 64-bit binaries + compile_commands.json
#   <src>/build-win/     PE32+ executables (64-bit Windows)
#
# This is a convenience wrapper, not a build system. Nothing here is required —
# plain cmake/ninja/g++ all work directly.
#
set -euo pipefail

TOOLCHAINS="${YOLO_CMAKE_TOOLCHAINS:-/opt/yolo/cmake-toolchains}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
JOBS="${YOLO_BUILD_JOBS:-$(nproc)}"

usage() {
  echo "usage: $(basename "$0") <source-dir> [linux|windows|both] [cmake args...]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
src="$1"; shift
[[ -d "$src" ]] || { echo "ERROR: source dir not found: $src" >&2; exit 1; }
src="$(cd "$src" && pwd)"

what="both"
if [[ $# -ge 1 && "$1" =~ ^(linux|windows|both)$ ]]; then
  what="$1"; shift
fi

common=(-S "$src" -G Ninja "-DCMAKE_BUILD_TYPE=$BUILD_TYPE" "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON")

# Reuse compilation results across rebuilds. ccache lives in the persistent
# home volume, so it survives replacing the container. Set YOLO_CCACHE=0 to
# bypass it for a clean timing run.
if [[ "${YOLO_CCACHE:-1}" != "0" ]] && command -v ccache >/dev/null; then
  common+=("-DCMAKE_C_COMPILER_LAUNCHER=ccache" "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache")
fi

common+=("$@")

build_linux() {
  echo ">> linux/amd64 (clang + lld) -> $src/build-linux"
  cmake -B "$src/build-linux" "${common[@]}" \
    "-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAINS/linux-x86_64-clang.cmake"
  cmake --build "$src/build-linux" --parallel "$JOBS"
}

build_windows() {
  echo ">> windows x86_64 (mingw-w64) -> $src/build-win"
  cmake -B "$src/build-win" "${common[@]}" \
    "-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAINS/mingw-w64-x86_64.cmake"
  cmake --build "$src/build-win" --parallel "$JOBS"
}

case "$what" in
  linux)   build_linux ;;
  windows) build_windows ;;
  both)    build_linux; build_windows ;;
esac

echo
echo ">> artifacts"
for d in "$src/build-linux" "$src/build-win"; do
  [[ -d "$d" ]] || continue
  # Show the produced binaries with their object format, which is the quickest
  # way to confirm a Windows-targeted build really produced PE32+.
  while IFS= read -r f; do
    printf '   %-28s %s\n' "$(file -b "$f" | cut -c1-28)" "${f#"$src"/}"
  done < <(find "$d" -maxdepth 1 -type f -executable ! -name '*.cmake' ! -name '*.ninja' | sort)
done
