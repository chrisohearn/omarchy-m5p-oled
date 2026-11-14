# Updates on the Edge channel

What keeps the K114s boot chain intact through package updates, and how that was tested.
Written 2026-11-14 for bundle r2.

## The situation

The installed image (betizzel/omarchy-m5 release 3) already uses Omarchy's Edge repositories. It
pins the packages its set built itself, in one line of `/etc/pacman.conf`:

```
IgnorePkg = aurora-sep aurora-speaker-upgrade hyprland-m5 libfprint-aurora linux-aurora m1n1-aurora
            mesa-aurora omarchy omarchy-aurora-firmware omarchy-mac omarchy-mac-boot omarchy-settings
            speakerguardd-v2 uboot-aurora vulkan-aurora
```

Edge's packages of those names are older or generic builds with no M5 Pro support. Read from the
image on 2026-11-14, Edge offers `linux-aurora 7.2.11.aurora16-1` against the installed
`7.3.0.aurora17.v272-4`, and likewise older `m1n1-aurora`, `uboot-aurora`, Mesa, firmware and
Omarchy builds. Without the pins a downgrade-capable upgrade installs them.

Three things can remove or bypass the pins:

1. **A channel refresh.** `omarchy-refresh-pacman` copies a template over `/etc/pacman.conf`
   (no `IgnorePkg` line), runs the user hook `pre-refresh-pacman`, then
   `pacman -Syyuu --noconfirm`. Channel changes and `omarchy reinstall` go through it.
2. **A named install or a removal.** pacman asks "is in IgnorePkg. Install anyway? [Y/n]" and
   `--noconfirm` answers yes; `IgnorePkg` never covers removals.
3. **The channel switch itself.** After the refresh it installs `omarchy-dev` and
   `omarchy-settings-dev`, which conflict with and remove `omarchy` and `omarchy-settings`.
   Different names, so no hold applies.

Separately, Omarchy's last update step (`update-verify`, from `omarchy-mac-boot`) compares the
kernel file with its package. The repair replaces that file, so the check fails on every update
and tells the user not to reboot.

## What bundle r2 installs (`linux/linux-persist.sh`, run once in Linux)

| Piece | Effect |
| --- | --- |
| `holds.list` + `apply-holds` | Records the image's own pinned set (read with `pacman-conf` before anything can drop it) plus the K114s boot stack, and writes it back as one managed block. The `pre-refresh-pacman` user hook calls it, so a refresh keeps the whole set, not three names |
| `00-k114s-hold-guard.hook` + `hold-guard` | A pacman pre-transaction hook in `/etc/pacman.d/hooks/`, which the template does not touch. It stops any transaction that installs, upgrades or removes `linux-aurora`, `m1n1-aurora`, `uboot-aurora`, `omarchy-aurora-firmware`, `omarchy-mac-boot` or `limine-mkinitcpio-hook`, or removes `omarchy` or `omarchy-settings`. pacman runs it before changing anything. A marker file lets a deliberate change through |
| `/etc/omarchy-mac-boot/owner-boot-chain` | Upstream's own declaration for a Mac whose owner builds part of the boot chain: a failed boot check becomes a warning, the update finishes, and the automatic rebuild after a snapshot restore is skipped |
| explicit install reasons | The boot-chain packages are marked explicitly installed, so `omarchy update`'s orphan cleanup never removes them |
| `k114s-booted-esp` | The Stage 2 hook and the persist script refuse to write to an ESP this boot did not come from (betizzel release 4's identity test) |
| `k114s-edge-check` | Read-only: solves the pending upgrade in a private copy of the package database and reports whether any held package would change |
| a record | Package list and boot-file checksums as they were before the script changed anything |

`--undo` reverses every step.

## Tests

**Fake root** (`tests/linux/`, on a Linux host, 2026-11-14): 79 tests of the persist script,
hold list, guard, declaration, install reasons, record, undo and refusals; 18 tests of the
Stage 2 hook against the image's real `boot.bin`.

**Replica** (`tests/macos/`, 2026-11-14): 85 tests of the macOS apply/rollback tool against the
image's ESP files, including applying r2 on top of r1.

**Inside a copy of the installed image** (`tests/isolation/edge-iso.sh`, 2026-11-14): the image's
`root.img` and `boot.img` and a FAT ESP built by the macOS tool, mounted on an x86 host and
entered with user-mode emulation, with real pacman against the live Edge repositories.

| Step | Result |
| --- | --- |
| Omarchy's boot check before persist | passes |
| persist, then undo | undo is exact: `pacman.conf`, kernel files, hook script, hook folder and install reasons as before |
| Omarchy's boot check after persist, without the declaration | fails: the kernel file "does not match the package mtree" |
| `update-verify` after persist, with the declaration | warns that the owner manages the boot chain; finishes with status 0 |
| `k114s-edge-check` | 40 packages would change; none held; no package changed by the check |
| `pacman -Syu` (what `omarchy update` runs) | status 0; 40 packages upgraded; the fifteen held packages unchanged; Stage 2, kernel file and boot menu unchanged |
| Channel refresh: template over `pacman.conf`, the user hook, `pacman -Syyuu` | the template has no `IgnorePkg`; the hook restores all fifteen; pacman ignores eight downgrades (kernel, loader, U-Boot, Mesa, Vulkan, firmware, Omarchy, Omarchy settings); 0 packages changed |
| The same upgrade with every hold removed | the guard stops it; status 1; 0 packages changed |
| A named reinstall of `linux-aurora`, a forced removal of `uboot-aurora` | pacman accepts each despite `IgnorePkg`; the guard stops both; 0 packages changed |
| The channel switch's package swap | the guard stops it; `omarchy` and `omarchy-settings` unchanged |
| A deliberate loader-package change with the marker file | goes through; the Stage 2 hook rebuilds the K114s file: same loader, exactly one device tree (`apple,k114s`, the pinned one), the package's new U-Boot |

## What this does not show

- **Nothing here ran on a K114s.** The isolation run used emulation, with pacman's download
  sandbox turned off because emulation has no Landlock.
- It ran the package transaction and the boot check. It did not run the rest of `omarchy update`:
  the snapshot, the migrations, the orphan step, or anything that needs a desktop session.
- **Switching the desktop to Edge's `omarchy-dev` is untested.** Forced through in the image copy,
  the swap stopped in another package hook that needs a running session, so there is no result
  either way. r2 therefore stops the switch; lifting that needs a run on hardware.
- The kernel is still a file placed under a package-owned path. The proper fix is a K114s kernel
  package, after which the boot-chain declaration can go.

## Still open

| Gap | State |
| --- | --- |
| Kernel as a real package with the K114s tree | planned with the next kernel candidate |
| A recovery set from one moment (root snapshot, `/boot`, ESP, package archives) | r2 records state and the macOS tool keeps a checked copy of the ESP boot files; archives of the held packages are not kept yet |
| Edge desktop swap (`omarchy-dev`) | needs a hardware run; stopped by the guard until then |
| The loader's ESP name on a K114s | read `/proc/device-tree/chosen/asahi,efi-system-partition` at the next boot; if absent the check passes without checking |
