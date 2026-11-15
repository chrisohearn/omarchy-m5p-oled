# r3a: the integrated K114s kernel candidate, its package and its staged install

Evidence labels: **agent-run** (run on this Mac or its build area), **emulator/replica** (QEMU, fake
trees), **read from source** (code and hooks read, not provoked). Nothing here has run on the K114s
hardware. Nothing built for r3a is installed; every root step is in the runbook at the end.

## 1. What r3a is

| Part | State |
| --- | --- |
| Kernel | the running kernel's source (aurora-silicon/linux `a34d26c2` + betizzel's 19 patches + `pr1568.patch`) plus 20 r3 patches and the r3 configuration delta (`sleep-lid/0010` is not in r3a, section 2). Release `7.3.0-17.v272-4-k114s-r3a-ARCH` (the running one is `7.3.0-17.v272-4-ARCH`) |
| Package | `linux-k114s 7.3.0.r3a-2`, installs beside `linux-aurora`, shares no file with it (`-1` had `sleep-lid/0010` and is superseded) |
| Device tree | `dts/t6050-k114s-r3a.dts`: the proven r1 tree plus the sleep pieces (three properties). Sound is a build variant that needs this Mac's own data (section 4) |
| Stage 2 | `boot-ctxr-r3a.bin` (the r3a tree in the installed Aura loader), tried as a one-boot trial, never first |
| Staging | (i) r3a kernel on the proven r1 tree, started once through Limine's own one-shot request; (ii) the r3a tree as a one-boot Stage 2 trial; (iii) the r3a kernel on the GPU tree, as its own step; (iv) promotion, only after (ii) and (iii) are proven. The GPU Stage 2 trial is ended for (i) and (ii) |

## 2. The merge, and what was left out

`r3/integrate` merges `r3/config`, `r3/sound`, `r3/usb`, `r3/sleep-lid` and `r3/buildenv` (the native
build tooling and the `build-dtb.sh` fix that every dtc here needs). The merges keep the
branches' own commits and so their authorship; `NOTICE.md` carries the rows of every branch.

From `r3/display-gpu` only these six kernel patches were taken, because they are inert unless the
device tree describes a DCP or a GPU, which r3a does not:

