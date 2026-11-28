# r3: update handling on the Linux side

Branch `r3/update-tooling`, written 2026-11-14. This replaces bundle r2c's guards
([edge-update-path.md](edge-update-path.md)) and adds the part r2c did not have: letting a held
package go, by itself, once Omarchy's channel carries a build that is fit for the K114s.

The owner's goal, in his words: "be able to update from omarchy as new fixes take place and only
overwrite our custom stuff when it's fixed".

**Evidence.** Nothing here has been installed on the K114s. What ran, and where:

| Label | What |
| --- | --- |
| agent-run, fake root | 537 tests as a normal user against throwaway folders (`tests/linux/test-r3-*.sh`) |
| agent-run, replica | 156 tests in which a **real pacman** runs real transactions through the real hook files, inside a user namespace built with bubblewrap (`tests/linux/test-r3-pacman.sh`). The packages, the boot hooks and "a boot" are stand-ins; see the head of that file |
| agent-run, replica | 5 tests of a **real `pacman -U`** signature check (`tests/linux/test-r3-pacman-sig.sh`): a throwaway keyring as pacman's GPGDir, `LocalFileSigLevel` Optional and Required, compared with `signed_ok`. Result: Optional accepts an unsigned archive (the gap `signed_ok` closes) and refuses a bad, untrusted or mismatched signature, as `signed_ok` does |
| agent-run, on the K114s, read-only | the release check against the live Edge channel; the criteria evaluated against this Mac's own packages; the space guard's trigger list against the hooks installed here; the formats of the EFI variable and kernel banner the tools read; the standing aura-try trial (`chosen/aurora,trial`, `/etc/omarchy-k114s/stage2-trial`) as `k114s-release status` reports it |
| owner-observed | nothing yet |

Compiling, parsing and passing in a replica do not show that anything boots. The boot-chain steps
are built so that the owner's own boot is the proof (below).

## The pieces

All under `linux/`, installed to `/usr/local/lib/omarchy-k114s` by `k114s-tooling-install`.

| File | Role |
| --- | --- |
| `k114s-guard` + `00-k114s-guard-install.hook`, `00-k114s-guard-remove.hook`, `01-k114s-guard-esp.hook` | pacman pre-transaction guards: held packages, their rivals, removals, the channel, room on the EFI partition |
| `k114s-holds` + `k114s-holds.path`, `k114s-holds.service` | the managed block in `/etc/pacman.conf` (`IgnorePkg`, `NoUpgrade`, `NoExtract`), written back whenever the file changes |
| `k114s-repackage` | rebuild an installed package into a pacman archive from the files on disk and the local database |
| `k114s-recovery-set` | archives of every held package, `/boot`, the ESP boot files, hashes, from one moment |
| `k114s-release-check` + `release-criteria.conf`, `kernel-config.required` | is the channel's build of a held package fit for the K114s? |
| `k114s-release` | release, adopt, trial, retire, Stage 2 switch, abandon, status |
| `k114s-boot-success` + `.service`, `.timer` | records what each boot came up with |
| `k114s-modules-cleanup` + `linux-modules-cleanup-k114s-keep.conf` | the stock module cleanup with a keep list |
| `hooks/pre-refresh-pacman-k114s-holds`, `hooks/post-update-k114s-release-check` | Omarchy user hooks |
| `k114s-fdt`, `k114s-binscan` | read-only readers of device tree blobs and AArch64 code (the image has no `dtc`) |
| `holds.default`, `rivals.list`, `protected.list`, `noextract.list`, `extras.list`, `esp-audit-ignore.list`, `release.conf` | data |
| `k114s-lib.sh` | shared functions; every path hangs off `K114S_ROOT`, which is how the tests run the same code as a normal user |
| `update-boot-ctxr-k114s` | r2c's Stage 2 hook with two additions: once the tooling is installed (`/etc/omarchy-k114s/stage2-managed`, made by the installer) the pacman hook never rewrites `boot-ctxr.bin`: only `k114s-release` changes it, at the switch, after a candidate has booted. It also leaves it alone while `/etc/omarchy-k114s/stage2-frozen` exists (the "a switch is pending" marker), and with `K114S_STAGE2_OUT=boot-ctxr-NAME.bin` (and `K114S_STAGE2_DTB=packaged\|pinned`) it writes a candidate beside it instead. Its default behaviour is r2c's |

r2c's own files (`apply-holds`, `hold-guard`, `esp-space-guard`, the two old hook files,
`linux-persist.sh`) are unchanged in the repository; `--undo` puts them back.

State lives in `/var/lib/omarchy-k114s` (release state, rollback sets, recovery sets, boot
records), settings and deliberate-override markers in `/etc/omarchy-k114s`, the one-transaction
permit in `/run/omarchy-k114s` (gone at every boot).

## (a) `k114s-release-check`: is the channel's build fit?

For each held package it refreshes the repository lists into a **private** copy of the package
database, takes the channel's package from pacman's cache or downloads it into a **private** cache,
checks its SHA-256 against the repository list, unpacks it there and evaluates
`release-criteria.conf`. Nothing is installed, pacman's database and cache are not written, and
nothing from the package is executed. It needs no root (it uses `fakeroot` for the private list
refresh, as `checkupdates` does). On this Mac it takes about two seconds when nothing is newer.

