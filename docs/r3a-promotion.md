# r3a promotion: the r3a kernel and the GPU Stage 2 become what this Mac boots

Written 2026-11-15, after the r3a trial window (`docs/r3-integration.md`, sections 6 and 8): the r3a kernel booted cleanly
once on the r1 tree, twice on the r3a tree and twice on the GPU tree; on the GPU tree the GPU mailbox receive interrupt
fires at about 400 per second without a storm and Hyprland renders on the GPU.

**The owner's decision (2026-11-15):** promote r3a with the GPU desktop, now, with the owner at the Mac for every reboot.

- The r3a kernel (Limine entry `Omarchy/linux-k114s`, id `Omarchy.linux-k114s`) becomes the default boot.
- The GPU tree (`m1n1/boot-ctxr-r3-gpu.bin`) becomes the configured Stage 2.
- After two clean default boots the static repair image comes off the ESP. A copy stays on the Linux disk, and one in the
  macOS bundle folder with its exact Limine block, so macOS can still put it back (D11).
- Omarchy updates resume.
- A combined r3a-plus-GPU tree is later work and not part of this runbook.

Evidence labels as in `docs/r3-integration.md`: **agent-run** (run on this Mac, read-only, or on copies of its files in a
scratch folder), **emulator/replica** (fake trees and stand-ins), **read from source**. Nothing in this document has been
run as root on the Mac yet: every write below is the lead's, in the order given, with the owner at the Mac.

Hard limits that hold for every step: nothing touches macOS, Apple's boot policy, Stage 1, Apple firmware or NVRAM;
no security control is weakened or bypassed; the speakers stay without a path (nothing here touches sound); suspend stays
blocked (the four masked targets and the two `30-k114s-r3a-trial.conf` drop-ins stay); no block prints the kernel command
line (blocks compare it, they never show it). A hang has one recovery: hold the power button until the Mac is off. The
loader's trial watchdog does not arm on this Mac, Limine has no boot counter, and the built-in keyboard does not work in
Limine's menu, so a boot that stops at the menu is a hang too.

## 1. Where it starts and where it ends

