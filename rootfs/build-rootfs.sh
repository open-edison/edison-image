#!/bin/bash
# Build our packages, the Debian rootfs and the flashable images. Runs inside the tooling
# container (docker/rootfs.Dockerfile) as root, with:
#   /src         this repo (read-only)
#   /in/kernel   kernel build output (linux-image-*.deb, vmlinuz, RELEASE, PKGVERSION)
#   /out         output directory
#   /cache       optional: .deb cache kept between builds (only changed packages download)
# and DEB_VERSION (our packages' version), IMAGE_VERSION and IMAGE_COMMIT set.
set -euo pipefail

SUITE=trixie
MIRROR=http://deb.debian.org/debian
ROOT=/work/rootfs
USER_NAME=edison

release=$(cat /in/kernel/RELEASE)
mkdir -p /work /out
rm -rf "$ROOT"

# What this image is, for /etc/edison-image-release and the login banner.
cat > /work/edison-image-release <<EOF
VERSION=${IMAGE_VERSION:-unknown}
COMMIT=${IMAGE_COMMIT:-unknown}
KERNEL=$release
BUILT=$(date -u +%Y-%m-%dT%H:%MZ)
URL=https://github.com/open-edison/edison-image
EOF

# Our packages (into /out/debs), installed below like any other: the image and apt deliver
# the same files.
bash /src/package/build-debs.sh
chmod 0644 /out/debs/*.deb

packages=$(grep -v -e '^#' -e '^$' /src/rootfs/packages.txt | paste -sd, -)
# mmdebstrap checks the paths outside the chroot, and apt hands them to dpkg inside it, so
# the files must be at the same path in both (inside: setup hook).
mkdir -p /work/debs
cp /out/debs/*.deb /work/debs/
debs=()
for f in /work/debs/*.deb; do
    debs+=("--include=/work/debs/${f##*/}")
done

