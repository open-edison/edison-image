# Mainline LTS kernel for the Edison, pinned by version and tarball checksum.
# Build with: docker build --output out/kernel -f docker/kernel.Dockerfile .
ARG BASE=debian:trixie-slim

FROM ${BASE} AS build
ARG KERNEL_VERSION=6.18.56
ARG KERNEL_SHA256=4633bbda2ab95eaf2a7af4041236451d6759c72e6946265531af4b3aacefbf89
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils patch \
      gcc make bc bison flex libssl-dev libelf-dev cpio kmod python3 \
      build-essential dpkg-dev debhelper rsync libdw-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN curl -fsSLO "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/linux-${KERNEL_VERSION}.tar.xz" \
 && echo "${KERNEL_SHA256}  linux-${KERNEL_VERSION}.tar.xz" | sha256sum -c - \
 && tar xf "linux-${KERNEL_VERSION}.tar.xz" --strip-components=1 \
 && rm "linux-${KERNEL_VERSION}.tar.xz"

COPY kernel/patches/ /patches/
RUN for p in /patches/*.patch; do echo "applying ${p##*/}"; patch -p1 --forward --no-backup-if-mismatch < "$p" || exit 1; done

COPY kernel/fragments/ /fragments/
COPY kernel/required.txt kernel/check-config.sh /config/
RUN scripts/kconfig/merge_config.sh -m arch/x86/configs/x86_64_defconfig \
      /fragments/edison-fw/*.cfg /fragments/open-edison.cfg \
 && make olddefconfig \
 && sh /config/check-config.sh .config /config/required.txt

RUN make -j"$(nproc)" bzImage modules

# The kernel's own Debian packaging (linux-image-<release>: /boot/vmlinuz-<release>, its
# config and System.map, /lib/modules), in a separate step so that a new package version
# reuses the compiled tree. No headers package; the linux-libc-dev it always builds is
# dropped, as Debian's own version belongs on the board.
ARG KDEB_PKGVERSION=0~local
RUN DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders \
    DEBFULLNAME=open-edison DEBEMAIL=open-edison@users.noreply.github.com \
    make -j"$(nproc)" bindeb-pkg KDEB_PKGVERSION="${KDEB_PKGVERSION}" KDEB_CHANGELOG_DIST=trixie \
 && mkdir -p /out \
 && mv /linux-image-*.deb /out/ \
 && rm -f /out/linux-image-*-dbg_*.deb \
 && cp .config /out/config \
 && cp System.map /out/System.map \
 && make -s kernelrelease > /out/RELEASE \
 && echo "${KDEB_PKGVERSION}" > /out/PKGVERSION \
 && cd /out && sha256sum linux-image-*.deb > SHA256SUMS

FROM scratch
COPY --from=build /out/ /