| | Now (verified 2026-11-15, agent-run) | After P6 |
| --- | --- | --- |
| `default_entry` | `1` (the static repair entry, "Omarchy K114s repair r1 (trackpad fix B)") | `Omarchy/linux-k114s`, an entry path |
| Menu | 1 repair entry, 2 folder `/+Omarchy`, 3 `//linux-k114s` | 1 folder, 2 `//linux-aurora` (hook-built), 3 `//linux-k114s` |
| Kernel images on the ESP | `omarchy_linux-aurora-k114s.efi` (repair, 111,821,824 bytes, sha256 `51148ff7...`), `omarchy_linux-k114s.efi` (79,420,416) | `omarchy_linux-k114s.efi` (default) and `omarchy_linux-aurora.efi` (the hook's image of the installed `linux-aurora` package, about 79.3 MB) |
| Configured Stage 2 `m1n1/boot-ctxr.bin` | r1 tree, `45a5dbef...` | GPU tree, `9825a103...` (the same bytes as `m1n1/boot-ctxr-r3-gpu.bin`) |
| Pinned tree (`k114s-repair/k114s.dtb` on the ESP and `/usr/local/lib/omarchy-k114s/k114s.dtb`) | r1, `2ea22d26...` | GPU tree, `2c870ba9...` |
| r1 Stage 2 kept for the way back | as the configured file | `k114s-repair/known-good/boot-ctxr.bin` (`45a5dbef...`) and its tree beside it; the macOS bundle has its own copy |
| Standing GPU trial | `/etc/omarchy-k114s/stage2-trial` and `k114s-stage2-rearm.service` re-arm `aura-try` at every clean shutdown | retired; `aura-try` stays `spent` |
| Static repair image (`51148ff7...`) | on the ESP, entry 1 | off the ESP. Copies in the macOS bundle folder (`promotion/`, P4b) and on the Linux disk; its exact Limine block on the ESP (`k114s-repair/promotion/repair-block.conf`, root-only) and in the bundle. `restore-repair` from macOS puts both back (D11) |
| ESP free | 83,075,072 bytes (the space guard's minimum is 88,080,384: every package transaction is refused) | about 111 MB: the guard passes |
| Package updates | refused (trial window open) | resume under the installed r2c guards (holds, hold guard, space guard) |

## 2. The decisions, and the facts behind them

**D1. The default is written as an entry path, `default_entry: Omarchy/linux-k114s`, not as a number.** A number is a
position. Today `linux-k114s` is entry 3. Step P5 removes the repair block, after which it is entry 2. Then the next package
transaction that touches `usr/lib/firmware/*`, `usr/lib/initcpio/*`, systemd or cryptsetup makes the Limine hook rebuild
every kernel directory that has a `modules.builtin` (`/usr/share/libalpm/scripts/limine-mkinitcpio-install`, the
`rebuild_all` path). That includes `linux-aurora`, which stays installed (D6). `BOOT_ORDER="linux-aurora, *, ..."` in
`/etc/default/limine` puts that entry first in the folder, so `linux-k114s` becomes entry 3 again. A number set in P5 would
then boot the older kernel. A path keeps naming the same entry, so one value is right before P5, after P5 and after any
rebuild. What proves the path form:

- Read from source: the Limine `v12.9.6` tag (the installed version is `limine 12.9.6-1`), `common/menu.c`. A `default_entry`
  that is not all digits is resolved by `find_entry_by_path`, component by component against the entry names.
  `common/lib/config.c` drops the `+` of an expanded folder (`/+Omarchy`) and the blanks after the slashes. It keeps the
  rest of the line as the name, so the path is `Omarchy/linux-k114s`. The same file shows the failure the path avoids:
  "Selecting a directory is not an error; it just cannot be booted", which disables autoboot. So does a value that matches
  nothing ("Default entry is not valid, booting to menu"). The installed `/usr/share/doc/limine/CONFIG.md` documents both.
  The source also shows that Limine keeps a value's trailing blanks, so every write below is checked with `grep -x`.
- Agent-run: the entry lines on the Mac are exactly `/+Omarchy` and `  //linux-k114s`, with no trailing blank (`cat -A`).
- `limine-entry-tool` (a compiled binary) and `limine-snapper-sync` are observed, not proven, to keep a path default; the
  P6d check is what covers both. `limine-entry-tool` was observed to leave the header of `limine.conf`, `default_entry: 1`
  included, unchanged across `--remove-uki`, the r3a install and the 2026-11-14 rebuild. It writes `default_entry` only when it
  generates a new file. Its own template carries `#default_entry: <OS name>/<kernel name>`, which is the path form
  (`strings` of `/usr/lib/limine/limine-entry-tool`). That this holds for a path value is **not proven by source**. Step P5b
  is the first observed rebuild with the path in place, and every later transaction is followed by a check (P6d).
- The first boot that uses the path is P3. Until P5 the repair entry is still there, so a P3 that stops at the menu has a
  way back from macOS (`default repair`, section 5).
- The repo's tools were taught the path: `k114s-boot-once` (below), `k114s-lib.sh` (`limine_default`,
  `limine_default_index`, `limine_set_default`, which keeps a path a path), and the macOS tool (`status`, `default k114s`,
  `default aurora`). Each reads the option name in any case, as Limine does.

**D2. The GPU tree is pinned in both places before the configured file changes, and r1 is kept first.** The Stage 2 hook
`/usr/local/lib/omarchy-k114s/update-boot-ctxr` (the installed r2c version, without `stage2-managed` and without
`stage2-frozen`) rebuilds `m1n1/boot-ctxr.bin` at every transaction that touches `usr/lib/modules/*/dtbs/*` or
`usr/lib/asahi-boot/*`. It builds from the Aura loader `/usr/lib/asahi-boot/m1n1.bin`, the **pinned** tree (the ESP copy
if it is not empty, else the Linux copy) and the U-Boot tail of `m1n1/boot.bin`. With the pin left at r1, the first such
transaction would quietly turn the GPU Stage 2 back into r1. Agent-run on copies in a scratch root (`OMARCHY_ROOT`): the
installed hook with the GPU tree pinned writes `9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc`, byte for
byte the GPU file. With the r1 tree pinned it writes `45a5dbef...`. P0d and P1b repeat this on the Mac. The GPU tree is
not a separate file anywhere today. It is cut out of the GPU file: offset 3,997,696 (the loader is exactly
`/usr/lib/asahi-boot/m1n1.bin`, 3,997,696 bytes, sha256 `1546dd50...`), length 108,531 (the blob's own `totalsize`),
sha256 `2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5`. The r1 file goes to
`k114s-repair/known-good/boot-ctxr.bin` first, as `docs/r3-update-tooling.md` (the Stage 2 switch) and
`docs/r3-integration.md` step (iv) ask. The GPU result holds only for loader `1.0.0b13-g22b71758-dirty` on firmware
26B8125 (`docs/r3-gpu-result.md`). Nothing here changes the loader: `m1n1-aurora` and `uboot-aurora` stay held.

**D3. The standing trial is retired, not kept.** Once the configured file is the GPU file, `stage2-trial` would re-arm
`aura-try` for the same bytes at every shutdown. That changes nothing on the screen but adds a second boot path, makes
`k114s-boot-once arm` refuse (`stage2-trial would re-arm`), and hides which file a boot came through. It goes to the backup
folder and `k114s-stage2-rearm.service` is disabled. The GPU desktop opt-ins (`~/.config/k114s-gpu-desktop`, `.keep`,
`k114s-gpu-desktop-r3a`) and guard version 3 stay. After the retirement `chosen/aurora,trial` is absent, so a boot is
identified by the configured file's hash, `chosen/asahi,m1n1-stage2-version` and the render node.

**D4. The Stage 2 change and the default change are two reboots.** P1 boots the repair kernel on the configured GPU
file. That is the configuration the way back from a P3 hang returns to (`default repair` from macOS), so P1 proves the way
back before it is needed, and a failure points to one cause.

**D5. The macOS tool changes before the repair image goes (a hard prerequisite of P5).** The fixed tool on the Mac
(`911d43e9...`) finds the ESP by `omarchy_linux-aurora.efi` or `omarchy_linux-aurora-k114s.efi`. The first is already off
the ESP, and P5 removes the second, so the tool would print "expected exactly one Omarchy ESP, found 0" and could not even
run `stage2 r1` (the case is tested: `tests/macos/test-promoted-esp.sh`). The changed `macos/tools/k114s_repair.py` also
finds the ESP by `omarchy_linux-k114s.efi`. It reads and writes a path default (`default k114s`, `default aurora`; each
checks that the entry exists, that its image is on the ESP and that the image matches its `#hash`). `status` names the GPU
and r3a Stage 2 files and survives an image it cannot parse. `rollback all` now stops once the repair entry is gone,
because the pre-repair menu it would restore names an image that is no longer the one on the ESP. It also gains `restore-repair` (D11).
`k114s_esp_tool.py` is unchanged. The owner copies the new tool in macOS in P4b and confirms `status` and
`restore-repair --check` there, before P5.

**D6. `linux-aurora` stays installed and held, and its hook-built image is deliberately the second image (P5b).** It
cannot simply go: `omarchy-aurora-firmware` depends on it (`Required By`) and owns the initcpio hooks the r3a image is built
with, the hold guard stops its removal, and `IgnorePkg` also keeps the channel's older `7.2.11` build away. While it is
installed, the first update that triggers a full rebuild re-creates `omarchy_linux-aurora.efi` and its entry anyway, so P5b
makes that happen once, attended, with checks, instead of in the middle of an update. P5b runs right after P5a, before
any reboot, so no boot ever runs with only one Linux image on the ESP. What that image is: r2c's persist
step put the repair kernel into the package's path (`/usr/lib/modules/7.3.0-17.v272-4-ARCH/vmlinuz`, sha256
`92eabcf4...`, written 2026-11-14 14:32, with `updates/hid-magicmouse.ko`). So the hook's image boots the same kernel as
the repair entry, which ran on the GPU tree through the standing trial, with an initramfs built the way the r3a one is.
It is the second bootable image after P5, and macOS can point the default at it (`default aurora`). P6a boots it once by
the one-shot to prove it. It is also what the macOS tools of earlier revisions look for. Space: about 190 MB free after P5a,
about 111 MB after P5b, which is what the first boot without the repair entry (P5c) starts with. A full rebuild rewrites each image next to its old copy, which leaves about 32 MB at the peak. It
fits, and the 88 MB guard passes. A third image does not fit (P7).

**D7. Updates resume under the guards that are installed (r2c), not under the r3 tooling.** The r3 tooling
(`k114s-release`, `k114s-guard`) is not installed on this Mac. Its guard counts one full image per kernel directory and
would refuse every boot-touching transaction in this two-kernel state (about 195 MB needed against about 111 MB free). Its
release path is built around `linux-aurora` and cannot release `linux-k114s` (`docs/r3-update-tooling.md`, "For the next
kernel"). Installing it is later work. What resumes: `omarchy update` with the holds in `pacman.conf`, the hold guard and
the 88 MB space guard. `linux-k114s`, `limine-mkinitcpio-hook` and `limine-snapper-sync` join the hold list: the first so
nothing replaces the default kernel by accident; the second because the hold guard already stops any transaction that
changes it, so without the hold a newer channel build would stop the whole update instead of being skipped; the third
because it rewrites `limine.conf` and writes on the ESP, and a newer build was in the channel on 2026-11-15. Nothing
installed needs a newer one: its one dependant, `omarchy-mac-boot`, is held. What is **not** held: the desktop itself.
`IgnorePkg` names `omarchy` and `omarchy-settings`, but this Mac has `omarchy-dev` and `omarchy-settings-dev` (they
provide those names, and a hold matches only a package's own name). They upgrade, with their migrations and
`/etc/mkinitcpio.conf.d/omarchy_hooks.conf`, which the next image build uses. Holding them would stop the Omarchy updates
the owner decided to resume. A migration that runs `limine-mkinitcpio` rebuilds both images outside pacman, where the
space guard does not run; the P6d after-block is what catches a bad result before a reboot, and `restore-repair` (D11)
is the way back if it is missed.

**D8. `update-m1n1` is turned off while `linux-k114s` is installed** (`M1N1_UPDATE_DISABLED=1`, as `docs/r3b-kernel.md`
asks). It has been on since trial step D4 of `docs/r3-integration.md` restored it, and P6c turns it off. Its trees sort
above `linux-aurora`'s, so a run would rebuild `m1n1/boot.bin` from the r3a package's preliminary
trees (and add about 10 MB). The Stage 2 hook reads only the U-Boot tail of that file, and every package that ships
`dtbs/` or `asahi-boot/` is held, so this is a precaution, not a fix.

**D9. `k114s-trial-default-revert.service` is masked.** It is disabled and its marker is absent, but its script writes
`default_entry: 1` unconditionally. After P5, entry 1 is the Omarchy folder, so firing it would stop the Mac at the menu.
Its unit is a plain file in `/etc/systemd/system`, and `systemctl mask` refuses to replace one ("File ... already
exists", reproduced with `systemctl --root` on a fake tree). So P6c moves the file to the backup folder, reloads, masks,
and checks that `is-enabled` reads `masked`.

**D10. Kept on the ESP:** `m1n1/boot-ctxr-r3-gpu.bin` (the source of the configured file and of the P1 undo),
`m1n1/boot-ctxr-r3a.bin` (the start of the combined tree, later), `k114s-repair/backup-before-r1/` (macOS `stage2` needs
its `backup.json`), `k114s-repair/r2c/repair-uki.txt` (the record `restore-repair` checks the image against),
`k114s-repair/macos-r3a/` and `k114s-repair/promotion/` (D11). Together they take about 13 MB.

**D11. The static repair image leaves the ESP, not macOS's reach.** After P5 both images on the ESP are built by the
same hook from the same initramfs state. One update that breaks the initramfs (firmware, systemd, cryptsetup and
mkinitcpio are not held) breaks both at once, and so can an `omarchy-dev` migration that runs `limine-mkinitcpio` (D7).
`default aurora` then points at an image broken the same way, and `stage2 r1` changes only the device tree. The copy on
the Linux disk (`/var/lib/k114s-recovery/uki/`) is on the encrypted root, which macOS cannot read. So, before P5:

- P0e keeps the exact repair block of `limine.conf` (its command line included) in
  `k114s-repair/promotion/repair-block.conf` on the ESP. The ESP is mounted `fmask=0077`, so the file is root-only on
  Linux. P5a cuts the block only if what it cuts is byte for byte that file. The block never enters this repository, a
  PR or a log: the blocks count its lines and never print it.
- In P4b the owner copies the repair image (checked against sha256 `51148ff7...`) and the block into the bundle folder on
  macOS (`promotion/`, ignored by git), and runs `restore-repair --check`. That proves the image matches the ESP's own
  record (`k114s-repair/r2c/repair-uki.txt`, written by `apply`) and that the saved block is the live entry.
- `sudo ./k114s-repair restore-repair` puts them back. Both modes count free space and the clusters freed by planned
  deletions before any write. The budget covers the image, the full new menu beside the old one, and an 8 MiB reserve
  for an image write. When recovery requires a new image, the tool removes `omarchy_linux-aurora.efi` and its entry
  only if recovery fits with that deletion and needs the space. A verified repair image already on the ESP can
  finish with space for the menu alone.
  The tool verifies the image, puts the saved block first, and sets `default_entry: 1`.
  Apply refuses while a repair entry is still there or if the image or block fails verification.
  Rerun the command to finish recovery after an interrupted write.

This keeps the owner's decision (the image is off the ESP) and a way back that does not depend on any hook-built image.
The bundle may also still hold the original image from the 2026-11-14 `apply` (`work/*-apply-*/live/EFI/Linux/`, the
tool's live copy). That is the package's own kernel without the trackpad fix, and this runbook does not use it.

### Code changed for this runbook

| File | Change | Tests |
| --- | --- | --- |
| `linux/r3a-trial/k114s-boot-once` | `check` and `arm` no longer require `default_entry: 1` with the repair entry first. The fallback is whatever `default_entry` names, an index or a path, resolved as Limine 12.9.6 resolves it. It must be exactly one line and boot an entry (not a folder, not nothing), and its file must be on the ESP and match its `#hash`. The self-test gate and `mark-not-durable` follow the default entry, and `arm` refuses a target that boots the default's own file | `tests/linux/test-boot-once.sh`, 108 passed (73 before): the promoted layout, a path that survives an entry removed in front of it, index 1 naming the folder, a path naming a folder or nothing, a trailing blank, two default lines, a `#` suffix, a missing default, a hash mismatch, the self-test and the not-durable gate on the path default |
| `linux/k114s-lib.sh`, `linux/k114s-release`, `linux/k114s-recovery-set` | `limine_default` returns the value as written and reads the option name in any case, as Limine does; `limine_default_index` and `limine_path_of` are new; `limine_set_default` keeps a path a path. `k114s-release` compares indexes, so a path default is no longer rewritten into a number when the proven entry is put back, and a put-back that fails is now a `PROBLEM` note instead of passing silently | `tests/linux/test-r3-release.sh`, 162 passed (150 before) |
| `macos/tools/k114s_repair.py`, `macos/k114s-repair` | D5, and `restore-repair [--check] [IMAGE]` (D11) | `tests/macos/test-promoted-esp.sh`, 84 passed (new); `tests/macos/test-no-original-uki.sh`, 24 passed (unchanged) |
| `tests/linux/run-r3.sh`, `tests/linux/k114s-syntax.sh` | the runner now also runs `test-boot-once.sh`, `test-gpu-guard.sh` and `test-promotion-runbook.sh`; the syntax check parses the two r3a-trial scripts | |
| `tests/linux/test-promotion-runbook.sh` | new: runs the blocks of P0e, P1, P2, P5a, P5b and P6c and their undos, cut out of this file, against a fake ESP with the real `k114s-boot-once`, the real `apply-holds` and stand-ins for the Limine hook and `systemctl` (whose `mask` refuses a plain unit file, as systemd does), and parses every block | 53 passed |
| `.gitignore` | `/macos/promotion/`: the bundle folder that holds the owner's copy of the repair image and block (D11) never goes into git | |

## 3. Rules for the whole run

- From P0 to P6c, no package transaction and no `omarchy update`. The space guard refuses them until P5 anyway, and
  after P5 they would run before the holds are in place.
- On macOS, never `rollback all`, `rollback stage2`, `kernel`, `apply` or `default original`. `rollback stage2` restores the
  pre-repair **trial1** tree, not r1. The way back to r1 is `stage2 r1`.
- The owner is at the Mac for every reboot. A hang, a black screen, or a Limine menu that stays up: hold the power button
  until the Mac is off, then follow section 5.
- Variables do not survive a reboot. Set them again at the top of each step:

      REPO=<a checkout of this repository that has this file>
      K=/usr/local/lib/omarchy-k114s/k114s-boot-once
      P=/var/lib/k114s-recovery/promotion

- Every block with a `findmnt` guard is a subshell `( ... )`. A `STOP` ends it with `exit 1`, the rest of the block does not
  run, and the terminal stays open. Paste each block whole. Stop at the first expectation that is not met.
- Record each step's result in the lead's recovery log before the next step.

## 4. The runbook

### P0. Preconditions and backups

**P0a. Look (changes nothing).**

    (
    : "${K:?STOP: set K, REPO and P first (section 3)}" "${REPO:?STOP: set REPO first}" "${P:?STOP: set P first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*; nothing was changed"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    c=/boot/efi/limine.conf
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "the running kernel is $(uname -r), not r3a"
    [ "$(pacman -Q linux-k114s 2>/dev/null)" = "linux-k114s 7.3.0.r3a-2" ] || stop "linux-k114s is not 7.3.0.r3a-2"
    [ "$(pacman -Q linux-aurora 2>/dev/null)" = "linux-aurora 7.3.0.aurora17.v272-4" ] || stop "linux-aurora is not 7.3.0.aurora17.v272-4"
    echo "this boot's Stage 2: $({ tr -d '\0' < /proc/device-tree/chosen/aurora,trial; } 2>/dev/null || echo 'the configured m1n1/boot-ctxr.bin')"
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = 45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4 ] || stop "boot-ctxr.bin is not the r1 file"
    [ "$(h /boot/efi/m1n1/boot-ctxr-r3-gpu.bin)" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || stop "boot-ctxr-r3-gpu.bin is not the proven GPU file"
    [ "$(h /boot/efi/m1n1/boot-ctxr-r3a.bin)" = 5164bb1e1be1fba39aee64229863b2f835828edd8b4f90e8cfa91e71a6fd8cd9 ] || stop "boot-ctxr-r3a.bin changed"
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = 2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2 ] || stop "the ESP pin is not the r1 tree"
    [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = 2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2 ] || stop "the Linux pin is not the r1 tree"
    [ "$(h /usr/lib/asahi-boot/m1n1.bin)" = 1546dd5079cefe0f9bbdee9d1c95dcdbad39a73ae140612cd6dfab4596c2f7a3 ] || stop "the installed loader is not the one the GPU file was built from"
    [ "$(h /boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi)" = 51148ff7005d2986cfedbad3aaaedf3371a60fd0b1097daeddb0bf4e6a5f60f3 ] || stop "the repair image changed"
    [ "$(h /var/lib/k114s-recovery/uki/omarchy_linux-aurora-k114s.efi)" = 51148ff7005d2986cfedbad3aaaedf3371a60fd0b1097daeddb0bf4e6a5f60f3 ] || stop "the Linux-disk copy of the repair image is not the ESP file"
    sudo test -e /boot/efi/EFI/Linux/omarchy_linux-aurora.efi && stop "omarchy_linux-aurora.efi is on the ESP; this runbook expects the trial window's layout"
    sudo test -e /boot/efi/k114s-repair/known-good && stop "k114s-repair/known-good exists: an earlier run? read it first"
    sudo test -e "$P" && stop "$P exists: an earlier run? read it first"
    sudo test -e /boot/efi/k114s-repair/promotion && stop "k114s-repair/promotion exists: an earlier run? read it first"
    sudo grep -q -x 'uki EFI/Linux/omarchy_linux-aurora-k114s.efi 111821824 51148ff7005d2986cfedbad3aaaedf3371a60fd0b1097daeddb0bf4e6a5f60f3' /boot/efi/k114s-repair/r2c/repair-uki.txt || stop "the ESP's record of the repair image (restore-repair checks against it) does not name 51148ff7..."
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: 1' $c || stop "limine.conf does not have exactly one line 'default_entry: 1'"
    sudo grep -q -i -E '^[[:blank:]]*remember_last_entry:[[:blank:]]*yes' $c && stop "remember_last_entry is yes"
    grep -q -s -E '^[[:blank:]]*ENABLE_ENROLL_LIMINE_CONFIG=.?yes' /etc/default/limine /etc/limine-entry-tool.conf && stop "the Limine config hash is enrolled: a hand edit of limine.conf would not boot"
    [ "$(sudo grep -c -x '/+Omarchy' $c)" = 1 ] || stop "the folder line is not exactly /+Omarchy"
    [ "$(sudo grep -c -E '^[[:blank:]]*//linux-k114s' $c)" = 1 ] && [ "$(sudo grep -c -x -E '[[:blank:]]*//linux-k114s' $c)" = 1 ] || stop "the linux-k114s entry line is not exactly //linux-k114s (once, no trailing blank)"
    sudo $K check || stop "k114s-boot-once check is not clean"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    [ "$(sed -n 1p /etc/omarchy-k114s/stage2-trial)" = m1n1/boot-ctxr-r3-gpu.bin ] || stop "stage2-trial does not name the GPU file"
    [ "$(systemctl is-enabled k114s-stage2-rearm.service)" = enabled ] || stop "k114s-stage2-rearm.service is not enabled"
    [ "$(systemctl is-enabled hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] && case $(systemctl is-enabled suspend.target) in masked) true ;; *) sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check >/dev/null ;; esac || stop "a sleep target is not masked, or suspend.target is not masked and the lid-sleep gate does not hold it (sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check says why)"
    ls ~/.config/k114s-gpu-desktop ~/.config/k114s-gpu-desktop.keep ~/.config/k114s-gpu-desktop-r3a >/dev/null || stop "a GPU desktop opt-in is missing"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f ] && stop "a one-shot request is pending"
    echo "ESP free: $(df -B1 --output=avail /boot/efi | tail -1)"
    echo "P0a: as expected"
    )

Expected: `this boot's Stage 2: m1n1/boot-ctxr-r3-gpu.bin` (the standing GPU trial). The installed `k114s-boot-once` prints
`ok    default_entry is 1` and no `BAD`. ESP free is about 83,075,072. The last line is `P0a: as expected`. There is nothing to
undo.

**P0b. Install the changed `k114s-boot-once` and take back step G's stale arming record.**

    (
    : "${K:?STOP: set K, REPO and P first (section 3)}" "${REPO:?STOP: set REPO first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    sudo cp -p "$K" /var/lib/k114s-recovery/k114s-boot-once.before-promotion || { echo "STOP: no copy of the installed tool; nothing was changed"; exit 1; }
    sudo install -m755 "$REPO/linux/r3a-trial/k114s-boot-once" "$K" && cmp -s "$REPO/linux/r3a-trial/k114s-boot-once" "$K" || { echo "STOP: the tool was not installed as it is in the repository; put the copy back: sudo cp -p /var/lib/k114s-recovery/k114s-boot-once.before-promotion $K"; exit 1; }
    sudo $K check || { echo "STOP: the new check is not clean on the unchanged layout; put the copy back (see above)"; exit 1; }
    sudo $K clear
    )

Expected: `ok    default_entry is 1 (entry 1, id Omarchy-K114s-repair-r1--trackpad-fix-B-, boots boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi)`,
`ok    the default entry's file matches limine.conf`, `info  ... its sha256 is 51148ff7...`, the sleep and Stage 2 lines,
then `cleared`. Step G's arming record, `/var/lib/k114s-recovery/boot-once-armed`, names `Omarchy.linux-k114s`, which
becomes the default's id in P2. Without the clear, the first `status` after P3 would print a stale
`self-test: NOT MEASURED` line. The self-test marker stays.
Undo: `sudo cp -p /var/lib/k114s-recovery/k114s-boot-once.before-promotion /usr/local/lib/omarchy-k114s/k114s-boot-once`.

**P0c. Backups on the Linux disk, read back by hash.**

    (
    : "${P:?STOP: set P first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    sudo test -e "$P" && stop "$P exists; nothing was changed"
    sudo mkdir -p "$P" && sudo chmod 700 "$P" || stop "cannot make $P"
    sudo cp -p /boot/efi/limine.conf "$P/limine.conf.before-promotion" || stop "limine.conf was not copied"
    sudo cp -p /boot/efi/m1n1/boot-ctxr.bin "$P/boot-ctxr.bin.r1" || stop "boot-ctxr.bin was not copied"
    sudo cp -p /boot/efi/m1n1/boot-ctxr-r3-gpu.bin "$P/boot-ctxr-r3-gpu.bin" || stop "boot-ctxr-r3-gpu.bin was not copied"
    sudo cp -p /boot/efi/k114s-repair/k114s.dtb "$P/k114s.dtb.esp-pin.r1" || stop "the ESP pin was not copied"
    sudo cp -p /usr/local/lib/omarchy-k114s/k114s.dtb "$P/k114s.dtb.linux-pin.r1" || stop "the Linux pin was not copied"
    for f in /etc/omarchy-k114s/stage2-trial /boot/efi/aura-try /etc/default/update-m1n1 /etc/omarchy-mac-boot/owner-boot-chain \
        /usr/local/lib/omarchy-k114s/holds.list /etc/pacman.conf; do
      sudo cp -p "$f" "$P/" && sudo cmp -s "$f" "$P/${f##*/}" || stop "$f was not copied"
    done
    # the GPU tree, cut out of the proven GPU file: the loader is 3,997,696 bytes, the tree's own header says 108,531
    sudo sh -c "tail -c +3997697 /boot/efi/m1n1/boot-ctxr-r3-gpu.bin | head -c 108531 > '$P/k114s.dtb.gpu'"
    [ "$(sudo od -An -tx1 -N4 "$P/k114s.dtb.gpu" | tr -d ' \n')" = d00dfeed ] && [ "$(sudo od -An -tu1 -j4 -N4 "$P/k114s.dtb.gpu" | awk '{print (($1*256+$2)*256+$3)*256+$4}')" = 108531 ] || stop "the cut is not one device tree of 108,531 bytes"
    sudo sh -c "cd '$P' && sha256sum * > SHA256SUMS && sha256sum -c --quiet SHA256SUMS" || stop "the backup does not verify"
    [ "$(h "$P/boot-ctxr.bin.r1")" = 45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4 ] || stop "r1 copy"
    [ "$(h "$P/boot-ctxr-r3-gpu.bin")" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || stop "GPU copy"
    [ "$(h "$P/k114s.dtb.esp-pin.r1")" = 2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2 ] && [ "$(h "$P/k114s.dtb.linux-pin.r1")" = 2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2 ] || stop "r1 tree copies"
    [ "$(h "$P/k114s.dtb.gpu")" = 2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5 ] || stop "the GPU tree is not 2c870ba9..."
    sudo cmp -s /boot/efi/limine.conf "$P/limine.conf.before-promotion" || stop "limine.conf copy"
    n=$(sudo sh -c "cd '$P' && sha256sum -c SHA256SUMS" | grep -c ': OK$'); [ "$n" = 12 ] || stop "$n files verify in $P, not 12"
    echo "P0c: 12 files in $P, each read back by hash"
    )

Expected: `P0c: 12 files in /var/lib/k114s-recovery/promotion, each read back by hash`. This writes only on the Linux disk. The
`limine.conf` copy holds the command line, so the folder is root-only (`700`).
Undo: `sudo rm -r /var/lib/k114s-recovery/promotion` (only before P1).

**P0d. Prove that the installed Stage 2 hook turns the GPU tree into the GPU file byte for byte (changes nothing).** It
runs the installed hook as the user, on copies in a fresh scratch folder (`OMARCHY_ROOT`), and it writes only there.

    (
    : "${P:?STOP: set P first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    mkdir -p "$t/boot/efi/m1n1" "$t/boot/efi/k114s-repair" "$t/usr/lib/asahi-boot"
    sudo cat /boot/efi/m1n1/boot.bin > "$t/boot/efi/m1n1/boot.bin"; cp /usr/lib/asahi-boot/m1n1.bin "$t/usr/lib/asahi-boot/"
    sudo cat "$P/k114s.dtb.gpu" > "$t/boot/efi/k114s-repair/k114s.dtb"
    OMARCHY_ROOT=$t sh /usr/local/lib/omarchy-k114s/update-boot-ctxr || { echo "STOP: the hook refused the GPU tree; nothing was changed"; exit 1; }
    [ "$(sha256sum < "$t/boot/efi/m1n1/boot-ctxr.bin" | cut -c1-64)" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || { echo "STOP: with the GPU tree pinned the hook does not build the GPU file; do not run P1"; exit 1; }
    echo "P0d: the hook reproduces the GPU file"
    )

Expected: `update-boot-ctxr-k114s: wrote <scratch>/boot/efi/m1n1/boot-ctxr.bin (4440237 bytes, K114s device tree 2c870ba9f5963f5a)`,
then `P0d: the hook reproduces the GPU file` (agent-run on 2026-11-15 with these inputs: same result). Nothing to undo.

**P0e. Put the changed macOS tool and the exact repair block where macOS can reach them (D11).** The owner copies
both in P4b.

    (
    : "${REPO:?STOP: set REPO first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; U=EFI/Linux/omarchy_linux-aurora-k114s.efi; D=/boot/efi/k114s-repair/promotion
    sudo test -e $D && stop "$D exists: an earlier run? read it first; nothing was changed"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/old"
    bash -c '. "$1/linux/k114s-lib.sh"; limine_remove_entry_block "$2" "$3"' _ "$REPO" "$t/old" "$U" > "$t/new" || stop "the block could not be cut; nothing was changed"
    # the block is what P5a will cut: only removed lines, one flat entry with the repair title, one path, one command line
    diff "$t/old" "$t/new" | sed -n 's/^< //p' > "$t/block"
    [ "$(diff "$t/old" "$t/new" | grep -c '^>')" = 0 ] && [ "$(sed -n 1p "$t/block")" = '### K114s repair (added from macOS; remove this block to undo)' ] &&
      [ "$(sed -n 2p "$t/block")" = '/Omarchy K114s repair r1 (trackpad fix B)' ] && [ "$(grep -c -E '^[[:blank:]]*/' "$t/block")" = 1 ] &&
      [ "$(grep -c -x '  path: boot():/EFI/Linux/omarchy_linux-aurora-k114s.efi' "$t/block")" = 1 ] &&
      [ "$(grep -c -E '^[[:blank:]]*cmdline:[[:blank:]]*[^[:blank:]]' "$t/block")" = 1 ] || stop "the repair block is not one flat entry with one path and one command line; nothing was changed"
    sudo mkdir $D || stop "cannot make $D"
    sudo install -m600 "$t/block" $D/repair-block.conf && sudo install -m644 "$REPO/macos/tools/k114s_repair.py" $D/k114s_repair.py && sudo sync -f /boot/efi ||
      stop "a copy failed: sudo rm -r $D"
    sudo cmp -s "$t/block" $D/repair-block.conf && sudo cmp -s "$REPO/macos/tools/k114s_repair.py" $D/k114s_repair.py || stop "a copy on the ESP differs: sudo rm -r $D"
    echo "repair block saved: $(grep -c '' "$t/block") lines (not shown: it holds the command line)"
    sha256sum "$REPO/macos/tools/k114s_repair.py"
    )

Expected: `repair block saved: 7 lines` (the marker, the title, comment, protocol, path, cmdline and the blank line after
it; agent-run on a copy of today's `limine.conf`), then the sha256 of the changed tool. Write the sha256 down: the owner
compares it in macOS. About 50 KB on the ESP, root-only on Linux (`fmask=0077`).
Undo: `sudo rm -r /boot/efi/k114s-repair/promotion` (only before P5).

### P1. The GPU tree becomes the configured Stage 2 and the pinned tree

**P1a. Keep r1, pin the GPU tree, install the GPU file, retire the standing trial.**

    (
    : "${K:?STOP: set K and P first (section 3)}" "${P:?STOP: set P first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    R1=45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4; GPU=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
    R1T=2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2; GPUT=2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $R1 ] && [ "$(h /boot/efi/m1n1/boot-ctxr-r3-gpu.bin)" = $GPU ] || stop "the Stage 2 files are not as P0 found them; nothing was changed"
    [ "$(h "$P/boot-ctxr.bin.r1")" = $R1 ] && [ "$(h "$P/k114s.dtb.gpu")" = $GPUT ] && [ "$(h "$P/k114s.dtb.esp-pin.r1")" = $R1T ] || stop "the P0c backups do not verify; nothing was changed"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent; nothing was changed"
    # 1. the r1 Stage 2 and its tree, kept on the ESP for the way back
    sudo mkdir -p /boot/efi/k114s-repair/known-good
    sudo cp "$P/boot-ctxr.bin.r1" /boot/efi/k114s-repair/known-good/boot-ctxr.bin && sudo cp "$P/k114s.dtb.esp-pin.r1" /boot/efi/k114s-repair/known-good/k114s.dtb && sudo sync -f /boot/efi
    [ "$(h /boot/efi/k114s-repair/known-good/boot-ctxr.bin)" = $R1 ] && [ "$(h /boot/efi/k114s-repair/known-good/k114s.dtb)" = $R1T ] ||
      stop "the known-good copy does not read back; only that folder was written (sudo rm -r /boot/efi/k114s-repair/known-good)"
    # 2. both pins become the GPU tree, written beside and renamed: the Linux copy first, then the one the hook reads first
    sudo install -m644 "$P/k114s.dtb.gpu" /usr/local/lib/omarchy-k114s/k114s.dtb.k114s-new && sudo mv -f /usr/local/lib/omarchy-k114s/k114s.dtb.k114s-new /usr/local/lib/omarchy-k114s/k114s.dtb
    sudo cp "$P/k114s.dtb.gpu" /boot/efi/k114s-repair/k114s.dtb.k114s-new && sudo sync -f /boot/efi && sudo mv -f /boot/efi/k114s-repair/k114s.dtb.k114s-new /boot/efi/k114s-repair/k114s.dtb && sudo sync -f /boot/efi
    [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = $GPUT ] && [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $GPUT ] || stop "a pin does not read back as the GPU tree: run the undo of P1; do not reboot"
    # 3. the configured Stage 2 becomes the GPU file: written beside, read back, renamed, read back
    sudo cp /boot/efi/m1n1/boot-ctxr-r3-gpu.bin /boot/efi/m1n1/boot-ctxr.bin.k114s-new && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin.k114s-new)" = $GPU ] || { sudo rm -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new; stop "the new file does not read back; boot-ctxr.bin is still r1. Run the undo of P1 for the pins"; }
    sudo mv -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new /boot/efi/m1n1/boot-ctxr.bin && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $GPU ] || stop "boot-ctxr.bin does not read back as the GPU file: run the undo of P1 now; do not reboot"
    # 4. retire the standing trial: nothing re-arms aura-try any more (the GPU desktop opt-ins stay)
    sudo mv /etc/omarchy-k114s/stage2-trial "$P/stage2-trial.retired" || stop "stage2-trial was not moved: the GPU file is configured, the trial would re-arm the same bytes; run P1a's step 4 again"
    sudo systemctl disable k114s-stage2-rearm.service
    sudo $K check || stop "check is not clean"
    echo "P1a: done. ESP free: $(df -B1 --output=avail /boot/efi | tail -1)"
    )

Expected: `Removed ".../multi-user.target.wants/k114s-stage2-rearm.service"`, then the check with `ok    no Stage 2 trial
is armed` and `ok    no Stage 2 trial is configured to re-arm` and no `BAD`, then `P1a: done` with about 78.5 MB free.
The unit stays active until shutdown, and its stop script exits without doing anything once `stage2-trial` is gone.
The order means a stop at any point leaves a Mac that boots: until step 3, the configured file is r1. A transaction that
rebuilds the Stage 2 after step 2 writes the GPU file, and there is none in this window anyway.

**P1b. The pins now reproduce the configured file (changes nothing).** P0d again, with the live pins.

    (
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    sudo cmp -s /boot/efi/k114s-repair/k114s.dtb /usr/local/lib/omarchy-k114s/k114s.dtb || { echo "STOP: the two pins differ: run the undo of P1"; exit 1; }
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    mkdir -p "$t/boot/efi/m1n1" "$t/boot/efi/k114s-repair" "$t/usr/lib/asahi-boot"
    sudo cat /boot/efi/m1n1/boot.bin > "$t/boot/efi/m1n1/boot.bin"; cp /usr/lib/asahi-boot/m1n1.bin "$t/usr/lib/asahi-boot/"
    sudo cat /boot/efi/k114s-repair/k114s.dtb > "$t/boot/efi/k114s-repair/k114s.dtb"
    OMARCHY_ROOT=$t sh /usr/local/lib/omarchy-k114s/update-boot-ctxr || { echo "STOP: the hook refused the pinned tree: run the undo of P1"; exit 1; }
    sudo cat /boot/efi/m1n1/boot-ctxr.bin | cmp -s - "$t/boot/efi/m1n1/boot-ctxr.bin" || { echo "STOP: a hook run would not write the configured file: run the undo of P1; do not reboot"; exit 1; }
    echo "P1b: a run of the Stage 2 hook writes the configured file byte for byte"
    )

Expected: the hook's `wrote ... (4440237 bytes, K114s device tree 2c870ba9f5963f5a)` line, then the last line.

**P1c. Reboot (the repair kernel on the configured GPU file).** `sudo systemctl reboot`. Default is still entry 1.

After the boot, first thing:

    (
    : "${K:?STOP: set K first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    [ "$(uname -r)" = 7.3.0-17.v272-4-ARCH ] || stop "this is not the repair kernel"
    [ -e /proc/device-tree/chosen/aurora,trial ] && stop "this boot came through an aura-try trial: $(tr -d '\0' < /proc/device-tree/chosen/aurora,trial)"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version)" = 1.0.0b13-g22b71758-dirty ] || stop "not the proven loader"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || stop "boot-ctxr.bin is not the GPU file"
    ls /sys/bus/platform/drivers/aurora/*/drm/renderD* >/dev/null 2>&1 || stop "no GPU render node: this boot did not get the GPU tree"
    sudo $K status
    omarchy-hw-software-rendering --print
    grep -E '2302600000.mailbox-recv|2302e00000.mailbox-recv' /proc/interrupts | awk -v n="$(nproc)" '{s=0; for (i=2; i<=n+1; i++) s+=$i; print $NF": "s}'
    sudo dmesg | grep -E 'Oops|BUG:|WARNING:|SError|storm' && stop "the kernel log has an Oops, BUG, WARNING, SError or storm line (above)"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    echo "P1c: the repair kernel runs on the configured GPU Stage 2"
    )

Expected: `this boot started: Omarchy-K114s-repair-r1--trackpad-fix-B-`, `no LoaderEntryOneShot` twice,
`aura-try: spent m1n1/boot-ctxr-r3-gpu.bin`, the renderer `Apple M5 Pro (G17S B1)`, rising mailbox counts, then the last
line. The owner checks the keyboard, the trackpad, Wi-Fi and the desktop.
A hang: forced power-off. The next boot runs the same configuration again, so go to section 5, "a P1 boot that hangs".

**Undo of P1** (from Linux, before or after the reboot):

    (
    : "${P:?STOP: set P first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    R1=45a5dbef19c14898e73e79a42af360def638c319d14e2bae97a79f7962e4bfb4; R1T=2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2
    [ "$(h "$P/boot-ctxr.bin.r1")" = $R1 ] && [ "$(h "$P/k114s.dtb.esp-pin.r1")" = $R1T ] && [ "$(h "$P/k114s.dtb.linux-pin.r1")" = $R1T ] || stop "the P0c backups do not verify; nothing was changed"
    sudo cp "$P/boot-ctxr.bin.r1" /boot/efi/m1n1/boot-ctxr.bin.k114s-new && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin.k114s-new)" = $R1 ] || { sudo rm -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new; stop "the r1 copy does not read back; nothing was changed"; }
    sudo mv -f /boot/efi/m1n1/boot-ctxr.bin.k114s-new /boot/efi/m1n1/boot-ctxr.bin && sudo sync -f /boot/efi
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = $R1 ] || stop "boot-ctxr.bin does not read back as r1: run this undo again; do not reboot"
    sudo cp "$P/k114s.dtb.esp-pin.r1" /boot/efi/k114s-repair/k114s.dtb.k114s-new && sudo sync -f /boot/efi && sudo mv -f /boot/efi/k114s-repair/k114s.dtb.k114s-new /boot/efi/k114s-repair/k114s.dtb && sudo sync -f /boot/efi
    sudo install -m644 "$P/k114s.dtb.linux-pin.r1" /usr/local/lib/omarchy-k114s/k114s.dtb
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = $R1T ] && [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = $R1T ] || stop "a pin does not read back as r1: run this undo again"
    if sudo test -f "$P/stage2-trial.retired"; then sudo mv "$P/stage2-trial.retired" /etc/omarchy-k114s/stage2-trial; fi
    sudo systemctl enable k114s-stage2-rearm.service
    # the standing trial as before P1: the next boot goes through the GPU file once, and re-arms itself after it
    sudo sh -c "printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try && sync -f /boot/efi"
    echo "aura-try: $(sudo sed -n 1p /boot/efi/aura-try) (armed: the standing GPU trial is back; spent: the next boot is r1, also safe)"
    )

`k114s-repair/known-good/` can stay (4.5 MB).

### P2. `Omarchy/linux-k114s` becomes the default

**P2a. Write the path, under the boot-partition lock, through a file beside it.** Only after P1c passed.

    (
    : "${K:?STOP: set K first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || stop "P1 is not in place; nothing was changed"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: 1' $c || stop "limine.conf does not have exactly one line 'default_entry: 1'; nothing was changed"
    [ "$(sudo grep -c -x '/+Omarchy' $c)" = 1 ] && [ "$(sudo grep -c -x -E '[[:blank:]]*/[+]?[[:blank:]]*Omarchy' $c)" = 1 ] || stop "the Omarchy folder line is not exactly /+Omarchy, or another top-level entry is named Omarchy; nothing was changed"
    [ "$(sudo grep -c -E '^[[:blank:]]*//linux-k114s' $c)" = 1 ] && [ "$(sudo grep -c -x -E '[[:blank:]]*//linux-k114s' $c)" = 1 ] || stop "the linux-k114s entry line is not exactly //linux-k114s; nothing was changed"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/old"
    sed 's#^default_entry: 1$#default_entry: Omarchy/linux-k114s#' "$t/old" > "$t/new"
    [ "$(diff "$t/old" "$t/new" | grep -c '^[<>]')" = 2 ] && grep -q -x 'default_entry: Omarchy/linux-k114s' "$t/new" || stop "the edit is not that one line; nothing was changed"
    sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
      cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$t/old" "$t/new" ||
      stop "limine.conf was not written (sudo rm -f $c.k114s-new; then check that $c is unchanged: sudo grep default_entry $c)"
    sudo cmp -s $c "$t/new" || stop "limine.conf does not read back as written: run the undo of P2 now; do not reboot"
    sudo $K check || stop "check is not clean: run the undo of P2 now; do not reboot"
    sudo $K entries
    )

Expected: `ok    default_entry is Omarchy/linux-k114s (entry 3, id Omarchy.linux-k114s, boots boot():/EFI/Linux/omarchy_linux-k114s.efi#4d2647d5...)`,
`ok    the default entry's file matches limine.conf`, no `BAD`. `entries` lists `default_entry: Omarchy/linux-k114s` and entries 1
(repair), 2 (`Omarchy`, directory), 3 (`Omarchy.linux-k114s`). The repair entry stays in place as the fallback that macOS
can select (`default repair`). Nothing else in the file changes, and the hash of entry 3 matches its image, so Limine
will not stop at a hash prompt.

**Undo of P2** (from Linux):

    (
    : "${K:?STOP: set K first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf
    sudo grep -q 'omarchy_linux-aurora-k114s.efi' $c || stop "the repair entry is not in limine.conf (after P5 use the undo of P5 first); nothing was changed"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] || stop "not exactly one default_entry line; nothing was changed"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/old"; sed 's#^default_entry: .*$#default_entry: 1#' "$t/old" > "$t/new"
    sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
      cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$t/old" "$t/new" || stop "limine.conf was not written"
    sudo $K check || stop "check is not clean"
    )

Expected: `ok    default_entry is 1 (entry 1, id Omarchy-K114s-repair-r1--trackpad-fix-B-, ...)`.

### P3. The first default boot

`sudo systemctl reboot`. Nothing is armed, so Limine starts `default_entry`.

**C. The check after every default boot** (P3, P4, the return from macOS in P4b, P5c, P6b, after P6d). Run it first thing:

    (
    : "${K:?STOP: set K and REPO first (section 3): they do not survive the reboot}" "${REPO:?STOP: set REPO first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "this boot is $(uname -r), not the r3a kernel"
    [ "$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-$BLI | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" = Omarchy.linux-k114s ] || stop "Limine did not start Omarchy.linux-k114s"
    [ -e /sys/firmware/efi/efivars/LoaderEntryOneShot-$BLI ] && stop "a one-shot request is pending: this was not a default boot"
    [ -e /proc/device-tree/chosen/aurora,trial ] && stop "this boot came through an aura-try trial: $(tr -d '\0' < /proc/device-tree/chosen/aurora,trial)"
    [ "$(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version)" = 1.0.0b13-g22b71758-dirty ] || stop "not the proven loader"
    [ "$(sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-64)" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || stop "boot-ctxr.bin is not the GPU file"
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try does not read spent"
    sudo $K check || stop "check is not clean"
    sudo $K status
    t=$(mktemp) || exit 1; trap 'rm -f "$t"' EXIT
    "$REPO/tests/hardware/k114s-r3a-check.sh" --allow-gpu 2>/dev/null | tee "$t"
    grep -q '^BAD' "$t" && stop "the hardware check printed BAD (above)"
    grep -q 'render node /sys' "$t" || stop "no GPU render node"
    omarchy-hw-software-rendering --print
    sudo dmesg | grep -E 'Oops|BUG:|WARNING:|SError|storm' && stop "the kernel log has an Oops, BUG, WARNING, SError or storm line (above)"
    echo "C: a clean default boot of r3a on the configured GPU Stage 2"
    )

Expected: `this boot started: Omarchy.linux-k114s` and `no LoaderEntryOneShot` on both lines of `status`. The hardware
check shows `ok` lines for the r3a kernel, `info  Stage 2: the configured m1n1/boot-ctxr.bin`, the render node and the
mailbox counts (`2302600000.mailbox-recv` at about 400 per second after a minute), `ok    device tree is the r1 tree`
(correct: the GPU tree is r1 plus the GPU nodes and has no `apple,internal-panel`), the 11 `CONFIG_` lines `ok`, `wlan0`,
`hci0` and the masked sleep targets. The renderer is `Apple M5 Pro (G17S B1)`. The owner checks the keyboard, the
trackpad, Wi-Fi, Bluetooth and the desktop. Do not suspend: closing the lid locks the session and nothing more.

A hang, a black screen, or the Limine menu staying up: forced power-off. The next boot is the same default, so go to
section 5, "a default boot that hangs (P3 to P4b)".

### P4. The second default boot

`sudo systemctl reboot`, then block C. Two passes of block C, P3 and P4, are the "two clean default boots".

**P4b. The owner, in macOS: install the changed tool, keep the static fallback, and confirm both (a hard prerequisite
of P5).** Restart into macOS (Startup Options). In Terminal, in the repair bundle folder:

    diskutil list                                               # the EFI partition of the internal disk
    sudo diskutil mount readOnly <the EFI volume>
    shasum -a 256 /Volumes/EFI/k114s-repair/promotion/k114s_repair.py   # the value P0e printed
    cp tools/k114s_repair.py tools/k114s_repair.py.r3a          # keep the tool that worked today
    cp /Volumes/EFI/k114s-repair/promotion/k114s_repair.py tools/k114s_repair.py
    mkdir -p promotion && chmod 700 promotion                   # the static fallback (D11): stays on this Mac
    sudo cp /Volumes/EFI/EFI/Linux/omarchy_linux-aurora-k114s.efi /Volumes/EFI/k114s-repair/promotion/repair-block.conf promotion/
    sudo chown "$(id -un)" promotion/*; chmod 600 promotion/*
    shasum -a 256 promotion/omarchy_linux-aurora-k114s.efi      # 51148ff7005d2986cfedbad3aaaedf3371a60fd0b1097daeddb0bf4e6a5f60f3
    wc -l promotion/repair-block.conf                           # 7 (do not open it in a shared window: it holds the command line)
    diskutil unmount <the EFI volume>
    sudo ./k114s-repair status
    sudo ./k114s-repair restore-repair --check

Expected from `status` (it changes nothing):
`installed kernel UKI:  REMOVED (the original image is not on the ESP; the r3a image omarchy_linux-k114s.efi is)`,
`Stage 2 (boot-ctxr):   r3-gpu (GPU tree, not in this bundle)`, `repair UKI on ESP:     r1; Limine repair entry: yes`,
`Limine default entry:  Omarchy/linux-k114s -> linux-k114s (entry 3)`.
Expected from `restore-repair --check` (it changes nothing):
`repair image:   .../promotion/omarchy_linux-aurora-k114s.efi matches the ESP's record (111821824 bytes, sha256 51148ff7005d2986...)`,
`saved block:    the ESP's k114s-repair/promotion/repair-block.conf and the bundle's promotion/repair-block.conf, one repair entry (Omarchy K114s repair r1 (trackpad fix B))`,
`limine.conf:    the repair entry is in it now and is exactly the saved block (restore-repair is for after P5)`, a space
line, then `restore-repair check passed.` That proves the copy kept on this Mac is the image that boots and the block is
the entry that boots it.
A change to `macos/tools/k114s_repair.py` after this text (the `restore-repair` refusal-before-write fix, issue #89) means
the next promotion must copy the new tool to macOS first, as a fresh macOS step (M9 in `docs/r3-display-d5-d9.md`):
P0e/D9p print its sha256 (the new one is `66eed0721eed06dc81460e3cd8c495a0daa534341bbb7c2fb6d268cd8352e1ec`) and
the macOS copy must print the same value.
If either command prints `STOPPED`, or the image's sha256 differs, P5 must not run: put `tools/k114s_repair.py.r3a`
back and report the message. Then restart. The Mac starts Linux as usual (if it does not, use Startup Options and pick
the Omarchy volume), and the lead runs block C.

### P5. The repair image comes off the ESP, and the second image takes its place

P5a and P5b run in one sitting, from a default boot of r3a, with **no reboot between them**. Only P5c reboots, so every
boot after P5 has two Linux images on the ESP and the full set of macOS ways back (section 5).

**P5a. Remove the block, then the file.** Only after P3, P4 and P4b passed and were recorded.

    (
    : "${K:?STOP: set K, REPO and P first (section 3)}" "${REPO:?STOP: set REPO first}" "${P:?STOP: set P first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    RP=51148ff7005d2986cfedbad3aaaedf3371a60fd0b1097daeddb0bf4e6a5f60f3; c=/boot/efi/limine.conf; U=EFI/Linux/omarchy_linux-aurora-k114s.efi
    SB=/boot/efi/k114s-repair/promotion/repair-block.conf
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "run this from a default boot of r3a (block C); nothing was changed"
    [ "$(h /boot/efi/$U)" = $RP ] && [ "$(h /var/lib/k114s-recovery/uki/omarchy_linux-aurora-k114s.efi)" = $RP ] || stop "the repair image or its copy on the Linux disk is not 51148ff7...; nothing was changed"
    sudo test -s $SB || stop "the saved repair block of P0e is missing (the macOS way back needs it); nothing was changed"
    sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c && [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] || stop "default_entry is not the path (P2); nothing was changed"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/old"
    bash -c '. "$1/linux/k114s-lib.sh"; limine_remove_entry_block "$2" "$3"' _ "$REPO" "$t/old" "$U" > "$t/new" || stop "the block could not be cut; nothing was changed"
    # exactly the repair block went: only removed lines, and they are byte for byte the block saved in P0e
    [ "$(diff "$t/old" "$t/new" | grep -c '^>')" = 0 ] && [ "$(diff "$t/old" "$t/new" | grep -c '^<')" -le 10 ] || stop "the cut is not just the repair block; nothing was changed"
    diff "$t/old" "$t/new" | sed -n 's/^< //p' | sudo cmp -s - $SB || stop "the cut is not the block saved in P0e, so restore-repair would not put back the entry that boots; nothing was changed"
    [ "$(grep -c -E '^/[^/]' "$t/new")" = $(( $(grep -c -E '^/[^/]' "$t/old") - 1 )) ] && ! grep -q -e aurora-k114s -e 'K114s repair' "$t/new" || stop "the repair entry is still in the result; nothing was changed"
    grep -q -x 'default_entry: Omarchy/linux-k114s' "$t/new" || stop "the default line did not survive; nothing was changed"
    sudo cp -p $c "$P/limine.conf.before-p5" || stop "no copy of limine.conf; nothing was changed"
    sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
      cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$t/old" "$t/new" ||
      stop "limine.conf was not written (sudo rm -f $c.k114s-new; the repair entry and image are untouched)"
    sudo cmp -s $c "$t/new" || stop "limine.conf does not read back as written: run the undo of P5 now; do not reboot"
    sudo $K check || stop "check is not clean: run the undo of P5 now; do not reboot"
    # the file goes only now that nothing names it; its copies stay on the Linux disk and on macOS (P4b)
    sudo grep -q omarchy_linux-aurora-k114s.efi $c && stop "limine.conf still names the repair image; it stays on the ESP"
    sudo rm /boot/efi/$U && sudo sync -f /boot/efi
    sudo test -e /boot/efi/$U && stop "the repair image is still on the ESP"
    sudo ls /boot/efi/EFI/Linux
    sudo $K entries
    free=$(df -B1 --output=avail /boot/efi | tail -1); echo "ESP free: $free"
    [ "$free" -ge 185000000 ] || stop "the ESP has less free space than expected (about 190 MB); do not reboot, run the undo of P5"
    echo "P5a: done. Do not reboot: P5b now"
    )

Expected: the check with `ok    default_entry is Omarchy/linux-k114s (entry 2, id Omarchy.linux-k114s, ...)`. That is the
same path, now resolving to entry 2: the default needs no renumbering, and no file ever names the folder or a missing
entry. Then `omarchy_linux-k114s.efi` alone in `EFI/Linux`, `entries` with 1 `Omarchy` (directory) and 2
`Omarchy.linux-k114s`, about 190,300,000 bytes free, and `P5a: done`. Agent-run on a copy of today's `limine.conf`: the
cut removes exactly the 7 lines of the repair block, and the changed `check` resolves the path to entry 2 afterwards.
**Do not reboot here.** With only one Linux image on the ESP a hang would leave macOS just `stage2 r1` and
`restore-repair`. If P5b cannot follow now, run the undo of P5 before any reboot.

**P5b. The hook-built `linux-aurora` image as the standing second image (D6), before any reboot.**

    (
    : "${K:?STOP: set K and P first (section 3)}" "${P:?STOP: set P first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    c=/boot/efi/limine.conf; KU=/boot/efi/EFI/Linux/omarchy_linux-k114s.efi
    [ "$(uname -r)" = 7.3.0-17.v272-4-k114s-r3a-ARCH ] || stop "run this in the same boot as P5a; nothing was changed"
    sudo grep -q omarchy_linux-aurora-k114s.efi $c && stop "the repair entry is still in limine.conf: P5a first; nothing was changed"
    [ "$(pacman -Q linux-aurora)" = "linux-aurora 7.3.0.aurora17.v272-4" ] && [ -f /usr/lib/modules/7.3.0-17.v272-4-ARCH/modules.builtin ] || stop "linux-aurora is not as expected; nothing was changed"
    sudo test -e /boot/efi/EFI/Linux/omarchy_linux-aurora.efi && stop "omarchy_linux-aurora.efi is already there; nothing was changed"
    [ "$(df -B1 --output=avail /boot/efi | tail -1)" -ge 185000000 ] || stop "less than 185 MB free; P5a first; nothing was changed"
    sudo cp -p $c "$P/limine.conf.before-p5b" || stop "no copy of limine.conf; nothing was changed"
    kline=$(sudo grep -E '^[[:blank:]]*path: boot\(\):/EFI/Linux/omarchy_linux-k114s\.efi#' $c); ksum=$(sudo sha256sum $KU | cut -c1-64)
    sudo limine-mkinitcpio linux-aurora || stop "the hook failed: run the undo of P5b, then the undo of P5; do not reboot"
    # what the hook did, checked before any reboot
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c || stop "the hook changed default_entry: run the undo of P5b, then the undo of P5; do not reboot"
    sudo $K check || stop "check is not clean: run the undo of P5b, then the undo of P5; do not reboot"
    [ "$(sudo sha256sum $KU | cut -c1-64)" = "$ksum" ] && sudo grep -q -x -F -- "$kline" $c ||
      stop "the hook rebuilt the r3a image too (a full rebuild): that image is new and untested. Do not reboot; record it. The check above passed, so its #hash matches. The lead picks: reboot into it (block C tests it, with every way back of section 5), or the undo of P5b and then the undo of P5"
    al=$(sudo awk '/^[ \t]*\/\/linux-aurora[ \t]*$/ {f=1} f && /^[ \t]*path:/ {print; exit}' $c); af=${al#*boot():}; ah=${af#*#}; af=${af%%#*}
    [ "$ah" != "$af" ] && [ "$(sudo b2sum "/boot/efi$af" | cut -d' ' -f1)" = "$ah" ] || stop "the linux-aurora entry has no hash or does not match its image: run the undo of P5b"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    norm() { tr -d '\0' | tr -s ' \n' '\n' | sed '/^$/d' | sort; }
    sudo awk '/^[ \t]*\/\/linux-aurora[ \t]*$/ {f=1} f && /^[ \t]*cmdline:/ {sub(/^[ \t]*cmdline:[ \t]*/,""); print; exit}' $c | norm > "$t/a"
    sudo awk '/^[ \t]*\/\/linux-k114s[ \t]*$/ {f=1} f && /^[ \t]*cmdline:/ {sub(/^[ \t]*cmdline:[ \t]*/,""); print; exit}' $c | norm > "$t/k"
    [ -s "$t/a" ] && cmp -s "$t/a" "$t/k" || stop "the linux-aurora entry's command line differs from linux-k114s's: run the undo of P5b"
    sudo $K entries
    free=$(df -B1 --output=avail /boot/efi | tail -1); echo "ESP free: $free"
    [ "$free" -ge 100000000 ] || stop "less than 100 MB free with two images: run the undo of P5b"
    echo "P5b: two Linux images, the default unchanged"
    )