| Taken | What | Why it is safe without a new loader |
| --- | --- | --- |
| `display-gpu/0003`-`0006` (#1868) | the display driver offers only the 120 Hz mode on firmware 27.2 T6050 internal panels, keeps every mode on an external DCP | `appledrm` finds no DCP node in the r3a tree, so it never binds. `0006` scopes the gate to the T6050 internal path |
| `display-gpu/0009`, `0010` (#1648 bindings) | schema text only | no runtime effect |

**Left out, for candidate r3b (it needs the new Stage 2 loader and this Mac's Apple device tree data):**

| Left out | Why |
| --- | --- |
| `sleep-lid/0010` = `display-gpu/0002` (#1844 second commit, `788441e0`, GPU mailboxes by interrupt only) | **Left out of r3a after the device-tree review.** The GPU Stage 2 trial that this Mac runs binds two `apple,t6050-j775d-ascwrap-v6` mailboxes (`2302600000`, `2302e00000`) and receives on them by polling (`.rx_poll_only`, upstream `43c6ca839e`: on a 14-inch M5 Max the GPU ASC interrupt never reached the AIC). `0010` removes the polling and the storm guard, so receive would depend on an interrupt never seen on a 14-inch T6050. r3a keeps `0009` (polling stays until the interrupt delivers a message, storm guard stays). `0010` goes to r3b, after `/proc/interrupts` shows `2302600000.mailbox-recv` rising on a 0009-only kernel on the GPU tree (the r3a + GPU step) |
| `display-gpu/0001` (#1844 first commit) | already in `sleep-lid/0009`: taken once |
| `display-gpu/0007`, `0008` (#1688, eDP connector) | already in `sleep-lid/0004`, `0005`: taken once |
| `patches/aura/0001`-`0003` (the loader: panel pin table, #226, #230) | a new Stage 2 loader changes the chain that every boot entry uses and has never booted in this form. The installed loader refuses a K114s panel image it does not pin |
| `dts/t6050-k114s-display-gpu.dtsi` and the `r3-edp`, `r3-gpu`, `r3` trees | enable the DCP, the panel and the GPU. The panel hand-off is the one step that can cost the picture (`docs/r3-display-gpu.md`, risks), and the GPU without the panel is the lead's separate standing trial |
| display tools and tests (`tests/lint-display-gpu-dtb.py` and friends) | belong with the trees |

The sleep patch `0008` (PMP domains always on) has no effect in r3a (PMP stays disabled in the shipped tree). `0009`
(GPU mailbox receive, polling kept) has no effect on the r3a tree, which binds no GPU mailbox; on the GPU tree it acts on the two
bound GPU mailboxes but keeps their polling. (An earlier version of this document, and `docs/r3-sleep-lid.md`, said that no GPU
mailbox is bound at all: that was true of the r1 tree only, and is corrected.) They are in the kernel because the sound variant enables
the PMP and r3b enables the GPU display path, and a kernel without them makes those unsafe (`docs/r3-sleep-lid.md`).

## 3. Kernel

### Series and order

`patches/linux/r3a.series` lists the patches in the order applied. Summary:

1. base: `a34d26c2` + betizzel's `linux-j714s-27.2.patch` (19 patches). Our build area's `src/base`.
2. `patches/linux/pr1568.patch` with `patch -Np1 --no-backup-if-mismatch` (`git am` refuses it, one hunk
   needs fuzz; this is what the running kernel has). Result: `src/r1`.
3. `localversion.10-pkgrel` with the content `-17.v272-4-k114s-r3a`.
4. `sleep-lid/0001`-`0009`, `display-gpu/0003`-`0006`, `0009`, `0010`, `sound/0001`-`0004`,
   `usb/0001`, by `git am`, no fuzz (agent-run, 20 commits; the first build had 21 and `sleep-lid/0010` was taken out again
   with `git apply -R`, the same source: no later patch touches `mailbox.c` or `mailbox-g17-test.h`).

Reproduce (build area per `build/native/README-build.md` and `docs/r3-buildenv.md`):

    cd $K114S_BUILD_ROOT/src && git clone r1 r3a && cd r3a      # or: git worktree
    git checkout -b r3a && printf -- '-17.v272-4-k114s-r3a' > localversion.10-pkgrel
    git add localversion.10-pkgrel && git commit -m 'k114s r3a: release suffix'
    grep -v '^#' "$REPO/patches/linux/r3a.series" | while read p; do git am "$REPO/patches/linux/$p"; done

### Release string

Composed as `7.3.0` (the Makefile) + the content of `localversion.10-pkgrel` + `CONFIG_LOCALVERSION`
(`-ARCH`). The running kernel's file holds `-17.v272-4`; r3a's holds `-17.v272-4-k114s-r3a`, so the release is
`7.3.0-17.v272-4-k114s-r3a-ARCH`. It still ends in `-ARCH`, because `update-m1n1` globs
`/lib/modules/*-ARCH` and the Limine hook discovers kernels by `modules.builtin` (checked in section 5).
The two module directories coexist. This also answers the ABI risk in `docs/r3-config.md`: PSI,
CFS bandwidth, conntrack marks and policy routing change structure layouts and `MODVERSIONS` is
off, so a module from the old tree must never load into the new kernel. With different release
strings the kernel looks only in its own directory.

### Configuration

The running configuration (`zcat /proc/config.gz`) merged with `patches/linux/config/k114s-r3.config`:

    cp config-running $O/.config
    scripts/kconfig/merge_config.sh -m -O $O $O/.config patches/linux/config/k114s-r3.config
    kmake O=$O olddefconfig

(agent-run: this recipe reproduces the used `.config` line for line, ignoring `CC_VERSION_TEXT`.)
`build/validate-config.py` passes the result against `k114s-required.config` and `k114s-r3.config`:
385 requirements, 0 not met. The running kernel passes `k114s-required.config` (133 requirements),
so nothing the machine needs was dropped.

### Build (agent-run, this Mac)

    source $K114S_BUILD_ROOT/env.sh
    cd $K114S_BUILD_ROOT/src/r3a && kmake O=$K114S_BUILD_ROOT/build/r3a -j14 Image modules dtbs

6 min 13 s for the first build (21 patches); taking `sleep-lid/0010` out again was an incremental build of `mailbox.o`, the relink and the `Image` at -j8 (a few minutes). `kernelrelease` `7.3.0-17.v272-4-k114s-r3a-ARCH`, 1972 modules (the running kernel has 1728;
the difference is the config delta), `Image` 54,217,216 bytes (the running image: 54,086,144).
Toolchain as in the foundation build (clang 23.1.3, Rust 1.98.1).

Module comparison with the installed tree (`k114s-cmp-modules`, `integrate/cmp-modules-r3a.txt`): 1181 differ
as expected (the changed core structures and the new configuration change code; see the list), 244
are new, 547 identical.

## 4. Device tree

`dts/t6050-k114s-r3a.dts` = r1 (`K114S_R1_N1`, `K114S_R1_USB`, `t6050-k114s-common.dtsi`) + `t6050-k114s-usb.dtsi` +
`t6050-k114s-sleep.dtsi`. `t6050-k114s-r3a-sound.dts` defines `K114S_R3A_SOUND` and adds the sound fragment.

Build (against the r3a kernel tree's includes, writes nothing into it):

    build/build-r3a-dtb.sh $K114S_BUILD_ROOT/src/r3a t6050-k114s-r3a OUT        # prints the sha256

agent-run: **`154568feac3d5c0dc1e1e7f1bb9778c33de29904b49f1813afde4b0bb9b65297`** (107,727 bytes) with dtc 1.8.1
and with the kernel tree's own dtc. Against the old r1 kernel tree the same source gives `3b25b6c3...`:
the kernel's `t6050-k114.dtsi` carries `sleep-lid/0005` and `0008`, so the fragment sets properties
that are already set; the decompiled trees are identical. Use the blob built against the r3a tree.
The proven r1 tree stays `2ea22d26b2a1c81526e77e7f29eaff46def5310a9512be769ff3ed50465f4dd2` (built against the r1 tree).

`tests/lint-dtb.py` passes on both. dtc prints one warning (`simple_bus_reg` for `/soc/pmp@284e00000`),
present in r1 as well.

### Changed or added nodes, r1 blob against r3a blob (`tests/dtb-node-diff.py`)

0 nodes added, 0 removed. Four properties:

| Node | Change |
| --- | --- |
| `/chosen/framebuffer@0` | `+ apple,internal-panel` (the boot framebuffer's connector becomes `eDP-1`, `sleep-lid/0004`) |
| `.../power-management@280600000/power-controller@100` | `+ apple,always-on` (the PMP's `ps_pms`; the domain stays disabled, so no effect yet) |
| `.../power-controller@128` | `+ apple,always-on` (`ps_pmp`; same) |
| `.../power-controller@130` | `+ apple,always-on` (`ps_pms_sram`; same) |

USB: nothing changes in the tree, on purpose. `docs/r3-usb.md` shows that the empty `/sys/bus/usb/devices`
is the idle state (the xHCI is created when a device attaches), and that the K114s nodes equal the K116s
nodes at upstream head. The only USB change is kernel patch `usb/0001` (async probe of the port controller).
Test with a real device on the left-front or the right port.

### The sound variant (not shipped, built here only as a replica)

`t6050-k114s-r3a-sound.dts` does not compile without `t6050-k114s-pmp-tunables.dtsi`, which holds this Mac's
own PMP values (DRAM vendor, GPU voltage table, segment ranges, UUID) and comes from its Apple device
tree, readable by root only (`docs/r3-sound.md`). The build area has a copy generated by the sound worker
(one Mac's data, not in git). Built with it (emulator/replica: nothing booted), the node diff against the r3a tree is:

    ADDED  /soc@200000000/i2c@505018000/codec@4b      (CS42L84 jack codec)
    ADDED  /sound, /sound/dai-link@0, .../cpu, .../codec   (one link: "Headphone Jack")
    PROP~  status disabled -> okay: power-controller@100, @128, @130 (PMP domains), i2c@505018000,
           mailbox@290608000, iommu@290fc0000, dma-controller@293800000, aop@290c00000,
           /soc/mailbox@2d067c000, /soc/pmp@284e00000, mailbox@284e08000, pmp-report@284240000,
           iommu@2841a0000, dma-controller@2d3200000
    PROP+  power-management@286806000 apple,pmp; apple,static-voters <1 3> -> <0 1 3>
    PROP+  /soc/pmp@284e00000 apple,board-id, apple,dram-vendor-id, apple,pmc, apple,pmc-pmgr
    PROP~  pinctrl@29c000000 gpio-ranges (phandle), gpio-reserved-ranges (exposes 80, 134, 139)
    PROP+  aop audio apple,chassis-name "K114", apple,machine-kind "MacBook Pro"; dma-names "cout","cin","hpai"

Speaker check, done here independently on that blob (agent-run, on the compiled tree, not only by the
sound worker's lint): no `tas2764` or any amplifier node exists; `i2c1` and `i2c3` (the amplifier buses) are
not enabled; the `/sound` card has the single link "Headphone Jack" and no "Speaker" link; the AOP audio node's
`dma-names` has no `spkr` or `sense`; the amplifier shutdown and fault pins 106 and 107 and the speaker-ID
pins 136 and 137 are inside `gpio-reserved-ranges` (only 80, 134 and 139 are exposed). `tests/lint-sound-dtb.py` passes.

## 5. Package `linux-k114s`

`packaging/linux-k114s/PKGBUILD` packages a finished build (it compiles nothing); `check-package.sh`
tests the result; `dtbs.list` names the 46 device trees.

    source $K114S_BUILD_ROOT/env.sh
    cd packaging/linux-k114s && BUILDDIR=... PKGDEST=... makepkg -f --nodeps --skipinteg      # no root, about a minute
    ./check-package.sh PKG.pkg.tar.zst

Contents (agent-run listing): `usr/lib/modules/7.3.0-17.v272-4-k114s-r3a-ARCH/` with `vmlinuz` (the raw arm64
Image), `pkgbase` (`linux-k114s`), `modules.*`, `kernel/` (the modules, no `updates/`), `dtbs/` (flat, the same 46
names as `linux-aurora`, `t6050-k114s.dtb` is the kernel tree's preliminary tree, not the r3a tree, see below), plus `usr/share/linux-k114s/config-<release>`.
2,588 entries; the package file is 47,441,434 bytes. No symbolic links (the `build` and `source` links are removed).

Checks (agent-run, `check-package.sh`, all pass): one module directory; release ends in `-ARCH` and differs from
linux-aurora's; **no file in common with `pacman -Qlq linux-aurora`** (compared with `bsdtar -t`; only
parent directories overlap); the `vmlinuz` inside the package is the built `Image` byte for byte; all 1972 modules
carry vermagic `7.3.0-17.v272-4-k114s-r3a-ARCH` and `modinfo` reads them with the package's depmod data;
`depmod -a -e` over the package tree reports no error and no unresolved symbol; the kernel banner in `vmlinuz`
names the release.

### What the slot design is, and its limit

Constraints: the ESP has about 87.7 MB free; a UKI is about 79 MB; entry 1 (static repair UKI, 112 MB)
must stay and needs `/usr/lib/modules/7.3.0-17.v272-4-ARCH` on root. Nothing else on the ESP is mine to delete
(`asahi/` 90 MB, `vendorfw/` 113 MB and `m1n1/boot.bin*` 20 MB are the installer's and the hooks' files; deleting them is the owner's decision).
Inventory (agent-run, `du -ab`): `EFI/Linux` 191 MB (the two UKIs), `vendorfw` 113 MB, `asahi` 90 MB, `m1n1` 29 MB, the rest under 5 MB.

Chosen: **install `linux-k114s` beside `linux-aurora`, and for the length of the trial free the hook-managed slot first by removing
linux-aurora's hook-built UKI and its menu entry (`limine-entry-tool --remove-uki linux-aurora`), not the package.** The 79 MB
copy of that UKI is already in `/var/lib/k114s-recovery/uki/` (sha256 `cce61605...`, same bytes as the ESP file, checked in step D0), and the undo
puts that very file back, not a rebuilt one.

- `linux-aurora` stays installed and owned: its modules directory is package-owned, so
  `linux-modules-cleanup.service` leaves it alone; `IgnorePkg`, the K114s hold guard and entry 1 keep working. Wi-Fi
  on entry 1 (`apple_centauri_t6050` loaded after the initramfs) keeps its modules.
- The Limine hook builds the UKI per kernel directory found through `modules.builtin`
  (`pacman -Qqo` gives the package name, so the new UKI is `omarchy_linux-k114s.efi`), by
  `mkinitcpio --kernel <release> --uki ...`, not through the preset. Removing linux-aurora's preset would therefore not stop its UKI.
- **The macOS repair tool needed a change, and has one.** `macos/tools/k114s_repair.py` used to require
  `EFI/Linux/omarchy_linux-aurora.efi` in `status`, `default`, `stage2`, `kernel` and `rollback all`. With the file gone, `status` failed,
  `default` and `stage2` wrote and then reported STOPPED, `rollback all` (which `docs/bundle-r2c.md` tells the owner to run "if Linux does not start")
  would have restored a menu that points at the missing file and deleted the repair image, leaving no Linux entry that starts, and `default 1`
  (a value the tool never accepted) was the wrong word for `default repair`. Now, without the original image: `status`, `stage2`, `default repair`
  and `rollback stage2` work; `kernel`, `default original`, `rollback all` and `apply` stop with a message and write nothing
  (tests: `tests/macos/test-no-original-uki.sh`, 24 passed). The delivered earlier tool stops on that ESP (does not find it) and writes nothing, so the fixed file has to be on the Mac, confirmed by `status` there, before the window opens: a hard prerequisite of step D1.
- **Limit, not fixed here.** After the swap the ESP is expected to have about 87.6 MB free (replica UKI builds: r3a 79,363,072 bytes, baseline 79,252,992), 0.4 MB
  under the space guard's 88,080,384; that margin is an estimate, so step D4 measures the real value and stops if it is not below the minimum. While it is, every package transaction is refused by the guard for as long as both kernel directories exist.
  That refusal is correct, not a nuisance: a transaction that touches `usr/lib/firmware/*`, `usr/lib/initcpio/*`, `boot/dtbs/*` and the like
  makes the Limine hook rebuild **every** kernel directory it finds, which would create linux-aurora's 79 MB UKI again in what is left, and
  `allow-low-esp` switches the guard's space check off (never its mount check). So the swap is a **trial window**, not a steady state: it opens at step D1, closes with the undo (step Z)
  or with a promotion decision (below), and no other package transaction runs inside it. This is also why unattended updates cannot run while the
  window is open. The state that does allow unattended updates is a single hook-managed kernel directory, or a larger ESP; either
  is a decision for the owner and is not made here.
- Rejected: replacing `linux-aurora` (the hold guard, `IgnorePkg` and entry 1's module directory all depend on that package);
  a companion package owning the old modules directory (a second package that ships the same files as another is a file
  conflict); a third UKI (does not fit); a kernel on `/boot` instead of a UKI (Limine reading another filesystem and the hook's
  paths are both untested here, which would put a second new thing into the first trial).

### What installing the package triggers (read from the installed hooks; the install is not run)

`sudo pacman -U linux-k114s-7.3.0.r3a-2-aarch64.pkg.tar.zst`

| Order | Hook | What it does for this package |
| --- | --- | --- |
| Pre | `00-k114s-hold-guard` | triggers on `linux-aurora`, `m1n1-aurora`, `uboot-aurora`, `omarchy-aurora-firmware`, `omarchy-mac-boot`, `limine-mkinitcpio-hook`: **not this package. Passes** |
| Pre | `01-k114s-esp-space` (`K114S_ESP_MIN_FREE=88080384`) | runs for every transaction. **Free now 87,724,032: it stops today.** After the slot is freed (about +79 MB) it passes |
| Pre | `10-linux-modules-pre` | backs up the running kernel's module directory; `10-linux-modules-post` puts it back and removes the backup. No effect on r3a |
| Post | `60-depmod` | `depmod` for the new directory (already done in the package; harmless) |
| Post | `90-mkinitcpio-apple-install` (system, on `vmlinuz`) | `mkinitcpio install`: creates `/etc/mkinitcpio.d/linux-k114s.preset` from the template, copies `vmlinuz` to `/boot/vmlinuz-linux-k114s`, builds `/boot/initramfs-linux-k114s.img`. `/boot` is the 2 GB partition (1.8 GB free). Nothing is written to the ESP by this hook |
| Post | `/etc/pacman.d/hooks/90-mkinitcpio-install` (the Limine one, trigger `usr/lib/modules/*/modules.builtin`) | `limine-apple-gate` then `limine-mkinitcpio-install`: only this kernel directory is processed. Builds `omarchy_linux-k114s.efi` with `mkinitcpio --kernel 7.3.0-17.v272-4-k114s-r3a-ARCH --uki` (cmdline from `KERNEL_CMDLINE[default]` in `/etc/default/limine`), **copies it to `/boot/efi/EFI/Linux/omarchy_linux-k114s.efi` (about 79 MB)** and adds a menu entry with `limine-entry-tool --add-uki` (rewrites `/boot/efi/limine.conf`). The initramfs hooks (`omarchy-vendorfw`, `asahi`) put the K114s firmware, among it `/usr/lib/firmware/updates/apple/centauri/k114s-ftab.bin`, into it the same way as for entry 3, which booted with Wi-Fi |
| Post | `95-m1n1-install` (`/usr/bin/update-m1n1`, trigger `usr/lib/modules/*/dtbs/*`) | **fires.** It picks the dtbs of the highest `/lib/modules/*-ARCH` directory by `sort -rV`, with `LC_ALL=C` from `/etc/default/update-m1n1`. In the C locale `...-4-k114s-r3a-ARCH` sorts after `...-4-ARCH` (`k` after `A`), so r3a's 46 trees would replace linux-aurora's in `m1n1/boot.bin`, which is written as `boot.bin.new`, then the old file is kept as `boot.bin.old`: **about 19 MB of ESP traffic and about 9 MB net growth** on a partition that has none to spare. `boot.bin` is not the file the loader boots (`boot-ctxr.bin` is), but its hash is part of the recorded state. Recommended: disable it for this transaction, see the runbook |
| Post | `/etc/pacman.d/hooks/96-omarchy-j714s-boot-ctxr` (trigger on `dtbs/*`) | runs `update-boot-ctxr`, which rebuilds `boot-ctxr.bin` from the **pinned** tree `/boot/efi/k114s-repair/k114s.dtb` and the Aura loader plus the U-Boot tail of the existing `boot.bin`; it does not read the package's `t6050-k114s.dtb`. With `boot.bin` untouched it writes the same bytes (`45a5dbef...` for r1: reproduced here byte for byte from `/usr/lib/asahi-boot`, agent-run). With `boot.bin` rebuilt, the tree and tail are the same, so the result is the same too |
| Post | the rest (`25-systemd-*`, `30-...`, `35-...`) | unrelated |

Not triggered: `81-omarchy-mac-limine-deploy` (BOOTAA64.EFI), `80-limine-efi-deploy`, `03-k114s-omarchy-patches`.

What `boot.bin` choice means: the highest-version rule is only a risk to ESP space and to byte-stability of `boot.bin`. The
r3a package's `t6050-k114s.dtb` is **not** the r3a tree (corrected after the device-tree review): it is the kernel tree's own preliminary
`t6050-k114s.dts` plus the four properties, sha256 `d1011ecf0d88fa340cb4979a9443223308db057c0f8bde2aaf852a60a9cb16d7`, which lacks 35 nodes of the r3a tree (the N1, USB and
SMC sensors). `check-package.sh` now prints that hash. It does not change what boots: the Stage 2 is built from the pinned tree, and `use-packaged-dtb`
must stay absent; anyone who sets it, or boots `boot.bin`, would get a tree without Wi-Fi or USB.

## 6. Stage 2 and the one-boot entry, staged

### The one-boot entry (requirement: survives a hang before the root filesystem)

The old plan changed `default_entry` to the new entry and relied on a unit that reverts it once the boot reaches root. That unit is
disabled on this Mac, and it could not help anyway: a hang before the root filesystem never starts it, so `default_entry` would stay on
the trial entry for every later boot, and the built-in keyboard does not work in Limine's menu. **That mechanism is removed from the plan** (the installed
`k114s-trial-default-revert` unit stays disabled and nothing creates `/etc/omarchy-k114s/trial-default`).

The trial uses Limine's own boot-once request, read from the source of the installed Limine 12.9.6 (`common/lib/bli.c`, `common/menu.c`; the installed
`CONFIG.md` says "a Boot Loader Interface `LoaderEntryOneShot` request takes precedence over `default_entry`"):

- Linux writes the EFI variable `LoaderEntryOneShot` (GUID `4a67b082-0a4c-41cf-b6c7-440b29bb8c4f`, attributes NV|BS|RT) holding the entry id as UTF-16
  (`Omarchy.linux-k114s`: the entry path with `/` as `.` and every byte outside `[A-Za-z0-9+_.@-]` as `-`; the two entries now on the ESP give exactly
  the ids that Limine publishes in `LoaderEntries`, agent-run).
- **Limine erases the variable in the same call that reads it** (`handle_entry(..., erase = true)`), before it boots anything. A kernel that hangs
  leaves nothing behind. `default_entry` is never changed, so the next boot is entry 1, the proven repair entry, with the configured Stage 2.
  An id that matches no entry is erased too and falls through to `default_entry`.
- U-Boot keeps runtime variable writes in RAM (`RTStorageVolatile`), and `omarchy-mac-efi-vars.service` copies them to `ubootefi.var` only at shutdown
  (the J604 finding). So `k114s-boot-once arm` runs `efi-vars-save` immediately, then checks that `ubootefi.var` holds the id as a UTF-16 string, and takes the
  request back if it does not (agent-run on a fake ESP with a stand-in saver: `tests/linux/test-boot-once.sh`; the real saver and Limine are the self-test, step B).
- **What step B proves, and what it does not.** The gate reads `ubootefi.var` from Linux in the boot where Limine took the request, and that boot then runs normally. It proves the erase is *visible later in the same power cycle*. It does **not** prove the erase survives a forced power-off shortly after U-Boot's write (a write still in the NVMe controller's cache would read back fine). If it did not survive, every later boot would run the trial entry again; see "Ways back, a stuck request". Step B therefore also has an optional durability check (runbook step 3).
- **Nothing observed yet shows that a boot-time write or erase reaches `ubootefi.var`.** `LimineLastBootedEntry` is in that file, but its mtime
  (2026-11-14 17:05:00) is the Linux shutdown save (`efi-vars-save` logged 17:05:00.346 in the previous boot's journal; this boot's kernel started at 17:05:39), so that variable being
  there is explained by the shutdown save and proves nothing about U-Boot at boot (agent-run, read as root). The erase has to reach the file at boot time, because a hang means no
  shutdown and no later save. **Step B is the first and only proof, and failing it is a realistic outcome that blocks steps E to G** (then a kernel trial would have to use a different
  mechanism, an owner decision). The gate is mechanical: `k114s-boot-once status`, run first thing in the boot after step B's request, measures it and writes
  `/var/lib/k114s-recovery/boot-once-selftest-ok` only if that boot is the one right after arming (checked against the journal's previous boot id), Limine started the requested entry, the variable is gone from efivarfs
  **and** from U-Boot's file, and that file was not written during this boot. `arm` refuses every target except entry 1 (the request that changes nothing) unless that marker exists
  (tests: `tests/linux/test-boot-once.sh`, 61 passed, which covers pass, fail, wrong boot, a save during the boot and `clear` between arm and reboot).

`k114s-boot-once arm` also refuses (a hard check, not advice) unless `default_entry` is 1 and entry 1 is the repair entry, the target's EFI file is on the ESP and
matches its `#hash`, no Stage 2 trial is armed or configured to re-arm, the four sleep targets are masked, `remember_last_entry` is not `yes` (Limine would then boot the last booted entry ahead of `default_entry`), and, for any target but entry 1, the step B marker exists. It numbers entries the way Limine's
`default_entry` does (every entry line counts, directories included; `entries` prints the index, the id and the file), which replaces the earlier
`grep -n` line numbers.

### The Stage 2 of each step, and the GPU

The Stage 2 file is shared by every boot entry. This Mac now boots through a standing trial of `m1n1/boot-ctxr-r3-gpu.bin` (the GPU tree):
`/etc/omarchy-k114s/stage2-trial` names it and `k114s-stage2-rearm.service` re-arms `aura-try` at every clean shutdown after a good trial boot.
The device-tree review showed that this matters for the kernel: on that boot `2300000000.gpu` is driven by the `aurora` driver and two
`ascwrap-v6` GPU mailboxes are bound, and the old kernel receives on them by polling. So:

- **Steps (i) and (ii) never run on the GPU tree.** Step C ends the standing trial before the kernel boots: `stage2-trial` is *moved aside* (so the re-arm unit does nothing at
  shutdown) and `aura-try` is written `spent`. The kernel then boots on the configured, proven `boot-ctxr.bin` (r1 tree, `45a5dbef...`, no GPU node, no render node).
  `k114s-boot-once arm` refuses to arm while a trial is armed or configured, and `tests/hardware/k114s-r3a-check.sh` prints BAD if the booted Stage 2 is the GPU one or a render node exists.
- **How the desktop stays on the CPU.** On the r1 tree there is no render node, so the session guard (`/etc/systemd/user-environment-generators/70-k114s-gpu-desktop`) prints nothing and the session is exactly what it was before the GPU work.
  Version 2 of the guard (`linux/r3a-trial/70-k114s-gpu-desktop`, tested by `tests/linux/test-gpu-guard.sh`, 7 passed) adds a second lock for an accident (a trial left armed): on a
  `...-k114s-r3a-ARCH` kernel it keeps the desktop on the CPU even with `~/.config/k114s-gpu-desktop`, until the separate opt-in `~/.config/k114s-gpu-desktop-r3a` exists.
- **r3a + GPU is its own step (G).** After (i) and (ii) are clean. It restores the parked trial, creates the second opt-in, and boots the r3a kernel on the GPU tree once. The kernel there is the
  0009-only kernel: 0009 enables the mailbox receive interrupt beside both pollers (a line that never fires keeps polling, the storm guard is in place), which is the first time it is enabled on this Mac, and everything else in r3a is new on that tree too. `0010` stays out until r3b.
- Suspend stays forbidden on the GPU tree until `0010` is in and proven (`docs/r3-sleep-lid.md`).

### The Stage 2 files

    m1n1/boot-ctxr.bin           configured, proven r1 tree; never overwritten until promotion
    m1n1/boot-ctxr-r3-gpu.bin    the standing GPU trial's file (parked by step C, restored by step G)
    m1n1/boot-ctxr-r3a.bin       the r3a tree, 4,439,433 bytes (step F)

Built exactly as `update-boot-ctxr-k114s` does (`build/make-stage2.sh`): `/usr/lib/asahi-boot/m1n1.bin` (3,997,696 bytes,
Aura) + exactly one tree + `gzip -c u-boot-nodtb.bin`, with the file name and mtime of the U-Boot file in the gzip header. The same script reproduces
the proven r1 file (`45a5dbef19c1...`) byte for byte, which is the check that the method is right (agent-run).

| File | sha256 |
| --- | --- |
| `boot-ctxr-r3a.bin` | `5164bb1e1be1fba39aee64229863b2f835828edd8b4f90e8cfa91e71a6fd8cd9` |
| prefix (Aura) | `1546dd5079cefe0f9bbdee9d1c95dcdbad39a73ae140612cd6dfab4596c2f7a3` (same as the r1 file's) |
| tree `t6050-k114s-r3a.dtb` | `154568feac3d5c0dc1e1e7f1bb9778c33de29904b49f1813afde4b0bb9b65297` (rebuilt against the final kernel tree: identical) |
| gzip U-Boot tail | `9d8dc11ea755e8405a7380683bd82cfeb7391b1fc68245e56e10bf5155a746ad` |
| `linux-k114s-7.3.0.r3a-2-aarch64.pkg.tar.zst` | `122fdcf88b72102c31ca5e3f8fe8f576c5bf9055f643e242e53e5ff9c4594b80` |
| `vmlinuz` inside it (= the built `Image`) | `bbf5ad5e675a2ac09f6183e463819486f598562648c61f06c6e1111f4710c04f` |

`build/make-stage2.sh` prints the first four values for any tree; the lead verifies the file by the first row.

### Steps

- **(i) r3a kernel on the proven r1 tree**, once, by the Limine one-shot request. Tests the configuration delta (RFCOMM, firewall rules, BBR, PSI, binfmt,
  policy routing, PKCS8) and that the kernel is sound. The sleep, sound and USB changes that need the tree stay off. The kernel does
  contain `sleep-lid/0003`, which admits the K114s to suspend-to-idle: suspend is blocked three ways for the whole trial (masked targets, `sleep.conf.d`, `logind` lid action `lock`; step C).
- **(ii) the r3a tree**, as a one-boot Stage 2 trial (`aura-try`) together with a one-shot r3a kernel. The loader's trial watchdog does not arm on this Mac
  (its log says `WDT: could not arm the trial watchdog`), so a Stage 2 that hangs needs a forced power-off (hold the power button); the trial marker is already
  spent, so the next boot uses the configured, proven file. Run it only with someone at the Mac. Needs an `eDP-1` monitor rule first (`docs/r3-sleep-lid.md`, the connector is renamed).
- **(iii) the r3a kernel on the GPU tree**, once, as step G.
- **(iv) promotion**, only after (ii) and (iii) boot cleanly twice: copy the configured file to
  `/boot/efi/k114s-repair/known-good/boot-ctxr.bin`, then put the r3a file in place and update the pinned tree
  (`/boot/efi/k114s-repair/k114s.dtb` and `/usr/local/lib/omarchy-k114s/k114s.dtb`), otherwise the next run of the Stage 2 hook rebuilds the r1 tree. Not part of this runbook.

### Ways back

- **From Linux, a kernel trial:** there is nothing to undo: the request is consumed and `default_entry` was never touched. `k114s-boot-once clear` takes back a request that has not been used.
- **Stage 2:** the configured file was never touched. Disarm with `printf 'spent\n...\n' > /boot/efi/aura-try`; the standing GPU trial comes back by moving `stage2-trial.parked-r3a` back (step C undo).
- **From macOS, a stuck request** (the trial entry boots again and again, because the erase did not survive a power cut; `default_entry` is already 1, so `default repair` changes nothing): mount the Linux ESP read-write (`sudo diskutil mount <EFI volume>`), rename the trial entry in `/Volumes/EFI/limine.conf` so its id matches nothing, for example
  `sudo sed -i '' 's#^\([[:blank:]]*//linux-k114s\)[[:blank:]]*$#\1-off#' /Volumes/EFI/limine.conf`, check with `grep -n 'linux-k114s' /Volumes/EFI/limine.conf` that the line now ends in `-off`, unmount, and boot Linux. Per Limine's source an id that matches no entry is erased and falls through to `default_entry` (entry 1). Then, from Linux, `k114s-boot-once clear`, and undo the rename (`-off`) once the request is gone. This writes only that one line. It is a manual edit, not a `k114s-repair` subcommand (the tool deliberately writes nothing outside its own files).
- **From macOS** (only if the repair entry itself fails): with the fixed tool, `sudo ./k114s-repair stage2 r1` (it accepts the r3a file as `same-loader-other-trees`), `rollback stage2`, `default repair`, `status`.
  **Never `rollback all`, `default original` or `kernel` while the original image is off the ESP**: with the fixed tool they stop and write nothing.
  **The tool delivered before this change does not work at all once the original image is gone**: it picks the ESP by that file, so `status`, `default repair`, `stage2 r1` and `rollback stage2` all print
  "STOPPED" (on the Mac, via `diskutil`: "expected exactly one Omarchy ESP, found 0"; the text "is not an Omarchy ESP" only appears in `--esp-dir` test mode, which is what `tests/macos/test-no-original-uki.sh`'s old-tool case runs) and write nothing. So the fixed tool on the Mac, with `status` confirmed there, is a hard
  prerequisite of step D1 (runbook step 1); without it the window must not open.
- The kernel side is independent: entry 1 (repair r1) and its module directory are never touched.

## 7. Tests

| Test | Result | Label |
| --- | --- | --- |
| QEMU (TCG), r3a-2 Image, shell | PASS: kernel boots, `uname -r` is the r3a release | emulator/replica |
| QEMU, all 1972 modules from the package tree in an initramfs (r3a-1 Image, which had `sleep-lid/0010`) | `modprobe ok=1965 failed=7`; the same seven as the baseline kernel (tcrypt, ipmi_si, cppc_cpufreq, sun50i-cpufreq-nvmem, stratix10-soc, apple-pmp-j613-hwmon, xen-pciback); no Oops, BUG or panic | emulator/replica |
| QEMU, the same for r3a-2 | `modprobe ok=1965 failed=7`, the same seven failures; no Oops, BUG or panic (`logs/qemu-smoke-r3a-2-modules.log`) | emulator/replica |
| `depmod -a -e` over the package, vermagic of all 1972 modules, no file shared with `linux-aurora`, banner | `check-package.sh`: all passed (r3a-2) | agent-run |
| `validate-config.py` | 385 requirements, 0 not met (the configuration is unchanged by r3a-2) | agent-run |
| `lint-dtb.py`, `lint-sound-dtb.py` | pass | agent-run |
| dtb reproducibility against the final kernel tree | `154568fe...`, same as before | agent-run |
| Stage 2 reproduction of the proven r1 file | byte for byte | agent-run |
| `tests/linux/test-boot-once.sh` | 61 passed, 0 failed (bytes written to the variable, UTF-16 id, every refusal, a saver that does not persist, a failing saver, `remember_last_entry`, the self-test gate) | emulator/replica |
| `tests/linux/test-gpu-guard.sh` | 7 passed | emulator/replica |
| `tests/macos/test-no-original-uki.sh` | 24 passed (synthetic bundle and ESP; includes the old tool stopping on the no-original ESP) | emulator/replica |
| `k114s-boot-once entries` on a copy of this Mac's `limine.conf` | ids `Omarchy-K114s-repair-r1--trackpad-fix-B-` and `Omarchy.linux-aurora`, equal to Limine's published `LoaderEntries` | agent-run |
| `tests/hardware/k114s-r3a-check.sh` on the running kernel | prints BAD for the GPU Stage 2 trial and the render node, and BAD for the 11 CONFIG_ options, as it should | agent-run |

**Not verified:** anything on the hardware; the hooks (read, not run); the real `efi-vars-save` and Limine consuming the request (step B measures it); the
full `tests/macos/test-macos-tool.sh` regression (it needs the assembled bundle and the installer image, which this branch does not have: the original-image
code paths are unchanged); the size of the UKI the hook builds (replica: 79,363,072 bytes); whether `limine-entry-tool` leaves `default_entry` on 1 after adding the entry
(`k114s-boot-once check` asserts it); the interaction of the GPU Stage 2 trial with this kernel (step G); the tipd async probe; any first-boot behaviour of the configuration delta;
the PMP (sound) values on this Mac; the fixed macOS tool on the Mac.

## 8. Runbook (for the lead; root needed)

`R` is `$K114S_BUILD_ROOT/integrate/release/`, `REPO` is a checkout of branch `r3/integrate`, `K=/usr/local/lib/omarchy-k114s/k114s-boot-once`.
Entry 1, "Omarchy K114s repair r1", stays the default through every step; **no step changes `default_entry`**, and the owner never picks an entry (the keyboard does not work in Limine's menu).
Each step has an expected result; stop at the first one that is not met.

**Rules for the window (from step D1 to step Z).** No package transaction except the ones written here (the guard will refuse them anyway). No `omarchy-update`. On macOS: no `rollback all`, `default original` or `kernel`.

**0. Verify and look (no root for the first lines).**

    cd $R && sha256sum -c SHA256SUMS                       # 3 lines OK
    uname -r                                               # 7.3.0-17.v272-4-ARCH
    tr -d '\0' < /proc/device-tree/chosen/aurora,trial; echo   # which Stage 2 THIS boot is. Label everything you read as "r1 kernel on the <this> tree"
    sudo cat /boot/efi/aura-try /etc/omarchy-k114s/stage2-trial

**1. Put the fixed macOS tool where macOS can reach it, and confirm it on the Mac. This is a hard prerequisite of step D1: if it is not done, D1 must not run.** The tool the Mac has today does not recognise the ESP once the original image is off it (section 6), so without the fixed one the window has no way back from macOS. Not testable from Linux.

    sudo mkdir -p /boot/efi/k114s-repair/macos-r3a
    sudo install -m644 $REPO/macos/tools/k114s_repair.py /boot/efi/k114s-repair/macos-r3a/k114s_repair.py
    sudo sha256sum /boot/efi/k114s-repair/macos-r3a/k114s_repair.py $REPO/macos/tools/k114s_repair.py    # equal

On the Mac, once, in Terminal (the owner): mount the Linux EFI partition (`diskutil list`, then `sudo diskutil mount readOnly <the EFI volume of the internal disk>`: read-only, because the Linux ESP has about 84 MB free and a read-write mount lets macOS add `.fseventsd`, Spotlight or AppleDouble files), copy
`/Volumes/EFI/k114s-repair/macos-r3a/k114s_repair.py` over `tools/k114s_repair.py` in the repair bundle folder, run `diskutil unmount <the EFI volume>`, and run `sudo ./k114s-repair status` (read-only). The owner reports that it printed the status and not "STOPPED"; only then does the root continue past step 5's D0.

**2. Step A: a plain reboot on the current command line (no new kernel or tree).** This boot still goes through the standing GPU trial. The r3a UKI embeds the same command line, so the trial must not be the first boot to test it.

    sudo systemctl reboot

After the boot: `findmnt /boot/efi` shows the ESP mounted and `sudo journalctl -b -p warning --no-pager | head -40` shows nothing new. If anything is off, **stop**.

**3. Step B: install the helper and measure the one-shot mechanism on a request that changes nothing.** This is the first and only proof that U-Boot persists a boot-time erase; it can fail.

    sudo install -m755 $REPO/linux/r3a-trial/k114s-boot-once /usr/local/lib/omarchy-k114s/k114s-boot-once
    K=/usr/local/lib/omarchy-k114s/k114s-boot-once
    sudo $K entries                                        # default_entry: 1; entry 1 Omarchy-K114s-repair-r1--trackpad-fix-B-; 3 Omarchy.linux-aurora
    sudo $K check                                          # all ok / info; no BAD
    sudo $K arm 'Omarchy K114s repair r1 (trackpad fix B)' --with-stage2-trial     # the repair entry itself: what boots does not change
    sudo $K status                                         # efivarfs holds it AND "U-Boot file ...: holds LoaderEntryOneShot"
    sudo systemctl reboot

After the boot, **as the very first command** (no shutdown has run since Limine read the request; do not run `clear` or anything that saves first):

    sudo $K status

**Expected: `no LoaderEntryOneShot` on the efivarfs line and on the `U-Boot file` line.** `this boot started: Omarchy-K114s-repair-r1--trackpad-fix-B-` only rules out a wrong entry: the request names entry 1, which is also the default, so the line reads the same whether or not Limine saw the request. The proof that it was consumed is the name missing from `ubootefi.var` (a file that held it at shutdown), which the `U-Boot file` line reports. `status` then ends with `self-test: PASSED ... marker /var/lib/k114s-recovery/boot-once-selftest-ok written`. Any other self-test line (`FAILED`, `NOT MEASURED`) means no marker: if the U-Boot line still says
`holds LoaderEntryOneShot`, the erase did not reach disk before the shutdown save: **the mechanism is not hang-safe; do not run step E** (`sudo $K clear`; report it, a different mechanism is an owner decision);
if it says `NOT MEASURED`, repeat step B (a shutdown save, a clear, or a status run in a later boot voids it). `arm` for the real kernel refuses without the marker. (`clear` between arm and reboot also voids it: it removes the arming record, so a later boot cannot give a false PASSED.) `NOT MEASURED: ... written during this boot` prints the file's mtime and the boot start; if they differ by about a whole number of hours, U-Boot stamps FAT times in UTC and the gate cannot pass: report it, do not work around it.

*Optional durability check (recommended before step E):* `sudo $K arm 'Omarchy K114s repair r1 (trackpad fix B)' --with-stage2-trial`, reboot, and during Limine's 5 s menu (after it has read and erased the request) hold the power button until off. Then boot **macOS** through Startup Options, which does not run U-Boot or Limine: do **not** boot Linux first, because a Linux boot goes through Limine again and erases the request a second time, which hides the result. In macOS mount the Linux EFI partition read-only (`sudo diskutil mount readOnly <device>`) and test the file: `python3 -c "d=open('/Volumes/EFI/ubootefi.var','rb').read();print('HOLDS' if 'LoaderEntryOneShot'.encode('utf-16-le') in d else 'gone')"`, then `diskutil unmount`. `gone` means the erase survived the power cut; `HOLDS` means it is not durable: in Linux run `sudo $K mark-not-durable` (it writes the sticky `boot-once-not-durable` marker, removes the self-test marker and the arming record; `arm` then refuses every real target, `status` never re-measures, and `clear` leaves the marker alone), then `sudo $K clear`. Do not remove the self-test marker by hand: the next `status` would measure again and write it back. Do not run step E (and use the stuck-request way back if a trial entry was armed). Without this check, step B proves visibility only.

**4. Step C: prepare the kernel trial: end the GPU Stage 2 trial, keep the desktop on the CPU, block every suspend path.**

    sudo cp -p /etc/systemd/user-environment-generators/70-k114s-gpu-desktop /var/lib/k114s-recovery/70-k114s-gpu-desktop.v2-before-r3a
    sudo install -m755 $REPO/linux/r3a-trial/70-k114s-gpu-desktop /etc/systemd/user-environment-generators/70-k114s-gpu-desktop
    sudo install -m644 $REPO/linux/r3a-trial/logind-30-k114s-r3a-trial.conf /etc/systemd/logind.conf.d/30-k114s-r3a-trial.conf
    sudo install -D -m644 $REPO/linux/r3a-trial/sleep-30-k114s-r3a-trial.conf /etc/systemd/sleep.conf.d/30-k114s-r3a-trial.conf
    sudo systemctl kill -s HUP systemd-logind
    systemd-analyze cat-config systemd/logind.conf | grep -E '^HandleLidSwitch'        # lock, lock, ignore
    systemctl is-enabled suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target    # masked x4
    sudo mv /etc/omarchy-k114s/stage2-trial /etc/omarchy-k114s/stage2-trial.parked-r3a     # the re-arm unit now does nothing at shutdown
    sudo sh -c "printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try && sync -f /boot/efi"
    sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-16                              # 45a5dbef19c14898: the proven r1 Stage 2 is what boots next
    sudo $K check                                          # all ok: "no Stage 2 trial is armed", "... configured to re-arm"

Expected on the next boot: no render node, the desktop on the CPU (`Hyprland renders on the CPU (llvmpipe ...)`), because the r1 tree has no GPU node. `~/.config/k114s-gpu-desktop` and `.keep` stay where they are.
Undo of this step: `sudo mv /etc/omarchy-k114s/stage2-trial.parked-r3a /etc/omarchy-k114s/stage2-trial`, `sudo sh -c "printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try"`,
remove the two drop-ins (then `systemctl kill -s HUP systemd-logind`), and `sudo cp -p /var/lib/k114s-recovery/70-k114s-gpu-desktop.v2-before-r3a /etc/systemd/user-environment-generators/70-k114s-gpu-desktop`.

**5. Step D: free the slot and install (this opens the window).**

D0. Backups and facts. Stop if a hash pair differs: the recovery copy is what the undo puts back.

    sudo mkdir -p /var/lib/k114s-recovery && sudo cp -p /boot/efi/limine.conf /var/lib/k114s-recovery/limine.conf.before-r3a
    sudo sh -c 'sha256sum /boot/efi/EFI/Linux/*.efi /var/lib/k114s-recovery/uki/*.efi | cut -c1-16,65-'
    # expect cce616053713ec3b (omarchy_linux-aurora.efi) twice and 51148ff7005d2986 (omarchy_linux-aurora-k114s.efi) twice

D1. Free the slot, and check that the repair entry survived. **Prerequisite: step 1 is complete (the owner confirmed `sudo ./k114s-repair status` with the fixed tool on the Mac) and step B passed (the marker exists).**

    (
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted; go to step Z"; exit 1; }      # the installed guard does not check this
    sudo limine-entry-tool --remove-uki linux-aurora
    sudo $K check                                          # default_entry 1; entry 1 boots the repair image; its hash matches; NO "BAD"
    sudo sha256sum /boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi | cut -c1-16     # 51148ff7005d2986, unchanged
    ls /boot/efi/EFI/Linux                                  # omarchy_linux-aurora-k114s.efi only
    df -B1 --output=avail /boot/efi | tail -1               # about 79 MB more than before: expect > 160,000,000
    )

If `check` prints BAD, the repair image is missing, or its hash changed: **stop and run the undo (step Z)**, which first puts the repair image back from its recovery copy.

D2. Keep `update-m1n1` from rewriting `boot.bin` during the install (it would use r3a's trees and grow the ESP).

    sudo cp -p /etc/default/update-m1n1 /var/lib/k114s-recovery/update-m1n1.before-r3a
    echo 'export M1N1_UPDATE_DISABLED=1' | sudo tee -a /etc/default/update-m1n1 >/dev/null

D3. Install. (The space guard passes only now.)

    (
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted; go to step Z"; exit 1; }      # the installed guard does not check this
    sudo pacman -U $R/linux-k114s-7.3.0.r3a-2-aarch64.pkg.tar.zst
    )

Expected lines: the hold guard and the space guard hooks pass silently; `Updating linux initcpios under /boot (Apple Silicon)...` with a
`mkinitcpio` run for `linux-k114s` ending in `Image generation successful`; `Updating linux initcpios...` (Limine) with
`Building UKI for linux-k114s (7.3.0-17.v272-4-k114s-r3a-ARCH)`; `Updating m1n1 image...` printing nothing (disabled);
`Updating the confined m1n1 Stage 2` printing `update-boot-ctxr-k114s: wrote /boot/efi/m1n1/boot-ctxr.bin (4439xxx bytes, K114s device tree 2ea22d26...)`.
If a Limine step fails, the package is installed without its image: **step Z**.

D4. Restore `update-m1n1` and check what happened, before anything is armed.

    (
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted; go to step Z"; exit 1; }      # the installed guard does not check this
    sudo cp -p /var/lib/k114s-recovery/update-m1n1.before-r3a /etc/default/update-m1n1
    sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-16                               # 45a5dbef19c14898 (unchanged: r1)
    sudo $K entries                                                                         # entry 1 is still the repair entry; a new Omarchy.linux-k114s line
    sudo $K check                                                                           # default_entry 1 and the repair image checks, no BAD
    sudo sha256sum /boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi | cut -c1-16         # 51148ff7005d2986
    ls -l /boot/efi/EFI/Linux/ ; ls /boot/vmlinuz-linux-k114s /boot/initramfs-linux-k114s.img ; ls /usr/lib/modules/   # both release directories
    free=$(df -B1 --output=avail /boot/efi | tail -1); echo $free                           # about 87.6 MB: must be BELOW 88,080,384 (the guard's minimum, see section 5)
    [ "$free" -lt 88080384 ] || { echo "STOP: free space is at or above the guard's minimum; the guard would pass a rebuild-all. Go to step Z"; exit 1; }
    echo "space guard will refuse transactions"
    t=$(mktemp -d); sudo objcopy --dump-section .cmdline=$t/c /boot/efi/EFI/Linux/omarchy_linux-k114s.efi /dev/null 2>/dev/null   # objcopy exits 1 ("file truncated") although the dump is fine
    [ -s $t/c ] || { echo "STOP: no .cmdline section dumped; go to step Z"; exit 1; }
    norm() { tr -d '\0' | tr -s ' \n' '\n' | sed '/^$/d' | sort; }        # the hook's .cmdline ends in a space, a newline and a NUL: drop the empty token
    sudo cat $t/c | norm > $t/embedded
    sudo sh -c "grep -m1 '^  cmdline:' /boot/efi/limine.conf | sed 's/^  cmdline: //'" | norm > $t/entry1
    diff $t/embedded $t/entry1 && echo "UKI embedded command line = entry 1's"             # expect no difference (dry-run on the existing hook-built UKI: 23 tokens, no empty one): same command line, which step A proved
    # the trial boots the new entry's own cmdline: line (systemd-stub prefers the loader's options over .cmdline), so compare that one too
    sudo awk '/^[ \t]*\/\/linux-k114s/ {f=1} f && /^[ \t]*cmdline:/ {sub(/^[ \t]*cmdline:[ \t]*/,""); print; exit}' /boot/efi/limine.conf | norm > $t/new
    diff $t/new $t/entry1 && echo "new entry's cmdline: line = entry 1's"                  # expect no difference
    )

Each block above that starts with the `findmnt` guard is wrapped in a subshell `( ... )`: when a guard fails, `exit 1` ends the subshell, so the rest of the pasted block does not run and the terminal stays open. Variables set inside a block (`free`, `t`) are gone after it. Paste each block whole.

Stop (step Z) if entry 1 is not the repair entry, `default_entry` is not 1, a hash changed, the free space is not below the guard's minimum, or either command line differs from entry 1's in anything but order.

**6. Step E: the r3a kernel, once, on the proven r1 tree.**

    sudo $K arm Omarchy/linux-k114s                         # refuses unless every check above still holds; then saves to U-Boot and proves it
    sudo $K status                                          # efivarfs: LoaderEntryOneShot = Omarchy.linux-k114s ; U-Boot file holds it
    sudo systemctl reboot

If the Mac hangs before the root filesystem or shows nothing: hold the power button until it is off and start it. Nothing is armed any more (Limine erased the request when it read it),
`default_entry` is 1, and the Mac comes up on the repair entry with the proven Stage 2. If it also fails to come up, macOS: `sudo ./k114s-repair stage2 r1` and `sudo ./k114s-repair default repair`
(section 6, "Ways back"; if instead the trial entry keeps booting, section 6, "a stuck request"). To try again, run `arm` again: every trial is one boot.

**7. What the owner looks at.** On the trial boot, with the desktop up:

After the reboot, run the whole block (it stops at its first line if the ESP is not mounted):

    (
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted; go to step Z"; exit 1; }
    uname -r                                          # 7.3.0-17.v272-4-k114s-r3a-ARCH
    sudo $K status                                    # "this boot started: Omarchy.linux-k114s"; no request left
    $REPO/tests/hardware/k114s-r3a-check.sh           # "ok" lines; the 11 CONFIG_ BAD lines must be gone; not the GPU trial, no render node, sleep targets masked
    )

Success criteria for (i): keyboard, trackpad, Wi-Fi, Bluetooth, battery and fans work (the same list as r1); `ufw` active (the IPv6 rules load), `bluetoothd` without RFCOMM errors,
`sysctl net.ipv4.tcp_congestion_control` `bbr`, `systemd-oomd` active; no Oops or WARNING in `sudo dmesg`. Take a picture of the failed-units list (`systemctl --failed`) if anything is red.
Do not suspend. Closing the lid locks the session (drop-in from step C) and nothing more. The next reboot returns to the repair entry by itself.

**8. Step F: (ii) the r3a tree, with the r3a kernel, as a one-boot Stage 2 trial.** Only after step E is clean. First add the `eDP-1` monitor rule (`docs/r3-sleep-lid.md`).

After the reboot, run the whole block (it stops at its first line if the ESP is not mounted):

    (
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted; go to step Z"; exit 1; }
    sudo cp $R/boot-ctxr-r3a.bin /boot/efi/m1n1/boot-ctxr-r3a.bin
    sudo sha256sum /boot/efi/m1n1/boot-ctxr-r3a.bin | cut -c1-64          # 5164bb1e1be1fba3...
    sudo sh -c "printf 'armed\nm1n1/boot-ctxr-r3a.bin\n' > /boot/efi/aura-try && sync -f /boot/efi"
    sudo $K arm Omarchy/linux-k114s --with-stage2-trial || { echo "STOP: the arm failed; go to step Z"; exit 1; }    # only this check is lifted
    sudo systemctl reboot                                   # inside the block: a STOP above never reaches it
    )

`stage2-trial` stays parked, so the trial is one boot: the re-arm unit does nothing. Expected after the boot: `tr -d '\0' < /proc/device-tree/chosen/aurora,trial` prints `m1n1/boot-ctxr-r3a.bin`;
`tests/hardware/k114s-r3a-check.sh --expect-tree r3a` says `device tree is the r3a tree`; the connector is `eDP-1`. A hang needs a forced power-off (hold the power button: the loader's trial watchdog does not arm on this Mac); the next boot then uses the configured proven file. What that boot runs depends on where it hung: if the hang came before Limine ran (m1n1 or U-Boot), the request is still pending, so the next boot is the r3a kernel again, on the proven tree (the step E configuration); if Limine had already read and erased the request, the next boot is the repair entry. Undo: `sudo sh -c "printf 'spent\nm1n1/boot-ctxr-r3a.bin\n' > /boot/efi/aura-try"`; `sudo rm /boot/efi/m1n1/boot-ctxr-r3a.bin`.

**9. Step G: (iii) the r3a kernel on the GPU tree, as its own step.** Only after step F is clean. The kernel is the 0009-only kernel: 0009 enables the receive interrupt beside both pollers, so a line that never fires keeps polling as before and the storm guard is in place, but **this is the first time that interrupt is enabled on this Mac** (r1 had `rx_poll_only`, the interrupt never on).

    (
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted; go to step Z"; exit 1; }
    touch ~/.config/k114s-gpu-desktop-r3a                  # the guard's second opt-in (the first, ~/.config/k114s-gpu-desktop, is already there)
    sudo mv /etc/omarchy-k114s/stage2-trial.parked-r3a /etc/omarchy-k114s/stage2-trial
    sudo sh -c "printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try && sync -f /boot/efi"
    sudo $K arm Omarchy/linux-k114s --with-stage2-trial || { echo "STOP: the arm failed; go to step Z"; exit 1; }
    sudo systemctl reboot
    )

Expected: `aurora,trial` names `boot-ctxr-r3-gpu.bin`; `tests/hardware/k114s-r3a-check.sh --allow-gpu` lists the render node and the mailbox interrupt counts; the desktop is on the GPU as before (`journalctl -b | grep 'renders on'`);
`/var/lib/k114s-recovery/trial-boot-report.log` has the boot. A hang needs a forced power-off (hold the power button); the next boot uses the configured Stage 2 and the repair entry. Because `stage2-trial` is back, the clean shutdown after a good boot
re-arms the GPU trial for the next boot, which returns the Mac to the standing state of today (repair kernel on the GPU tree). Suspend stays forbidden.

**Z. Undo of the whole install (closes the window).** Paste the whole block: it first makes sure the ESP is mounted and stops, having changed nothing, if it cannot be. (`allow-low-esp` does not skip the guard's mount check.)

    (
    findmnt /boot/efi >/dev/null || sudo mount /boot/efi
    findmnt /boot/efi >/dev/null || { echo "STOP: /boot/efi is not mounted and could not be mounted; fix that first, nothing was changed"; exit 1; }
    sudo $K clear
    sudo cp -p /etc/default/update-m1n1 /var/lib/k114s-recovery/update-m1n1.before-undo
    echo 'export M1N1_UPDATE_DISABLED=1' | sudo tee -a /etc/default/update-m1n1 >/dev/null
    sudo touch /etc/omarchy-k114s/allow-low-esp                     # the guard also runs on removal
    sudo pacman -R linux-k114s                                      # removes the UKI, the menu entry, the preset, /boot files
    sudo rm /etc/omarchy-k114s/allow-low-esp
    sudo cp -p /var/lib/k114s-recovery/update-m1n1.before-undo /etc/default/update-m1n1
    sudo cp -p /var/lib/k114s-recovery/uki/omarchy_linux-aurora.efi /boot/efi/EFI/Linux/omarchy_linux-aurora.efi
    # the repair image too, if step D1 (limine-entry-tool) removed or changed it
    h=$(sudo sha256sum /boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi 2>/dev/null | cut -c1-16); [ "$h" = 51148ff7005d2986 ] || sudo cp -p /var/lib/k114s-recovery/uki/omarchy_linux-aurora-k114s.efi /boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi
    sudo sha256sum /boot/efi/EFI/Linux/omarchy_linux-aurora-k114s.efi | cut -c1-16        # 51148ff7005d2986
    sudo cp -p /var/lib/k114s-recovery/limine.conf.before-r3a /boot/efi/limine.conf && sudo sync -f /boot/efi
    sudo sh -c 'sha256sum /boot/efi/EFI/Linux/omarchy_linux-aurora.efi | cut -c1-16; b2sum /boot/efi/EFI/Linux/omarchy_linux-aurora.efi | cut -c1-20'    # cce616053713ec3b ; a3028af4d7d75799ce3f
    sudo $K check ; ls /usr/lib/modules/ ; df -B1 --output=avail /boot/efi | tail -1
    )

The recovery copy is restored byte for byte, and so is the repair image when it was missing or different (not rebuilt, so today's command line is not baked into it), and the pre-install `limine.conf` goes with it, whose `#hash` is that file's. Move the parked Stage 2 trial back (step C undo) if it is still parked and the GPU state is wanted.

Nothing in this runbook touches macOS, Apple's boot policy, Stage 1 or Apple firmware. Entry 1, its UKI, its module directory, the configured Stage 2 file and the pinned tree stay as they are through step G.

## 9. Risks

- **The one-shot is measured, not assumed.** The mechanism is read from Limine's source; nothing yet shows that U-Boot persists a boot-time erase, step B measures it (it can fail), and `arm` refuses a kernel target until it has passed. A hang that loses power before Limine reads the request simply retries the trial once more.
- The slot swap removes the only hook-managed UKI of the known-good image for the length of the window; the recovery copy and `limine.conf.before-r3a` restore it. Entry 1 is the fallback; if entry 1 breaks, macOS is the way back, and only the fixed tool (step 1, a prerequisite of D1) works once the original image is off the ESP.
- **The space guard in this branch also refuses when `/boot/efi` is not a mount point** (with fstab `nofail` a failed ESP mount makes `df` report the root filesystem and the guard pass). `allow-low-esp` overrides only the space check, not the mount check. The guard installed on the Mac today is r2c's and does **not** check this: it reaches the Mac only with the next bundle revision. Until then steps D1, D3, D4 and the first command after each reboot of the window (the first command of steps 7 and 8, after the trial reboots of steps E and F) run the `findmnt /boot/efi` guard, which ends its subshell with `exit 1` when the ESP is not mounted. Step Z starts with a mount check too.
- **During the window the ESP is expected about 0.4 MB under the space guard's minimum (replica UKI sizes) and cannot hold a second 79 MB UKI.** The guard refuses package transactions (correct) only if that estimate holds; D4 therefore measures the real free space and stops (step Z) if it is at or above the minimum. Do not use `allow-low-esp` except in step Z. Unattended updates are not possible while the window is open; the steady state that allows them (one hook-managed kernel directory, or a larger ESP) is the owner's decision.
- `limine-entry-tool` might renumber the menu or not keep `default_entry` on entry 1; steps D1 and D4 check it before any reboot.
- The configuration delta changes first-boot behaviour (`docs/r3-config.md`, risks): `ufw` loads fully, qdisc `fq` and BBR, Tailscale rules, `systemd-oomd`, qemu-user binfmt.
- `sleep-lid/0003` makes suspend possible on a tree that has never suspended. Suspend is blocked three ways during the trial; remove the two drop-ins only after an attended, deliberate suspend test passes (step (ii) onward). The step (ii) tree renames the connector to `eDP-1`: without the drop-in a lid close would lock and suspend even while agents run (`docs/r3-sleep-lid.md`).
- Step G puts the r3a kernel on the GPU tree. Only `sleep-lid/0010`'s change (interrupt receive) is kept out, but 0009 still enables the mailbox receive interrupt, which is new on this Mac (not "as proven"); the rest of the kernel is new on that tree too.
- The packaged `t6050-k114s.dtb` is the kernel tree's preliminary one, not the r3a tree (section 5); nothing boots it unless `use-packaged-dtb` is set, which it must not be.
- Rust modules and the kernel embed the build area's absolute path (including the user name); the package is for this Mac only and must not be published.
- Five upstream author mailboxes are redacted in the sleep-lid patches and three in display-gpu (publish check); authorship names and SHAs are intact.
- The sound variant, the PMP and the speaker path are not in r3a. They need the root-run Apple device tree read first (`docs/r3-sound.md`), and speakers stay without a path.
