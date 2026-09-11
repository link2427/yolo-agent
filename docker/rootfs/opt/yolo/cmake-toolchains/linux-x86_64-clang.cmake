# CMake toolchain file — native linux/amd64 builds with clang + lld.
#
#   cmake -B build-linux -S . \
#     -DCMAKE_TOOLCHAIN_FILE=/opt/yolo/cmake-toolchains/linux-x86_64-clang.cmake \
#     -DCMAKE_BUILD_TYPE=Release
#   cmake --build build-linux
#
# Clang 14 with lld is the fastest native configuration in this image; plain
# gcc/g++ also work with no toolchain file at all.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER   clang)
set(CMAKE_CXX_COMPILER clang++)

set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")