Expected: `Building UKI for linux-aurora (7.3.0-17.v272-4-ARCH)` and the Limine tool's lines; no change to
`default_entry`; the check line now reads `(entry 3, id Omarchy.linux-k114s, ...)`, because the hook puts `linux-aurora`
first in the folder (`BOOT_ORDER`), and the path follows the entry. `entries`: 1 `Omarchy`, 2 `Omarchy.linux-aurora`,
3 `Omarchy.linux-k114s`. About 111 MB free, then `P5b: two Linux images`. If the hook put the entry after `linux-k114s`,
the check line says entry 2 and everything else holds. This is the first observed rebuild with a path default, the open
point of D1. If it rewrote `default_entry`, the block stops, and the path form must not be relied on until that is
understood: run the undo of P5b and the undo of P5, so the next boot has the repair entry again.

**Undo of P5b** (from Linux, before any reboot):

    (
    : "${K:?STOP: set K and P first (section 3)}" "${P:?STOP: set P first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*; do not reboot"; exit 1; }
    c=/boot/efi/limine.conf
    sudo limine-entry-tool --remove-uki linux-aurora || stop "limine-entry-tool failed (its message is above)"
    sudo test -e /boot/efi/EFI/Linux/omarchy_linux-aurora.efi && stop "omarchy_linux-aurora.efi is still on the ESP"
    if ! { [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c; }; then
      # the hook or the tool changed the default: put the path back, the P2a way (one line, under the lock, read back)
      [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] || stop "limine.conf has $(sudo grep -c -i '^default_entry:' $c) default_entry lines: compare it with $P/limine.conf.before-p5b by hand"
      t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
      sudo cat $c > "$t/old"
      awk 'tolower(substr($0, 1, 14)) == "default_entry:" { print "default_entry: Omarchy/linux-k114s"; next } { print }' "$t/old" > "$t/new"
      sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
        cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$t/old" "$t/new" || stop "limine.conf was not written"
      sudo cmp -s $c "$t/new" || stop "limine.conf does not read back as written"
    fi
    sudo $K check || stop "check is not clean"
    sudo cmp -s $c "$P/limine.conf.before-p5b" && echo "limine.conf is again the file from before P5b" ||
      echo "limine.conf differs from $P/limine.conf.before-p5b (for example a rebuilt r3a image's new hash); the check above decides"
    sudo ls /boot/efi/EFI/Linux
    )

