# K114s repair r1 (trackpad, built-in Wi-Fi, USB-C host)

For one machine: MacBook Pro 14-inch OLED, M5 Pro, Mac17,13, `apple,k114s`, board 0x14, with the
Omarchy trial install of 2026-11-13 (kernel `7.3.0-17.v272-4-ARCH`).

This is applied **in place** from macOS. No installer is rerun, nothing is repartitioned, no
Recovery step is needed (the enrolled boot object and boot policy do not change), and the
encrypted Linux root is not opened from macOS. Everything goes onto the existing Linux EFI
partition, which the loader, the boot menu and the firmware loader already read at boot.

**Nothing here has run on a K114s yet.** It was built, booted in an emulator and tested against
replicas. The first real test is your next Linux boot.

## What it changes on the Linux EFI partition (about 270 MB)

| File | Change | Way back |
| --- | --- | --- |
| `EFI/Linux/omarchy_linux-aurora-k114s-r1.efi` | new: repair kernel, trackpad fix B | original entry stays in the boot menu |
| `EFI/Linux/omarchy_linux-aurora-k114s-r1a.efi` | new: repair kernel, trackpad fix A | same |
| `limine.conf` | two entries added first; `r1` is the default; the menu is shown for 5 s | `default original`, `rollback all` |
| `m1n1/boot-ctxr.bin` | K114s device tree with Wi-Fi/Bluetooth, two USB-C ports, sensors | `rollback stage2` |
| `vendorfw/firmware.cpio`, `firmware.tar`, `manifest.txt` | K114s Wi-Fi firmware added; existing files kept | `rollback all` |
| `k114s-repair/` | backups, Linux-side scripts, the pinned device tree | only added; stays after a rollback |

The original kernel image `EFI/Linux/omarchy_linux-aurora.efi` and `m1n1/boot.bin` are never
written.

One caveat: the device tree is shared by every boot entry. If the new tree stops Linux from
starting, the original entry does not help; `rollback stage2` from macOS does.

## Run in macOS (Terminal)

```sh
cd bundle-r1    # the folder this bundle was delivered in
sudo ./k114s-repair check     # read-only: finds the Linux EFI partition, verifies it, writes nothing
sudo ./k114s-repair apply     # shows the plan, asks you to type "apply", backs up, writes, verifies
```

`sudo` asks for your macOS password; that is the only credential. The tool finds the partition
by its contents, refuses any Mac that is not a K114s, refuses if the installed kernel is not the
exact one this was built for, checks free space, and stops without writing if anything does not
match. If `check` stops, send me its output and do not run `apply`.

Then restart, hold the power button, choose **Omarchy**. The boot menu shows for 5 seconds:

1. `Omarchy K114s repair r1 (trackpad fix B)`, the default
2. `Omarchy K114s repair r1a (trackpad fix A)`
3. `Omarchy` > `linux-aurora`, the original kernel

## Check in Linux

```sh
uname -v                         # contains K114S-R1 (or K114S-R1A)
hyprctl devices | sed -n '/mice/,/keyboards/p'
ip -br link                      # a wl* interface should exist
sudo dmesg | grep -iE 'magicmouse|centauri|report_size|xhci|pcie' | tail -40
sudo dmesg > ~/k114s-r1-dmesg.txt
```

Then join Wi-Fi from the Omarchy menu and run `ping -c3 1.1.1.1`.

- Pointer does not move on entry 1: restart and pick entry 2. If neither works, in macOS run
  `sudo ./k114s-repair stage2 gp1c` (the trackpad reset line the 16-inch model needs) and retry.
- The boot menu does not react to the built-in keyboard: change the default from macOS with
  `sudo ./k114s-repair default r1a` (or `default original`).
- No `wl*` interface: `sudo dmesg | grep -i centauri` shows whether the driver
  (`apple_centauri_t6050`) found the radio and its firmware.
- USB-C: the left-front and right ports are USB hosts now, so a USB keyboard, mouse or Ethernet
  adapter is a fallback for input and network. The left-back port stays the debug port.

## If Linux does not start

Hold the power button, choose **Macintosh HD**, then one of:

```sh
sudo ./k114s-repair rollback stage2   # the trial-1 device tree back; keeps the new kernels and firmware
sudo ./k114s-repair rollback all      # limine.conf, device tree and firmware as before; repair kernels removed
sudo ./k114s-repair status            # read-only: what is on the partition now
```

macOS is not touched by any of this and keeps starting.

## After it works: make it stick (in Linux, once)

```sh
sudo bash /boot/efi/k114s-repair/r1/linux-persist.sh
```

This installs the repair kernel image and the patched trackpad module into the Linux system,
makes the boot-file hook rebuild the K114s file instead of the stock one, and holds three
packages (`linux-aurora`, `m1n1-aurora`, `uboot-aurora`), including across an Omarchy channel
refresh. Until it has run, **do not update packages or change the channel**: the stock hook
would replace the K114s boot file and Linux would stop starting. `--undo` reverses it.

## What is tested, and what is not

| | State | Evidence in `../logs/`, `../tests/` |
| --- | --- | --- |
| Kernels r1 and r1a | built; release string and config identical to the installed kernel; an untouched module matches the installed copy byte for byte; the two kernels differ only in the trackpad drivers | `cmp-build-vs-installed.log`, `config-diff-r1b.txt`, `cmp-objects-*.log` |
| Repair boot images | booted in QEMU: kernel starts, initramfs unpacks, the patched module is the one present, 77 of 78 original modules load, the same as under the original kernel | `qemu3-ctl.log`, `qemu5-r1.log`, `qemu5-r1a.log` |
| macOS apply/rollback tool | 67 tests against a replica of the partition; not yet run on the real one | `test-macos-tool.log` |
| Linux persistence script, boot-file hook, hold helper | 36 + 14 tests in a fake root on Linux; the hook rebuilds the exact file from the image's real `boot.bin` | `test-persist.log`, `test-hook.log` |
| Device trees | built with a pipeline that reproduces the image's own K114s and J714s trees byte for byte; lint: pin ranges fit, only pin 80 exposed | `../tests/lint-dtb.py`, `cmp-build-vs-installed.log` |
| Trackpad, Wi-Fi, Bluetooth, USB-C on a K114s | **not tested**: needs your boot | |
| Omarchy Edge updates with the repair in place | **not tested**; only the hold-keeping hook is built | `../REPAIR-NOTES.md` |

Not run: the upstream KUnit case for the trackpad descriptor clamp, and two shell tests of the
installer tree that need Bash 5.

Not included on purpose: OLED brightness and the display coprocessor, GPU acceleration, speakers,
microphones, camera, touchscreen, Touch ID, sleep fixes, SD reader. The display stays the boot
framebuffer.

## Sources

Exact pins are in `manifest.json` (`sources`), the device tree sources and both upstream trackpad
patches in `src/`, and the build host scripts in `src/build-scripts.txt`.
