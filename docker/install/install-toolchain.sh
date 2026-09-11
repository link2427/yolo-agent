#!/usr/bin/env bash
#
# Install the complete offline C/C++ toolchain for yolo-agent-cpp.
#
#   native linux/amd64 : gcc, g++, clang(+clangd), lld, lldb, gdb, make, ninja,
#                        cmake, pkg-config, nasm, ccache, lcov, gcovr, strace,
#                        ltrace, valgrind, doxygen, graphviz, autotools
#   cross Windows x64  : x86_64-w64-mingw32-gcc / -g++  -> PE32+ executables
#
# Notes that matter on a rebuild:
#   * There is no `gdb-mingw-w64-x86-64` package in Debian 12 — do not add it.
#   * Debian 12 ships clang/lld/lldb 14. That is what "latest available in the
#     base distro" means here; a newer LLVM would have to be vendored, which
#     would pull the image well past the lightweight budget.
#   * Everything comes from the distro, so this whole layer is apt-only and
#     needs no GitHub egress.
#
# Debian's mingw-w64 defaults to the POSIX threading model. That is the more
# capable variant (std::thread, std::mutex, std::condition_variable work), so it
# is left as the default and the win32 variant is only mentioned in the docs.
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Package list is an array, not a backslash continuation: a `#` comment inside a
# continuation ends the command and makes apt try to execute the next line.
packages=(
  # --- native C/C++ ---
  gcc g++ make
  clang clangd clang-tools-14
  lld lldb
  gdb
  cmake ninja-build pkg-config
  ccache lcov gcovr
  # --- binary analysis / debugging ---
  strace ltrace valgrind binutils
  # --- assembly ---
  nasm
  # --- mingw-w64 cross toolchain (64-bit Windows) ---
  # The umbrella `mingw-w64` package plus both C and C++ frontends for x86_64.
  mingw-w64
  gcc-mingw-w64-x86-64
  g++-mingw-w64-x86-64
  binutils-mingw-w64-x86-64
  # --- documentation / graph output ---
  doxygen graphviz
  # --- autotools, for source trees that ship configure.ac ---
  autoconf automake libtool bison flex gettext gperf texinfo patch
  # --- headers commonly needed by real projects ---
  libssl-dev zlib1g-dev libsqlite3-dev libffi-dev
  libncurses-dev libreadline-dev liblzma-dev libbz2-dev
)

apt-get install -y --no-install-recommends "${packages[@]}"
rm -rf /var/lib/apt/lists/*
apt-get clean

# --- select the POSIX threading model for the cross compiler ------------------
# Installing g++-mingw-w64-x86-64 pulls in BOTH threading variants, and the
# win32 one wins by default (alternative priorities: win32 60, posix 30). Under
# win32, `_GLIBCXX_HAS_GTHREADS` is undefined, so <mutex> fails to compile and
# std::thread's variadic constructor disappears -- and `-pthread` is accepted
# silently rather than erroring. Worse, `std::thread t;` still compiles, so a
# shallow test passes while real spawn-and-join code does not.
#
# The posix variant is the capable one (std::thread, std::mutex,
# std::condition_variable), so select it explicitly. Slaves (cpp, c++, gcc-12,
# gcov, ...) follow the master alternative automatically.
update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

# --- let clang find the mingw C++ headers ------------------------------------
# The headers live in a variant-suffixed directory (12-posix). clang 14's
# installation detector only matches a plain numeric version directory, so it
# looks for include/g++-v0, finds nothing, and dies with
# "fatal error: 'cstdio' file not found". A plain-named symlink fixes detection,
# after which `clang++ --target=x86_64-w64-windows-gnu -fuse-ld=lld` works for
# both headers and link. (`--gcc-toolchain=` does NOT help; it is reported as
# unused. Newer LLVM handles 12-posix natively.)
MINGW_GCC_ROOT=/usr/lib/gcc/x86_64-w64-mingw32
if [[ -d "$MINGW_GCC_ROOT/12-posix" && ! -e "$MINGW_GCC_ROOT/12" ]]; then
  ln -sfn "$MINGW_GCC_ROOT/12-posix" "$MINGW_GCC_ROOT/12"
fi

echo ">> verifying the toolchain actually works"

gcc --version | head -1
g++ --version | head -1
clang --version | head -1
cmake --version | head -1
ninja --version
ccache --version | head -1
x86_64-w64-mingw32-gcc --version | head -1
x86_64-w64-mingw32-g++ --version | head -1

# Build a Linux ELF and a Windows PE from one translation unit, and assert on
# the resulting object formats. This is the check that proves the image can
# really produce both kinds of binary — a missing mingw linker would fail here
# rather than on the offline host.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/probe.cpp" <<'EOF'
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

int main() {
    std::vector<std::string> v{"cross", "toolchain", "ok"};
    std::mutex m;
    int total = 0;
    // Spawn and join for real: under the win32 threading model the default
    // constructor still compiles, so only an actual spawn detects a broken
    // <thread>. <mutex> cover the same ground at compile time.
    std::thread t([&] {
        std::lock_guard<std::mutex> g(m);
        for (const auto& s : v) total += static_cast<int>(s.size());
    });
    t.join();
    std::printf("%zu parts, %d chars\n", v.size(), total);
    return total > 0 ? 0 : 1;
}
EOF

g++ -O2 -std=c++17 "$tmp/probe.cpp" -o "$tmp/probe.elf" -pthread
file -b "$tmp/probe.elf" | grep -q '^ELF 64-bit'

x86_64-w64-mingw32-g++ -O2 -std=c++17 "$tmp/probe.cpp" -o "$tmp/probe.exe" -pthread -static
file -b "$tmp/probe.exe" | grep -q 'PE32+ executable (console) x86-64'

# Static linking must remove the mingw runtime DLLs, or the .exe is not
# self-contained on a bare Windows host.
if x86_64-w64-mingw32-objdump -p "$tmp/probe.exe" | grep -qE 'DLL Name: (libstdc\+\+|libgcc|libwinpthread)'; then
  echo "ERROR: cross binary depends on mingw runtime DLLs" >&2
  x86_64-w64-mingw32-objdump -p "$tmp/probe.exe" | grep 'DLL Name:' >&2
  exit 1
fi

# clang can drive the same mingw sysroot through lld, but Debian's clang does
# not know where the mingw C++ headers live: without an explicit hint it fails
# with `fatal error: 'cstdio' file not found`. --gcc-toolchain points it at the
# tree that g++-mingw-w64-x86-64-{posix,win32} installed.
#
# This path is a convenience, not the supported one -- the gcc cross frontend
# above is what the smoke suite asserts on -- so it stays non-fatal and reports
# its own error rather than failing the build.
if clang++ --target=x86_64-w64-windows-gnu \
     -O2 -std=c++17 "$tmp/probe.cpp" -pthread \
     -o "$tmp/probe-clang.exe" -fuse-ld=lld 2>"$tmp/clang.err"; then
  file -b "$tmp/probe-clang.exe" | grep -q 'PE32+ executable' \
    && echo ">> clang -> windows PE also verified"
else
  echo ">> note: clang cross-compile unavailable; use the gcc cross frontend"
  sed -n '1,3p' "$tmp/clang.err" || true
fi

echo ">> install-toolchain.sh: native + mingw-w64 toolchain installed and verified"
