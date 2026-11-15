# r3a: the integrated K114s kernel candidate, its package and its staged install

Evidence labels: **agent-run** (run on this Mac or its build area), **emulator/replica** (QEMU, fake
trees), **read from source** (code and hooks read, not provoked). Nothing here has run on the K114s
hardware. Nothing built for r3a is installed; every root step is in the runbook at the end.

## 1. What r3a is

| Part | State |
| --- | --- |
| Kernel | the running kernel's source (aurora-silicon/linux `a34d26c2` + betizzel's 19 patches + `pr1568.patch`) plus 21 r3 patches and the r3 configuration delta. Release `7.3.0-17.v272-4-k114s-r3a-ARCH` (the running one is `7.3.0-17.v272-4-ARCH`) |
| Package | `linux-k114s 7.3.0.r3a-1`, installs beside `linux-aurora`, shares no file with it |
| Device tree | `dts/t6050-k114s-r3a.dts`: the proven r1 tree plus the sleep pieces (three properties). Sound is a build variant that needs this Mac's own data (section 4) |
| Stage 2 | `boot-ctxr-r3a.bin` (the r3a tree in the installed Aura loader), tried as a one-boot trial, never first |
| Staging | (i) r3a kernel on the proven r1 tree; (ii) the r3a tree as a one-boot Stage 2 trial; (iii) promotion, only after (ii) is proven |

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
| `display-gpu/0001`, `0002` (#1844, GPU mailboxes by interrupt) | already in `sleep-lid/0009`, `0010`: taken once |
| `display-gpu/0007`, `0008` (#1688, eDP connector) | already in `sleep-lid/0004`, `0005`: taken once |
| `patches/aura/0001`-`0003` (the loader: panel pin table, #226, #230) | a new Stage 2 loader changes the chain that every boot entry uses and has never booted in this form. The installed loader refuses a K114s panel image it does not pin |
| `dts/t6050-k114s-display-gpu.dtsi` and the `r3-edp`, `r3-gpu`, `r3` trees | enable the DCP, the panel and the GPU. The panel hand-off is the one step that can cost the picture (`docs/r3-display-gpu.md`, risks), and the GPU without the panel is the lead's separate standing trial |
| display tools and tests (`tests/lint-display-gpu-dtb.py` and friends) | belong with the trees |

The sleep patches `0008` (PMP domains always on) and `0009`/`0010` (GPU mailbox interrupts) have no
effect in r3a (PMP stays disabled in the shipped tree, no GPU mailbox is bound). They are in the
kernel because the sound variant enables the PMP and r3b enables the GPU, and a kernel without
them makes those unsafe (`docs/r3-sleep-lid.md`).

## 3. Kernel

### Series and order

`patches/linux/r3a.series` lists the patches in the order applied. Summary:

1. base: `a34d26c2` + betizzel's `linux-j714s-27.2.patch` (19 patches). Our build area's `src/base`.
2. `patches/linux/pr1568.patch` with `patch -Np1 --no-backup-if-mismatch` (`git am` refuses it, one hunk
   needs fuzz; this is what the running kernel has). Result: `src/r1`.
3. `localversion.10-pkgrel` with the content `-17.v272-4-k114s-r3a`.
4. `sleep-lid/0001`-`0010`, `display-gpu/0003`-`0006`, `0009`, `0010`, `sound/0001`-`0004`,
   `usb/0001`, by `git am`, no fuzz (agent-run, 21 commits).

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

6 min 13 s. `kernelrelease` `7.3.0-17.v272-4-k114s-r3a-ARCH`, 1972 modules (the running kernel has 1728;
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
names as `linux-aurora`, `t6050-k114s.dtb` built from the r3a kernel tree), plus `usr/share/linux-k114s/config-<release>`.
2,588 entries, 47,439,440 bytes. No symbolic links (the `build` and `source` links are removed).

Checks (agent-run, `check-package.sh`, all pass): one module directory; release ends in `-ARCH` and differs from
linux-aurora's; **no file in common with `pacman -Qlq linux-aurora`** (compared with `bsdtar -t`; only
parent directories overlap); the `vmlinuz` inside the package is the built `Image` byte for byte; all 1972 modules
carry vermagic `7.3.0-17.v272-4-k114s-r3a-ARCH` and `modinfo` reads them with the package's depmod data;
`depmod -a -e` over the package tree reports no error and no unresolved symbol; the kernel banner in `vmlinuz`
names the release.

### What the slot design is

Constraints: the ESP has about 87.7 MB free; a UKI is about 80 MB; entry 1 (static repair UKI, 112 MB)
must stay and needs `/usr/lib/modules/7.3.0-17.v272-4-ARCH` on root.

Chosen: **install `linux-k114s` beside `linux-aurora`, and free the hook-managed slot first by removing
linux-aurora's hook-built UKI and its menu entry (`limine-entry-tool --remove-uki linux-aurora`), not the package.**

- `linux-aurora` stays installed and owned: its modules directory is package-owned, so
  `linux-modules-cleanup.service` leaves it alone; `IgnorePkg`, the K114s hold guard and entry 1 keep working. Wi-Fi
  on entry 1 (`apple_centauri_t6050` loaded after the initramfs) keeps its modules.
- The Limine hook builds the UKI per kernel directory found through `modules.builtin`
  (`pacman -Qqo` gives the package name, so the new UKI is `omarchy_linux-k114s.efi`), by
  `mkinitcpio --kernel <release> --uki ...`, not through the preset. Removing linux-aurora's preset would therefore not stop its UKI. Removing the UKI and the menu
  entry does, and it frees the 79 MB that the new UKI needs. The cost: a hook that rebuilds all kernels
  (a change under `usr/lib/firmware/*`, `usr/lib/initcpio/*`, `usr/lib/modprobe.d/`, `boot/dtbs/*` ...) would rebuild linux-aurora's UKI too,
  which no longer fits. The space guard (below) refuses such a transaction beforehand: after the swap the ESP has less than the
  guard's 84 MiB again, exactly as today. So the steady state is "package transactions need `allow-low-esp`" as it is now.
- Rejected: replacing `linux-aurora` (the hold guard, `IgnorePkg` and entry 1's module directory all depend on that package);
  a companion package owning the old modules directory (a second package that ships the same files as another is a file
  conflict; moving ownership is a change to the proven chain for no gain); a third UKI (does not fit).

### What installing the package triggers (read from the installed hooks; the install is not run)

`sudo pacman -U linux-k114s-7.3.0.r3a-1-aarch64.pkg.tar.zst`

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
r3a package's `t6050-k114s.dtb` is the r3a tree (identical to `154568fe...`), so even a rebuilt `boot.bin`
would carry a K114s tree no worse than before. It does not change what boots.

## 6. Stage 2, staged

The Stage 2 file is shared by every boot entry, so the new tree is a separate file, tried alone:

    m1n1/boot-ctxr.bin           configured, proven r1 tree; never overwritten until (iii)
    m1n1/boot-ctxr-r3a.bin       the r3a tree, 4,439,433 bytes

Built exactly as `update-boot-ctxr-k114s` does (`build/make-stage2.sh`): `/usr/lib/asahi-boot/m1n1.bin` (3,997,696 bytes,
Aura) + exactly one tree + `gzip -c u-boot-nodtb.bin`, with the file name and mtime of the U-Boot file in the gzip header. The same script reproduces
the proven r1 file (`45a5dbef19c1...`) byte for byte, which is the check that the method is right (agent-run).

| File | sha256 |
| --- | --- |
| `boot-ctxr-r3a.bin` | `5164bb1e1be1fba39aee64229863b2f835828edd8b4f90e8cfa91e71a6fd8cd9` |
| prefix (Aura) | `1546dd5079cefe0f9bbdee9d1c95dcdbad39a73ae140612cd6dfab4596c2f7a3` (same as the r1 file's) |
| tree `t6050-k114s-r3a.dtb` | `154568feac3d5c0dc1e1e7f1bb9778c33de29904b49f1813afde4b0bb9b65297` |
| gzip U-Boot tail | `9d8dc11ea755e8405a7380683bd82cfeb7391b1fc68245e56e10bf5155a746ad` |
| `linux-k114s-7.3.0.r3a-1-aarch64.pkg.tar.zst` | `7fe50b9aa061021f282999677ff24301b6ff23951f1c856579c6fdfbec0f377d` |

`build/make-stage2.sh` prints the first four values for any tree; the lead verifies the file by the first row.

### Steps

- **(i) r3a kernel on the proven r1 tree.** Tests the configuration delta (RFCOMM, firewall rules, BBR, PSI, binfmt,
  policy routing, PKCS8) and that the kernel is sound. The sleep, sound and USB changes that need the tree stay off. The kernel does
  contain `sleep-lid/0003`, which admits the K114s to suspend-to-idle: **do not suspend in this step** (the r1 tree
  has no PMP and the owner's test plan in `docs/r3-sleep-lid.md` is for step ii).
- **(ii) the r3a tree**, as a watchdog-protected one-boot Stage 2 trial (`aura-try`, section "Runbook"). The configured file is the
  watchdog's fallback, so a Stage 2 that hangs returns to the proven tree by itself. Needs an `eDP-1` monitor rule first
  (`docs/r3-sleep-lid.md`, the connector is renamed).
- **(iii) promotion**, only after (ii) boots cleanly twice: copy the configured file to
  `/boot/efi/k114s-repair/known-good/boot-ctxr.bin`, then put the r3a file in place and update the pinned tree
  (`/boot/efi/k114s-repair/k114s.dtb` and `/usr/local/lib/omarchy-k114s/k114s.dtb`), otherwise the next run of the Stage 2 hook rebuilds the r1 tree.

### Ways back to the proven Stage 2

- From Linux, during or after a trial: the configured file was never touched. Disarm with `rm /boot/efi/aura-try`
  (or write `spent`), remove `/etc/omarchy-k114s/stage2-trial` if it names the r3a file.
- From macOS: `sudo ./k114s-repair stage2 r1` writes the bundle's r1 Stage 2 file and the pinned tree. The tool accepts a live Stage 2 with
  the same Aura loader and U-Boot tail and any other trees (`same-loader-other-trees`), which the r3a file is, so it works on it
  (read from `macos/tools/k114s_repair.py`; not run). `rollback stage2` restores the pre-repair backup.
- From Linux after promotion: `sudo cp /boot/efi/k114s-repair/known-good/boot-ctxr.bin /boot/efi/m1n1/boot-ctxr.bin`, and put the r1 tree back as the pinned one.
- The kernel side is independent: entry 1 (repair r1) and its module directory are never touched.

## 7. Tests

| Test | Result | Label |
| --- | --- | --- |
| QEMU (TCG), r3a Image, shell | PASS: kernel boots, `uname -r` is the r3a release | emulator/replica |
| QEMU, all 1972 modules from the package tree in an initramfs | `modprobe ok=1965 failed=7`; the same seven as the baseline kernel (tcrypt, ipmi_si, cppc_cpufreq, sun50i-cpufreq-nvmem, stratix10-soc, apple-pmp-j613-hwmon, xen-pciback); no Oops, BUG or panic in the serial log | emulator/replica |
| `depmod -a -e` over the package | clean, no unresolved symbol | agent-run |
| vermagic of every packaged module against the kernel inside `vmlinuz` | 1972 of 1972 equal | agent-run |
| `validate-config.py` | 385 requirements, 0 not met | agent-run |
| `lint-dtb.py`, `lint-sound-dtb.py` | pass | agent-run |
| dtb reproducibility | same hash with dtc 1.8.1 and the kernel's dtc | agent-run |
| Stage 2 reproduction of the proven r1 file | byte for byte | agent-run |
| No file shared with `linux-aurora` | confirmed with `bsdtar -t` against `pacman -Qlq` | agent-run |

**Not verified:** anything on the hardware; the hooks (read, not run); the size of the UKI the hook would
build (estimated from entry 3: the new image is 131,072 bytes larger than the one in entry 3, so about 79 MB); whether
`limine-entry-tool` leaves `default_entry` pointing at entry 1 after adding the entry; the interaction of the standing GPU trial with
a different kernel; the tipd async probe; any of the configuration delta's first-boot behaviours; the PMP (sound) values
on this Mac.

## 8. Runbook (for the lead; root needed)

Files: `$K114S_BUILD_ROOT/integrate/release/` (`SHA256SUMS`, the package, `boot-ctxr-r3a.bin`, `k114s-r3a.dtb`). `R` below is that directory.
The default entry stays "Omarchy K114s repair r1" (entry 1) until r3a is proven, and the owner never has to pick an entry:
the keyboard does not work in the Limine menu, so a trial is one boot as `default_entry`.

**0. Verify and look (no root for the first two).**

    cd R && sha256sum -c SHA256SUMS                       # 3 lines "OK"
    uname -r                                              # 7.3.0-17.v272-4-ARCH
    sudo cat /boot/efi/aura-try /etc/omarchy-k114s/stage2-trial
    tr -d '\0' < /proc/device-tree/chosen/aurora,trial
    sudo grep -n -E '^ *//?[A-Za-z]|^default_entry' /boot/efi/limine.conf     # entry names and their numbers

**1. Decide the Stage 2 of step (i).** This Mac currently starts through a standing trial of `m1n1/boot-ctxr-r3-gpu.bin`
(the GPU tree). The r3a kernel is meant to be tested on the proven r1 tree, one change at a time. To do that, end the standing trial:

    sudo rm -f /etc/omarchy-k114s/stage2-trial
    sudo sh -c "printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try && sync -f /boot/efi"

Expected: nothing printed. Undo: `sudo sh -c "printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try"` and write the two lines `m1n1/boot-ctxr-r3-gpu.bin` and
its sha256 (`9825a103...`) to `/etc/omarchy-k114s/stage2-trial`. (If the lead prefers to test r3a on the GPU tree, skip this step; that combination is untested.)

**2. Back up the menu, then free the slot.** The static entry 1 is the fallback, so the 79 MB UKI of entry 3 can go.

    sudo mkdir -p /var/lib/k114s-recovery && sudo cp -p /boot/efi/limine.conf /var/lib/k114s-recovery/limine.conf.before-r3a
    sudo limine-entry-tool --remove-uki linux-aurora
    df -B1 --output=avail /boot/efi | tail -1             # about 79 MB more than before: expect > 160,000,000

Undo (needs about 80 MB free, so only before step 4 or after step 6's undo):
`echo usr/lib/modules/7.3.0-17.v272-4-ARCH/modules.builtin | sudo /usr/share/libalpm/scripts/limine-mkinitcpio-install`, then
compare `limine.conf` with the backup.

**3. Keep `update-m1n1` from rewriting `boot.bin` during the install (it would use r3a's trees and grow the ESP).**

    sudo cp -p /etc/default/update-m1n1 /var/lib/k114s-recovery/update-m1n1.before-r3a
    echo 'export M1N1_UPDATE_DISABLED=1' | sudo tee -a /etc/default/update-m1n1 >/dev/null

**4. Install.** (The space guard passes only after step 2.)

    sudo pacman -U R/linux-k114s-7.3.0.r3a-1-aarch64.pkg.tar.zst

Expected lines: the hold guard and space guard hooks pass silently; `Updating linux initcpios under /boot (Apple Silicon)...` with a
`mkinitcpio` run for `linux-k114s` ending in `Image generation successful`; `Updating linux initcpios...` (Limine) with
`Building UKI for linux-k114s (7.3.0-17.v272-4-k114s-r3a-ARCH)`; `Updating m1n1 image...` printing nothing (disabled);
`Updating the confined m1n1 Stage 2` printing `update-boot-ctxr-k114s: wrote /boot/efi/m1n1/boot-ctxr.bin (4439xxx bytes, K114s device tree 2ea22d26...)`.
If a Limine step fails, the package is installed without its image: do the undo below.

**5. Restore `update-m1n1` and check what happened.**

    sudo cp -p /var/lib/k114s-recovery/update-m1n1.before-r3a /etc/default/update-m1n1
    sudo sha256sum /boot/efi/m1n1/boot-ctxr.bin | cut -c1-16        # 45a5dbef19c14898 (unchanged: r1)
    ls -l /boot/efi/EFI/Linux/                                      # omarchy_linux-aurora-k114s.efi (112 MB, static) and omarchy_linux-k114s.efi (~79 MB)
    ls /boot/vmlinuz-linux-k114s /boot/initramfs-linux-k114s.img
    sudo grep -n -E '^ *//?[A-Za-z]|^default_entry' /boot/efi/limine.conf
    df -B1 --output=avail /boot/efi | tail -1

Expected: the Stage 2 file is the proven one; two UKIs; `default_entry: 1` still names "Omarchy K114s repair r1"; if the entry numbers moved
(the new entry sits above the repair entry), set `default_entry` back to the repair entry's number before any reboot.
Entry 1's own module directory is still there: `ls /usr/lib/modules/` shows both release directories.

**6. Boot the trial once.** Make the new entry the default for ONE boot (use the unit already installed) and reboot:

    N=<number of the "linux-k114s" entry from step 5>
    sudo touch /etc/omarchy-k114s/trial-default
    sudo sed -i "s/^default_entry: .*/default_entry: $N/" /boot/efi/limine.conf && sudo sync -f /boot/efi
    sudo systemctl reboot

`k114s-trial-default-revert` puts `default_entry` back to 1 as soon as the trial boot reaches the root filesystem. If the boot
hangs, force power off: the next boot uses entry 1. If entry 1 also fails, from macOS: `sudo ./k114s-repair default 1`.

**7. What the owner looks at.** On the trial boot, with the desktop up:

    tests/hardware/k114s-r3a-check.sh                 # all "ok", "BAD" lines for the 11 CONFIG_ options must be gone
    cat /var/lib/k114s-recovery/trial-default.log     # shows LimineLastBootedEntry and that default_entry went back to 1

Success criteria for (i): `uname -r` is `7.3.0-17.v272-4-k114s-r3a-ARCH`; keyboard, trackpad, Wi-Fi, Bluetooth, battery and fans work (the same
list as r1); `ufw` active (the IPv6 rules load), `bluetoothd` without RFCOMM errors, `sysctl net.ipv4.tcp_congestion_control` `bbr`,
`systemd-oomd` active; no Oops or WARNING in `sudo dmesg`. Take a picture of the failed-units list (`systemctl --failed`) if anything is red.
Do not suspend in this step.

**8. Step (ii): the r3a tree as a one-boot Stage 2 trial.** Only after (i) is clean. First add the `eDP-1` monitor rule (`docs/r3-sleep-lid.md`).

    sudo cp R/boot-ctxr-r3a.bin /boot/efi/m1n1/boot-ctxr-r3a.bin
    sudo sha256sum /boot/efi/m1n1/boot-ctxr-r3a.bin | cut -c1-64          # 5164bb1e1be1fba3...
    sudo sh -c "printf 'armed\nm1n1/boot-ctxr-r3a.bin\n' > /boot/efi/aura-try && sync -f /boot/efi"
    # keep the k114s entry as the one-boot default as in step 6, then reboot

Expected after the boot: `tr -d '\0' < /proc/device-tree/chosen/aurora,trial` prints `m1n1/boot-ctxr-r3a.bin`;
`tests/hardware/k114s-r3a-check.sh --expect-tree r3a` says `device tree is the r3a tree`; the connector is `eDP-1`. A hang resets, within
the loader's watchdog (178 s), onto the configured proven file. Undo: `sudo sh -c "printf 'spent\nm1n1/boot-ctxr-r3a.bin\n' > /boot/efi/aura-try"`; `sudo rm /boot/efi/m1n1/boot-ctxr-r3a.bin`.

**Undo of the whole install.**

    sudo touch /etc/omarchy-k114s/allow-low-esp                     # the guard also runs on removal
    sudo pacman -R linux-k114s                                      # removes the UKI, the menu entry, the preset, /boot files
    sudo rm /etc/omarchy-k114s/allow-low-esp
    echo usr/lib/modules/7.3.0-17.v272-4-ARCH/modules.builtin | sudo /usr/share/libalpm/scripts/limine-mkinitcpio-install   # entry 3 back
    sudo sed -i 's/^default_entry: .*/default_entry: 1/' /boot/efi/limine.conf

Nothing in this runbook touches macOS, Apple's boot policy, Stage 1 or Apple firmware. Entry 1, its UKI, its module directory,
the configured Stage 2 file and the pinned tree stay as they are through step 8.

## 9. Risks

- The slot swap removes the only hook-managed UKI of the known-good image. Entry 1 is the fallback; if entry 1 breaks, macOS is the way back.
- After the swap the ESP is back at about the guard's limit: any later package transaction needs `allow-low-esp`, and a transaction that rebuilds all kernels would try to rebuild linux-aurora's UKI as well.
- `limine-entry-tool` might renumber the menu or not keep `default_entry` on entry 1; step 5 checks it before a reboot.
- The configuration delta changes first-boot behaviour (`docs/r3-config.md`, risks): `ufw` loads fully, qdisc `fq` and BBR, Tailscale rules, `systemd-oomd`, qemu-user binfmt.
- `sleep-lid/0003` makes suspend possible on a tree that has never suspended: a suspend that never wakes needs a forced power-off.
- The step (ii) tree renames the connector to `eDP-1`: a lid close then locks and suspends even while agents run (`docs/r3-sleep-lid.md`).
- Rust modules and the kernel embed the build area's absolute path (including the user name); the package is for this Mac only and must not be published.
- Five upstream author mailboxes are redacted in the sleep-lid patches and three in display-gpu (publish check); authorship names and SHAs are intact.
- The sound variant, the PMP and the speaker path are not in r3a. They need the root-run Apple device tree read first (`docs/r3-sound.md`), and speakers stay without a path.