Expected: the Limine tool's removal lines, then `ok    default_entry is Omarchy/linux-k114s (entry 2, ...)`, no `BAD`,
`limine.conf is again the file from before P5b`, and only `omarchy_linux-k114s.efi` in `EFI/Linux`. Then run the undo
of P5 before any reboot. `--remove-uki` is the command trial step D1 used.

**P5c. Reboot:** `sudo systemctl reboot`, then block C. This is the first boot without a repair entry. It has two Linux
images on the ESP, about 111 MB free, and every way back of section 5.

**Undo of P5** (from Linux; after P5b, run the undo of P5b first: the two images do not fit with the repair image):

    (
    : "${K:?STOP: set K, REPO and P first (section 3)}" "${REPO:?STOP: set REPO first}" "${P:?STOP: set P first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    RP=51148ff7005d2986cfedbad3aaaedf3371a60fd0b1097daeddb0bf4e6a5f60f3; c=/boot/efi/limine.conf; U=EFI/Linux/omarchy_linux-aurora-k114s.efi
    sudo test -e /boot/efi/EFI/Linux/omarchy_linux-aurora.efi && stop "omarchy_linux-aurora.efi is on the ESP: run the undo of P5b first; nothing was changed"
    t=$(mktemp -d) || exit 1; trap 'rm -rf "$t"' EXIT
    sudo cat $c > "$t/now"; sudo cat "$P/limine.conf.before-p5" > "$t/old"
    bash -c '. "$1/linux/k114s-lib.sh"; limine_remove_entry_block "$2" "$3"' _ "$REPO" "$t/old" "$U" | cmp -s - "$t/now" || stop "limine.conf changed since P5 (a rebuild?); the P5 copy would not match the images. Nothing was changed: restore the repair image and its block by hand"
    if ! sudo test -e /boot/efi/$U; then
      sudo cp /var/lib/k114s-recovery/uki/omarchy_linux-aurora-k114s.efi /boot/efi/$U.k114s-new && sudo sync -f /boot/efi || stop "no room or no copy; nothing else was changed"
      [ "$(sudo sha256sum /boot/efi/$U.k114s-new | cut -c1-64)" = $RP ] || { sudo rm -f /boot/efi/$U.k114s-new; stop "the copy does not read back; nothing was changed"; }
      sudo mv -f /boot/efi/$U.k114s-new /boot/efi/$U && sudo sync -f /boot/efi
    fi
    sudo flock -w 120 /run/lock/boot-partition.lock sh -c 'cmp -s "$1" "$2" || { echo "limine.conf changed while this block ran"; exit 1; }
      cp "$3" "$1.k114s-new" && sync -f "${1%/*}" && cmp -s "$3" "$1.k114s-new" && mv -f "$1.k114s-new" "$1" && sync -f "${1%/*}"' _ $c "$t/now" "$t/old" || stop "limine.conf was not written; the repair image is back on the ESP"
    sudo $K check && sudo $K entries
    )

