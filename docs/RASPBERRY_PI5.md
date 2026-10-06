# Raspberry Pi 5 (2 GB) feasibility notes

Research notes on what it would take to run Turbocharged natively on a
Raspberry Pi 5 with 2 GB of RAM and launch it from RetroPie. Nothing here has
been run on real Pi hardware yet; the build findings come from an armhf
cross-compile of this tree.

## Short answer

Feasible, and far less work than it first looks. The game only insists on
**4-byte pointers**, not on x86. A **32-bit ARM (armhf) build compiles and
links today** with two CMake changes (see "Build changes"). The remaining work
is runtime verification on the Pi, the RetroPie launcher glue, and performance
tuning of the default options.

A 64-bit (aarch64) build is a different project: 689 compile errors and about
365 pointer/integer cast warnings across 56 files, all from the PS1 memory
layout (`docs/MEMORY_MODEL.md`). Do not take that route for a Pi port; use
the 32-bit userland instead.

## Why 32-bit ARM works

| Requirement | Pi 5 status |
| --- | --- |
| 4-byte pointers (`CMAKE_SIZEOF_VOID_P == 4`) | armhf userland has 4-byte pointers. Raspberry Pi OS (32-bit, Bookworm) runs on the Pi 5 with a 64-bit kernel, and Debian multiarch lets a 64-bit Bookworm (what RetroPie uses on Pi 5) run armhf binaries. |
| OpenGL 3.x core, GLSL 1.40 | Mesa's V3D driver exposes OpenGL 3.1 (not conformant, but complete enough that Mesa advertises it) and conformant OpenGL ES 3.1. The context code in `platform/renderer/native_renderer_device.c` asks for 3.3 and steps down to 3.0, and the shaders are `#version 140` (GL 3.1). Every `gl*` entry point used is core in 3.1 except `glPolygonMode` (also 3.1 core) and the GPU timer queries, which are already gated behind a support check. The glad loader only tests up to `GLAD_GL_VERSION_3_1`. |
| ARM code paths | Upstream High Octane shipped on PS Vita (ARMv7 + NEON), so the game logic has already run on 32-bit ARM. The 254 `__asm__` blocks are MIPS GTE macros in `include/psn00bsdk` and PS1 overlays, compiled out under `CTR_NATIVE`. |
| RAM | The disc image is streamed with `fread` from a worker thread (`platform/native_cd.c`), not loaded into memory. The static footprint of the armhf executable is 2.5 MB text and 75 MB BSS. Expect well under 500 MB resident; 2 GB is fine. |
| Audio | SDL3 tries PulseAudio, PipeWire, then ALSA, same as x86 Linux. |
| Display without X | SDL3's KMSDRM driver is enabled by default on Linux. RetroPie launches ports from the console, so the game must be tested under KMSDRM (EGL + GBM), not only X11. |

### Build changes (already applied to `CMakeLists.txt`)

1. `-msse2 -mfpmath=sse` was added for every non-Emscripten target. The ARM
   compiler rejects both flags. They are now only added for x86 processors.
2. `-fsigned-char` is now added for ARM targets. The game assumes plain
   `char` is signed (x86 and MIPS default); ARM defaults to unsigned. The
   Vita makefile already passed `-fsigned-char`. Without it GCC flags
   `game/224.c:126` (`newHighScoreIndex > -1` is always true) and similar
   comparisons silently misbehave.

With those two changes the armhf cross-build (`arm-linux-gnueabihf-gcc`
13.3, SDL built with `-DSDL_UNIX_CONSOLE_BUILD=ON` and no video drivers so
it links without armhf X11 libraries) produces a 10 MB ELF with no errors and
the same warnings as the x86 build.

The configure step also needs a toolchain file or must run on the Pi itself.
A preset like this belongs in `CMakePresets.json` once the Pi build is
confirmed:

```json
{
  "name": "linux-gcc-armhf-release",
  "inherits": "common",
  "generator": "Ninja",
  "binaryDir": "${sourceDir}/build-linux-gcc-armhf-release",
  "cacheVariables": {
    "CMAKE_BUILD_TYPE": "Release",
    "CMAKE_C_COMPILER": "arm-linux-gnueabihf-gcc"
  }
}
```

On a 64-bit Bookworm host (Pi or desktop) the armhf dev packages come from
multiarch:

```sh
sudo dpkg --add-architecture armhf
sudo apt update
sudo apt install crossbuild-essential-armhf cmake ninja-build \
  libx11-dev:armhf libxext-dev:armhf libxcursor-dev:armhf libxi-dev:armhf \
  libxrandr-dev:armhf libxfixes-dev:armhf libgl-dev:armhf libegl-dev:armhf \
  libgbm-dev:armhf libdrm-dev:armhf libasound2-dev:armhf libpulse-dev:armhf \
  libpipewire-0.3-dev:armhf libudev-dev:armhf libdbus-1-dev:armhf \
  libxkbcommon-dev:armhf libwayland-dev:armhf libdecor-0-dev:armhf
```

This mirrors the i386 list in `.github/workflows/build-native.yml`. Runtime
packages are the non-`-dev` versions plus `libgl1-mesa-dri:armhf`, which
contains the armhf V3D driver.

## Things that still need testing on hardware

