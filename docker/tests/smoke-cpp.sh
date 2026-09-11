#!/usr/bin/env bash
#
# yolo-agent-cpp smoke suite.
#
# Runs after smoke-common.sh inside the C++ image. Its job is to prove the
# toolchain really produces both an ELF64 and a PE32+ binary — not merely that
# the compiler binaries exist — because the offline host has no way to install
# a missing linker or sysroot later.
#
set -euxo pipefail

# --- compilers and build tools are present ----------------------------------
for tool in gcc g++ clang clang++ clangd lld ld.lld lldb gdb make ninja cmake \
            pkg-config ccache lcov gcovr nasm strace ltrace valgrind \
            x86_64-w64-mingw32-gcc x86_64-w64-mingw32-g++ \
            x86_64-w64-mingw32-ar x86_64-w64-mingw32-windres; do
  command -v "$tool" >/dev/null
done

# The cross compiler must be the POSIX-threading variant, or <mutex> and
# std::thread's variadic constructor do not exist. Check the resolved binary
# rather than trusting update-alternatives to have picked what we asked for.
x86_64_w64_gpp="$(readlink -f "$(command -v x86_64-w64-mingw32-g++)")"
case "$x86_64_w64_gpp" in
  *-posix) echo ">> cross compiler is the posix variant: $x86_64_w64_gpp" ;;
  *) echo "ERROR: x86_64-w64-mingw32-g++ resolves to $x86_64_w64_gpp," >&2
     echo "       expected the -posix variant (win32 breaks <mutex>/std::thread)" >&2
     exit 1 ;;
esac

cmake --version | head -1
ninja --version
gcc --version | head -1
clang --version | head -1
x86_64-w64-mingw32-gcc --version | head -1

# --- the ccache directory must be writable in the image ---------------------
test -d "$CCACHE_DIR"
test -w "$CCACHE_DIR"

# --- direct compiler checks: one ELF64, one PE32+ ---------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/hello.cpp" <<'EOF'
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

int main() {
    std::vector<std::string> parts{"yolo", "agent", "cpp"};
    std::string joined;
    std::mutex m;
    // Spawn and join: the win32 threading model compiles `std::thread t;` but
    // has no variadic constructor, so only a real spawn detects it.
    std::thread t([&] {
        std::lock_guard<std::mutex> g(m);
        for (const auto& p : parts) joined += p + " ";
    });
    t.join();
    std::cout << joined << std::this_thread::get_id() << '\n';
    return joined.empty() ? 1 : 0;
}
EOF

# Uses <mutex> and spawns+joins a real thread on purpose. Under mingw's win32
# threading model `std::thread t;` (default ctor) still compiles and links, so a
# shallow check passes while real code fails -- and -pthread is accepted
# silently rather than erroring. The cross build below is what guards that.
g++ -O2 -std=c++20 "$work/hello.cpp" -o "$work/hello-gcc.elf" -pthread
file -b "$work/hello-gcc.elf" | grep -q '^ELF 64-bit'
"$work/hello-gcc.elf" >/dev/null

clang++ -O2 -std=c++20 "$work/hello.cpp" -o "$work/hello-clang.elf" -fuse-ld=lld -pthread
file -b "$work/hello-clang.elf" | grep -q '^ELF 64-bit'
"$work/hello-clang.elf" >/dev/null

# Cross build. -pthread exercises the POSIX threading model, and hello.cpp uses
# <mutex> plus a real spawned thread, so this fails loudly under the win32
# variant instead of silently producing a binary that cannot use threads.
x86_64-w64-mingw32-g++ -O2 -std=c++20 "$work/hello.cpp" \
  -o "$work/hello-mingw.exe" -pthread -static
file -b "$work/hello-mingw.exe" | grep -q 'PE32+ executable (console) x86-64'

# The PE must not depend on the mingw runtime DLLs, since the target Windows
# host will not have them.
if x86_64-w64-mingw32-objdump -p "$work/hello-mingw.exe" | grep -q 'DLL Name: libstdc++'; then
  echo "ERROR: cross binary links libstdc++ dynamically" >&2
  exit 1
fi

# --- CMake end to end for both targets --------------------------------------
# A small project with a library, an executable, and a test that is only
# registered for native builds.
mkdir -p "$work/proj/src" "$work/proj/include"
cat > "$work/proj/include/mathx.hpp" <<'EOF'
#pragma once
namespace mathx { long long fib(int n); }
EOF
cat > "$work/proj/src/mathx.cpp" <<'EOF'
#include "mathx.hpp"
namespace mathx {
long long fib(int n) {
    long long a = 0, b = 1;
    for (int i = 0; i < n; ++i) { long long t = a + b; a = b; b = t; }
    return a;
}
}
EOF
cat > "$work/proj/src/main.cpp" <<'EOF'
#include "mathx.hpp"
#include <cstdio>
#include <cstdlib>
int main(int argc, char** argv) {
    int n = argc > 1 ? std::atoi(argv[1]) : 10;
    std::printf("fib(%d) = %lld\n", n, mathx::fib(n));
    return mathx::fib(10) == 55 ? 0 : 1;
}
EOF
cat > "$work/proj/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(probe LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(mathx STATIC src/mathx.cpp)
target_include_directories(mathx PUBLIC include)
add_executable(probe src/main.cpp)
target_link_libraries(probe PRIVATE mathx)

# Only native builds can run their own tests.
if(NOT CMAKE_CROSSCOMPILING)
  enable_testing()
  add_test(NAME fib COMMAND probe 10)
endif()
EOF

# Linux: configure, build, and RUN the test suite.
cmake -S "$work/proj" -B "$work/proj/build-linux" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake
cmake --build "$work/proj/build-linux" --parallel "$(nproc)"
test -f "$work/proj/build-linux/compile_commands.json"
ctest --test-dir "$work/proj/build-linux" --output-on-failure
file -b "$work/proj/build-linux/probe" | grep -q '^ELF 64-bit'
"$work/proj/build-linux/probe" 10 | grep -q 'fib(10) = 55'

# Windows: configure and cross build. Nothing is executed.
cmake -S "$work/proj" -B "$work/proj/build-win" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake
cmake --build "$work/proj/build-win" --parallel "$(nproc)"
file -b "$work/proj/build-win/probe.exe" | grep -q 'PE32+ executable (console) x86-64'

# --- the documented helper produces both artifacts --------------------------
/opt/yolo/cpp-build.sh "$work/proj" both >/tmp/cpp-build.log 2>&1
test -f "$work/proj/build-linux/probe"
test -f "$work/proj/build-win/probe.exe"

# --- debugger can attach (ptrace is allowed in this image's seccomp) --------
gdb --batch -ex "run" -ex "bt" "$work/hello-gcc.elf" >/tmp/gdb.log 2>&1
grep -q 'yolo agent cpp' /tmp/gdb.log

echo "cpp smoke tests passed"
