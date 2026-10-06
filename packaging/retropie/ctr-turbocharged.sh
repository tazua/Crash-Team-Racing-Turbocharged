#!/usr/bin/env bash

# RetroPie scriptmodule for Crash Team Racing: Turbocharged.
#
# Install it into RetroPie-Setup's third-party module directory, then build and
# configure it from the RetroPie-Setup menus or the command line:
#
#   sudo mkdir -p ~/RetroPie-Setup/ext/ctr-turbocharged/scriptmodules/ports
#   sudo cp ctr-turbocharged.sh ~/RetroPie-Setup/ext/ctr-turbocharged/scriptmodules/ports/
#   cd ~/RetroPie-Setup && sudo ./retropie_packages.sh ctr-turbocharged
#
# README.md next to this file walks through it; docs/RASPBERRY_PI5.md in the
# repository explains the 32-bit build the module makes.
#
# Licensed under the GPL-3.0, like the game; see LICENSE at the repository root.

rp_module_id="ctr-turbocharged"
rp_module_desc="Crash Team Racing: Turbocharged - native port of CTR (needs your own NTSC-U disc dump)"
rp_module_help="Copy your raw NTSC-U Crash Team Racing disc image (single-track MODE2/2352 BIN, not a 2048-byte ISO) to $romdir/ports/ctr-turbocharged/assets/ctr-u.bin. Settings (config.ini), saves (memcards/) and the log live in $romdir/ports/ctr-turbocharged as well."
rp_module_licence="GPL3 https://raw.githubusercontent.com/tazua/Crash-Team-Racing-Turbocharged/turbocharged/LICENSE"
rp_module_repo="git https://github.com/tazua/Crash-Team-Racing-Turbocharged.git turbocharged"
rp_module_section="exp"
rp_module_flags="!all rpi5"

# The game needs 4-byte pointers, so it is always a 32-bit binary. On a 32-bit
# OS it builds natively; on the 64-bit OS RetroPie documents for the Pi 5 it is
# cross-compiled to armhf with Debian's cross toolchain and the :armhf
# development packages, which multiarch installs next to the arm64 ones.
function depends_ctr-turbocharged() {
    local depends=(cmake ninja-build pkg-config libwayland-bin)
    local sdl_depends=(
        libx11-dev libxext-dev libxcursor-dev libxi-dev libxrandr-dev libxfixes-dev
        libgl-dev libegl-dev libgbm-dev libdrm-dev libasound2-dev libpulse-dev
        libpipewire-0.3-dev libudev-dev libdbus-1-dev libxkbcommon-dev
        libwayland-dev libdecor-0-dev libgl1-mesa-dri
    )
    local pkg
    # The Pi 5's default kernel (kernel_2712.img) uses 16 KB pages. 32-bit
    # programs and the 32-bit libraries they load are laid out for 4 KB pages
    # and die in execve under anything larger, so the 4 KB kernel is a hard
    # requirement; see docs/RASPBERRY_PI5.md.
    if [[ "$(getconf PAGESIZE)" != "4096" ]]; then
        md_ret_errors+=("This kernel uses $(getconf PAGESIZE)-byte pages. 32-bit programs such as Turbocharged only run under 4 KB pages: add 'kernel=kernel8.img' to /boot/firmware/config.txt, reboot, then install again.")
        return 1
    fi
    if isPlatform "64bit"; then
        if ! dpkg --print-foreign-architectures | grep -qx armhf; then
            dpkg --add-architecture armhf
            apt-get update
        fi
        depends+=(crossbuild-essential-armhf)
        for pkg in "${sdl_depends[@]}"; do
            depends+=("$pkg:armhf")
        done
    else
        depends+=(build-essential "${sdl_depends[@]}")
    fi
    getDepends "${depends[@]}"
}

function sources_ctr-turbocharged() {
    gitPullOrClone
}

function build_ctr-turbocharged() {
    local params=(-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF)
    if isPlatform "64bit"; then
        params+=(-DCMAKE_TOOLCHAIN_FILE="$md_build/cmake/toolchain-linux-armhf.cmake")
    fi
    rm -rf build
    cmake -S . -B build -G Ninja "${params[@]}"
    cmake --build build
    md_ret_require="$md_build/build/ctr_native"
}

function install_ctr-turbocharged() {
    md_ret_files=(
        'build/ctr_native'
        'build/assets'
        'LICENSE'
        'THIRD_PARTY_NOTICES.md'
        'licenses'
    )
}

function configure_ctr-turbocharged() {
    local data_dir="$romdir/ports/$md_id"

    # One entry under Ports. The data folder holds the disc image, config.ini,
    # memcards/ and the log. --fullscreen applies to the run only, so the window
    # mode saved in config.ini is never touched by the launcher.
    addPort "$md_id" "$md_id" "Crash Team Racing - Turbocharged" "CTR_TURBOCHARGED_DATA_DIR=$data_dir $md_inst/ctr_native --fullscreen"

    [[ "$md_mode" == "remove" ]] && return

    mkRomDir "ports/$md_id"
    mkUserDir "$data_dir/assets/fonts"

    # Seed only the redistributable assets the game ships with. The disc image
    # is the player's, and user fonts (crash-a-like.ttf) and saves are left
    # alone; the bundled files are refreshed so an update carries fixes along.
    local file
    for file in dualshock.png fonts/FuzzyBubbles-Bold.ttf fonts/FuzzyBubbles-OFL.txt \
        fonts/LuckiestGuy-Regular.ttf fonts/LuckiestGuy-Apache-2.0.txt \
        fonts/LuckiestGuy-NOTICE.txt fonts/README.md; do
        cp -f "$md_inst/assets/$file" "$data_dir/assets/$file"
    done
    chown -R "$__user":"$__group" "$data_dir"
}