Expected: the default `Omarchy/linux-k114s` at entry 3 again, the repair entry 1 back, and its image `51148ff7...`. The
undo of P2 then makes the repair entry the default again. If `limine.conf` changed since P5 and this undo stops, the
macOS `restore-repair` does the same from the saved block (section 5).

### P6. `linux-aurora`, closing the window, and updates

What happens to `linux-aurora` (D6): it stays installed and held, and P5b made its hook-built image the standing second
image. It is not removed (its dependant `omarchy-aurora-firmware` and the hold guard stop that), and it is not left
installed without an image, because the first full rebuild would bring the image back in the middle of an update.

**P6a. Boot the second image once, by the one-shot (the default does not change).**

    (
    : "${K:?STOP: set K first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    sudo $K arm Omarchy/linux-aurora || { echo "STOP: the arm refused; nothing is armed"; exit 1; }
    sudo $K status
    sudo systemctl reboot
    )

Expected before the reboot: `armed: the next boot starts 'Omarchy/linux-aurora' (id Omarchy.linux-aurora) once`,
`default_entry stays Omarchy/linux-k114s`. After the boot: `uname -r` is `7.3.0-17.v272-4-ARCH`, `sudo $K status` says
`this boot started: Omarchy.linux-aurora` and `no LoaderEntryOneShot` twice, the render node exists and
`omarchy-hw-software-rendering --print` names the M5 Pro. The owner checks the keyboard, the trackpad, Wi-Fi and the
desktop. A hang: forced power-off. Limine erased the request when it read it, so the next boot is the default again.
In that case record that `default aurora` is **not** a way back. The image stays, because the hook rebuilds it at the next
full rebuild anyway.

