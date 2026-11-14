# K114s repair, bundle r2

For one machine class: MacBook Pro 14-inch OLED, M5 Pro, Mac17,13, `apple,k114s`, board 0x14, with
the Omarchy trial install built on betizzel/omarchy-m5's J714s release 3 (kernel
`7.3.0-17.v272-4-ARCH`).

**What r2 is.** The boot files are r1's, byte for byte: repair kernels r1 and r1a (trackpad), the
K114s device tree with Wi-Fi/Bluetooth, two USB-C host ports and sensors, and the K114s Wi-Fi
firmware. What is new is the Linux-side update handling in `linux/`:

| | r1 | r2 |
| --- | --- | --- |
| Packages kept held | three (kernel, loader, U-Boot) | every package the installed image pinned itself, plus those three; restored after an Omarchy channel refresh |
| If the holds are lost | the upgrade goes ahead | a pacman pre-transaction hook stops any transaction on the boot-chain packages before anything changes |
| Channel switch | swaps Omarchy for Edge's build, untested | stopped by the same hook until that combination has been run |
| Omarchy's post-update boot check | fails on every update ("do not reboot yet") | told that this Mac's owner manages its boot chain: it warns and the update finishes |
| Orphan cleanup | could remove a held package | the boot-chain packages are marked explicitly installed |
| Which ESP gets written | whatever is mounted at `/boot/efi` | refuses an ESP this boot did not come from (betizzel release 4's check) |
| Before an update | nothing | `k114s-edge-check`: a read-only solve of the pending upgrade |
| Record of the state before | none | package list and boot-file checksums |

**Nothing here has run on a K114s yet.** The kernels booted in an emulator, the tools were tested
against replicas, and the update handling ran inside a copy of the installed image (see
`docs/edge-update-path.md` in the repository). The first real test is the next Linux boot.

It is applied in place from macOS. No installer is rerun, nothing is repartitioned, no Recovery
step is needed, and the encrypted Linux root is not opened from macOS.

## What it changes on the Linux EFI partition (about 270 MB)

| File | Change | Way back |
| --- | --- | --- |
| `EFI/Linux/omarchy_linux-aurora-k114s-r1.efi`, `...-r1a.efi` | new: the two repair kernels | the original entry stays in the boot menu |
| `limine.conf` | two entries added first; `r1` is the default; the menu shows for 5 s | `default original`, `rollback all` |
| `m1n1/boot-ctxr.bin` | K114s device tree with Wi-Fi/Bluetooth, two USB-C ports, sensors | `rollback stage2` |
| `vendorfw/firmware.cpio`, `firmware.tar`, `manifest.txt` | K114s Wi-Fi firmware added; existing files kept | `rollback all` |
| `k114s-repair/` | backups, the pinned device tree, the Linux-side files in `r2/` | only added; stays after a rollback |

The original kernel image `EFI/Linux/omarchy_linux-aurora.efi` and `m1n1/boot.bin` are never
written. The device tree is shared by every boot entry: if the new tree stops Linux from starting,
the original entry does not help, and `rollback stage2` from macOS does. Before it writes, the
tool also keeps a checked copy of the current boot files on the Mac, under `work/`.

On an ESP that already has r1's boot files, `apply` adds only `k114s-repair/r2/`.

## Run in macOS (Terminal), from this folder

```sh
sudo ./k114s-repair check     # read-only: finds the Linux EFI partition, verifies it, writes nothing
sudo ./k114s-repair apply     # shows the plan, asks you to type "apply", backs up, writes, verifies
sudo ./k114s-repair status    # read-only: what is on the partition now
```

The tool finds the partition by its contents, refuses any Mac that is not a K114s, refuses if the
installed kernel is not the exact one this was built for, and stops without writing if anything
does not match.

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
tr -d '\0' < /proc/device-tree/chosen/asahi,efi-system-partition; echo
```

- Pointer does not move on entry 1: restart and pick entry 2. If neither works, in macOS run
  `sudo ./k114s-repair stage2 gp1c` and retry.
- The boot menu does not react to the built-in keyboard: from macOS, `sudo ./k114s-repair default r1a`
  (or `default original`).
- No `wl*` interface: `sudo dmesg | grep -i centauri`.
- The left-front and right USB-C ports are USB hosts now: a USB keyboard, mouse or Ethernet adapter
  is a fallback. The left-back port stays the debug port.

## If Linux does not start

Hold the power button, choose **Macintosh HD**, then:

```sh
sudo ./k114s-repair rollback stage2   # the trial-1 device tree back; keeps the new kernels and firmware
sudo ./k114s-repair rollback all      # limine.conf, device tree and firmware as before; repair kernels removed
```

macOS is not touched by any of this.

## After it works: make it stick (in Linux, once)

```sh
sudo bash /boot/efi/k114s-repair/r2/linux-persist.sh
```

Until it has run, do not update packages. After it has run:

- *Update > Omarchy* is expected to work; its last step warns that this Mac's owner manages the
  boot chain, which is this repair.
- `sudo /usr/local/lib/omarchy-k114s/k114s-edge-check` shows what an update would change, without
  changing anything.
- *Update > Channel* stops with "K114s hold guard: stopped" and changes nothing. The switch swaps
  Omarchy itself for Edge's build, and that combination has not run on a K114s. Everything else
  already follows the Edge repositories.
- `--undo` reverses everything the script did.

## Not included

OLED brightness and the display coprocessor, GPU acceleration, speakers, microphones, camera,
touchscreen, Touch ID, sleep fixes, SD reader. The display stays the boot framebuffer. These are
tracked per subsystem in the repository's `docs/matrix.md`.

## Sources

Exact pins are in `manifest.json` (`sources`); the device tree sources, both upstream trackpad
patches and the kernel build scripts are in `src/`.
