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
            gfortran x86_64-w64-mingw32-gfortran \
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

x86_64_w64_gfortran="$(readlink -f "$(command -v x86_64-w64-mingw32-gfortran)")"
case "$x86_64_w64_gfortran" in
  *-posix) echo ">> cross Fortran is the posix variant: $x86_64_w64_gfortran" ;;
  *) echo "ERROR: x86_64-w64-mingw32-gfortran resolves to $x86_64_w64_gfortran," >&2
     echo "       expected the -posix variant to match the C/C++ cross compiler" >&2
     exit 1 ;;
esac

cmake --version | head -1
ninja --version
gcc --version | head -1
gfortran --version | head -1
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

# --- debugger works (this image's seccomp allows ptrace) --------------------
# `gdb --batch -ex run` exits non-zero when the program it runs exits after
# finishing, so assert on gdb's OUTPUT rather than its exit status. Non-fatal by
# design: gdb is a convenience here, and the meaningful guarantee is that the
# seccomp profile permits ptrace at all.
gdb --batch -ex run -ex bt "$work/hello-gcc.elf" >/tmp/gdb.log 2>&1 || true
if grep -q 'yolo agent cpp' /tmp/gdb.log; then
  echo ">> gdb ran the binary (ptrace permitted)"
else
  echo ">> note: gdb produced no program output; inspect /tmp/gdb.log"
  tail -5 /tmp/gdb.log || true
fi
# The seccomp profile must ALLOW ptrace for a debugger to attach at all. This
# image ships seccomp-toolchain.json (the base profile minus ptrace and the
# process_vm_* pair), so those names appearing in the BAKED profile would mean
# the wrong file was copied in. Delegated so the assertion is readable.
/opt/pyenv/bin/python /tmp/check-seccomp.py

# --- Fortran: CMake, LAPACK, mixed C++/Fortran, and a Windows cross build ----
# solve2 solves [[2,1],[1,3]] x = [3,5] through LAPACK, so x = (0.8, 1.4). It is
# exported with bind(C) so the C++ caller needs no name-mangling guesses.
mkdir -p "$work/fproj"
cat > "$work/fproj/solve.f90" <<'EOF'
subroutine solve2(x) bind(C, name="solve2")
  use iso_c_binding, only: c_double
  implicit none
  real(c_double), intent(out) :: x(2)
  double precision :: a(2,2)
  integer :: ipiv(2), info
  a = reshape([2d0, 1d0, 1d0, 3d0], [2,2])
  x = [3d0, 5d0]
  call dgesv(2, 1, a, 2, ipiv, x, 2, info)
end subroutine solve2
EOF
cat > "$work/fproj/main.f90" <<'EOF'
program main
  use iso_c_binding, only: c_double
  implicit none
  interface
    subroutine solve2(x) bind(C, name="solve2")
      import :: c_double
      real(c_double), intent(out) :: x(2)
    end subroutine solve2
  end interface
  real(c_double) :: x(2)
  call solve2(x)
  print '(a,2f8.4)', 'x =', x
end program main
EOF
cat > "$work/fproj/mixed.cpp" <<'EOF'
#include <cstdio>
extern "C" void solve2(double* x);
int main() { double x[2]; solve2(x); std::printf("mixed %.4f %.4f\n", x[0], x[1]); }
EOF
cat > "$work/fproj/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(fprobe LANGUAGES CXX Fortran)
find_package(LAPACK REQUIRED)
add_executable(fprobe main.f90 solve.f90)
target_link_libraries(fprobe PRIVATE LAPACK::LAPACK)
# C++ main + Fortran object: CMake links with the C++ driver and adds the
# Fortran runtime libraries itself.
add_executable(mixed mixed.cpp solve.f90)
target_link_libraries(mixed PRIVATE LAPACK::LAPACK)
EOF
cmake -S "$work/fproj" -B "$work/fproj/build" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$work/fproj/build" --parallel "$(nproc)"
"$work/fproj/build/fprobe" | grep -q '0\.8000 *1\.4000'
"$work/fproj/build/mixed" | grep -q 'mixed 0.8000 1.4000'

mkdir -p "$work/fhello"
cat > "$work/fhello/hello.f90" <<'EOF'
program hello
  print *, 'yolo agent fortran'
end program hello
EOF
cat > "$work/fhello/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(fh LANGUAGES Fortran)
add_executable(fh hello.f90)
EOF

# Native through the clang toolchain file (gfortran + lld on the Fortran side).
cmake -S "$work/fhello" -B "$work/fhello/build-linux" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake
cmake --build "$work/fhello/build-linux"
"$work/fhello/build-linux/fh" | grep -q 'yolo agent fortran'

# Windows: a static PE with no Fortran runtime DLL dependency.
cmake -S "$work/fhello" -B "$work/fhello/build-win" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake
cmake --build "$work/fhello/build-win"
file -b "$work/fhello/build-win/fh.exe" | grep -q 'PE32+ executable (console) x86-64'
if x86_64-w64-mingw32-objdump -p "$work/fhello/build-win/fh.exe" | grep -qE 'DLL Name: (libgfortran|libquadmath|libgcc|libwinpthread)'; then
  echo "ERROR: Fortran cross binary depends on mingw runtime DLLs" >&2
  x86_64-w64-mingw32-objdump -p "$work/fhello/build-win/fh.exe" | grep 'DLL Name:' >&2
  exit 1
fi

echo "cpp smoke tests passed"
