# Troubleshooting

How to tell what state an Edison is in, and fixes for the common problems. The board's
hardware and its quirks are described in [hardware.md](hardware.md); flashing in the guides
for [Linux](flashing-linux.md), [macOS](flashing-macos.md) and [Windows](flashing-windows.md).

## What state is my board in?

Nothing here writes to the board. You need the Edison on the Arduino kit, SW1 towards the
micro-USB ports, and micro-USB **data** cables (charge-only cables are the most common reason
nothing shows up).

### 1. Watch the serial console

Plug a cable into **J3** before powering the board, so you see the boot from the start, and
open the port at 115200 8N1 with no flow control:

- **Linux:** `picocom -b 115200 /dev/ttyUSB0` (exit with Ctrl+A, Ctrl+X).
- **macOS:** `screen /dev/cu.usbserial-* 115200` (exit with Ctrl+A, K).
- **Windows:** PuTTY (or KiTTY), connection type Serial, the *USB Serial Port (COMx)* from
  Device Manager. If it shows as an unknown device, install FTDI's VCP driver.

Then power the board (DC jack, or J16) and watch for a minute without typing:

| The console shows | The board has | Next |
|---|---|---|
| `U-Boot 2026.xx`, then edison-image's boot messages or `edison login:` | edison-image | Log in, or reflash: the flashing guides |
| `U-Boot 2026.xx`, then failing to boot and starting again | This project's U-Boot, no OS (as after recovery) | Flash edison-image |
| `U-Boot 2014.04`, then Intel's Yocto Linux | Intel's original software | Flash edison-image |
| Boot firmware messages (`PSH KERNEL VERSION`, …) ending in `*** Ready to receive application ***`, no U-Boot, the same again every 1-2 minutes | No working U-Boot; the boot ROM is fine | Recover with [edison-recovery](https://github.com/open-edison/edison-recovery), then flash |
| Garbage characters | | Check the speed: 115200 |
| Nothing | | Reseat or swap the cable, check the port and the power; then step 2 |

### 2. Check what appears on J16

Connect J16 to the computer. What it shows depends on the state:

| USB device | When |
|---|---|
| A network adapter and a serial port | edison-image is running |
| `8087:0a99` (DFU) for 3 seconds | Each boot, while U-Boot waits for a flasher; held for flashing by `sudo edison-dfu` |
| `8086:e005` for **under a second** | Each boot of a board with no working U-Boot (the boot ROM's download mode) |

`8086:e005` is too brief to catch by looking. Both Windows and Linux record it, though:
leave the board running for a few minutes (it restarts itself every 1-2 minutes), then
check the history.

- **Windows (PowerShell):** every Intel device Windows has seen, with when it last arrived:

  ```
  Get-PnpDevice | Where-Object InstanceId -match 'VID_808[67]' | ForEach-Object { [pscustomobject]@{ Id = $_.InstanceId; LastArrival = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_LastArrivalDate).Data } }
  ```

- **Linux:**

  ```
  journalctl -k | grep -iE "idVendor=808[67]"
  ```

If nothing at all appears on either port, suspect the cables before the board: swap the two
cables between J3 and J16 (a cable that works on the console carries data), and check that
SW1 is towards the micro-USB ports.

## Common problems

| Symptom | Cause and fix |
|---|---|
| Nothing appears on USB or the console | Charge-only or loose cable (swap J3 and J16 cables), SW1 in host mode, or no power. See above. |
| An unknown device, or "error -32" in the host's log, for a few seconds at power-on | U-Boot's DFU window (5 seconds with edison-image, 3 right after recovery). Harmless. |
| `8250_mid 0000:00:04.0: probe with driver 8250_mid failed with error -16` at every boot | Harmless. PCI function 04.0 isn't a UART but the UARTs' shared register block, with the same PCI ID; the kernel refuses it on purpose (it has a bogus IRQ 0). The three UARTs (ttyS0–ttyS2) are unaffected. |
| `flash.py` finds no DFU device, or misses the window | See your flashing guide's troubleshooting. `sudo edison-dfu` on a running board holds DFU mode open. |
| Windows: the DFU device has no driver | Install WinUSB for it with Zadig: [flashing-windows.md](flashing-windows.md), step 4. |
| Many header pins don't work; `edison-acpi-tables.service` failed with "TRI_STATE_ALL not found" | The reset button was pressed while Linux ran, which leaves an I/O expander unresponsive. Unplug all power (DC and both USB cables) and reconnect. Use `sudo reboot` instead of the button. |
| The USB port or the board cuts out under load | USB power is limited to 500 mA. Use the DC supply, especially with WiFi or shields. |
| No I2C device answers once several breakout boards are connected | Too many pull-ups on SDA/SCL. Keep one board's at most: [hardware.md](hardware.md#quirks). |
| A 3.3 V module (TFT display, sensor) misbehaves | The header's I/O runs at IOREF, 5 V as shipped. Set J9 to 3.3 V: [hardware.md](hardware.md#jumpers). |
| `apt update` fails with "Not live until …" | The board has no battery-backed clock. Wait for it to sync over the network. |
| Can't find the board's address | Over USB it's always `192.168.2.15`. On WiFi, use `edison.local`. |
| An Arduino sketch's pin does nothing | Check the sketch's log: `journalctl -u edison-sketch`. IO0/IO1 (UART1) and A4/A5 (I2C) are reserved, and say so there. |
| An Arduino upload asks for a password | Only the first upload from each computer, and the first after a reflash, needs it: see [arduino-core-edison](https://github.com/open-edison/arduino-core-edison#uploading). |
| `pulseIn()` or interrupt timings are off | See [GPIO timing](hardware.md#gpio-timing). |
| The board resets during shutdown, or panics with "Kernel Watchdog" | Watchdog settings changed from edison-image's: see [hardware.md](hardware.md#quirks). |
