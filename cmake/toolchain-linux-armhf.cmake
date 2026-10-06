# Cross-compile for 32-bit ARM Linux (Debian/Raspberry Pi OS "armhf").
#
# The game needs 4-byte pointers, so on a 64-bit Raspberry Pi OS it is built as
# an armhf binary and run through Debian multiarch; see docs/RASPBERRY_PI5.md.
#
#   cmake --preset linux-gcc-armhf-cross-release
#   cmake --build build-linux-gcc-armhf-cross-release
#
# Expects Debian's crossbuild-essential-armhf plus the :armhf development
# packages listed in docs/RASPBERRY_PI5.md. Multiarch keeps those under
# /usr/include/arm-linux-gnueabihf and /usr/lib/arm-linux-gnueabihf, which the
# cross compiler already searches, so no sysroot is needed; only pkg-config has
# to be pointed at the armhf .pc files.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

# Host tools (wayland-scanner, pkg-config) stay native.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

if(NOT DEFINED ENV{PKG_CONFIG_LIBDIR})
    set(ENV{PKG_CONFIG_LIBDIR} "/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/share/pkgconfig")
endif()

# To run the test suite on the build host, configure with qemu-user-static as
# the emulator: -DCMAKE_CROSSCOMPILING_EMULATOR=qemu-arm-static