- **Context creation under KMSDRM.** Mesa's EGL supports desktop GL
  contexts, so the 3.3 → 3.1 fallback loop should succeed, but this has only
  been reasoned about. If only ES contexts work, the Emscripten GLES path
  (`#version 300 es`, `SDL_GL_CONTEXT_PROFILE_ES`) exists but disables
  Native 3D and the title logo; a `CTR_NATIVE_GLES` define separate from
  `__EMSCRIPTEN__` would be the clean way to reuse it.
- **Unaligned access.** PS1 packet code casts byte buffers to wider types.
  AArch32 traps unaligned `LDM`/`LDRD`; the arm64 kernel since 6.1 fixes up
  these faults for 32-bit processes, and the Vita build never needed changes,
  so this is a low risk, but watch for `SIGBUS` in the log.
- **`-Wstrict-aliasing` warnings** appeared three times in the ARM build.
  They exist on x86 too, but ARM's stricter codegen can expose them.
- **Performance.** Defaults are the Classic renderer, FXAA, depth buffer on,
  60 FPS, HD resolution. The VideoCore VII is far faster than the Vita GPU
  this renderer was tuned on, but it is not a desktop GPU. Start with
  `ps1_resolution=1` or a 720p mode, FXAA rather than MSAA/SSAA, and
  Classic rather than Native 3D, then raise settings. Shaders declare
  `precision highp float`, which V3D handles.
- **First-run disc picker.** It needs XDG portals or Zenity. On RetroPie
  there is no desktop, so document placing `assets/ctr-u.bin` manually
  (the path logic already supports it).

## RetroPie integration

RetroPie on the Pi 5 is installed on top of Raspberry Pi OS Bookworm Lite
64-bit via the setup script; there is no Pi 5 image. Ports live under
`RetroPie-Setup/scriptmodules/ports/` and appear in EmulationStation's
"Ports" system as a launcher script in `~/RetroPie/roms/ports/`.

The game already has what a port launcher needs:

- `CTR_TURBOCHARGED_DATA_DIR` picks the writable folder for `assets/`,
  `config.ini`, `memcards/` and the log (`platform/native_assets.c`).
- `borderless=1` in `config.ini` gives fullscreen. Only `--version` is
  parsed on the command line, so a `--fullscreen` flag would be a small,
  worthwhile addition for launchers.

Sketch of a scriptmodule (`scriptmodules/ports/ctr-turbocharged.sh`),
following the pattern of existing ports such as `sdlpop.sh`:

```sh
rp_module_id="ctr-turbocharged"
rp_module_desc="Crash Team Racing: Turbocharged (native port, needs your NTSC-U disc dump)"
rp_module_licence="GPL3 https://raw.githubusercontent.com/CameronRedmore/Crash-Team-Racing-Turbocharged/turbocharged/LICENSE"
rp_module_repo="git https://github.com/CameronRedmore/Crash-Team-Racing-Turbocharged.git turbocharged"
rp_module_section="exp"
rp_module_flags="!all rpi5"

function depends_ctr-turbocharged() {
    # 64-bit Bookworm: pull the armhf toolchain and SDL build deps via multiarch.
    dpkg --add-architecture armhf
    getDepends cmake ninja-build crossbuild-essential-armhf \
        libx11-dev:armhf libgl-dev:armhf libegl-dev:armhf libgbm-dev:armhf \
        libdrm-dev:armhf libasound2-dev:armhf libpulse-dev:armhf \
        libudev-dev:armhf libdbus-1-dev:armhf libxkbcommon-dev:armhf \
        libgl1-mesa-dri:armhf
}

function sources_ctr-turbocharged() {
    gitPullOrClone
}

function build_ctr-turbocharged() {
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc
    cmake --build build -j"$(nproc)"
    md_ret_require="$md_build/build/ctr_native"
}

function install_ctr-turbocharged() {
    md_ret_files=(build/ctr_native build/assets LICENSE THIRD_PARTY_NOTICES.md licenses)
}

function configure_ctr-turbocharged() {
    local data="$romdir/ports/ctr-turbocharged"
    mkRomDir "ports/ctr-turbocharged"
    mkUserDir "$data/assets"
    cp -rn "$md_inst/assets/." "$data/assets/"
    chown -R "$__user":"$__group" "$data"
    addPort "$md_id" "ctr-turbocharged" "Crash Team Racing: Turbocharged" \
        "CTR_TURBOCHARGED_DATA_DIR=$data $md_inst/ctr_native"
    # The player copies their raw MODE2/2352 dump to $data/assets/ctr-u.bin.
}
```

Because `$md_inst/ctr_native` is an armhf binary on an arm64 system, the
runtime armhf libraries listed above must be installed; `depends_` covers
that. The alternative, a full 32-bit Raspberry Pi OS install, avoids multiarch
but RetroPie's own Pi 5 support targets the 64-bit OS.

## Suggested order of work

1. Build on a Pi 5 (or cross-build) with the applied CMake changes, run
   `./ctr_native --version`, then start it under X11 with a disc image.
2. Try KMSDRM from a console (`SDL_VIDEODRIVER=kmsdrm`) and record the
   `*OpenGL version:` line from the log.
3. Tune defaults for the Pi (resolution, anti-aliasing) and add a
   `--fullscreen` argument.
4. Add the armhf preset to `CMakePresets.json` and an armhf job to CI.
5. Write the RetroPie scriptmodule and submit it to RetroPie-Setup, or ship
   it in this repo under `packaging/retropie/` for manual installation.
