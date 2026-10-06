#!/usr/bin/env bash
# Build the 32-bit ARM (armhf) Linux package for the Raspberry Pi 5 inside a
# Debian bookworm container, using the same steps as the linux-armhf CI job.
#
# usage: ./tools/build-armhf-in-container.sh [version]
#
# Needs docker or podman on the host. The source tree is copied into the
# container, so nothing in the checkout is written as root; the result lands in
# dist/ctr-turbocharged-<version>-linux-armhf.tar.gz next to its .sha256.
# The display-independent tests run under qemu-user-static before packaging.
#
# See docs/RASPBERRY_PI5.md.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-$(tr -d '[:space:]' < "${repo_root}/VERSION")}"

if command -v docker >/dev/null 2>&1; then
    engine=docker
elif command -v podman >/dev/null 2>&1; then
    engine=podman
else
    echo "build-armhf-in-container: docker or podman is required" >&2
    exit 1
fi

mkdir -p "${repo_root}/dist"

# The inner script mirrors .github/workflows/build-native.yml (linux-armhf).
read -r -d '' inner <<'INNER' || true
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture armhf
apt-get update
apt-get install -y --no-install-recommends \
    git ca-certificates file cmake ninja-build pkg-config \
    crossbuild-essential-armhf qemu-user-static libwayland-bin \
    libx11-dev:armhf libxext-dev:armhf libxcursor-dev:armhf libxi-dev:armhf \
    libxrandr-dev:armhf libxfixes-dev:armhf libgl-dev:armhf libegl-dev:armhf \
    libasound2-dev:armhf libpulse-dev:armhf libpipewire-0.3-dev:armhf \
    libjack-jackd2-dev:armhf libudev-dev:armhf libdbus-1-dev:armhf \
    libibus-1.0-dev:armhf libusb-1.0-0-dev:armhf libwayland-dev:armhf \
    libxkbcommon-dev:armhf libdecor-0-dev:armhf libdrm-dev:armhf libgbm-dev:armhf
# Work on a copy so the mounted checkout stays untouched and user-owned.
cp -a /src /work
cd /work
git config --global --add safe.directory /work || true
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=ON \
    -DCTR_NATIVE_RENDERER_TESTS=ON \
    -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-linux-armhf.cmake \
    -DCMAKE_CROSSCOMPILING_EMULATOR=qemu-arm-static
cmake --build build
ctest --test-dir build --output-on-failure -LE gpu
ARCH=armhf ./package.sh linux "$CTR_VERSION"
cp dist/*linux-armhf.tar.gz dist/*linux-armhf.tar.gz.sha256 /out/
chown "$HOST_UID:$HOST_GID" /out/*linux-armhf.tar.gz*
INNER

"$engine" run --rm \
    -e CTR_VERSION="${version}" \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -v "${repo_root}:/src:ro" \
    -v "${repo_root}/dist:/out" \
    debian:bookworm bash -c "${inner}"

echo "Wrote dist/ctr-turbocharged-${version}-linux-armhf.tar.gz"