`k114s-release` installs exactly that verified archive (`pacman -U` of the file named in `verdict.tsv`, as `adopt` does), after hashing it again and comparing with the verdict's SHA-256, and after checking its detached signature (`NAME.pkg.tar.zst.sig`, which the check fetches beside it) with gpg on pacman's own keyring: the signature must be valid and its key fully or ultimately trusted (`pacman-key --verify` is not used, because it does not fail on an untrusted key). A cached signature is dropped when its archive is downloaded again, and one that is not a binary OpenPGP signature is dropped and fetched again by the next check. `pacman -U` goes by `LocalFileSigLevel`, which is `Optional` on Omarchy, so without this step the signature check that `pacman -S` makes would be lost. A file that is missing, differs, or has a missing or failing signature stops the release. A `fixed` verdict always carries that file: when no criterion read it (`version-newer` and `manual` only), the check fetches and verifies it at the end. It does not run `pacman -S NAME`, which would take whatever build pacman's own lists carry under the same version. The version in pacman's own lists must still equal the checked one (so its dependencies resolve against lists that are as new as the check's), but the bytes come from the check.

Output: a summary, and in the cache folder `verdict.tsv`, `checks.tsv` and `verdict.json`.
Verdicts: `fixed`, `not-fixed`, `absent` (the channel has no such package), `no-criteria`,
`not-installed`, `error`. Exit 0 ran, 10 at least one package is fixed, 2 could not run.
A held package without a `package` line in the criteria is never released.

The criteria are data. Check types: `version-newer`, `file-exists`, `file-contains`,
`file-matches`, `dtb-root-compatible`, `dtb-node`, `dtb-okay`, `dtb-prop`, `kconfig`,
`module-parm`, `code-imm16`, `tree-drivers`, `depends-on`, `not-installed`, `manual`. A `package` line may end in `keep-held` (see the userland rule below), and `keep-held` may be followed by `gpu`: the explicit marker of the GPU stack (`mesa-aurora`, `vulkan-aurora`), the only packages that follow `AUTO_RELEASE_GPU` and the GPU trial. `asahi-fwextract` and `omarchy-mac` are `keep-held` without it. `check` lines must all pass;
`any` lines of one label need one pass. An unknown type or an unreadable package is `error`, never
a pass.

| Package | Class | Fit when |
| --- | --- | --- |
| `linux-aurora` | boot-uki | not older than ours; ships `t6050-k114s.dtb` whose root is `apple,k114s`; that tree has the N1 control function with platform id `0x00146050`, the Wi-Fi and Bluetooth functions, the PCIe controller enabled, two USB controllers and two port controllers enabled, the SMC sensors enabled, the keyboard/trackpad transport; the N1 and trackpad drivers are there; the trackpad needs BOTH halves: the report-size clamp in the image (`report-clamp`) AND a `hid-magicmouse` module that parses the frames, checked in the module (`trackpad-module`: the PR 1568 raw-event path, or product `0x0361` admitted). The clamp string alone proves nothing (on this Mac it is in the running image and r2c still had to patch the module). `tree-drivers`: for every compatible of the tree this Mac boots (the running device tree, which is r1 or r3-gpu with the GPU, plus the Stage 2 tree: the pinned one, or the packaged one after `stage2 --dtb packaged`) that the running, proven kernel carries a driver for (an exact string in `vmlinuz`, or an `of:` alias in `modules.alias`), the channel's kernel must carry one too; `apple,t6050-nvme-ans2` is also checked by name. The packaged-tree checks above stay as additional gates (they can only over-block); the built-in config meets `kernel-config.required` |
| `m1n1-aurora` | boot-stage2 | not older; the loader binary knows the T6050 SoC, its PCIe and its USB PHY |
| `uboot-aurora` | boot-stage2 | not older; U-Boot knows the T6050 NVMe and SART |
| `omarchy-aurora-firmware` | boot-uki | not older; its initramfs script loads the N1 driver for `apple,k114s`; its install hook still adds `apple_centauri` |
| `mesa-aurora`, `vulkan-aurora` | userland, `keep-held` | newer; carry the M5 Pro device (`G17S`) AND the bringup gate (`ASAHI_M5_BRINGUP`, without which Mesa refuses the device and the greeter does not start); Mesa also carries `llvmpipe`, because the desktop guard (`70-k114s-gpu-desktop`) falls back to the CPU with `LIBGL_ALWAYS_SOFTWARE` and the greeter always runs on it. Read from this Mac's installed libraries on 2026-11-14 (all three strings are in `libgallium`, the first two in `libvulkan_asahi`). A string check is still not a boot of the GPU, so a channel build is on trial after its release (`release/gpu-trial`): if the next recorded boot (`k114s-boot-success`, a boot id other than the one it was installed in) has no desktop, the next `auto` puts the rollback archive back under the permit by itself, keeps it held, and never installs that build again (`release/gpu-given-up`); a later boot that reaches the desktop ends the trial. Only a finished verdict counts: a record with `result ok`, or the record of a boot that is over (`k114s-boot-success` writes an interim `incomplete` record into the running boot, for example a login screen that waits, and replaces it until the boot is ok). A desktop that only runs on the CPU fallback counts as a desktop; `rm ~/.config/k114s-gpu-desktop` (CPU) is the way out of that. Adopting an archive over a build on trial ends the trial the same way |
| `omarchy-hyprland-titlebars` | userland | not older; depends on `hyprland-m5` (built against its headers), or `hyprland-m5` is no longer installed |
| `hyprland-m5` | userland | the channel has no such package; if one appears, a person decides (`manual`) |
| `omarchy-mac-boot`, `limine-mkinitcpio-hook`, `limine`, `asahi-scripts`, `asahi-fwextract`, `omarchy-mac` | boot or userland | channel-built tooling whose scripts write the boot files. Nothing in such a package can be checked for "knows the K114s", so each has a `manual` line: `sudo k114s-release release --accept-manual NAME` |

Three things about the criteria the lead should know:

- **"Not older", and our build tags.** Our builds carry a tag in the version (`.v272`, `.j714s3`,
  `.j714s9`, an epoch on the rebuilt plugin), and pacman sorts a tagged version above the
  channel's build of the same upstream version for ever (`vercmp 2026.07.aurora6-2
  2026.07.aurora6.j714s3-1` is -1). `version-newer REGEX` therefore also passes for the channel's
  build of the same or a later upstream version, with the tag taken out and release numbers not
  compared. The identical version never passes. The version check only says "not older"; the
  content checks say "fit". Read today: Edge's `uboot-aurora 2026.07.aurora6-1` passes the version
  check and fails both content checks, which is the right answer.
- **`kernel-config.required`** holds the five options whose absence broke something on
  2026-11-14, in the language `build/validate-config.py` reads (branch `r3/config`). To require
  the whole r3 configuration of a channel kernel, replace the file with
  `patches/linux/config/k114s-r3.config` at integration.
- **The tree checks describe the r1 tree.** When the r3 device tree adds what the K114s relies on
  (sound, display, more USB), add a line per node here, or a channel kernel without them would be
  released.

Agent-run on the K114s (read-only): the kernel criteria were evaluated against this Mac's own
`linux-aurora`, rebuilt into a package by `k114s-repackage`. Every check type worked on the real
files: the packaged K114s tree fails the six node checks (that is why r1 pins its own), the pinned
r1 tree passes all of them, the repair kernel image has the PR 1568 clamp, and the config check
names exactly the five missing options.

## (b) `k114s-release`: letting a package go

Rules it keeps, each with a test:

1. Only a package whose channel build passed the check, run fresh as root, is released, at the
   version pacman's own lists offer. If the two differ it waits for the next update.
2. A **rollback set** is written first. No set, no release.
3. The hold guard lets **exactly that transaction** through: a permit in `/run` names the
   packages; anything else held in the same transaction still stops it. The permit is removed
   right after and ignored when older than an hour.
4. A failed transaction leaves the package held.
5. **A boot-chain package is never released**, not even for the transaction: the permit lets exactly
   that transaction through the guard and pacman installs the named, ignored package, so the
   package is held before, during and after. The next channel build, kernel or loader, has to pass
   the check and the trial again. (`k114s-holds release` refuses them, and the guard and the holds
   block ignore a `released.list` line for one. Before this, a released kernel or loader followed
   the channel in ordinary updates and replaced the proven boot path in one step.)

**Rollback set** (`k114s-recovery-set --packages ...`, under `/var/lib/omarchy-k114s/rollback`):
the installed package rebuilt into an archive by `k114s-repackage`, the files in `/boot`,
`limine.conf`, `m1n1/boot.bin`, `m1n1/boot-ctxr.bin`, the boot images (boot classes only), a
SHA-256 of every file on the ESP, files no package owns that the boot needs, `SHA256SUMS`.
The recovery command publishes `SHA256SUMS` only after all checksums are written.
If recovery set creation fails, the release stops before the package or boot-file change.

`k114s-repackage` is the lesson of the 2026-11-14 repair: the image's own archives are in no
cache, and copying files by pacman's file lists copied far too much. It archives exactly the paths
the local database lists, each as itself (a directory is one entry, never its contents), with
`.PKGINFO` rebuilt from the database entry, the install scriptlet and a fresh `.MTREE`. Files are
taken as they are now, and a report beside the archive names what differs from the package as
installed (for `linux-aurora` here: the repair kernel image and the depmod files). The way back is
one pacman transaction. Agent-run on the K114s as a normal user: `linux-aurora` rebuilt to 2,313
entries, the same list `pacman -Ql` prints.

**Userland** (the plugin): switched directly; afterwards the package follows the channel in
ordinary updates. The GPU stack (`mesa-aurora`, `vulkan-aurora`: `keep-held gpu`) and the boot-time tooling a person
decides on (`omarchy-mac`, `asahi-fwextract`: `keep-held`, no trial), are switched directly
too, but stay held: each later channel build is
checked again and installed by `auto`, never by an ordinary update. Its rollback is
`sudo k114s-release adopt <rollback set>/packages/NAME-*.pkg.tar.zst` (a bare `pacman -U` of a held
package is stopped by the guard).

**Boot chain** (`linux-aurora`, `omarchy-aurora-firmware`, `m1n1-aurora`, `uboot-aurora`): never
replaces the proven boot path in one step.

| Step | What happens | What stays |
| --- | --- | --- |
| before | the proven chain must be recorded (`mark-known-good`: the image the EFI stub was started from, its hash, the Stage 2 this boot came through and its hash, and the hash of the configured `m1n1/boot-ctxr.bin` the loader falls back to), intact and the one running; no boot-menu trial of someone else may be under way; the ESP must be the booted one; space is computed | nothing changes if any of this fails; the run says what it waits for |
| stage | Stage 2 is frozen, the running kernel's release goes on the module keep list, the fixed packages are installed in one transaction (under the permit; they stay held). Omarchy's `11-omarchy-mac-saved-modules.hook` moves the running kernel's modules to `/usr/lib/modules/.old` in that transaction when the new kernel's release string sorts below the running one (the channel's `7.3.0-17-ARCH` against our `7.3.0-17.v272-4-ARCH`); the tool checks afterwards and moves them back (never into an existing folder: that is a PROBLEM note) before anything is recorded, or says PROBLEM. While it works on the ESP or `limine.conf` it holds `/run/lock/boot-partition.lock`, the mutex `limine-entry-tool` and `limine-snapper-sync` use, and lets it go while pacman runs. After the transaction it waits for the lock only after the module restore, and a timeout is a log line, not a stop: the Stage 2 put-back, the default entry and the trial record are always written. The system's own hooks build the new kernel's boot image as `omarchy_linux-aurora.efi` | the proven image byte for byte; `m1n1/boot-ctxr.bin` byte for byte, and the Stage 2 file a standing trial boots (both put back from the rollback set if anything changed them); the default menu entry (put back if a hook moved it); the proven kernel's modules. When the proven image **is** `omarchy_linux-aurora.efi`, it is first copied to `omarchy_linux-aurora-known-good.efi` with a first, default menu entry |
| prove | `k114s-boot-success` must record a boot with result ok for exactly the trial's image hash and Stage 2 hash, from a **different boot** than the one that staged it | everything; the run that proves retires nothing |
| retire | on a later run, with `RETIRE_AFTER_BOOTS` (2) recorded boots and the trial chain running: the old image and its menu entry go, the default moves, the keep list empties | the old image stays in the rollback set; the menu as it was is kept beside it |

`k114s-release abandon` gives a trial up: the old packages come back from the rollback set's
archives as a pacman transaction (the saved module folder is handed back to its package with
`--overwrite`), they are held again and the trial's markers go.

**Stage 2** (m1n1, U-Boot, the device tree) is one file for every menu entry, so a new one cannot
be an additional boot entry. It can be tried beside the proven file, though: the installed loader
(Aura) has a one-boot trial. A file `aura-try` at the root of the EFI partition holding
`armed\n<path>\n` makes it boot `<path>` once in place of the configured `m1n1/boot-ctxr.bin`: it
marks the file `spent` before it reads the image, runs the trial under its 178-second watchdog,
tells Linux through `chosen/aurora,trial`, and a trial that hangs is reset onto the configured file.
(Read from the lead's GPU trial on this Mac, 2026-11-14; `docs/r3-gpu-result.md` on `r3/gpu-desktop`.)

So loader packages are installed with Stage 2 frozen, and Stage 2 is tried as its own step, by
the owner unless `AUTO_STAGE2_SWITCH=yes`: `sudo k114s-release stage2 [--dtb packaged|pinned]`.

| Step | What happens | What stays |
| --- | --- | --- |
| before | the proven chain is intact and running; no other trial is under way (a standing trial in `/etc/omarchy-k114s/stage2-trial`, an armed `aura-try` naming another file, a boot-menu trial in `/etc/omarchy-k114s/trial-default`, a boot that came through someone else's trial); room for three Stage 2 sized files and the margin | nothing is written if any of this fails |
| try | the Stage 2 hook builds a candidate from the installed packages as `m1n1/boot-ctxr-try.bin`, with the named tree; `aura-try` is armed for it | `m1n1/boot-ctxr.bin` byte for byte (it is the watchdog's fallback); the freeze |
| boots | each start through the candidate that `k114s-boot-success` records as ok arms it again for the next start. A start that is not ok, a start that hung and was reset, or a start through the configured file leaves it spent; `auto` says so (`stage2 --rearm` tries again) | the proven file is what the next start uses unless the trial is armed |
| switch | on a later run, with `RETIRE_AFTER_BOOTS` (2) recorded ok starts through the candidate and the candidate running: the configured file is copied to `k114s-repair/known-good/boot-ctxr.bin` (with its hash), the candidate replaces `m1n1/boot-ctxr.bin` (written beside, renamed, verified), the marker goes, the freeze goes, the tree choice is kept in `use-packaged-dtb` | the old file on the ESP for the way back from macOS, and in the rollback set. The candidate file stays until a start no longer comes through it |

`k114s-release abandon` during a Stage 2 trial disarms it (only a marker that names our candidate)
and removes the candidate; nothing proven was overwritten, so nothing has to be put back.
`--dtb packaged` is how the pinned K114s tree is given up for the released kernel's own.

**The lead's standing trial.** On 2026-11-14 this Mac boots `m1n1/boot-ctxr-r3-gpu.bin` through
`aura-try` at every start (`stage2-rearm` arms it again at a clean shutdown after a start through
it); `m1n1/boot-ctxr.bin` (r1, `45a5dbef...`) is the fallback. The tooling lives with that:

- `mark-known-good` (and so the installer) records what booted: Stage 2 `m1n1/boot-ctxr-r3-gpu.bin`
  with its hash, and the configured file's hash beside it. The proven chain is then "intact and
  running" only while both files are as recorded and the start came through the trial file.
- A kernel or firmware trial goes ahead under the standing trial: Stage 2 does not change. A start
  that fell back to the configured file does not count as a boot of the trial chain.
- `k114s-release stage2` waits until the standing trial is over (made the configured file, its
  `stage2-trial` file removed), and then `mark-known-good` is run once from a start that works.
- Boot records, recovery sets and `status` name the Stage 2 file each start came through.

**Locally built packages** take the same roads and stay held: `sudo k114s-release adopt FILE...`.
A userland package (the plugin rebuilt against `hyprland-m5`, branch `r3/titlebars`) switches
directly, with its `NoExtract` lifted for that one transaction. A boot-chain package (the next
K114s kernel as a real package) goes through stage, prove and retire.

**The EFI partition** (499 MB, one boot image is 80 to 112 MB). Before staging, the sum is: the new
image (the larger of the existing standard image and kernel + initramfs + 2 MiB), a copy of the
proven image when it has to be kept under another name, `boot.bin` twice and `boot-ctxr.bin` once,
and the margin (`ESP_MARGIN_MB`, 8, as the macOS tool keeps). If the standard image is not the
proven one and is in the way, it is removed first (its copy is already in the rollback set).
Otherwise the release waits and says so. `sudo k114s-release forget-image EFI/Linux/NAME.efi`
makes room by hand: it takes an image that is neither proven, running nor on trial off the ESP
with its menu entry, after a verified copy.

The assumption behind "the new image is written while the old one is still there" was not
confirmed: `limine-entry-tool` is a compiled program. Unsure means block.

## (c) Hooks into Omarchy

Read on the machine: `omarchy update` runs `omarchy-hook post-update` after the package upgrade,
migrations and service restarts, while its sudo authorisation is still kept alive, and before its
own boot check and reboot prompt.

- `~/.config/omarchy/hooks/post-update.d/k114s-release-check`: with sudo still authorised it runs
  `k114s-release auto` (move a trial forward, check, release what `release.conf` allows) and
  reports through `notify-send`. Without sudo it runs the check as the user and says what is
  ready. It never fails the update.
- `/etc/omarchy-k114s/release.conf`: `AUTO_RELEASE=yes` (the owner's choice), `AUTO_RELEASE_BOOT=yes`
  (stage a fixed kernel as an additional entry), `AUTO_RETIRE=yes`, `RETIRE_AFTER_BOOTS=2`,
  `AUTO_STAGE2_SWITCH=no`. It is read as data, never sourced.
- Nothing in the tooling restarts the machine; a test greps every script, hook and unit for it.

## (d) The gaps the review found

| Gap | Now |
| --- | --- |
| guard named six packages | what is held is data: `holds.list` (the image's pinned set plus `holds.default`: boot chain, `limine`, `asahi-fwextract`, `asahi-scripts`, `omarchy-mac`, `hyprland-m5`, `mesa-aurora`, `vulkan-aurora`, the plugin). The install hook triggers on every package and compares with the list |
| a rival replaces a held package (`hyprland` for `hyprland-m5`, `mesa`, `vulkan-asahi`, `m1n1`, ...) | `rivals.list`: a rival is stopped while its partner is held |
| removals; `omarchy reinstall`; channel switch | the remove hook stops the removal or replacement of anything held or in `protected.list` (including `omarchy-dev` and `omarchy-settings-dev`, which a switch to stable or rc removes). `omarchy-pkg-defaults` names `hyprland` on this Mac, so `omarchy reinstall` stops at the rival guard |
| stable or rc | the install hook reads the `[omarchy]` server in `pacman.conf` and stops any transaction while it is not the channel in `/etc/omarchy-k114s/channel` (edge). The marker `allow-channel-change` lifts that; removing the Edge desktop still needs its own decision |
| the title-bar plugin | `noextract.list`: `NoExtract = usr/lib/omarchy-hyprland-titlebars/titlebars.so` until the installed build has `+m5` in its version or the package is released. With it, even a forced install of the channel's package leaves the stock-ABI plugin file out |
| pre-refresh hook ignores a failed sudo | it waits for the path unit, then asks sudo, then fails loudly (red banner, critical notification). `omarchy-hook` only prints "Hook failed", so the pacman guards are what stops the upgrade; if they are missing as well, the hook ends the refresh that called it |
| the image's "Test image only" lines | they go at the first refresh; our block is written back by `k114s-holds.path` (root, no prompt) within the same second, by the user hook, and at every boot |
| space guard stops every transaction | `01-k114s-guard-esp.hook` has no catch-all trigger. Its triggers are every trigger of every hook on this system that can rewrite a boot file, so pacman runs it only for transactions that can reach the ESP, and its needs are summed per class (boot image, loader files, Limine). `k114s-guard audit` compares the list with the hooks present, at install, at every boot and in the tests; an unknown boot hook makes every install count as able to write the ESP until it is reviewed |
| no archives of the held packages | `sudo k114s-recovery-set` (the installer runs it once) |

Owner overrides, all deliberate files in `/etc/omarchy-k114s`: `allow-coupled-update`,
`allow-channel-change`, `allow-low-esp`, `esp-guard-conservative`.

## (d2) The second review (blocker, highs, mediums, lows) and what changed

| Finding | Now |
| --- | --- |
| a released kernel or loader followed the channel and replaced the proven boot path in one step; the hook rewrote `boot-ctxr.bin` once the freeze was gone | boot-chain packages are never released (rule 5 in section (b)); the hook never writes `boot-ctxr.bin` once the tooling is installed (`stage2-managed`), only `k114s-release` does, at the switch. Tested in the replica: after a retire the next kernel is stopped by an ordinary update and by a named install; after a Stage 2 switch the next loader is stopped, and even with the owner's blanket override its hooks leave `boot-ctxr.bin` alone |
| Omarchy's `11-omarchy-mac-saved-modules.hook` deleted the proven kernel's modules | the replica carries a stand-in of that hook (same decision, `uname -r` replaced by `K114S_UNAME_R`) and a channel kernel `7.3.0-17-ARCH` that sorts below the running `7.3.0-17.v272-4-ARCH`; the tool puts the modules back from `/usr/lib/modules/.old` before it records the trial (or says PROBLEM). Not run with the real script: that one reads the real `uname -r` |
| trackpad accepted the clamp string alone | `trackpad-module` (module symbol or product `0x0361`) and `report-clamp` (image) are separate required groups; `k114s-boot-success` also requires a HID device bound to `magicmouse` |
| GPU stack released on a version string | content checks (device, M5 gate, CPU renderer), `keep-held`, and a session trial with automatic rollback when the next boot has no desktop; see the table in (a) |
| A GPU rollback that cannot install (its archives need a dependency the channel replaced) | the trial is closed as failed instead of retried on every run, and a newer channel build is checked as usual; the PROBLEM note names the manual `adopt` command. Limit: the trial only catches a boot where no session reaches the desktop at all (a CPU-rendered desktop or the greeter counts as a desktop) |
| GPU stack switched unattended (`AUTO_RELEASE_GPU`, default **no**) | the GPU stack (the packages marked `gpu`: mesa-aurora, vulkan-aurora; not hyprland-m5, whose release is permanent and on no trial, and not asahi-fwextract or omarchy-mac, which a person decides) is only reported by `auto` and the preflight; `sudo k114s-release release NAME` switches it. Reason: the rollback brings back only the package itself, not the dependencies a new build pulls in (a new LLVM), so an unattended switch could leave the desktop without a way back. Known limits that stay with `AUTO_RELEASE_GPU=yes`: the rollback runs on the next `omarchy update` or `k114s-release` run, not on the boot without a desktop, and a boot without a desktop for another reason (a failed kernel trial) is also counted against the GPU build |
| ESP model left out limine-snapper-sync | superseded by (d3): the guard takes the boot partition lock itself and reserves nothing for the sync; `status` shows `limine_history`; `k114s-release` holds `/run/lock/boot-partition.lock` for its ESP and `limine.conf` edits (not across a pacman transaction, where `limine-entry-tool` takes it) |
| device-tree criteria read only the packaged tree | `tree-drivers` and `nvme-ans` (see (a)) |
| `--undo` and the `use-packaged-dtb` marker, `stage2-frozen` | the marker is saved at install and restored; undo is refused while Stage 2 is frozen and the loader packages differ from the install's; the saved originals' folder is named in the output |
| installer died when the last hold name was not installed | the loop is an `if`; the holds are written and applied before r2c's hooks are removed |
| test overrides reached production; concurrent `k114s-holds` | `k114s-guard` honours `K114S_ROOT` and `K114S_ESP_FREE` only under `K114S_TEST`; `k114s-holds` takes a lock and writes through `mktemp` |

## (d3) The second repair round

| Finding | Now |
| --- | --- |
| the snapper reservation made every boot-file update and every automatic release wait for room on this ESP | dropped in `k114s-guard` and in `stage_boot`. `limine-snapper-sync` limits itself (`LIMIT_USAGE_PERCENT`) and checks the usage before it writes, and `limine_history` holds a few hundred bytes. This Mac's real sizes (vmlinuz 54,086,144, initramfs 25,023,354, standard image 79,253,504) with the snapper config present pass at 166 MB free in the guard and in the release tests |
| a lock timeout after the transaction killed `k114s-release` before the restores and the trial record | the module restore runs first, then `boot_lock soft` (a timeout is logged), then the Stage 2, image and default-entry put-backs and the trial record. Replica test: a hook leaves the lock held for 4 s after the transaction, `K114S_LOCK_WAIT=1`; it fails against the old `die` |
| `keep-held` (and every boot-chain package) stops every update when a channel dependency bumps | the pre-refresh hook runs `k114s-release preflight` (sudo, when it is authorised): the check's private lists give the upgrade pacman would try (`-Sup`). Only dependency-error lines (`breaks dependency ... required by NAME`, `unable to satisfy dependency ... required by NAME`) and conflict lines (`:: A and B are in conflict`, either name may be held) count; `-Sup` never runs pacman's conflict step, so a dry run that succeeds is also checked against the printed upgrade list: a held package whose rival (`rivals.list`) or `Conflicts With` entry is in that list is blamed. The preflight runs pacman with `LC_ALL=C`, because the parser reads English messages. The release hint is printed only for a package that is not yet at the checked build (a `keep-held` or boot-chain package stays held after a successful release), and only whole package names: pacman's `ignoring package upgrade` warnings and `lib32-mesa-aurora` do not blame `mesa-aurora`. A blocking package whose channel build is `fixed` goes through `do_release auto` on the spot, so `AUTO_RELEASE` (userland, the GPU stack with its trial) and `AUTO_RELEASE_BOOT` (kernel, firmware, loader: an additional boot entry, the usual trial) decide as they do after an update; with them off it prints the exact `release NAME` command and notifies. The preflight runs before the update refreshes pacman's lists, so on the first run pacman may not offer the build yet: it stays held and says so, the update fails, and the preflight of the next `omarchy update` (lists now refreshed) installs it before the upgrade is tried. Not released by it, by design: a build that is not fit yet (the update stops until it is: that is the hold doing its job), a boot-chain package while another trial or a missing proven chain makes it wait, and a `keep-held` build that was rolled back. Not done: releasing a `keep-held` package after N good sessions (the GPU stack's M5 gate is the reason for the hold; the owner decides if that should lapse). The adopt hint now names `k114s-release adopt` |
| hook `11` ran after Omarchy's `10-omarchy-hyprland-reload-pause.hook`, so a stop left Hyprland's reload paused | the guard is `01-k114s-guard-esp.hook` again (before every hook) and takes `/run/lock/boot-partition.lock` with `flock -w` (`ESP_LOCK_WAIT_SECONDS`, 120) while it measures; the installer removes an `11-` copy |
| the module restore could nest a directory; `update-m1n1` could cut a later `boot.bin` from the restored proven kernel's tree | the restore refuses an existing destination (PROBLEM note). `stage2 --dtb packaged` now verifies the candidate carries the tree of the installed linux-aurora (read from `pacman -Ql`) and refuses, writing nothing, when `boot.bin` was cut from another kernel directory. The one-boot trial still guards the boot |

## (e) Guards before the first boot: a proposal

r2c left the guards as an optional later step, and one menu choice in that window downgraded the
boot chain. From macOS the Linux root is closed, so apply cannot install anything there. The
repair boot image is ours, though, and its initramfs is systemd-based
(`HOOKS=(base systemd ...)`, read on the machine).

1. The bundle's boot image carries the guard files (about 100 kB of text) in its initramfs,
   beside the Wi-Fi firmware that already rides there.
2. An initramfs unit copies them to `/run/omarchy-k114s/firstboot/` and drops
   `k114s-firstboot.service` into `/run/systemd/system` with a `sysinit.target.wants` link.
   `/run` survives the switch to the real root, so the real system's systemd runs the unit.
   The initramfs writes nothing to the root filesystem.
3. The unit has `DefaultDependencies=no`, `After=systemd-remount-fs.service local-fs.target`,
   `Before=basic.target`: the root is writable, and no login, timer or update has started. It is
   idempotent. It installs the three hook files, `k114s-guard`,
   `k114s-holds` and their data; writes the hold list (what `pacman.conf` pins now plus
   `holds.default`); applies the block; enables `k114s-holds.path`. If anything fails it writes
   `/etc/omarchy-k114s/esp-guard-conservative` and a hook that stops every transaction with the
   reason, so the failure is closed, not open.
4. It writes a small record with hashes to `k114s-repair/guards.json` on the ESP, so the macOS
   tool's `status` can say "guards installed at first boot" or "pending".
5. The rest (boot-success timer, recovery set, user hooks) stays in the installer, which then
   finds the guards in place. Until it has run, updates are stopped, not unguarded.

Not tried: that systemd in the real root picks up a unit the initramfs left in
`/run/systemd/system`. It is how initramfs-made units are documented to carry over, and
`build/qemu-test-init` is the place to show it before a bundle relies on it.

What this does not cover: a first boot of the image's original entry, which has no such
initramfs. Apply makes the repair entry the default, and the unit installs persistently, so every
later boot of any entry has the guards. The macOS tool should say so when the default is changed
before the first boot.

## Installing over r2c, and going back

As root, from a checkout of this branch (the lead runs this; no agent has root):

```sh
sudo bash linux/k114s-tooling-install
sudo /usr/local/lib/omarchy-k114s/k114s-release status
```

It needs r2c's persistence (`persist-r2c`), checks that every file is beside it and parses, saves
what it replaces under `/usr/local/lib/omarchy-k114s/tooling-r3`, and then: installs the tools and
data; swaps r2c's two pacman hooks for the three new ones; merges the hold list (what was held
and is installed, plus the defaults that are installed; `omarchy` and `omarchy-settings` drop out
because Edge's `omarchy-dev` replaced them); writes the block; installs and enables the units and
the module-cleanup drop-in; installs both user hooks; records the running boot chain as proven;
writes a recovery set. It installs no package, changes no file on the ESP and does not reboot.

If the backup cannot be written, the installer stops before replacing files. Correct the
backup error and retry. If an older installer left an incomplete `tooling-r3` directory,
inspect its contents and the existing tooling before running undo.

- `--refresh` copies scripts and data again after a repository update; settings, the hold list
  and state are kept.
- `--undo` puts back exactly what r2c left (the test compares every file by content and mode).
  It is refused while a trial is in progress, and it says which packages were released meanwhile.
- `--no-recovery-set` skips the archive step (about 350 MB with both boot images).

Two things to settle on the machine first, both read on 2026-11-14:

- **The standing GPU trial.** The installer records the start it runs in as proven, Stage 2
  included. Run it from a start that came through the GPU trial (as every start does today), or
  from one through the configured file once the trial has been made the configured file. The
  `stage2-trial` file blocks Stage 2 trials of this tool, by design.
- **Which image is proven.** The EFI variable says the running system was started from
  `EFI/Linux/omarchy_linux-aurora.efi`, the standard image, not the repair image. The installer
  records the running one. If the repair entry should be the proven one, boot it and run
  `sudo k114s-release mark-known-good`.
- **Room.** The ESP has 87.7 MB free with two images on it. An update that rebuilds the boot
  image is counted at about 90 MB (kernel 54.1 + initramfs 25.0 + 2.1, plus the 8 MiB margin) and
  is stopped until one image goes; a kernel release needs more. r2c's guard stops every
  transaction below 100 MB, so this is no step back, and ordinary updates now pass. With the
  standard image proven: `sudo k114s-release forget-image EFI/Linux/omarchy_linux-aurora-k114s.efi`
  frees 112 MB after a verified copy.

## For the next kernel

- Give the r3 kernel a **release string of its own** (`uname -r`). A kernel package with the
  running kernel's release string would replace the proven kernel's modules in place, and
  `k114s-release` refuses to stage it unless `K114S_ACCEPT_SHARED_MODULES=1`.
- Do not name its package `linux-aurora-k114s` while `omarchy_linux-aurora-k114s.efi` is the
  repair image: the system's hook names boot images after the package and would overwrite it.
- As package `linux-aurora` with a version above the installed one, it goes in with
  `sudo k114s-release adopt FILE` and stays held; the channel's kernel then has to pass the
  criteria and be at least that upstream version to replace it.

## Tests

`bash tests/linux/run-r3.sh`, as a normal user, no fixtures, on 2026-11-14 on the K114s:

```
r3 syntax and data checks: 80 passed, 0 failed
r3 guard tests: 183 passed, 0 failed
r3 recovery tests: 58 passed, 0 failed
r3 release-check tests: 87 passed, 0 failed
r3 release tests: 137 passed, 0 failed
r3 install tests: 58 passed, 0 failed
r3 pacman tests (replica: real pacman in a user namespace): 187 passed, 0 failed
r3 update tooling: 790 passed, 0 failed, 0 test file(s) skipped
```

`R3_DEBUG=1` prints the output of a failing test, `R3_KEEP=1` keeps the temp folder. A test file
that lacks a tool on the host says SKIPPED. r2c's own tests (`test-persist.sh`, `test-hook.sh`)
need the build fixtures and were not rerun here; the one r2c file changed,
`update-boot-ctxr-k114s`, has its additions tested in `test-r3-release.sh` and in the replica. `test-omarchy-patches.sh linux` (origin/main's) passes beside them: 67 passed, 0 failed.

What the replica run shows, in order: the installer over r2c's state; an ordinary update with a
full ESP goes through and the space guard does not even run; an update that rebuilds the boot
image is stopped by the sum and goes through with room; the 2026-11-14 refresh replayed (stopped
with no holds, harmless with them); named installs and removals; a switch to stable; `omarchy
reinstall`; `NoExtract`; adopting the rebuilt plugin; a userland release through the post-update
hook, its rollback from the archive; a refused kernel transaction; a kernel, firmware and loader
release staged, abandoned, staged again, booted from the old entry, booted incomplete, proven,
retired on the second boot; a Stage 2 trial refused beside a standing trial of someone else, then
armed beside the proven file, a trial start that hangs and falls back, `--rearm`, two good trial
starts that arm it again, the switch on a later run, the candidate cleaned up; the steady state where
the proven image is the standard one; a locally built kernel through the same road; undo. Since
the second review it also shows: a released kernel and a released loader staying held (an ordinary
update and a named install both stopped; the owner's blanket override leaves `boot-ctxr.bin` alone);
a channel kernel whose release string sorts below the running one, with a stand-in of Omarchy's
saved-modules hook (the modules are put back; the test fails when that step is switched off); the
stand-in `limine-entry-tool` taking the boot-partition lock inside the transaction (it times out
if `k114s-release` keeps holding it); Mesa installed under the permit and still held, the next
build released by `auto`, the rollback through `adopt`.

Read on the live Mac as a normal user (agent-run, read-only, 2026-11-14 17:57): `k114s-release
status` from this branch reports `booted: Stage 2 m1n1/boot-ctxr-r3-gpu.bin (a one-boot trial)` and
the lead's standing trial under `elsewhere:`; the r3 guards are not installed yet.

Bugs these tests found in the first draft, all fixed: a check that always passed because a glob
ran with globbing off; a trial that a record from the staging boot could have "proven"; a retire
that looked for the old image under its new name; an abandon that pacman refused over the saved
module folder; three silent exits under `set -e`.

## What is not shown, and what can go wrong

- **No boot.** Whether a channel kernel that passes the criteria starts this Mac is shown only by
  the owner booting the additional entry. The criteria are evidence, not proof; `code-imm16` in
  particular looks for a constant in machine code.
- **The boot-success record** is written a minute after boot and retried every ten minutes until
  the boot is ok. It says what a script observed (a Hyprland process, `wlan0`, the
  input device `Apple MTP multi-touch`); all three names were read on this Mac. It does not know
  whether the pointer moves.
- **Stage 2** has no additional menu entry; its safety is the loader's one-boot trial and its
  watchdog, as the lead used it for the GPU Stage 2. A candidate that starts Linux but breaks
  something the boot check does not look at would still be armed again; the switch to it needs two
  recorded ok starts and a later run, and the way back after the switch is from macOS. The
  `aura-try` format and the `chosen/aurora,trial` property were read from the lead's files and
  this Mac's device tree, not from the loader's source.
- **The real boot hooks** (`limine-mkinitcpio`, `update-m1n1`, `kernel-modules-hook`) were stood
  in for. Their triggers were read from this machine; that Limine keeps the K114s menu block and
  `default_entry` is taken from the 2026-11-14 pacman log, and `k114s-release` checks both after
  the transaction and says so loudly when they are gone.
- **`omarchy update`'s own boot check** runs after the post-update hook. With a kernel staged in
  that hook it judges the new boot files; r2c's `owner-boot-chain` declaration turns its failure
  into a warning. Not run here.
- **Holding channel tooling for long** (`limine`, `omarchy-mac-boot`, `asahi-scripts`, ...) will
  one day stop `omarchy update` on a dependency. Each has a `manual` line for that day.
- **`hyprland-m5` provides `hyprland=0.57.2`.** When the channel's desktop needs a newer
  Hyprland, updates stop on that dependency until a newer `hyprland-m5` exists.
- **Free space as pacman sees it** uses `df` on `/boot/efi`; a transaction on another mounted ESP
  is refused by `k114s-booted-esp` as in r2c.

## Provenance

This repository's own work (MIT). One row for `NOTICE.md`, which this branch does not edit:

| Path | Origin | Author | License |
| --- | --- | --- | --- |
| `linux/k114s-modules-cleanup` | the `ExecStart` line of `linux-modules-cleanup.service` in kernel-modules-hook 0.1.7, written out, with a keep list | saber-nyan (kernel-modules-hook); keep list here | The Unlicense |

Methods taken, not code: `checkupdates` (pacman-contrib) for the private list refresh under
`fakeroot`; makepkg's `.MTREE` options for the rebuilt archives.