**P6b. Reboot** (`sudo systemctl reboot`): the default comes back by itself. Run block C.

**P6c. Close the trial window and prepare updates.**

    (
    : "${P:?STOP: set P first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*"; exit 1; }
    L=/usr/local/lib/omarchy-k114s; TU=k114s-trial-default-revert.service
    # 1. linux-k114s, limine-mkinitcpio-hook and limine-snapper-sync join the held set (D7)
    for p in linux-k114s limine-mkinitcpio-hook limine-snapper-sync; do grep -q -x "$p" $L/holds.list || echo "$p" | sudo tee -a $L/holds.list >/dev/null; done
    sudo $L/apply-holds || stop "apply-holds failed: put the P0c copies back (sudo cp -p $P/holds.list $L/; sudo cp -p $P/pacman.conf /etc/)"
    held=$(grep -m1 '^IgnorePkg = ' /etc/pacman.conf)
    for p in linux-k114s limine-mkinitcpio-hook limine-snapper-sync linux-aurora m1n1-aurora uboot-aurora; do echo " $held " | grep -q " $p " || stop "$p is not in the first IgnorePkg line"; done
    # 2. update-m1n1 is turned off while linux-k114s is installed (D8)
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || echo 'export M1N1_UPDATE_DISABLED=1' | sudo tee -a /etc/default/update-m1n1 >/dev/null
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is not off"
    # 3. the dormant trial-default unit can never fire (D9): its plain unit file goes to the backup folder, then the mask
    sudo test -e /etc/omarchy-k114s/trial-default && stop "/etc/omarchy-k114s/trial-default exists: read it; the holds and update-m1n1 are done"
    sudo systemctl disable $TU
    if sudo test -f /etc/systemd/system/$TU && ! sudo test -L /etc/systemd/system/$TU; then
      sudo mv /etc/systemd/system/$TU "$P/$TU" || stop "the unit file was not moved"
    fi
    sudo systemctl daemon-reload && sudo systemctl mask $TU || stop "the mask failed (its message is above)"
    [ "$(systemctl is-enabled $TU)" = masked ] || stop "$TU is '$(systemctl is-enabled $TU)', not masked"
    # 4. the owner's boot-chain declaration names what boots now (update-verify prints its first line)
    echo "K114s: kernel linux-k114s 7.3.0.r3a-2 (Limine default Omarchy/linux-k114s; second image linux-aurora) and the GPU-tree Stage 2 (m1n1/boot-ctxr.bin = boot-ctxr-r3-gpu.bin) from omarchy-m5p-oled, promoted 2026-11-15; see /usr/local/lib/omarchy-k114s and docs/r3a-promotion.md" |
      sudo tee /etc/omarchy-mac-boot/owner-boot-chain >/dev/null
    # 5. no override marker is left, sleep stays blocked, the space guard will pass
    for f in allow-low-esp allow-coupled-update; do [ -e /etc/omarchy-k114s/$f ] && stop "/etc/omarchy-k114s/$f exists: remove it first"; done
    [ "$(systemctl is-enabled hibernate.target hybrid-sleep.target suspend-then-hibernate.target | sort -u)" = masked ] && case $(systemctl is-enabled suspend.target) in masked) true ;; *) sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check >/dev/null ;; esac || stop "a sleep target is not masked, or suspend.target is not masked and the lid-sleep gate does not hold it (sudo /usr/local/lib/omarchy-k114s/k114s-lid-sleep check says why)"
    ls /etc/systemd/logind.conf.d/30-k114s-r3a-trial.conf /etc/systemd/sleep.conf.d/30-k114s-r3a-trial.conf >/dev/null || stop "a suspend drop-in is missing"
    free=$(df -B1 --output=avail /boot/efi | tail -1); [ "$free" -ge 88080384 ] || stop "below the space guard's minimum"
    echo "P6c: holds $(echo "$held" | wc -w) words; update-m1n1 off; trial-default-revert $(systemctl is-enabled $TU); ESP free $free"
    )

