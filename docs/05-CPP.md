# 05 — C/C++

`yolo-agent-cpp` is the base image plus a complete offline C/C++ toolchain. Its
purpose is the one thing the base image cannot do: **produce a 64-bit Windows
executable on a machine that has no internet**.

## What is installed

| Kind | Tools |
|---|---|
| Native compilers | `gcc`, `g++`, `clang` / `clang++` **14**, `clangd` 14, `lld`, `ld.lld` |
| Cross compiler | `x86_64-w64-mingw32-gcc`, `-g++`, `-ar`, `-ranlib`, `-strip`, `-windres` (mingw-w64 10.0.0, GCC 12.2) |
| Build systems | `cmake` 3.25, `ninja` 1.11, `make`, autotools (`autoconf`, `automake`, `libtool`, `bison`, `flex`, `gettext`, `gperf`, `texinfo`) |
| Build helpers | `pkg-config`, `ccache` 4.8, `nasm` |
| Debug / analysis | `gdb` 13, `lldb` 14, `strace`, `ltrace`, `valgrind`, `binutils` |
| Coverage / docs | `lcov`, `gcovr`, `doxygen`, `graphviz` |
| Headers | `libssl-dev`, `zlib1g-dev`, `libsqlite3-dev`, `libffi-dev`, `libncurses-dev`, `libreadline-dev`, `liblzma-dev`, `libbz2-dev` |

Two things worth knowing up front:

- Debian 12 provides **clang/lld/lldb 14**. That is the newest available without
  vendoring a toolchain, which would add several hundred MB to an image that has
  to be carried across an air gap.
