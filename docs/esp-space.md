# The EFI partition: what is on it, the space budget, and what can go

Written 2026-11-15 for issue #65 (Omarchy updates paused by the space guard). Every number below is **agent-run, read-only**
(`df`, `stat -f`, `sudo du -a`, `sudo sha256sum`, `sudo ls`, reading the installed hooks and scripts) on this Mac on 2026-11-15, unless a row
says replica or derived. Nothing was written to the partition and nothing was deleted. File hashes are of our own images, or a 16-character
prefix; no firmware bytes are quoted.

## 1. The two figures that were stale

| | bytes | MiB | what it was called |
| --- | ---: | ---: | --- |
| Partition size (`/dev/nvme0n1p4`, FAT, 4096-byte clusters) | 523,132,928 | 499.0 | "499 MB" |
| Used | 435,449,856 | 415.3 | "415 MB" |
| **Free, today** | **87,683,072** | 83.6 | README and matrix said 87 MB; `df -h` says 84M |
| The installed guard's minimum (`K114S_ESP_MIN_FREE=88080384`, `/etc/pacman.d/hooks/01-k114s-esp-space.hook`) | 88,080,384 | 84.0 | "88 MB" |
| **Short by** | **397,312** | 0.38 | |

"87 MB" in the old text was the guard's own message (bytes divided by 1,000,000, truncated); it is the same number as "84M" in `df -h`.
The shortfall is 388 KiB: the guard refuses every pacman transaction, including ones that never touch the boot files, for 0.4 MB.
README.md and `docs/matrix.md` now carry these figures. The free space was 87,724,032 bytes when `docs/r3-integration.md` was written; it
drifts down by tens of KiB as `limine.conf`, its snapshot history, `aura-try` and the Stage 2 files are rewritten.

## 2. What the partition holds

`sudo du -a /boot/efi` (allocated KiB, largest first; the rest of the 415 MiB is cluster rounding and directory entries):

| Path | KiB | Bytes (apparent) | Role | Who reads it | Boot entry |
| --- | ---: | ---: | --- | --- | --- |
| `EFI/Linux/omarchy_linux-aurora-k114s.efi` | 109,204 | 111,821,824 | the **repair kernel** UKI (r1: trackpad fix B), static, sha256 `51148ff7005d2986...` | Limine | entry 1, `default_entry: 1`, the only entry that is the default |
| `EFI/Linux/omarchy_linux-aurora.efi` | 77,396 | 79,253,504 | the **standard** UKI the Limine hook builds for `linux-aurora` 7.3.0-17.v272-4, sha256 `cce61605...`, b2sum `a3028af4...` (the `#hash` in its menu line) | Limine | entry "Omarchy > linux-aurora" (hook-managed) |
| `vendorfw/firmware.cpio` | 54,940 | 56,256,116 | Apple firmware for the **initramfs**: `asahi` initcpio hook unpacks it from the ESP at every boot | `/usr/lib/initcpio/hooks/asahi` | boot-critical |
| `vendorfw/firmware.tar` | 55,132 | 56,453,120 | the same package as a tar, extracted to `/lib/firmware` by `omarchy-vendor-firmware.service` when newer than `/var/lib/omarchy/vendor-firmware.stamp` (the stamp exists, so it has run) | that unit | user space |
| `asahi/all_firmware.tar.gz` | 55,732 | 57,066,623 | the raw firmware the Asahi installer copied; **source** of `vendorfw/` | `asahi-fwupdate`, `omarchy-mac` Touch ID scripts (`--archive /boot/efi/asahi/all_firmware.tar.gz`) | source |
| `asahi/kernelcache.release.mac17j` | 31,824 | 32,587,084 | kernel-side firmware source for `asahi-fwextract` | `asahi-fwupdate` | source |
| `m1n1/boot.bin` | 9,808 | 10,041,185 | Aura loader + all 46 device trees + U-Boot, built by `update-m1n1`; **not** what the Mac boots, but the source of the U-Boot tail `update-boot-ctxr` reuses | `update-boot-ctxr` | source |
| `m1n1/boot.bin.old` | 9,980 | 10,219,362 | `update-m1n1`'s copy of the previous `boot.bin` (made by `cp` only when the new bundle differs) | nothing (grep of the repository, `/usr/bin`, `/usr/lib/omarchy-mac`, `/usr/share/asahi-scripts`) | none |
| `m1n1/boot-ctxr.bin` | 4,336 | 4,439,364 | the **Stage 2 the Mac boots** (r1 tree), sha256 `45a5dbef19c14898...` | Stage 1 | boot-critical |
| `m1n1/boot-ctxr-r3-gpu.bin` | 4,340 | 4,440,237 | the standing GPU-tree trial, sha256 `9825a10317866865...b8fc` | the `aura-try` trial | trial |
| `k114s-repair/` | 4,632 | | the macOS repair bundle's state: `backup-before-r1/` (4,352: the pre-r1 `boot-ctxr.bin` and `limine.conf`, the `rollback all` target), the pinned r1 tree `k114s.dtb` (108), `r2c/` (the r2c guards, 116), `macos-r3a/` (the fixed macOS tool, 44) | the macOS tool, the Stage 2 hook | recovery |
| `aurora/` | 4,600 | | Stage 1 (`stage1-k114s.bin`, `.macho`) and the macOS recovery app | Apple's boot chain | boot-critical |
| `.Spotlight-V100/`, `.Trashes/` | 1,492 + 12 | | macOS index and trash folders, written when macOS mounted the volume read-write | nothing on Linux | none |
| `EFI/limine/limine_aa64.efi` = `EFI/BOOT/BOOTAA64.EFI` (identical) and `limine_aa64.bak` (older, different hash) | 328 + 328 + 332 | | the boot loader, its fallback path, a backup | firmware | boot-critical (the first two) |
| `asahi/` small files, `installer.log`, `BuildManifest.plist`, `limine.conf`, `limine.conf.old`, `aura-try`, `ubootefi.var`, `loader/random-seed`, `0a06.../limine_history/`, `omarchy/._install.conf`, other small files | under 1,000 together | | | | |

