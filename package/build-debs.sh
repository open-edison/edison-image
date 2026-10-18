#!/bin/bash
# Build our Debian packages (edison-base, edison-firmware, linux-image-edison) into
# /out/debs, next to the kernel package from the kernel build. Run by build-rootfs.sh in the
# tooling container, with /src, /in/kernel and /out as described there, and DEB_VERSION set.
set -euo pipefail

: "${DEB_VERSION:?}"
work=/work/package
rm -rf "$work"
cp -r /src/package "$work"
# Checkouts on some filesystems (WSL's /mnt) show every file as executable, and debhelper
# runs executable config files (.install etc.) as scripts.
find "$work/debian" "$work/edison-base" -type f -exec chmod 0644 {} +
chmod 0755 "$work/debian/rules" "$work"/edison-base/usr/sbin/* "$work"/edison-base/etc/kernel/postinst.d/*
mkdir -p "$work/build/acpi" "$work/build/firmware" /out/debs
rm -f /out/debs/*.deb

# Edison-specific Broadcom files, fetched and verified (see firmware.lock).
while read -r sha name url; do
    case "$sha" in ''|'#'*) continue ;; esac
    curl -fsSL --retry 3 -o "$work/build/firmware/$name" "$url"
    echo "$sha  $work/build/firmware/$name" | sha256sum -c --quiet -
done < /src/package/firmware.lock

# The ACPI table overlays listed in acpi/tables.txt.
defines=$(sed -n 's/^defines: *//p' /src/acpi/tables.txt)
grep -E '^[^#].*\.asl$' /src/acpi/tables.txt | while read -r asl; do
    # $defines is a list of separate -D flags.
    # shellcheck disable=SC2086
    iasl -vs $defines -I /src/acpi/meta-acpi -p "$work/build/acpi/${asl%.asl}" "/src/acpi/meta-acpi/$asl" >/dev/null \
        || { echo "iasl failed for $asl" >&2; exit 1; }
done
ls "$work"/build/acpi/*.aml >/dev/null

# Architecture-independent files only: debhelper is all the build needs (the tooling image
# has it), not build-essential, hence --no-check-builddeps below.
cat > "$work/debian/changelog" <<EOF
edison-image ($DEB_VERSION) trixie; urgency=medium

  * Built from ${IMAGE_COMMIT:-unknown}; see https://github.com/open-edison/edison-image

 -- open-edison <open-edison@users.noreply.github.com>  $(date -R)
EOF

(cd "$work" && KERNEL_RELEASE=$(cat /in/kernel/RELEASE) KERNEL_PKGVERSION=$(cat /in/kernel/PKGVERSION) \
    dpkg-buildpackage --build=binary --no-sign --no-check-builddeps)
cp /work/*_"$DEB_VERSION"_*.deb /in/kernel/linux-image-*.deb /out/debs/
ls -l /out/debs
