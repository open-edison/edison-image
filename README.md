# edison-image

Debian 13 (trixie) for the Intel Edison (Kit for Arduino), on a mainline LTS kernel,
booted by mainline U-Boot.

**Status:** boots and passes the hardware checks (serial, USB networking, SSH, WiFi,
Bluetooth, I2C, GPIO) on a real board. Flashing is tested from Linux, macOS and Windows.

## What you get

- Linux 6.18 LTS (x86_64) with the Edison drivers built in: no initramfs.
- Debian 13 with `apt`, systemd, SSH, WiFi (`wpa_supplicant`), Bluetooth (`bluez`, with
  each board's factory address), `gpiod`, `i2c-tools`.
- **USB networking with nothing to configure on the computer:** plug J16 in, and the Edison
  appears as a USB network adapter (NCM) and hands your computer an address by DHCP.
  The board is `192.168.2.15`, or `edison.local`.
- A USB serial port (ACM) on the same cable, reserved for Arduino sketches as `Serial`
  (see [arduino-core-edison](https://github.com/open-edison/arduino-core-edison)). Log
  in over SSH on the same cable, or on the FTDI serial console on J3.
- Arduino sketches run as the `edison-sketch` service from `/var/lib/edison-sketch/`,
  restarted automatically when a new one is uploaded; the board advertises itself to the
  Arduino IDE over mDNS.
- The Arduino kit's I/O: expanders, level shifters and muxing described by ACPI overlays,
  with UART1 on IO0/IO1 and I2C-6 on SDA/SCL. The other header pins, including IO13 and
  its DS2 LED, are left for sketches to drive.
- **Updates with pt**, the kernel included (see below), and almost the whole eMMC
  (~3.6 GiB) for the root filesystem.

## Get an image

- **Releases:** download from the
  [releases page](https://github.com/open-edison/edison-image/releases).
- **Latest build:** each push to `main` builds the image in CI. Open the newest successful
  [build run](https://github.com/open-edison/edison-image/actions/workflows/build.yml)
  and download its `edison-image-*` artifact (kept for 7 days).
- **From source:** see [CONTRIBUTING.md](CONTRIBUTING.md).

A download contains `u-boot.bin`, `u-boot-env.bin`, `rootfs.ext4.xz`,
`SHA256SUMS`, `packages.manifest` and `flash.py`.

## Flash

Step-by-step guides: **[Linux](docs/flashing-linux.md)** ·
**[macOS](docs/flashing-macos.md)** · **[Windows](docs/flashing-windows.md)**.

In short: install `dfu-util` and [uv](https://docs.astral.sh/uv/), then in the extracted
download run

```
uv run flash.py
```

and reboot the board into DFU mode when asked (`sudo edison-dfu` on a board already running
this image). The board must already run U-Boot with working DFU: a board recovered with
[edison-recovery](https://github.com/open-edison/edison-recovery), or with the vendor
U-Boot.

> **The first flash is a clean slate.** It replaces U-Boot and rewrites the partition
> table: everything on the old rootfs, `update` and `home` partitions is lost. The IFWI
> and the factory partition are never touched.

## First steps on the board

- **Log in** over SSH (`ssh edison@edison.local`) or a serial console: `edison` /
  `edison`. You must change the password at first login. Root login over SSH is disabled;
  use `sudo`.
- **WiFi:**

  ```
  sudo sh -c 'wpa_passphrase "MyNetwork" >> /etc/wpa_supplicant/wpa_supplicant-wlan0.conf'
  ```

  ```
  sudo wpa_cli -i wlan0 reconfigure
  ```

- **Time zone and locale:** `sudo timedatectl set-timezone Area/City`;
  `sudo dpkg-reconfigure locales`. The image defaults to UTC and `C.UTF-8`.

## Updates

The kernel and the Edison-specific parts of the image are Debian packages too, from the
[open-edison apt repository](https://open-edison.github.io/edison-image/) (signed; the
image has its source and key). So one command updates everything:

```
sudo apt update && sudo apt full-upgrade
```

then `sudo reboot` when a new kernel or `edison-base` was installed (services aren't
restarted during an upgrade, so as not to cut off a session over USB networking).

| Package | Contents |
|---|---|
| `linux-image-edison` | Depends on the current kernel, `linux-image-<version>-edison` |
| `edison-base` | The Edison's services, tools (`edison-dfu`, ...), udev rules, network config, ACPI overlays, kernel command line defaults |
| `edison-firmware` | The board's WiFi calibration and Bluetooth patch |

U-Boot and its environment don't update through apt: those need a full flash. Boards
flashed with v0.2.8 or earlier need one full flash with v0.3.0 or later.

## Booting and the kernel command line

The board boots the standard way for U-Boot boards running Debian: kernels live in `/boot`,
and U-Boot reads `/boot/extlinux/extlinux.conf`, which Debian's
[u-boot-menu](https://manpages.debian.org/trixie/u-boot-menu/u-boot-update.8.en.html)
rewrites whenever a kernel is installed or removed. It lists every installed kernel, newest
first, so on the serial console you can pick an older one if a new kernel won't boot (the
menu waits one second). To change the kernel command line, set `U_BOOT_PARAMETERS` in
`/etc/default/u-boot`, run `sudo u-boot-update`, and reboot. Start from the Edison's
defaults (in `/usr/share/u-boot-menu/conf.d/edison.conf`):

```
U_BOOT_PARAMETERS="ro rootfstype=ext4 rootwait console=ttyS2,115200n8 quiet"
```

If the board doesn't boot at all, U-Boot still opens its DFU window at every power-on:
reflash it (below).

## Reflashing

Update with `apt`, as above; a reflash is a reinstall. It replaces the whole root
filesystem, settings and `/home` included, so the board starts fresh: change the password,
set up WiFi again, re-upload the sketch, and expect a new SSH host key. USB networking needs
no setup, so a freshly flashed board is always reachable at `192.168.2.15`. Keep data you
want to survive a reflash elsewhere, such as a microSD card (the Kit for Arduino has a
slot). To reflash, run `sudo edison-dfu` on the board, then `uv run flash.py` on the
computer.

| Partition | Size | Contents |
|---|---|---|
| 1–6 | 32 MiB | U-Boot (×2), its environment (×2), factory data, panic |
| `rootfs` | the rest (~3.6 GiB) | Debian, including `/boot` and `/home` |

## Notes

See **[docs/hardware.md](docs/hardware.md)** for what the board's connectors, switch,
buttons, jumpers and LEDs do, and its known quirks, and
**[docs/troubleshooting.md](docs/troubleshooting.md)** to tell what state a board is in and
for common problems.

- **Use `sudo edison-dfu` or `sudo reboot`, not the reset button:** an abrupt reset while
  Linux is running (the reset button, and presumably a watchdog reset) can leave the kit's
  I/O expander at I2C-1 0x20 unresponsive, because the expanders stay powered while the SoC
  restarts. A clean reboot or a power cycle is fine. The chip has no reset pin and doesn't
  support the I2C general-call reset, so only removing power clears it.
  `edison-acpi-tables.service` then fails with "TRI_STATE_ALL not found"; unplug all power
  and reconnect.
- **Clock:** there's no battery-backed time source, so the board boots with a stale clock
  until `systemd-timesyncd` syncs over the network. `apt update` fails ("Not live until")
  until then.
- **SPI on the header** (IO11–IO13) is switched on by a sketch's `SPI.begin()`; until then
  those pins work as GPIO. Kernel drivers for SPI devices need an ACPI overlay: see
  `acpi/README.md`.
- **AppArmor** is on, as in Debian, with Debian's base profiles (`sudo aa-status`); none
  of the services in this image has a profile of its own, so it matters for profiles you add
  (`apparmor-profiles`, `apparmor-profiles-extra`, your own). It costs about 1.3 s of boot
  and 10 MB of memory; to turn it off, add `apparmor=0` to the kernel command line (above).
  SELinux is disabled: Debian ships no policy for it.

## Licence

Our own code is under the MIT licence (`LICENSE`). Third-party files keep their licences:

| Path | Licence |
|---|---|
| `kernel/patches/` | GPL-2.0 (they modify the Linux kernel) |
| `kernel/fragments/edison-fw/` | MIT, from [edison-fw/meta-intel-edison](https://github.com/edison-fw/meta-intel-edison) |
| `acpi/meta-acpi/` | MIT, Copyright (C) 2017 Intel Corporation, from [westeri/meta-acpi](https://github.com/westeri/meta-acpi) |

**Built images** contain GPL software (Linux, U-Boot, Debian packages). Corresponding
source: Linux from kernel.org at the version and checksum pinned in
`docker/kernel.Dockerfile`, plus `kernel/patches/` and the config in each release
(`kernel.config`); U-Boot at the commit pinned in
[edison-recovery](https://github.com/open-edison/edison-recovery)'s
`docker/uboot.Dockerfile`; Debian packages at the exact versions listed in each release's
`packages.manifest`, available from [snapshot.debian.org](https://snapshot.debian.org/).
The Broadcom WiFi/Bluetooth firmware is redistributed unmodified under
`LICENCE.broadcom_bcm43xx` / Debian's `firmware-brcm80211` terms.

## Credits

Kernel config fragments and patches: [edison-fw/meta-intel-edison](https://github.com/edison-fw/meta-intel-edison)
(Ferry Toth, based on Andy Shevchenko's Edison kernel work). Arduino kit ACPI tables:
[meta-acpi](https://github.com/westeri/meta-acpi) (Intel).