The two kernel images are not duplicates: different kernels (the repair image carries the trackpad fix, the standard one is the hook's build of the
package's kernel). `limine.conf` has exactly two entries, both read from the installed file: entry 1, "Omarchy K114s repair r1 (trackpad fix B)"
(`boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi`, no hash anchor), and "Omarchy > linux-aurora" (`omarchy_linux-aurora.efi#<b2sum>`). There are no
snapshot entries (`limine_history` is 12 KiB). There are no old kernels, no recovery copies of images and no second `boot-ctxr` set on the partition:
the recovery copies are on the root filesystem in `/var/lib/k114s-recovery`.

`aura-try` reads `spent` / `m1n1/boot-ctxr-r3-gpu.bin` today, so no trial is armed.

## 3. The budget

Of the 425,244 KiB `du` reports: kernel images 186,604 KiB (182 MiB), firmware 198,376 KiB (194 MiB: `asahi/` 88,144, the installer's source files, and
`vendorfw/` 110,232, what was extracted from them), loader bundles `m1n1/` 28,468 KiB, the repair bundle and Stage 1 about 9,200 KiB, everything else under
7,000 KiB. Free space is the 83.6 MiB on top of that, and the guard wants 84 MiB kept free.

### 3.1 What a boot-image rebuild needs

`limine-mkinitcpio-install` and `limine-entry-tool` write the new `EFI/Linux/omarchy_<kernel>.efi` **while the old one is still there**
(`linux/k114s-guard`, boot image estimate: "the new one is written while the old one is still there"). So one rebuild needs about one UKI of free space:
79.3 MB for the standard image, 111.8 MB for the repair image (which is static: no hook rebuilds it). The installed r2c guard's 84 MiB is "one 79 MB
image plus about 5 MB". `update-m1n1` needs `boot.bin.new` (10.0 MB) beside `boot.bin`, then copies `boot.bin` to `.old` (10.2 MB): a loader change is
a transient +20 MB, and ends +10 MB net when `.old` did not exist.

### 3.2 What the r3a install frees (it removes the standard UKI)

Runbook step D1 removes the hook-built UKI of `linux-aurora` (`limine-entry-tool --remove-uki linux-aurora`) and step D3 builds
`omarchy_linux-k114s.efi` for the r3a kernel in the same slot.

| | free bytes | against 88,080,384 |
| --- | ---: | ---: |
| Today | 87,683,072 | 397,312 short |
| D1: standard UKI removed (+79,253,504) | 166,936,576 | 78.9 MB over (the guard passes) |
| D3: r3a UKI written (-79,363,072, derived from the replica build; `docs/r3-integration.md` section 5) | **87,573,504** | **506,880 short** |
| Net of the swap | -109,568 | |

Derived, not measured: step D4 on the Mac measures the real value. **The r3a install frees nothing.** It removes one 79.25 MB image and adds a 79.36 MB
image; the partition ends 0.1 MB fuller and 0.5 MB under the guard. The loader files are unchanged (D2 disables `update-m1n1`; the Stage 2 hook rewrites
`boot-ctxr.bin` with the same bytes), `limine.conf` changes by a few lines. The docs already said this ("a trial window, not a steady state");
the table is the number. The runbook's D4 stops the install if the free space is at or above 88,080,384, because that would let the r2c guard pass a
rebuild of **both** kernels' images (158 MB) that cannot fit.

### 3.3 What can be removed, and what it is worth

Rows are ordered by how safe they are. "Free after" is added to today's 87,683,072 on its own, not cumulatively.

| Candidate | Frees (allocated) | Verdict | Why |
| --- | ---: | --- | --- |
| `.Spotlight-V100`, `.Trashes` (and `.fseventsd` if present) | 1.5 MiB | **safe**: tool item `macos-junk` | macOS metadata folders; nothing on Linux or in the boot chain reads them (repository grep, installed hooks). macOS recreates them if it mounts the volume read-write: the runbook already says to mount it read-only. Passes today's guard by 1.1 MB |
| `m1n1/boot.bin.old` | 9.7 MiB | **safe**, but short-lived: tool item `m1n1-old` | no reader anywhere; `update-m1n1` recreates it by `cp` the next time `boot.bin` changes. It is a rollback copy of a file that is not booted. The tool refuses if `boot.bin` or `boot-ctxr.bin` is missing or a Stage 2 switch is pending |
| `EFI/Linux/omarchy_linux-aurora.efi` | 75.6 MiB | **the r3a swap**; or later, never on its own | removed by D1 and replaced by a same-size image. On its own it takes the only standard-kernel entry away (`rollback all` from macOS and the hook both depend on it; `docs/r3-integration.md` section 6) |
| `EFI/Linux/omarchy_linux-aurora-k114s.efi` (repair kernel) | 106.6 MiB | **not now; yes after promotion** | it is the default entry and the only kernel with the trackpad fix. r3a contains the same fix (`pr1568.patch`), so once r3a is promoted (booted clean on all steps, runbook step (iv)) the repair UKI is a second copy of what the hook builds. Dropping it leaves one hook-managed UKI and about 199 MB free (211 MB with the two trims): the steady state `docs/r3-integration.md` section 5 asks for. Owner decision after the r3a trial |
| `k114s-repair/backup-before-r1/` | 4.3 MiB | not now | the pre-r1 `limine.conf` and `boot-ctxr.bin`: what the macOS tool's `rollback all` restores. Keep until r3a is promoted |
| `EFI/limine/limine_aa64.bak` | 0.3 MiB | possible, not worth it | a backup of the loader written by the Limine hook; below the noise |
| `vendorfw/firmware.tar` | 53.9 MiB | **not now; candidate** | already extracted to `/lib/firmware` (the stamp exists), and rebuildable from `asahi/` by `asahi-fwupdate`. But `omarchy-vendor-firmware.service` expects it on every Omarchy firmware update, and asahi-fwupdate itself needs about 110 MB free on the ESP to rebuild (it moves a freshly built `vendorfw.new` onto the ESP before removing the old one). Needs a look at what Omarchy's unit does with no tar, then the owner's go |
| `asahi/all_firmware.tar.gz` + `kernelcache.release.mac17j` | 85.5 MiB together | **not now; candidate with a code change** | the sources of `vendorfw/`; also read from `/boot/efi/asahi/` by the Touch ID scripts. `asahi-fwupdate` reads `ASAHIFW` from `/etc/default/asahi-fwupdate`, so the sources could live on the root filesystem, but the Touch ID scripts' default path and Apple's own installer/recovery use of `asahi/` are unchecked. Not done |
| `vendorfw/firmware.cpio`, `m1n1/boot.bin`, `m1n1/boot-ctxr*.bin`, `aurora/`, `EFI/BOOT/`, `EFI/limine/limine_aa64.efi`, `limine.conf`, `ubootefi.var` | | **never** | the initramfs, the loader and the boot chain read them on every boot |

The only trims that do not need the owner's judgment about firmware or kernels are the first two. Together (11.2 MiB) they clear today's guard (87,683,072 +
about 11.7 MB = 99.4 MB against 88.1 MB) but **do not clear it after the r3a swap with room to spare**: 87,573,504 + 11.7 MB = 99.3 MB passes the
installed guard, which in the window is exactly the case D4 calls a STOP (two kernel directories exist, a rebuild-all needs 158 MB). So:

- **Before the r3a window.** Trimming makes the installed guard pass (99.4 MB free against 88.1 MB). **Restore the trim with `esp-trim --restore <backup>` before runbook step D1**: D4 measures free space after the swap (about 99.3 MB trimmed) and STOPs when it is at or above 88,080,384, so a trimmed ESP loses the attended window. A kernel-only update then fits: it rebuilds
  `omarchy_linux-aurora.efi` (79.3 MB). A transaction that also changes `boot.bin` does not fit if the loader transient and the image write overlap: with `boot.bin.old` gone, `update-m1n1` peaks at
  `boot.bin` + `.new` + `.old` (+20.3 MB over today) plus the 79.3 MB image, about 99.6 MB against 99.4 MB free (nothing here shows the two peaks do not overlap; treat it as the worst case), so at best no margin, and the r2c guard does not count the loader (the
  r3 guard, `k114s-guard`, does: one image per kernel directory + loader transient + 8 MiB margin, and would refuse). So the trims alone are a partial fix; installing
  the r3 tooling first is what makes the pause lift safely.
- **Inside the r3a window**, do not trim to pass the guard. The window has two kernel directories; the r3 guard refuses it correctly. Do not delete `macos-junk` or `boot.bin.old` for
  the window's sake: the swap's 0.5 MB shortfall is not what makes the window unsafe.
- **The real fix** is one UKI: after r3a is promoted, remove the repair image (106.6 MiB), keep the trims for margin, and the guard's own number
  stops mattering.

## 4. `linux/esp-trim`: the dry-run-by-default tool

`linux/esp-trim` removes only the two safe items, nothing else can be named. It is not installed by anything and no hook calls it.

    sudo linux/esp-trim                     # dry run (the default): items, sizes, free after, refusals. Changes nothing
    sudo linux/esp-trim --apply [ITEM...]   # ATTENDED: backs up to /var/lib/k114s-recovery/esp-trim-STAMP, verifies the copies, deletes, syncs
    sudo linux/esp-trim --restore FOLDER    # puts a backup's files back, never over an existing file, only if its SHA256SUMS match

What it checks before it deletes: root, `/boot/efi` is a mount point (a delete on an unmounted ESP would hit the root filesystem), the backup folder
is on root with room for the files plus 50 MiB, the backup is byte-identical to the live files (`sha256sum -c`), and the item-specific refusals above.
A stop at any point leaves the ESP as it was. Evidence: `tests/linux/test-esp-trim.sh`, 32 checks on a replica of the layout (agent-run, replica): the dry run changes
nothing byte for byte, unknown names and paths are refused, kernels, firmware, Stage 2 files, repair bundle and `limine.conf` stay untouched,
apply then restore returns the files byte for byte, a restore never overwrites, a tampered backup restores nothing, an unmounted folder is refused, and failure handling is checked for each stop: a failed rm or apply-sync stops and prints the `--restore` undo command, a failed restore cp removes the partial file and says to run `--restore` again, a failed restore sync says to check the ESP, and a restore refused for too little room says nothing was restored.
**It has not been run on the Mac** and this branch does not run it. The replica cannot show how vfat behaves on the real partition or that
macOS tolerates the missing folders (it recreates them).

**Needs the owner at the Mac** (a write to the boot partition, so attended): the dry run needs root only for reading; `--apply` is the
write. Nothing here needs a reboot, but a bad write to the ESP could cost a forced power-off or macOS recovery.

## 5. What is still open

- Owner decision: whether to trim the two safe items before the r3a window (this document recommends installing the r3 tooling first).
- Owner decision, after the r3a trial: promote r3a and drop the repair image. This is the only change that makes the partition roomy.
- Not checked: whether `asahi/` can leave the ESP (Apple's recovery and the Touch ID scripts), and what Omarchy's `omarchy-vendor-firmware.service`
  does with no `firmware.tar`. Both would free 50 to 90 MB and both need the owner.
- A hazard the guard does not count: `asahi-fwupdate` rebuilds `vendorfw/` on the ESP with the old copy still in place (peak +110 MB). No pacman hook or
  systemd unit under `/usr/share/libalpm/hooks`, `/etc/pacman.d/hooks`, `/usr/lib/systemd/system` or `/etc/systemd/system` runs it (agent-run grep); it is run by hand or by a
  boot script, which was not found.