Expected: `k114s apply-holds: holds in /etc/pacman.conf: ...` with 22 names, `Removed ...` only if the unit had a link,
`Created symlink /etc/systemd/system/k114s-trial-default-revert.service -> /dev/null`, and
`P6c: holds 24 words; update-m1n1 off; trial-default-revert masked; ESP free <about 111,000,000>` (24 words: `IgnorePkg`,
`=`, 22 names). The trial window is closed: the window rules of `docs/r3-integration.md` section 8 end here.
Undo: `sudo cp -p $P/holds.list /usr/local/lib/omarchy-k114s/holds.list && sudo /usr/local/lib/omarchy-k114s/apply-holds`,
`sudo cp -p $P/update-m1n1 /etc/default/update-m1n1`,
`sudo systemctl unmask k114s-trial-default-revert.service && sudo mv $P/k114s-trial-default-revert.service /etc/systemd/system/ && sudo systemctl daemon-reload`
(it stays disabled, as before), `sudo cp -p $P/owner-boot-chain /etc/omarchy-mac-boot/owner-boot-chain`.

**P6d. The first `omarchy update`, attended.** First a record of the boot state, kept for the comparison:

    (
    : "${P:?STOP: set P first (section 3)}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    sudo sh -c "cd /boot/efi && { sha256sum m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; grep -i '^default_entry' limine.conf; grep -E '^[[:blank:]]*/' limine.conf; grep -E '^[[:blank:]]*path:' limine.conf; sed -n 1p aura-try; } > '$P/before-update.txt'"
    sudo test -s "$P/before-update.txt" || { echo "STOP: the before-record is empty or unreadable; do not run the update"; exit 1; }
    sudo cat "$P/before-update.txt"
    )

Then `omarchy update`, in a terminal, with the owner there. Expected: the hold guard and the space guard pass without a
word, and pacman reports `ignoring package upgrade` for held packages that have a newer channel build
(`limine-mkinitcpio-hook` and `limine-snapper-sync` among them on 2026-11-15). **Not held, and expected to upgrade:**
`omarchy-dev` and `omarchy-settings-dev` (the desktop, D7) and other userland packages. After pacman, Omarchy runs the
new migrations. A migration that calls `limine-mkinitcpio` rebuilds both images outside pacman, so the space guard does
not see it; the after-block below does. A review on 2026-11-15 found that no package pending then hit a full-rebuild
trigger and that the new migrations that call `limine-mkinitcpio` are all limited to other hardware (not re-checked
here: read the update's output). If the transaction touches firmware, initcpio, systemd or cryptsetup, the Limine hook
prints `Building UKI for linux-aurora` and `Building UKI for linux-k114s`. `Updating the confined m1n1 Stage 2` runs only
if a `dtbs/` or `asahi-boot/` path changes (all such packages are held). At the end, update-verify either warns that
`/etc/omarchy-mac-boot/owner-boot-chain` declares an owner-managed chain, or says `Boot files verified; ...
owner-boot-chain is present`. Its check looks at `linux-aurora`, not at the r3a default, so neither message is evidence
about the default. **Do not follow its advice to run `sudo mkinitcpio -P && sudo update-m1n1 && sudo
omarchy-mac-boot-update`**, and do not accept its reboot prompt before the block below passes. If the space guard stops
the update, nothing has changed: read the free space; do not use `allow-low-esp`.

    (
    : "${K:?STOP: set K and P first (section 3)}" "${P:?STOP: set P first}"
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted"; exit 1; }
    stop() { echo "STOP: $*; do not reboot"; exit 1; }
    c=/boot/efi/limine.conf; h() { sudo sha256sum "$1" 2>/dev/null | cut -c1-64; }
    [ "$(h /boot/efi/m1n1/boot-ctxr.bin)" = 9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc ] || stop "boot-ctxr.bin is no longer the GPU file (put back: the undo of P1's first lines with $P/boot-ctxr-r3-gpu.bin)"
    [ "$(h /boot/efi/k114s-repair/k114s.dtb)" = 2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5 ] && [ "$(h /usr/local/lib/omarchy-k114s/k114s.dtb)" = 2c870ba9f5963f5ae1ed18a7effa520daa234583997470d9552a795b4aafcda5 ] || stop "a pin is no longer the GPU tree"
    [ "$(sudo grep -c -i '^default_entry:' $c)" = 1 ] && sudo grep -q -x 'default_entry: Omarchy/linux-k114s' $c || stop "default_entry changed"
    sudo $K check || stop "check is not clean"
    for e in linux-aurora linux-k114s; do
      l=$(sudo awk -v e="$e" '{ s = $0; sub(/^[ \t]+/, "", s) } s == "//" e {f=1; next} f && /^[ \t]*\/\// {exit} f && /^[ \t]*path:/ {print; exit}' $c); f=${l#*boot():}; hh=${f#*#}; f=${f%%#*}
      [ -n "$l" ] && [ "$hh" != "$f" ] && [ "$(sudo b2sum "/boot/efi$f" | cut -d' ' -f1)" = "$hh" ] || stop "the $e entry has no hash or does not match its image (Limine would wait for a key)"
    done
    [ "$(sudo sed -n 1p /boot/efi/aura-try)" = spent ] || stop "aura-try is not spent"
    grep -q -x 'export M1N1_UPDATE_DISABLED=1' /etc/default/update-m1n1 || stop "update-m1n1 is on again"
    grep -m1 '^IgnorePkg = ' /etc/pacman.conf | grep -q -w linux-k114s || stop "the holds block is gone (run sudo /usr/local/lib/omarchy-k114s/apply-holds)"
    [ "$(systemctl is-enabled k114s-trial-default-revert.service)" = masked ] || stop "k114s-trial-default-revert.service is no longer masked"
    sudo test -s /boot/efi/k114s-repair/promotion/repair-block.conf && sudo test -s /boot/efi/k114s-repair/r2c/repair-uki.txt || stop "a file restore-repair needs is gone from the ESP"
    sudo true || stop "sudo is not available (a failed sudo would look like a diff)"
    sudo sh -c "cd /boot/efi && { sha256sum m1n1/boot-ctxr.bin k114s-repair/k114s.dtb EFI/Linux/*.efi; sha256sum /usr/local/lib/omarchy-k114s/k114s.dtb; grep -i '^default_entry' limine.conf; grep -E '^[[:blank:]]*/' limine.conf; grep -E '^[[:blank:]]*path:' limine.conf; sed -n 1p aura-try; }" | sudo diff "$P/before-update.txt" -
    r=${PIPESTATUS[1]}
    case $r in 0) echo "no boot file changed" ;; 1) echo "the diff above is the change: compare it with the Expected text below (new image hashes, their path: lines, a Snapshots sub-entry)" ;; *) stop "the before-record could not be read or compared (diff exit $r; $P is root-only, so it is read with sudo)" ;; esac
    echo "ESP free: $(df -B1 --output=avail /boot/efi | tail -1)"
    echo "P6d: the boot chain checks out; reboot, then run block C"
    )

Expected: either `no boot file changed`, or a diff that shows only new hashes of the two images and their `path:` lines,
with every check above passing. A new `Snapshots` sub-entry after the kernels is also expected: `limine-snapper-sync`
adds it, and the path default does not move. Then reboot and run block C.

**What to watch from now on** (each `omarchy update`):

- The same after-block as P6d, before every reboot that follows an update, whether or not pacman's hook ran: a migration
  can rebuild both images without it. A changed `default_entry`, a missing `#hash` match, or a Stage 2 that is no longer
  the GPU file is a stop.
- What upgrades: `omarchy-dev`, `omarchy-settings-dev` and their migrations (they are not held, D7), and the userland. Read
  the migration output for `limine-mkinitcpio` and `Building UKI`. What does not: everything in the hold list, including
  `limine-snapper-sync` and `limine-mkinitcpio-hook` since P6c.
- ESP free space: about 111 MB with two images. A full rebuild needs about 79.4 MB next to the old image, so about 32 MB at
  the peak. `limine-snapper-sync` limits itself to 85 % use (`LIMIT_USAGE_PERCENT`). The ESP is at about 79 %, so a snapshot
  copy of an image does not fit, and the sync should skip it. **Not measured.** If free space falls below 88,080,384, the
  guard stops updates. That is correct: find what took the space before anything else.
- A held package whose channel build moves a dependency can one day stop an update (`limine-mkinitcpio-hook`, `limine`,
  `limine-snapper-sync`, `hyprland-m5`, ...). That is the hold doing its job. Releasing one is a deliberate step, not part
  of an update.
- Keep the macOS bundle's `promotion/` folder and `k114s-repair/promotion/` on the ESP: they are the static way back (D11).
- `hyprland-m5 0.57.2-3` (the CMonitor ABI fix that lets the stock title-bar plugin load) is still a separate, attended
  adoption. Nothing here changes it.

### P7. The next kernel trial (r3b) after the promotion, briefly

- **Not as `linux-k114s`.** An upgrade of the same package overwrites `omarchy_linux-k114s.efi` and the entry the default
  names, and it replaces the r3a module directory. The one-shot would then try the default itself, with only the
  `linux-aurora` image left to fall back to. `k114s-boot-once arm` treats a request for the default as the self-test, and it
  refuses a target that boots the default's own file.
- **As its own package** (a distinct `pkgname`, for example `linux-k114s-r3b`, release `7.3.0-17.v272-11-k114s-r3b-ARCH`). The
  hook builds `omarchy_linux-k114s-r3b.efi` with its own entry `Omarchy/linux-k114s-r3b` and its own module directory. The
  default path keeps naming r3a, whatever the hook inserts. The trial is `sudo $K arm Omarchy/linux-k114s-r3b`, one boot at a
  time, exactly as step E was. Promotion later is a one-line `default_entry` change, with the P2 checks.
- **Space**: a third image does not fit beside two (about 32 MB would be left). For the window, the `linux-aurora` image
  comes off first (`sudo limine-entry-tool --remove-uki linux-aurora`, as trial step D1), which leaves about 111 MB after r3b.
  In that window no package transaction may run: a full rebuild would bring the `linux-aurora` image back and could not
  rewrite a third one. The installed 88 MB guard would not stop that on its own, so it is a window rule, as in
  `docs/r3-integration.md` section 8. `restore-repair` stays the static way back: in that window it finds no
  `omarchy_linux-aurora.efi` to remove, so it needs the r3b image to come off first (it says so and writes nothing).
