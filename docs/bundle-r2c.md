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

## Which Stage 2 the tool knows

`status` and `stage2` start from what `m1n1/boot-ctxr.bin` is now (`stage2` refuses to replace an `unknown` one; `rollback stage2` restores the backup
whatever the live file is). A Stage 2 is
`<Aura loader> <device tree(s)> <gzip U-Boot>`. `split_known` in `macos/tools/k114s_repair.py` cuts it at each
known loader's length and accepts it only when the cut-off prefix is exactly that loader (sha256) and the tail is
exactly a known U-Boot (sha256). The tree is not checked: `status` prints `<loader>-loader-other-trees(N)` for N trees,
and `stage2` replaces the whole file. A loader or tail that is not listed gives `unknown`, `stage2` stops, and nothing
is guessed from a length or a name. The lists are:

| Source | Loaders | U-Boot tails |
|---|---|---|
| `manifest.json` of the bundle (`installed`, `bundle`) | the r2c-era `m1n1-aurora`, 3,997,696 bytes | its `uboot_trailer_sha256` |
| `KNOWN_LOADERS`, `KNOWN_TRAILERS` in the tool | `pin` (4,063,232, `beceb683...`), `aura-b13` (3,932,160, `4742dd6a...`, configured since 2026-11-23), `aura-b15` (3,932,160, `788277b6...`, the self-built one of `docs/r3d-stage2.md` on branch `r3d/stage2-tree`) | `aurora9` (`6ee8bd9f...`) |
| `k114s-repair/known-loaders.json` on the ESP | whatever the Linux side listed | likewise |

A Stage 2 is known when its loader is in any of the three loader lists and its tail in any of the three tail lists. The
ESP file only adds entries (`{"loaders": [{"name", "bytes", "sha256"}], "trailers": [{"name", "sha256"}]}`); a missing file
adds none, a damaged one is ignored (`status` says so on its `known-loaders.json:` line), and an entry that is not a name,
a byte count and a lower-case sha256 is dropped. The built-in lists are the fallback that works with no file, and a
promoted Stage 2 with a new loader or U-Boot needs one change here: a line in the table above, from `tools/k114s-repair-tool-install`.

### The copy on the ESP

The Mac does not get the tool from this repository. It gets `k114s-repair/promotion/k114s_repair.py` from the ESP, which the
owner copies over `tools/k114s_repair.py` in the repair bundle folder (`docs/r3a-promotion.md` P4b,
`docs/r3-display-d5-d9.md` M9). That copy is put there by root on the Linux machine, from a checkout of this repository, and
**nothing updates it by itself**: not `repo-sync`, not the pacman hooks, not `k114s-release`. The runbook steps
(P0e, D9p) wrote it by hand, so it is as old as the last of those steps; on 2026-11-23 it was older than the repository's
tool. The step that does it:

```sh
sudo python3 -B -I tools/k114s-repair-tool-install --check    # reads everything, says what it would write
sudo python3 -B -I tools/k114s-repair-tool-install            # writes the tool and the list
```

Run it from a worktree of this repository (`-B` keeps root from leaving `__pycache__` there),
after every change to `macos/tools/k114s_repair.py` and after every Stage 2 promotion (`k114s-release stage2`). It checks that the
configured Stage 2 starts with the loader file it was built from (`/usr/lib/asahi-boot/m1n1-ctxr.bin`, else `m1n1.bin`; or
`--loader FILE`), carries one K114s device tree and ends in a gzip U-Boot, then writes two files on the ESP, each through a
temporary file, a sync, a rename and a read back: the tool (the one it replaces is kept as `k114s_repair.py.prev`) and
`known-loaders.json` (entries already in it stay; a loader or tail the tool already has built in is not listed twice). It writes
nothing else and about 100 KB at most. Then, on the Mac, copy the file again and run `sudo ./k114s-repair status`: the
`Stage 2 (boot-ctxr)` line must not say `unknown`. Test: `tests/macos/test-repair-tool-install.sh`.

## Not included

OLED brightness and the display coprocessor, GPU acceleration, speakers, microphones, camera,
touchscreen, Touch ID, sleep fixes, SD reader. The display stays the boot framebuffer. These are
tracked per subsystem in the repository's `docs/matrix.md`.

## Sources

Exact pins are in `manifest.json` (`sources`); the device tree sources, both upstream trackpad
patches and the kernel build scripts are in `src/`.
