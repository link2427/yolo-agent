# CMake toolchain file — cross-compile a 64-bit Windows executable from Linux.
#
#   cmake -B build-win -S . \
#     -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/mingw-w64-x86_64.cmake \
#     -DCMAKE_BUILD_TYPE=Release
#   cmake --build build-win
#
# Produces PE32+ binaries that run on Windows x64. This image has no Wine, so
# CMake cannot execute the binaries it builds: test execution and try_run checks
# are disabled below, and projects should guard those with
# `if(NOT CMAKE_CROSSCOMPILING)`.
#
# Debian's mingw-w64 defaults to the POSIX threading model (std::thread,
# std::mutex, std::condition_variable all work). Switch to the win32 variant
# with `update-alternatives` if a project requires it.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(TOOLCHAIN_PREFIX x86_64-w64-mingw32)

set(CMAKE_C_COMPILER   ${TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++)
set(CMAKE_RC_COMPILER  ${TOOLCHAIN_PREFIX}-windres)
set(CMAKE_AR           ${TOOLCHAIN_PREFIX}-ar)
set(CMAKE_RANLIB       ${TOOLCHAIN_PREFIX}-ranlib)
set(CMAKE_STRIP        ${TOOLCHAIN_PREFIX}-strip)

set(CMAKE_FIND_ROOT_PATH /usr/${TOOLCHAIN_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Nothing can be executed: the host cannot run PE binaries. Compiling a static
# library instead of an executable is what keeps CMake's compiler probes from
# trying to run anything during configuration.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Static-link the GCC runtime so the resulting .exe has no libstdc++/libgcc
# DLL dependency, which matters on a bare Windows host.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static-libgcc -static-libstdc++ -static")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-static-libgcc -static-libstdc++")