- **The Stage 2 is the GPU tree now.** Every r3b boot runs on it. `docs/r3b-kernel.md` keeps r3b off the GPU tree until the
  interrupt-only mailbox (`sleep-lid/0010`) is accepted on the evidence of step G (`2302600000.mailbox-recv` fired at about
  400 per second on r3a). If the lead does not accept it, an r3b boot needs the r1 tree for that one boot:
  `printf 'armed\nk114s-repair/known-good/boot-ctxr.bin\n' > /boot/efi/aura-try` (the known-good r1 file kept in P1) together
  with the one-shot. The trial is then one boot of both, and it falls back to r3a on the GPU file.
- The GPU desktop on r3b needs its own opt-in, `~/.config/k114s-gpu-desktop-r3b` (guard version 3). Suspend stays blocked.
  `M1N1_UPDATE_DISABLED=1` stays.

## 5. Ways back

Each step's undo is next to it. When Linux does not come up, hold the power button until the Mac is off, start macOS
(Startup Options), open Terminal in the repair bundle folder, and pick the case:

- **A P1 boot that hangs** (the repair kernel on the configured GPU file). The next boot is the same, so
  `sudo ./k114s-repair stage2 r1`. That writes the bundle's r1 Stage 2 (`45a5dbef...`) and the r1 pin on the ESP. It
  accepts the live GPU file because the loader prefix and U-Boot tail are the bundle's. Then `sudo ./k114s-repair status`
  (`Stage 2 (boot-ctxr): r1`) and boot Linux, which is now the state before P1. In Linux run the undo of P1, which also
  puts the Linux pin back. The tool that works here is the one on the Mac today, or the changed one.
- **A default boot that hangs (P3 to P4b)**, or a Limine menu that stays up. The default boots again and again, so
  `sudo ./k114s-repair default repair`. It writes `default_entry: 1` over the path (tested:
  `tests/macos/test-promoted-esp.sh`; it replaces whatever value is there), and the repair entry is still entry 1. Boot
  Linux: the repair kernel on the GPU file, which P1c proved. If that also fails, `sudo ./k114s-repair stage2 r1` as well.
  In Linux, run the undo of P2 (it finds the default already 1), and the undo of P1 if Stage 2 was rolled back.
- **A boot that hangs after P5** (P5c on: no repair entry, two Linux images), with the changed tool (P4b). In this order:
  1. If the GPU Stage 2 is the suspect (the boot stops before the kernel's first lines), `sudo ./k114s-repair stage2 r1`,
     with the default unchanged: r3a ran on the r1 tree in step E (on that tree the desktop draws on the CPU).
  2. If the r3a image is the suspect, `sudo ./k114s-repair default aurora`. The default then names the hook-built
     `linux-aurora` image, which P6a booted (before P6a it is unproven).
  3. **If both images are the suspect** (a hang after an update that rebuilt them, or 2 also hangs):
     Run `sudo ./k114s-repair restore-repair --check`. A space refusal exits with status 1 and reports the free,
     reclaimable, and required byte counts. On a passing check, run `sudo ./k114s-repair restore-repair`. It writes the
     static repair image from `promotion/` and checks it against the ESP's record (`51148ff7...`), puts the saved block
     back as entry 1 and writes `default_entry: 1`.
     Expected: `Restored the repair entry as entry 1 and the default (default_entry: 1) ...`, then
     `status` with `repair UKI on ESP:     r1; Limine repair entry: yes` and
     `Limine default entry:  1 -> Omarchy K114s repair r1 (trackpad fix B) (entry 1)`. Boot Linux: the static repair
     kernel on the configured Stage 2 (P1c proved it on the GPU file; add `stage2 r1` if in doubt). It does not depend on
     anything the hook built.
  - Then boot Linux, and from Linux undo what the macOS step did once the cause is known: `default k114s` from macOS, or
    the P2 edit with the value `Omarchy/linux-k114s` from Linux, and P1 for the pins. After `restore-repair` the Mac is
    in the layout of P4 with one image fewer: fix the cause, rebuild the images (`sudo limine-mkinitcpio`), run the
    P6d after-block, and repeat P5a and P5b to promote again (P5a's P0e check still holds, because the saved block is
    the one restored).
- **If the tool cannot be used, a manual edit from macOS**, the same class of edit as `docs/r3-integration.md`, "a stuck
  request": `sudo diskutil mount <the EFI volume>` (read-write: it may add macOS folders, and `linux/esp-trim` removes them
  later), then, for the default only,
  `sudo sed -i '' 's#^default_entry: .*#default_entry: Omarchy/linux-aurora#' /Volumes/EFI/limine.conf` (or `: 1` while the
  repair entry exists). Check with `grep -n '^default_entry' /Volumes/EFI/limine.conf`, then `diskutil unmount`. It writes
  that one line. To put the static image back by hand (the same as `restore-repair`), in the bundle folder:

      E=/Volumes/EFI
      # r3b window only: first sudo rm $E/EFI/Linux/omarchy_linux-k114s-r3b.efi (the free-space check below stops without it)
      [ -f $E/EFI/Linux/omarchy_linux-aurora.efi ] && sudo rm $E/EFI/Linux/omarchy_linux-aurora.efi   # makes room; its entry stays, unused
      df -k $E | awk 'NR==2 && $4 < 120000 {print "STOP: under 120 MB free (remove the r3b image first if present); not copying"; exit 1}' &&
        sudo cp promotion/omarchy_linux-aurora-k114s.efi $E/EFI/Linux/
      shasum -a 256 $E/EFI/Linux/omarchy_linux-aurora-k114s.efi               # 51148ff7005d2986...
      sudo cat $E/limine.conf | awk -v b=promotion/repair-block.conf '!d && /^\// { while ((getline l < b) > 0) print l; d = 1 } { print }' |
        sed 's#^default_entry: .*#default_entry: 1#' > promotion/limine.conf.new
      grep -c '' promotion/limine.conf.new; grep -n -e '^default_entry' -e '^/' promotion/limine.conf.new   # the repair title is the first '/' line
      # no limine.conf write unless the image is whole
      shasum -a 256 $E/EFI/Linux/omarchy_linux-aurora-k114s.efi | grep -q '^51148ff7005d2986' &&
        sudo cp promotion/limine.conf.new $E/limine.conf && sync && diskutil unmount $E

  In the r3b window the r3b image (`omarchy_linux-k114s-r3b.efi`) must come off first (the commented line before the
  `df` line), or the free-space check stops the copy, and the `limine.conf` write is skipped unless the image's `shasum`
  matches. On `STOP`, the volume is still mounted read-write: remove the r3b image if it is present and paste the block
  again, or otherwise run `diskutil unmount $E` and report. The `awk` puts the saved block before the first top-level
  entry, which is where P5a cut it from. Check the `grep` output before the `cp`: one `default_entry: 1` line, and `/Omarchy K114s repair r1 (trackpad fix B)` as the first entry.
- **Never from macOS:** `rollback all` (it now stops once the repair entry is gone; before that it would restore the
  pre-repair menu), `rollback stage2` (it restores trial1, not r1), `kernel`, `apply`, `default original`.

## 6. Risks the owner should know

- **Both images on the ESP are hook-built after P5.** An update or a migration that breaks the initramfs can break both
  in one go, and the P6d after-block checks hashes and command lines, not that the images boot. The static fallback is
  now on macOS (D11): the repair image in the bundle's `promotion/` folder, its block on the ESP and in the bundle, and
  `restore-repair`, which was run on synthetic ESPs only. On the Mac only its `--check` runs (P4b). Keep the bundle folder;
  if it is lost, the copy on the Linux disk cannot be reached from macOS.
- **The path default rests on Limine's source and has its first boot in P3.** `limine-entry-tool` and `limine-snapper-sync`
  keeping a path value is observed (P5b, and P6d for `limine-snapper-sync`), not read from their source, which is not
  installed. Every boot-touching update is followed by the
  `default_entry` check.
- **`update-verify` checks `linux-aurora`, not the r3a default.** Its "verified" or warning text says nothing about the
  kernel that boots.
- **The desktop packages upgrade** (`omarchy-dev`, `omarchy-settings-dev`) and their migrations can rebuild both images
  outside pacman, without the space guard (D7).
- **The hook-built `linux-aurora` image** is the repair kernel only because r2c's persist step replaced the package's
  `vmlinuz`. A reinstall or upgrade of `linux-aurora` (held, and stopped by the hold guard) would turn it into the
  package's own kernel, which lacks the trackpad fix.
- **The GPU driver is experimental** ("general rendering is unqualified"). Rendering faults are possible. The OLED panel is
  still on the boot framebuffer with no brightness control, so avoid a static image on screen for long.
  `rm ~/.config/k114s-gpu-desktop` (then log out) puts the desktop back on the CPU without touching the boot chain.
- **Suspend stays blocked.** Closing the lid locks the session and nothing more, so shut down before packing the Mac. A
  package that rewrote logind or sleep configuration could undo the drop-ins; the masks would still hold.
- **Space margins are estimates from today's files.** After P1 about 78.5 MB, after P5a about 190 MB, after P5b about
  111 MB. Each block reads the real value.
- The r3 update tooling is not installed (D7). Releases of held packages are by hand, as they were under r2c.

## 7. Tests

Agent-run on 2026-11-15, as a normal user, nothing installed:

| Test | Result | Label |
| --- | --- | --- |
| `bash tests/linux/run-r3.sh` | `r3 update tooling: 1053 passed, 0 failed, 0 test file(s) skipped` (866 before this change; the new count includes the boot-once, GPU-guard and runbook files the runner now runs) | emulator/replica |
| `tests/linux/test-boot-once.sh` | 108 passed, 0 failed | emulator/replica |
| `tests/linux/test-promotion-runbook.sh` | 53 passed: the blocks of P0e, P1, P2, P5a, P5b and P6c and their undos, cut out of this file, run against a fake ESP with the real `k114s-boot-once` and `apply-holds`. Each happy path ends in the expected files, each STOP leaves the files as they were, a hook that rewrites `default_entry` is caught by P5b and undone, and P6c without the unit-file move stops at the mask. Every block of the runbook parses with `bash -n`, and every block that writes starts with the `findmnt` guard. P0a to P0d, P1c, block C, P6a and P6d are not run (they read the live system) | emulator/replica |
| `tests/macos/test-promoted-esp.sh` | 84 passed: the old tool (commit `364598e`) stops on the promoted ESP and the changed one does not; `restore-repair` with and without room, after a stopped run, and each refusal (wrong image, no record, no block, two different blocks, a block that is not one repair entry, a repair entry still present) writes nothing; the command line is never printed | emulator/replica |
| `tests/macos/test-no-original-uki.sh` | 24 passed | emulator/replica |
| `build/check-publishable.sh` | `check-publishable: ok (337 files)` | agent-run |
| The installed Stage 2 hook with the GPU tree pinned, on copies in a scratch root | `9825a103...`, the GPU file byte for byte; with r1 pinned, `45a5dbef...` | agent-run |
| The changed `k114s-boot-once check` on a copy of today's `limine.conf` and images | `default_entry is 1 (entry 1 ...)`; with the path, `entry 3`; after the repair block is cut by `limine_remove_entry_block`, `entry 2`; the cut is exactly the 7 lines of the block | agent-run |
| `restore-repair`'s checks and menu rebuild on copies of today's `limine.conf` and `k114s-repair/r2c/repair-uki.txt` (in memory, nothing printed but the results) | the live block passes `check_repair_block`; the record names 111,821,824 bytes, `51148ff7005d2986...`, the repair image's sha256; putting the cut block back into the promoted menu gives today's `limine.conf` byte for byte | agent-run |
| Limine `v12.9.6` `common/menu.c`, `common/lib/config.c` | path resolution, the folder `+`, the verbatim value, "booting to menu" for a folder or no match | read from source |

Not verified: anything that boots; `limine-entry-tool` with a path default (P5b observes it) and `limine-snapper-sync` with a path default (P6d observes it); the macOS tool on the real
ESP after the change (P4b runs `status` and `restore-repair --check`; `restore-repair` itself has run on synthetic ESPs
only); the full `tests/macos/test-macos-tool.sh` and `tests/macos/test-r2c-fat.sh` (they need the assembled bundle and
macOS); `limine-snapper-sync` on a 79 % full ESP; the packages pending in the channel on the day of P6d.
