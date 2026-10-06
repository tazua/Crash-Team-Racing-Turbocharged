# Raspberry Pi 5 build and RetroPie port

How Turbocharged runs natively on a Raspberry Pi 5 (2 GB is enough), what the
tree provides for it, and what still has to be confirmed on real hardware. The
build-side findings below come from cross-compiling this tree for armhf and
running the unit tests under qemu-user; no Pi has run the game yet.

## Summary

The game only insists on **4-byte pointers**, not on x86, so the Pi build is a
**32-bit ARM (armhf) binary**. It cross-compiles, links and passes the
display-independent test suite with the changes now in the tree. What remains
is runtime verification on a Pi (GL context under KMSDRM, performance) and
tuning of the default options once that is known.

A 64-bit (aarch64) build is a different project: an aarch64 syntax check of
the unity build produced 689 compile errors and about 365 pointer/integer cast
warnings across 56 files, all from the PS1 memory layout described in
`docs/MEMORY_MODEL.md`. Do not take that route; use the 32-bit userland.

## Why 32-bit ARM works

| Requirement | Pi 5 status |
| --- | --- |
| 4-byte pointers (`CMAKE_SIZEOF_VOID_P == 4`) | The armhf userland has them. Raspberry Pi OS (32-bit, Bookworm) runs on the Pi 5 on top of its 64-bit kernel, and Debian multiarch lets the 64-bit OS, which RetroPie documents for the Pi 5, run armhf binaries. |
| OpenGL 3.x core, GLSL 1.40 | Mesa's V3D driver exposes OpenGL 3.1 (non-conformant but complete enough for Mesa to advertise it) and conformant OpenGL ES 3.1. `platform/renderer/native_renderer_device.c` asks for 3.3 core and steps down to 3.0; the shaders are `#version 140` (GL 3.1). Every `gl*` entry point used is core in 3.1 except the GPU timer queries, which are already gated behind a support check. The glad loader only tests up to `GLAD_GL_VERSION_3_1`. |
| ARM code paths | Upstream High Octane shipped on PS Vita (ARMv7 + NEON), so the game logic has run on 32-bit ARM before. The 254 `__asm__` blocks are MIPS GTE macros in `include/psn00bsdk` and PS1 overlays, compiled out under `CTR_NATIVE`. |
| RAM | The disc image is streamed with `fread` from a worker thread (`platform/native_cd.c`), not loaded into memory. The armhf executable has 2.5 MB of code and 75 MB of static data; expect well under 500 MB resident. |
| Audio | SDL3 tries PulseAudio, PipeWire, then ALSA, as on x86 Linux. A RetroPie Lite image uses ALSA. |
| Display without X | SDL3's KMSDRM driver (EGL on GBM) is built in. With no display server running, SDL tries X11 and Wayland, which fail, and falls through to KMSDRM on its own. |

## What the tree provides

- **Build system.** `CMakeLists.txt` decides architecture facts with compiler
  checks rather than `CMAKE_SYSTEM_PROCESSOR` (which reads `aarch64` even on
  a 32-bit Pi OS, because `uname -m` reports the kernel). The x86-only
  `-msse2 -mfpmath=sse` flags apply to x86 only, and `-fsigned-char` is added
  wherever plain `char` is unsigned. The game assumes signed `char`, as on
  x86 and MIPS; without the flag GCC warns that `newHighScoreIndex > -1` in
  `game/224.c` is always true, and similar comparisons misbehave silently. The
  Vita makefile already passed the same flag.
- **Toolchain file and presets.** `cmake/toolchain-linux-armhf.cmake` plus the
  `linux-gcc-armhf-cross-*` presets cross-compile with Debian's
  `arm-linux-gnueabihf` toolchain; the `linux-gcc-armhf-*` presets build
  natively on a 32-bit OS.
- **Launcher flags.** `--fullscreen` and `--windowed` override the saved
  `borderless` setting for one run without writing it back, so a launcher can
  pass one on every start. `--help` lists the options. Fullscreen comes from
  `borderless=1` in `config.ini` as before.
- **Video driver order.** The 32-bit Linux build used to force SDL to
  `x11,wayland`, a workaround for 32-bit x86 GPU drivers under Wayland. That
  list excluded KMSDRM, which would have left a RetroPie console with no
  display at all. It now applies to 32-bit x86 only; ARM keeps SDL's default
  order.
- **Packaging and CI.** `ARCH=armhf ./package.sh linux` makes the tarball,
  and the `linux-armhf` job in `.github/workflows/build-native.yml`
  cross-builds on `debian:bookworm`, runs the headless tests under
  `qemu-user-static`, and uploads the tarball. That job has not run yet; the
  same steps were verified locally with a console-only SDL configuration.
- **RetroPie.** `packaging/retropie/ctr-turbocharged.sh` is a RetroPie-Setup
  port module; `packaging/retropie/README.md` walks through installing it.

## Building

### Cross-compile on a 64-bit Bookworm host (Pi OS 64-bit or a desktop)