mkdir -p /cache/apt
# Hooks are run by mmdebstrap with the rootfs path as $1, so most must stay unexpanded here.
# shellcheck disable=SC2016
mmdebstrap \
    --variant=apt \
    --components="main non-free-firmware" \
    --include="$packages" "${debs[@]}" \
    --skip=download/empty --skip=essential/unlink \
    --setup-hook='mkdir -p "$1/var/cache/apt/archives"' \
    --setup-hook='sync-in /cache/apt /var/cache/apt/archives/' \
    --setup-hook='mkdir -p "$1/work/debs" && cp /work/debs/*.deb "$1/work/debs/"' \
    --customize-hook='sync-out /var/cache/apt/archives /cache/apt' \
    --customize-hook='rm -rf "$1/work"' \
    --customize-hook='cp -r --no-preserve=mode,ownership /src/rootfs/overlay/. "$1/"' \
    --customize-hook='test -e "$1/usr/lib/firmware/brcm/brcmfmac43340-sdio.bin" || { echo "firmware-brcm80211 lacks brcmfmac43340-sdio.bin" >&2; exit 1; }' \
    --customize-hook="test -f \"\$1/boot/vmlinuz-$release\" && test -d \"\$1/lib/modules/$release/kernel\"" \
    --customize-hook="install -d -m 0755 -o 1000 -g 1000 \"\$1/var/lib/edison-sketch\"" \
    --customize-hook='install -m 0644 /work/edison-image-release "$1/etc/edison-image-release"' \
    --customize-hook='. /work/edison-image-release; printf "\nopen-edison edison-image %s (kernel %s)\n%s\n\n" "$VERSION" "$KERNEL" "$URL" > "$1/etc/motd"' \
    --customize-hook='ln -sf /var/lib/edison/wifi/wpa_supplicant-wlan0.conf "$1/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"' \
    --customize-hook='for f in /usr/bin/login /usr/sbin/agetty /usr/sbin/sshd /usr/sbin/wpa_supplicant /usr/sbin/rfkill /usr/bin/gpioset /usr/sbin/i2cdetect /usr/sbin/mkfs.ext4 /usr/sbin/e2fsck /usr/bin/script /usr/bin/fw_setenv /usr/sbin/apparmor_parser /usr/sbin/edison-config; do test -x "$1$f" || { echo "missing $f in rootfs" >&2; exit 1; }; done' \
    --customize-hook='for u in edison-acpi-tables edison-gadget edison-config-restore edison-sketch.path edison-pinmux.socket; do chroot "$1" systemctl is-enabled -q $u || { echo "$u not enabled by edison-base" >&2; exit 1; }; done' \
    --customize-hook='chroot "$1" systemctl enable systemd-networkd systemd-resolved systemd-timesyncd wpa_supplicant@wlan0' \
    --customize-hook="chroot \"\$1\" useradd -m -s /bin/bash -G sudo,netdev,plugdev,dialout,gpio,i2c $USER_NAME" \
    --customize-hook='find "$1/etc/systemd" "$1/etc/udev/rules.d" "$1/usr/lib/systemd/system" "$1/usr/lib/udev/rules.d" -type f -perm /022 -print -exec false {} + >&2 || { echo "group/world-writable config files in rootfs" >&2; exit 1; }' \
    --customize-hook="echo '$USER_NAME:$USER_NAME' | chroot \"\$1\" chpasswd" \
    --customize-hook="chroot \"\$1\" passwd --expire $USER_NAME" \
    --customize-hook='ln -sf /run/systemd/resolve/stub-resolv.conf "$1/etc/resolv.conf"' \
    --customize-hook='rm -f "$1"/etc/ssh/ssh_host_*' \
    --customize-hook=': > "$1/etc/machine-id"; rm -f "$1/var/lib/dbus/machine-id"' \
    --customize-hook='chroot "$1" dpkg-query -W -f="\${Package} \${Version} \${source:Package} \${source:Version}\n" > /out/packages.manifest' \
    --customize-hook='rm -rf "$1"/var/lib/apt/lists/* "$1"/var/cache/apt/*.bin' \
    "$SUITE" "$ROOT" "$MIRROR"

# ext4 image: used space + 25% + 64 MiB headroom; it grows to the partition on first boot.
# The rootfs partition is the rest of the eMMC (about 3.5 GiB); keep the image well below.
used_kib=$(du -sk "$ROOT" | cut -f1)
size_kib=$(( used_kib * 125 / 100 + 65536 ))
max_kib=$(( 3000 * 1024 ))
if [ "$size_kib" -gt "$max_kib" ]; then
    echo "rootfs (${size_kib} KiB) is too big for the rootfs partition" >&2
    exit 1
fi
rm -f /out/rootfs.ext4
mke2fs -q -t ext4 -L rootfs -d "$ROOT" /out/rootfs.ext4 "${size_kib}k"

# FAT boot partition (64 MiB) with the kernel; later kernels come from the linux-image
# packages (edison-base's kernel hook copies them here).
rm -f /out/boot.vfat
mkfs.vfat -n BOOT -C /out/boot.vfat 65536 >/dev/null
mcopy -i /out/boot.vfat /in/kernel/vmlinuz ::vmlinuz

# Redundant U-Boot environment (comments and blank lines stripped first).
grep -v -e '^#' -e '^$' /src/uboot/env.txt > /work/env.txt
mkenvimage -r -s 0x10000 -o /out/u-boot-env.bin /work/env.txt

cp /in/kernel/RELEASE /out/KERNEL_RELEASE
cp /work/edison-image-release /out/edison-image-release
cd /out
sha256sum rootfs.ext4 boot.vfat u-boot-env.bin > SHA256SUMS
chmod 0644 rootfs.ext4 boot.vfat u-boot-env.bin KERNEL_RELEASE SHA256SUMS packages.manifest \
    edison-image-release
echo "rootfs: ${used_kib} KiB used, image $(( size_kib / 1024 )) MiB; kernel ${release}"
