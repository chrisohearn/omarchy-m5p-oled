# Incident: an Edge channel refresh downgraded the K114s boot chain (2026-11-14)

What happened to the K114s 20 minutes after bundle r2c's first boot, how it was put back, and
what changes because of it. Times are local (MST). Evidence labels follow [UPSTREAM.md](../UPSTREAM.md):
owner-observed, agent-run, emulator/replica.

## Summary

The owner ran an Omarchy update that switched the channel to Edge before `linux-persist.sh` had
been run. The refresh replaced `/etc/pacman.conf` (no `IgnorePkg` line), ran
`pacman -Syyuu --noconfirm`, and downgraded eight packages to Edge's generic builds, which have no
M5 Pro support. Their hooks then overwrote the K114s Stage 2 on the EFI partition. The Mac kept
running; the next boot would not have started Linux. Nothing was lost: every overwritten boot file
was rebuilt from files still on the machine and verified against the hashes bundle r2c recorded.
No reboot happened between the damage and the repair.

This is the failure [edge-update-path.md](edge-update-path.md) describes as path 1 and 3, and
[bundle-r2c.md](bundle-r2c.md) warns about ("Do not update packages during this trial"). The
warning was in a document; nothing on the machine enforced it until the finish step ran.

## Timeline

| Time | Event | Evidence |
| --- | --- | --- |
| 13:46 | Bundle r2c applied from macOS | `k114s-repair/applied-r2c.json` |
| 13:51 | First boot of the repair entry: desktop, keyboard, trackpad (fix B, r1), Wi-Fi associated | trackpad owner-observed; the rest agent-run (`uname -v` contains `K114S-R1`, `wlan0` up) |
| 14:11:04 | `pacman -Syyuu --noconfirm` from the channel refresh | `pacman.log` |
| 14:11:19-32 | Downgraded: `linux-aurora` 7.3.0.aurora17.v272-4 → 7.2.11.aurora16-1, `m1n1-aurora` 1.6.1.aurora24.v272-3 → 1.6.1.aurora23-2, `uboot-aurora` …j714s3-1 → 2026.07.aurora6-1, `omarchy-aurora-firmware` …j714s9-1 → 20261014-7, `mesa-aurora` and `vulkan-aurora` …j714s2 → 20261107, `omarchy` and `omarchy-settings` 4.5.0-3.7141 → 4.5.0-3 | `pacman.log` |
| 14:11:33 | `11-omarchy-mac-saved-modules.hook` moved the running kernel's modules to `/usr/lib/modules/.old` | `pacman.log` |
| 14:11:38 | Standard UKI rebuilt from the stock 7.2.11 kernel; `limine.conf` rewritten (the repair entry and `default_entry: 1` survived); the snapshot copy of the original UKI was pruned | `pacman.log`, ESP listing |
| 14:11:46 | `update-m1n1` wrote a stock `m1n1/boot.bin`; the image's J714s hook copied it over `m1n1/boot-ctxr.bin`. The stock kernel package has no `t6050` device trees, so the Stage 2 no longer carried a K114s tree | hashes: both files `11424729…` |
| 14:11:48 | Channel switch: `omarchy` and `omarchy-settings` replaced by `omarchy-dev` and `omarchy-settings-dev` 4.0.0.r7859; migrations ran | `pacman.log` |
| 14:22 | Stage 2 rebuilt and written back; `pacman.conf` restored from the refresh's own `.bak` | agent-run |
| 14:26 | First Hyprland abort (separate fault, below) | `coredumpctl` |
| 14:31 | Six packages restored from snapshot 1 | agent-run |
| 14:32 | `linux-persist.sh` (r2c) run; `update-m1n1` and the K114s hook re-run | agent-run |
| 14:33 | `/boot` initramfs and the standard UKI rebuilt from the repair kernel | agent-run |
| 15:05-15:10 | Collateral of the 14:31 restore found by review and undone (below); standard UKI rebuilt again | agent-run |
| 15:12 | Reboot into the repair entry: desktop, Wi-Fi, trackpad | owner-observed (desktop, trackpad), agent-run (the rest) |

## How it was put back

1. **Stage 2.** `boot-ctxr.bin` = the image's `m1n1.bin` (from snapshot 1) + `k114s-repair/k114s.dtb`
   + the gzip U-Boot payload cut from `k114s-repair/backup-before-r1/m1n1/boot-ctxr.bin`. Result:
   4,439,364 bytes, sha256 `45a5dbef…e4bfb4`, equal to the `writes` record in `applied-r2c.json`.
2. **Packages.** `linux-aurora`, `m1n1-aurora`, `uboot-aurora`, `omarchy-aurora-firmware`,
   `mesa-aurora` and `vulkan-aurora` were restored file for file from the root snapshot taken at
   install (snapshot 1), together with their entries in pacman's local database. No pacman
   transaction ran, so no hook touched the EFI partition. `pacman -Qkk` reports the same eleven
   depmod files as the snapshot's own baseline and nothing else. The image's package archives were
   not in the cache, which is why this was done from the snapshot.