```sh
sudo dpkg --add-architecture armhf
sudo apt update
sudo apt install cmake ninja-build pkg-config crossbuild-essential-armhf libwayland-bin \
  libx11-dev:armhf libxext-dev:armhf libxcursor-dev:armhf libxi-dev:armhf \
  libxrandr-dev:armhf libxfixes-dev:armhf libgl-dev:armhf libegl-dev:armhf \
  libgbm-dev:armhf libdrm-dev:armhf libasound2-dev:armhf libpulse-dev:armhf \
  libpipewire-0.3-dev:armhf libudev-dev:armhf libdbus-1-dev:armhf \
  libxkbcommon-dev:armhf libwayland-dev:armhf libdecor-0-dev:armhf
cmake --preset linux-gcc-armhf-cross-release
cmake --build build-linux-gcc-armhf-cross-release
```

This mirrors the i386 list in the CI workflow. Runtime packages are the
non-`-dev` versions plus `libgl1-mesa-dri:armhf`, which contains the armhf V3D
driver. To run the test suite on the build host, add
`-DCMAKE_CROSSCOMPILING_EMULATOR=qemu-arm-static` with `qemu-user-static`
installed, then `ctest --test-dir build-linux-gcc-armhf-cross-release -LE gpu`.

On Ubuntu, `gcc-multilib` (used for the i386 build) and the cross compiler
packages conflict; install one at a time.

### Native build on Raspberry Pi OS (32-bit)

Install the same development packages without the `:armhf` suffix plus
`build-essential`, then:

```sh
cmake --preset linux-gcc-armhf-release
cmake --build build-linux-gcc-armhf-release
```

### Running

Put the raw NTSC-U BIN at `assets/ctr-u.bin` next to the executable, or set
`CTR_TURBOCHARGED_DATA_DIR` to a writable folder holding `assets/`,
`config.ini` and `memcards/`. The first-run disc picker needs XDG portals or
Zenity, which a console-only install does not have, so place the file by
hand there. From a console, SDL picks KMSDRM by itself; `SDL_VIDEODRIVER=kmsdrm`
forces it. The log prints `*Video adapter:` and `*OpenGL version:` lines that
say what the driver provided.

## RetroPie

RetroPie on the Pi 5 is installed with the setup script on Raspberry Pi OS
Bookworm Lite 64-bit; there is no Pi 5 image. The scriptmodule in
`packaging/retropie/` goes into `RetroPie-Setup/ext/<name>/scriptmodules/ports/`,
where RetroPie-Setup picks up third-party modules. It installs the build
dependencies (the `:armhf` set through multiarch on the 64-bit OS, native
packages on a 32-bit OS), clones the `turbocharged` branch, builds, installs
to `/opt/retropie/ports/ctr-turbocharged`, and registers a Ports entry that
runs:

```sh
CTR_TURBOCHARGED_DATA_DIR=~/RetroPie/roms/ports/ctr-turbocharged \
    /opt/retropie/ports/ctr-turbocharged/ctr_native --fullscreen
```

The player copies the disc image to
`~/RetroPie/roms/ports/ctr-turbocharged/assets/ctr-u.bin`. Settings, saves and
the log live in that folder too. The module is flagged `rpi5` only; a Pi 4
has the same OpenGL 3.1 driver but a weaker CPU and GPU and has not been
looked at.

## Still to verify on hardware

- **GL context under KMSDRM.** Mesa's EGL supports desktop GL contexts on
  GBM, so the 3.3 to 3.1 fallback should succeed, but this has only been
  reasoned about. If only ES contexts are available, the Emscripten GLES path
  (`#version 300 es`, `SDL_GL_CONTEXT_PROFILE_ES`) exists but disables Native
  3D and the title logo; a `CTR_NATIVE_GLES` define separate from
  `__EMSCRIPTEN__` would be the clean way to reuse it at runtime.
- **Mesa versions on the 64-bit OS.** Multiarch requires `libgl1:armhf` and
  friends at exactly the version of the installed arm64 packages. Both
  Debian and the Raspberry Pi repository publish armhf and arm64 together, so
  this should hold; the 32-bit OS avoids the question entirely.
- **Unaligned access.** PS1 packet code casts byte buffers to wider types.
  AArch32 traps unaligned `LDM`/`LDRD`; the arm64 kernel can fix these up for
  32-bit processes when built with `CONFIG_COMPAT_ALIGNMENT_FIXUPS` (Linux
  6.1+). The Vita build never needed changes, and qemu-user does not trap, so
  the only real test is a Pi. Watch the log for `SIGBUS`.
- **Performance and defaults.** Defaults are the Classic renderer, FXAA,
  depth buffer on, 60 FPS, HD resolution. The VideoCore VII is far faster
  than the Vita GPU this renderer was first tuned on but is not a desktop GPU.
  Start with the PS1 preset or `ps1_resolution=1`, FXAA rather than MSAA/SSAA,
  and Classic rather than Native 3D, then raise settings. If the Pi needs
  different defaults, a first-run detection of `/proc/device-tree/model` is
  the place to add them.
- **`-Wstrict-aliasing` warnings** appear three times in the ARM build. They
  exist on x86 too, but ARM's codegen can expose them differently.
- **Struct layouts in files.** ARM EABI aligns 64-bit fields to 8 bytes where
  i386 uses 4, so any file the game writes as raw structs containing
  `u64`/`double` would differ between the x86 and ARM builds. This only
  matters for moving saves, replays or caches between platforms; it does not
  affect a Pi-only install.

## Verification done so far

- armhf cross-compile and link of the full game and test suite with GCC 13,
  with SDL in its console-only configuration (no display drivers), no errors
  and the same warnings as the x86 build.
- Headless unit tests run under `qemu-arm-static`.
- The i386 build still receives the SSE flags and builds and tests as before.