- There is **no Wine**. You can cross-*compile* a Windows executable, but you
  cannot *run* it in this container. See [Limitations](#limitations).

## Quick start

```bash
# Base image has no compilers -- use the cpp flavor.
docker compose -f compose.cpp.yaml run --rm agent
```

Inside the container:

```bash
# Native Linux, direct.
g++ -O2 -std=c++20 main.cpp -o main
./main

# 64-bit Windows, direct.
x86_64-w64-mingw32-g++ -O2 -std=c++20 main.cpp -o main.exe -static
file main.exe        # PE32+ executable (console) x86-64
```

## CMake: two toolchain files

Two toolchain files are baked in, so a project can be configured for either
target without editing anything:

| File | Target |
|---|---|
| `/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake` | native ELF64, clang + lld |
| `/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake` | 64-bit Windows PE32+, mingw-w64 |

```bash
# Native.
cmake -B build-linux -S . -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake
cmake --build build-linux

# Windows x64.
cmake -B build-win -S . -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake
cmake --build build-win
```

Omit the toolchain file entirely and CMake uses the default native `cc`/`c++`
(GCC), which also works.

### The cross compiler always uses the POSIX threading model

Installing `g++-mingw-w64-x86-64` pulls in **both** threading variants, and
Debian's default is the **win32** one (alternative priority 60 vs 30 for posix).
Under win32, `_GLIBCXX_HAS_GTHREADS` is undefined, which means:

- `<mutex>` fails to compile (`'mutex' is not a member of 'std'`);
- `std::thread`'s variadic constructor does not exist, so `std::thread t(f);`
  fails;
- **but** `std::thread t;` — the default constructor — still compiles and links,
  and `-pthread` is accepted *silently* rather than erroring.

That combination is a trap: a shallow test passes while real threaded code does
not work. The image therefore selects posix explicitly
(`update-alternatives --set x86_64-w64-mingw32-g++ …-posix`), and both the
toolchain installer and the smoke suite spawn and join an actual thread so the
win32 model cannot slip through. Verify it yourself:

```bash
readlink -f "$(command -v x86_64-w64-mingw32-g++)"   # must end in -posix
```

### clang cross-compilation works, via one symlink

The C++ headers for the cross compiler live in a variant-suffixed directory
(`/usr/lib/gcc/x86_64-w64-mingw32/12-posix/include/c++/`). clang 14's
installation detector only recognises a **plain numeric** version directory, so
it looks for `include/g++-v0`, finds nothing, and fails with
`fatal error: 'cstdio' file not found`.

The image creates `/usr/lib/gcc/x86_64-w64-mingw32/12` as a symlink to
`12-posix`, after which this works for both headers and linking:

```bash
clang++ --target=x86_64-w64-windows-gnu -fuse-ld=lld -std=c++20 -pthread \
  main.cpp -o main.exe
```

Note that `--gcc-toolchain=` does **not** help here — clang reports it as unused
— and `-isystem` alone fixes the headers while still failing at link time. Newer
LLVM handles the `12-posix` name natively; this workaround is specific to the
clang 14 that Debian 12 ships.

### What the mingw toolchain file sets

- `CMAKE_SYSTEM_NAME Windows`, processor `x86_64`, prefix `x86_64-w64-mingw32`.
- `CMAKE_FIND_ROOT_PATH_MODE_*` so headers and libraries are searched only under
  the mingw sysroot, never the host's `/usr/lib`.
- `CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY`, which stops CMake's compiler
  probes from trying to *run* a PE binary during configuration. Without this,
  configuring a cross build fails immediately.
- Static GCC runtime:
  `-static-libgcc -static-libstdc++ -static`. The resulting `.exe` has no
  dependency on `libstdc++-6.dll` or `libgcc_s_seh-1.dll`, which matters a great
  deal when you copy it to a bare Windows machine. The build smoke test asserts
  this by inspecting the import table.

### Writing a CMakeLists that works for both targets

The only change a cross build needs is guarding anything that would execute a
built binary:

```cmake
cmake_minimum_required(VERSION 3.20)
project(myapp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(mathx STATIC src/mathx.cpp)
target_include_directories(mathx PUBLIC include)

add_executable(myapp src/main.cpp)
target_link_libraries(myapp PRIVATE mathx)

# Tests and try_run() only make sense for a native build: the host cannot
# execute a PE binary.
if(NOT CMAKE_CROSSCOMPILING)
  enable_testing()
  add_test(NAME smoke COMMAND myapp)
endif()
```

`ctest --test-dir build-linux` then works natively, and
`cmake --build build-win` produces `myapp.exe` without ever running it.

## The `cpp-build.sh` helper

A convenience wrapper around the two configurations. It is optional — plain
cmake works fine.

```bash
cpp-build.sh <source-dir> [linux|windows|both] [extra cmake args...]
```

```bash
cpp-build.sh .                        # both targets, Release
cpp-build.sh . windows                # Windows PE only
cpp-build.sh . linux -DBUILD_TESTS=ON # native with an extra option
```

It writes `<src>/build-linux` and `<src>/build-win`, generates
`compile_commands.json` for both, enables **ccache** by default (set
`YOLO_CCACHE=0` to bypass), and prints each produced binary with its object
format so a Windows-targeted build is visibly `PE32+`.

| Variable | Default | Effect |
|---|---|---|
| `CMAKE_BUILD_TYPE` | `Release` | build type for both targets |
| `YOLO_BUILD_JOBS` | `nproc` | parallel build jobs |
| `YOLO_CCACHE` | `1` | set to `0` to disable the ccache launcher |
| `CCACHE_DIR` | `/home/agent/.cache/ccache` | cache location, inside the home volume |

Because the cache lives in the persistent `/home/agent` volume, rebuilds stay
fast across container replacement. Give it room with `CCACHE_MAXSIZE` if you
build large projects.

## Debugging

The image's seccomp profile (`config/seccomp-toolchain.json`) allows `ptrace`,
which is what makes `gdb` work. All privileged syscalls stay denied.

```bash
g++ -g -O0 main.cpp -o main
gdb ./main
# inside gdb: break main, run, bt, print x

valgrind --leak-check=full ./main
strace -f ./main
```

`lldb` is also present if you prefer it. This is the practical difference
between this image and the base image: in the base image `ptrace` is denied, so
debuggers do not attach. Use the cpp flavor for anything you intend to debug.

## Limitations

**No Wine.** The container can cross-compile a Windows executable but cannot
execute one. Consequences:

- CMake `try_run()` checks cannot run for a cross build. The toolchain file sets
  `CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY` to keep configuration working,
  and `if(NOT CMAKE_CROSSCOMPILING)` is how you guard everything else.
- To actually run the `.exe`, copy it out of `/workspace` to the Windows host.
  It is statically linked (toolchain-file default), so it needs no runtime DLLs.

**clang 14.** Newer C++ features that require a newer frontend (some C++23
library facilities, newer `-std=c++2b` support) may not be available through
clang. GCC 12 is the alternative and is usually the better choice for bleeding
edge language support here. Both handle C++20 well.

**No Windows-targeting debugger.** There is no `gdb-mingw-w64` package in
Debian 12 — do not look for one. Cross-builds are compiled, not stepped through.

**No cross-compilation for other architectures.** mingw-w64 x86_64 only. There
is no aarch64-windows or 32-bit i686 cross compiler in this image.

**Single architecture images.** Everything is linux/amd64.

## Baked-in values

| What | Where |
|---|---|
| Toolchain files | `/opt/yolo/cmake-toolchains/` |
| Build helper | `/opt/yolo/cpp-build.sh` |
| ccache dir | `/home/agent/.cache/ccache` (`CCACHE_DIR`) |
| Resource defaults | `compose.cpp.yaml`: 12 GB memory, 6 CPUs, 4 GB `/tmp`, 512 MB `/dev/shm` |

Compilation is memory-hungry, which is why the cpp compose file defaults higher
than the base image. Override with `YOLO_MEM` and `YOLO_CPUS` in
`config/cpp.env`, or at launch.

## Verifying the toolchain yourself

The image smoke suite (`docker/tests/smoke-cpp.sh`, run by
`docker buildx bake cpp-test`) already proves the important things: it compiles
a C++20 program with `<thread>`, asserts the native result is `ELF 64-bit`,
asserts the cross result is `PE32+ executable (console) x86-64`, checks the PE
import table for a dynamic `libstdc++` dependency, configures and builds a
two-target CMake project (including running `ctest` natively), and confirms gdb
can attach.

To reproduce the key check by hand:

```bash
printf '#include <cstdio>\nint main(){puts("ok");}\n' > /tmp/t.cpp
x86_64-w64-mingw32-g++ -O2 /tmp/t.cpp -o /tmp/t.exe -static
file /tmp/t.exe
x86_64-w64-mingw32-objdump -p /tmp/t.exe | grep 'DLL Name'
```

If `file` says `PE32+ executable (console) x86-64` and no `DLL Name:` line
mentions `libstdc++`, the cross toolchain is working.