3. **Proof the restore is exact.** `update-m1n1` then regenerated `m1n1/boot.bin` with sha256
   `3bfbff92…`, the value `applied-r2c.json` recorded before r2c was applied, and the K114s hook
   rebuilt `boot-ctxr.bin` with `45a5dbef…` again.
4. **Guards.** `linux-persist.sh` installed the holds, the hold guard, the EFI space guard, the
   K114s Stage 2 hook and the boot-chain declaration.
5. **Second boot entry.** The standard UKI was rebuilt from the repair kernel (79 MB). It has not
   been booted. The default entry is still the repair UKI, unchanged (`51148ff7…`).

`omarchy-dev` was left installed: the owner wants the Edge channel. That makes the desktop swap
"applied", not "hardware-verified": the session that was running reloaded under it, and a boot
under it is still to come.

## A mistake made during the repair, and its fix

Step 2 used `rsync --files-from` with pacman's file lists. Those lists name directories with a
trailing slash, and with `--files-from` rsync then copies each such directory's immediate files. So
besides the six packages, the copy reverted 190 files of 35 other packages to their snapshot-1
content (the top level of `/usr/bin`, `/usr/lib`, `/usr/lib/pkgconfig` and a few more) and brought
back 733 files of packages removed earlier that day. An independent review caught it 30 minutes
later, before the reboot. Fix: the 190 files restored from snapshot 2 (taken after the upgrade),
five from cached package archives, 690 timestamps reset, the 733 strays moved aside, and
`pacman -Qkk` (which compares SHA-256) run over every installed package: clean apart from the
kernel image and depmod files the finish step replaces on purpose. The lesson for the tooling: a
"repackage the installed package" tool that builds a real archive and lets pacman install it,
instead of copying files around the package manager.

## What the incident showed

- **The guards have to exist before the first boot, not after it.** r2c made the finish step
  optional so the first test stayed small. The cost was a window in which one menu choice undid the
  boot chain. The next bundle installs the holds and the hold guard as part of apply (from macOS the
  root is closed, so that means a first-boot unit carried in the repair image's initramfs or an
  ESP-side marker the image's own first-boot service acts on).
- **Package archives of the held set must be kept.** The recovery worked because snapshot 1 still
  existed. A recovery set (archives of every held package, `/boot`, the ESP boot files, hashes) is
  now a requirement, not an open gap.
- **`IgnorePkg` in the template-managed `pacman.conf` is not a hold.** The image's own comment
  ("Keep these three lines") did not survive the first refresh. The pre-transaction hook is the
  control that would have stopped this; it was sitting unused on the ESP.
- **The EFI partition is the scarce resource.** With the repair UKI (112 MB) and a standard UKI
  (79 MB) it has about 90 MB free, under the space guard's 100 MB, so every package transaction is
  refused until one of them goes. One UKI is the steady state.

## Separate faults found the same afternoon

| Fault | Cause | State |
| --- | --- | --- |
| Hyprland aborts on any mouse click once a workspace is set to floating (six times, 14:26-14:48) | `omarchy-hyprland-titlebars` 0.4.0-1 is built against stock Hyprland 0.57.2 headers. `hyprland-m5` 0.57.2-2 adds three fields (32 bytes) to `CMonitor` for its direct-scanout latch but reports the stock commit hash, so the plugin's version check passes and it reads `m_layerSurfaceLayers` 32 bytes early (agent-run: `offsetof` against the installed headers, disassembly, core) | Plugin file moved aside; package held. Rebuild against `hyprland-m5` headers pending |
| T3 Code (Electron 44) renderer dies with SIGILL | libyuv's SME row functions execute the SVE instruction `cntd` outside streaming mode; this CPU reports SME without SVE (agent-run: core, `objdump`, `/proc/cpuinfo`) | Not a boot-chain fault. To report to the app's upstream |
| `ufw.service` shows failed | Four ICMPv6 rules use the `hl` match; the kernel has `CONFIG_NETFILTER_XT_MATCH_HL` and the `IP6_NF_MATCH_*` options off. The firewall itself is active with default-deny incoming | Kernel configuration, next kernel candidate |
| Bluetooth hands-free profiles fail | `CONFIG_BT_RFCOMM` is not set | Next kernel candidate |
| `speakersafetyd` restarts every 16 s | It looks for `/usr/share/speakersafetyd/apple/k114.conf`, which does not exist; the image is tuned for J714 | Expected until the sound row; the unit should be masked until then |

## Recovery copies kept on the machine

Outside this repository: the stock packages' database entries and file lists, the stock kernel
leftovers, the `pacman.conf` the refresh wrote, and a copy of the verified Stage 2.
