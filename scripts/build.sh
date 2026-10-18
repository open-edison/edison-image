#!/usr/bin/env bash
# Build U-Boot, the kernel, then the rootfs and flashable images, into out/.
#   out/uboot/   u-boot.bin (built by edison-recovery at a pinned commit)
#   out/kernel/  linux-image-*.deb, vmlinuz, config, RELEASE, PKGVERSION
#   out/image/   boot.vfat, rootfs.ext4, u-boot-env.bin, debs/ (our packages, kernel included)
# Usage: scripts/build.sh [uboot|kernel|rootfs|all]   (default: all)
#
# EDISON_RECOVERY_DIR=/path/to/edison-recovery uses a local checkout instead of fetching
# the pinned commit.
set -euo pipefail

# edison-recovery owns the U-Boot build (and its OSIP/layout fixes).
EDISON_RECOVERY_URL=https://github.com/open-edison/edison-recovery.git
EDISON_RECOVERY_COMMIT=8af50cf04f77d6e33b9a70dead0bf6d9fe0d43b2

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${OUT:-$root/out}"
what="${1:-all}"
cd "$root"

# v0.1.0 on a tag, v0.1.0-3-gabc1234 after it, a bare commit hash before the first tag.
version="$(git describe --tags --always --dirty 2>/dev/null || echo unknown)"
# The same as a Debian version, for our packages: 0.1.0, 0.1.0+3+gabc1234 (after 0.1.0,
# before 0.1.1), 0~abc1234.
deb_version="$(echo "$version" | sed -e 's/^v//' -e 's/-/+/g' -e 's/^\([^0-9]\)/0~\1/')"
# The kernel package's version: kernel version plus ours, so that each image release's
# kernel package upgrades the last, even when the kernel version stays the same.
kernel_version="$(sed -n 's/^ARG KERNEL_VERSION=//p' docker/kernel.Dockerfile)"

if [ "$what" = uboot ] || [ "$what" = all ]; then
    recovery="${EDISON_RECOVERY_DIR:-}"
    if [ -z "$recovery" ]; then
        recovery="$out/src/edison-recovery"
        if [ ! -d "$recovery/.git" ]; then
            git clone --quiet "$EDISON_RECOVERY_URL" "$recovery"
        fi
        git -C "$recovery" fetch --quiet origin
        git -C "$recovery" checkout --quiet --detach "$EDISON_RECOVERY_COMMIT"
    fi
    docker build --output "$out/uboot" -f "$recovery/docker/uboot.Dockerfile" "$recovery"
fi

if [ "$what" = kernel ] || [ "$what" = all ]; then
    docker build --output "$out/kernel" --build-arg KDEB_PKGVERSION="$kernel_version-$deb_version" \
        -f docker/kernel.Dockerfile .
fi

if [ "$what" = rootfs ] || [ "$what" = all ]; then
    docker build -t edison-image/rootfs-tools -f docker/rootfs.Dockerfile docker
    mkdir -p "$out/image" "$out/cache"
    docker run --rm --privileged \
        -e IMAGE_VERSION="$version" \
        -e DEB_VERSION="$deb_version" \
        -e IMAGE_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
        -v "$root:/src:ro" \
        -v "$out/kernel:/in/kernel:ro" \
        -v "$out/image:/out" \
        -v "$out/cache:/cache" \
        edison-image/rootfs-tools bash /src/rootfs/build-rootfs.sh
fi
