# Contributing to edison-image

## Build from source

Needs Docker on Linux (WSL2 works). The rootfs step runs a privileged container, because
`mmdebstrap` mounts `/proc` in the chroot. CI runs exactly these scripts.

```
scripts/build.sh
```

`scripts/build.sh uboot|kernel|rootfs` builds one stage. Outputs:
- `out/uboot/`: mainline U-Boot, built from
  [edison-recovery](https://github.com/open-edison/edison-recovery) at the commit pinned
  in `scripts/build.sh` (set `EDISON_RECOVERY_DIR` to use a local checkout instead)
- `out/kernel/`: the kernel package (`linux-image-<release>_*.deb`), `vmlinuz`, `config`
- `out/image/`: `boot.vfat` (kernel), `rootfs.ext4`, `u-boot-env.bin`, `packages.manifest`,
  and `debs/`: our packages (below), which the rootfs installs like any other
- `out/cache/`: downloaded Debian packages, reused by later builds

Then `uv run scripts/flash.py` flashes `out/`.

## Layout

| Path | Purpose |
|---|---|
| `docker/kernel.Dockerfile` | Kernel build: pinned tarball, patches, config, required-symbol check, `make bindeb-pkg` |
| `docker/rootfs.Dockerfile` | Tooling image for the rootfs build |
| `kernel/fragments/edison-fw/` | Config fragments from edison-fw/meta-intel-edison (MIT), unchanged |
| `kernel/fragments/open-edison.cfg` | Our overrides: built-in eMMC/ext4/console, systemd needs, debug off |
| `kernel/patches/` | edison-fw patches still needed on 6.18 (8250_mid DMA, dwc3, tusb1210), and ours (`01xx`: spidev's chip select on ACPI, DMA only for long transfers on SPI5) |
| `kernel/required.txt` | Symbols the build checks after `olddefconfig` |
| `rootfs/build-rootfs.sh` | Our packages (via `package/build-debs.sh`), `mmdebstrap`, images |
| `rootfs/packages.txt` | Debian packages |
| `rootfs/overlay/` | Image-only files (`fstab`, hostname, locale), not packaged |
| `package/edison-base/` | The `edison-base` package's files at their installed paths: units, udev rules, network config, tools in `usr/sbin` (`edison-config` handles the settings that survive reflashing, `edison-dfu` the one-shot DFU request), the kernel hook that copies new kernels to the boot partition, the apt source and signing key |
| `package/debian/` | Packaging (debhelper) for `edison-base`, `edison-firmware` and the `linux-image-edison` meta package; the version comes from `git describe` |
| `package/firmware.lock` | Edison WiFi NVRAM and Bluetooth firmware (`edison-firmware`): URLs + SHA256 |
| `acpi/` | Arduino kit ACPI overlays (meta-acpi) and which ones to load |
| `uboot/env.txt` | U-Boot environment: partition layout, boot flow, DFU (window and one-shot request) |
| `docs/` | Per-OS flashing guides |
| `scripts/flash.py` | DFU flasher, standard library only |
| `scripts/apt-repo.sh` | Indexes and signs the apt repository (release workflow) |
| `tests/` | `flash.py` unit tests and a fake `dfu-util` |

## CI and tests

- `.github/workflows/build.yml` builds everything on a GitHub-hosted runner on each push
  and uploads the images (rootfs xz-compressed) as an artifact.
- `.github/workflows/release.yml` runs on `v*` tags: it builds through `build.yml`, checks
  the version stamped into the image matches the tag, and creates the GitHub release with
  notes and every file attached (tags with a `-`, like `v0.2.0-rc1`, become pre-releases).
  It then publishes the apt repository to GitHub Pages: the `.deb` files of the newest three
  releases, signed with the subkey in the `release` environment's secrets
  (`APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE`; only `v*` tags can use them). Pre-releases
  aren't published.
- `.github/workflows/test.yml` runs the `flash.py` unit tests on Linux, macOS and Windows
  (Python 3.9 and 3.13), Ruff (format and lint) and `shellcheck`.

Run them locally before pushing (the tests use only the standard library and a fake
`dfu-util`):

```
uv run --no-project python -m unittest discover -s tests
```

```
uvx ruff format . && uvx ruff check .
```

```
shellcheck scripts/*.sh rootfs/build-rootfs.sh kernel/check-config.sh package/build-debs.sh package/edison-base/usr/sbin/* package/edison-base/etc/kernel/postinst.d/* package/debian/*.postinst
```

## Releasing

1. Make sure `main` is green and the image has passed the hardware checks on a real board:
   flash the CI artifact of the commit you'll tag and check it.
2. Tag and push: `git tag -a v0.2.0 -m "edison-image v0.2.0"` then `git push origin v0.2.0`.
3. The release workflow does the rest. The image reports its version in
   `/etc/edison-image-release` and the login banner.

## Conventions

- **Commits:** [Conventional Commits](https://www.conventionalcommits.org)
  (`feat(rootfs): ...`, `fix: ...`, `docs: ...`).
- **Python:** formatted and linted with Ruff (settings in `pyproject.toml`, 100-column
  code). Standard library only unless a dependency clearly pays for itself; then manage it
  with uv. User-facing output stays within 80 columns (the tests check `flash.py`'s).
- **Shell:** clean under `shellcheck`.
- **Pin every external input** (kernel tarball, U-Boot and xFSTK commits, firmware) by
  version and checksum or commit. Nothing that can't be redistributed goes in the repo;
  fetch it and verify it instead.
- **Builds must work from a clone with only Docker,** using the same scripts as CI.
- **Workflow actions:** pin to the commit SHA of the latest release, with the version in a
  comment (`actions/checkout@<sha> # v7.0.1`). Actions published as immutable releases use
  their exact tag instead (`astral-sh/setup-uv@v10.3.0`). Dependabot opens one grouped pull
  request a month with updates.
- **Hardware changes need a hardware test.** Note what you tested on a real board in the
  pull request, with anything you found that users should know (it belongs in the README or
  the docs).
- **Flashing:** enter DFU with `sudo reboot`, not the reset button (see the README's Notes).
