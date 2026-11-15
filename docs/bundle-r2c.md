# K114s repair, bundle r2c (r2 compact)

For one machine class: MacBook Pro 14-inch OLED, M5 Pro, Mac17,13, `apple,k114s`, board 0x14, with
the Omarchy trial install built on betizzel/omarchy-m5's J714s release 3 (kernel
`7.3.0-17.v272-4-ARCH`).

**Why r2c.** Bundle r2 needed about 477 MB on the Linux EFI partition, which has 524 MB in all and
about 139 MB free (its `check` stopped there and wrote nothing). r2c carries the same fixes in
about 112 MB:

- ONE repair kernel image (trackpad fix B, `r1`, by default). The other trackpad fix, `r1a`, is
  swapped in with one command if B does not move the pointer.
- The K114s Wi-Fi firmware rides inside that image's own initramfs. The image's vendor firmware
  archives are not rewritten.
- The Linux finish step takes the kernel and the firmware out of that image, so no second copies
  sit on the partition.

Same boot fixes as r1 and r2: the trackpad kernels, the K114s device tree with the Wi-Fi/Bluetooth
radio, two USB-C host ports and sensors. **Nothing in it has run on a K114s yet.**

It is applied in place from macOS. No installer is rerun, nothing is repartitioned, no Recovery
step is needed, and the encrypted Linux root is not opened from macOS.

## What it changes on the Linux EFI partition

| File | Change | Way back |
| --- | --- | --- |
| `EFI/Linux/omarchy_linux-aurora-k114s.efi` | new: the repair kernel image (about 112 MB) | `rollback all` deletes it |
| `limine.conf` | one entry added first and made the default; the menu shows for 5 s | `default original`, `rollback all` |
| `m1n1/boot-ctxr.bin` | K114s device tree with Wi-Fi/Bluetooth, two USB-C ports, sensors | `rollback stage2` |
| `k114s-repair/` | backups of the two files above, the pinned device tree, the Linux-side files in `r2c/` | only added; stays after a rollback |

Not changed: the original kernel image (`EFI/Linux/omarchy_linux-aurora.efi`) and its snapshot
copy, `m1n1/boot.bin`, the vendor firmware, and the installer's data in `asahi/`. Before it
writes, the tool also keeps a checked copy of the current boot files on the Mac, under `work/`.

The device tree is shared by every boot entry. If the new tree stops Linux from starting, the
original entry does not help; `rollback stage2` from macOS does.

`check` prints the space plan: the writes are walked in order, a replaced file counts twice
while both copies exist, and an 8 MB margin must stay free at every step and afterwards.

## Run in macOS (Terminal), from this folder

```sh
sudo ./k114s-repair check     # read-only: finds the Linux EFI partition, verifies it and the space, writes nothing
sudo ./k114s-repair apply     # shows the plan, asks you to type "apply", backs up, writes, verifies
sudo ./k114s-repair status    # read-only: what is on the partition now
```

Then restart, hold the power button, choose **Omarchy**. The boot menu shows for 5 seconds:

1. `Omarchy K114s repair r1 (trackpad fix B)`, the default
2. `Omarchy` > `linux-aurora`, the original kernel (and its snapshot entry)

## Check in Linux

```sh
uname -v                         # contains K114S-R1
hyprctl devices | sed -n '/mice/,/keyboards/p'
ip -br link                      # a wl* interface should exist
sudo dmesg | grep -iE 'magicmouse|centauri|report_size|xhci|pcie' | tail -40
tr -d '\0' < /proc/device-tree/chosen/asahi,efi-system-partition; echo
```

- The pointer does not move: in macOS, `sudo ./k114s-repair kernel r1a`, then restart and try
  again (the entry is then called "trackpad fix A"). If neither works, `sudo ./k114s-repair stage2 gp1c`.
- No `wl*` interface: in Linux, `sudo bash /boot/efi/k114s-repair/r2c/linux-persist.sh`, then
  restart. It installs the Wi-Fi firmware on the Linux disk as well.
- The boot menu does not react to the built-in keyboard: in macOS, `sudo ./k114s-repair default original`.
- The left-front and right USB-C ports are USB hosts now. The left-back port stays the debug port.

## If Linux does not start

Hold the power button, choose **Macintosh HD**, then in this folder:

```sh
sudo ./k114s-repair rollback stage2   # the trial-1 device tree back; keeps the repair kernel
sudo ./k114s-repair rollback all      # limine.conf and device tree as before; repair kernel removed
```

**While the r3a kernel trial is in progress** (`docs/r3-integration.md`) the original kernel image
`EFI/Linux/omarchy_linux-aurora.efi` is off the ESP on purpose. Then `rollback all` would leave no Linux entry that
starts: with the tool from this branch it stops and writes nothing. Use `rollback stage2`, `stage2 r1` and `default repair`, and run `status`
afterwards. **The earlier delivered tool cannot be used in that state at all**: it finds the ESP by that image, so every command, including `status`, stops with
"expected exactly one Omarchy ESP, found 0" and writes nothing. (The text "is not an Omarchy ESP" appears only in `--esp-dir` test mode.) The fixed tool therefore has to be in the bundle on the Mac, and `status` confirmed there, before the image is removed.

macOS is not touched by any of this.

## Linux finish step (optional for the first test)

```sh
sudo bash /boot/efi/k114s-repair/r2c/linux-persist.sh
```

It makes the repair survive a later rebuild of the boot image, holds the K114s boot packages, and
installs guards. `--undo` reverses it.

**Do not update packages during this trial**, before or after it. With the repair on it, the
EFI partition has about 20 MB free, and an update can rebuild an 80 MB boot image there. After
the finish step a guard stops package changes until the partition has 100 MB free. The Omarchy
channel switch is stopped as well. Making room on the partition is a separate later step.

## Not included

OLED brightness and the display coprocessor, GPU acceleration, speakers, microphones, camera,
touchscreen, Touch ID, sleep fixes, SD reader. The display stays the boot framebuffer. These are
tracked per subsystem in the repository's `docs/matrix.md`.

## Sources

Exact pins are in `manifest.json` (`sources`); the device tree sources, both upstream trackpad
patches and the kernel build scripts are in `src/`.
