---
name: yolo-cpp
description: Build C, C++ and Fortran in the yolo cpp/full containers, for Linux and as static 64-bit Windows .exe files via mingw-w64. Use when compiling, cross-compiling, or setting up CMake.
---

# C, C++ and Fortran here

Installed (cpp and full tiers): gcc/g++/gfortran 12, clang/clang++ 14 with lld,
cmake, ninja, make, ccache, gdb, valgrind, LAPACK/BLAS (Linux only), and the
mingw-w64 cross compilers `x86_64-w64-mingw32-gcc`, `-g++`, `-gfortran`.

## CMake

```bash
# Linux, clang + lld
cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake
cmake --build build-linux

# Windows x64, static .exe (no DLLs needed on the target)
cmake -S . -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake
cmake --build build-win

# both at once
cpp-build . both
```

## Direct

```bash
g++ -O2 -std=c++20 main.cpp -o app -pthread
x86_64-w64-mingw32-g++ -O2 -std=c++20 main.cpp -o app.exe -pthread -static
gfortran -O2 prog.f90 -o prog -llapack -lblas
x86_64-w64-mingw32-gfortran -O2 prog.f90 -o prog.exe -static
```

## Rules

- Windows binaries cannot be run here (no Wine). Check them with
  `file app.exe` and `x86_64-w64-mingw32-objdump -p app.exe | grep 'DLL Name'`.
- Guard tests with `if(NOT CMAKE_CROSSCOMPILING)` so cross builds configure.
- LAPACK/BLAS exist only for Linux builds.
- The cross compilers use the POSIX threading model, so `std::thread` and
  `std::mutex` work.
