# r3c: the K114s kernel on betizzel's v272-18, with the light sensor and NVRAM pieces

Status 2026-11-17: **built, packaged, emulator-tested; not booted on the K114s.** The owner asked to "check all repos
and adopt their code" (intake 2026-11-17, kernel v272-18, lid sleep, camera, deep sleep and the release 9 packages).
r3c is the kernel half of that. Evidence labels: **agent-run**, **emulator/replica**, **upstream-reported**.

## 1. What r3c is

| | r3b.c4 (the default since 2026-11-16) | r3c |
| --- | --- | --- |
| Base | aurora-silicon/linux `a5ebec5f` + betizzel v272-11 (32 patches) | aurora-silicon/linux `677be395b9d2` + betizzel v272-18 (21 patches, `1bc6e1523b`) |
| Ours on top | 18 patches (`patches/linux/r3b-c4.series`) | 21 patches (`patches/linux/r3c.series`): 14 unchanged, 3 re-cut, 4 new |
| Release | `7.3.0-17.v272-11-k114s-r3b-ARCH` | `7.3.0-17.v272-18-k114s-r3c-ARCH` |
| Package | `linux-k114s-r3b 7.3.0.r3b.c4-1` | `linux-k114s 7.3.0.r3c-1`: the r3a slot (r3a retired, owner's decision 2026-11-17) |

What the base brings over v272-11 (upstream-reported, from the commit list): the T6050 suspend-to-RAM stack (compiled
out here, as in betizzel's config: `CONFIG_APPLE_SOC_SLEEP` is off, and it needs a boot object that offers
`/chosen/aurora,s2r-mailbox`), suspend-to-idle work for the N1 link, Type-C, the DCP and the GPU, many G17 GPU fixes, the
AVD SRAM ring wrap fix (long playback) and stream checks, the PMP and ATC usb-aon power domains kept on, the K116s
suspend-to-idle qualification (#1647), HDMI after a system sleep, and betizzel's network options (#19).

### Our patches

| r3b.c4 patch | r3c | Why |
| --- | --- | --- |
| `r3b/0001`-`0004` (trackpad), `sound/0004` (K114 card, speakers off), `brightness/0001`, `0003`, `0005`, `hdr/0001`-`0004`, `sleep-lid/0007`, `sep/0001` | unchanged | apply with `git am --3way` |
| `r3b/0005` (K114s suspend-to-idle) | `r3c/0001`, re-cut | the base now admits the K116s and the J714s in the same test; this adds only `apple,k114s` |
| `brightness/0002` (DCP syslog filter) | `r3c/0002`, re-cut | `dcp.c` gained `link_report_rtkit_ops` between `rtkit_ops` and the helper; the internal panel's `rtkit_ops` takes the filter |
| `brightness/0006` (panel floor) | `r3c/0003`, re-cut | only the `dcp_set_brightness()` hunk moved (the base passes a local `suspended`) |
| `vrr/0001` (`fw27_panel_vrr_min`) | **dropped** | it does not apply, and nothing sets it: panel VRR is blocked here (#19) and betizzel j714s15 stopped turning `fw27_panel_vrr` on |
| (new) | `r3c/0004` | aurora-silicon/linux #1983 (Joshua Warren, open, `242ce586c5`): the light sensor's 193-byte calibration |
| (new) | `r3c/0005`, `0006` | rolotrealanis98/m5pro-linux `contrib/pending/nvram` 0002, 0003 (Rolando Trevino, GPL-2.0-only; sha256 `926c73c7…`, `622ec6e8…` as their README lists): T6050 QSPI NVRAM writes, the J716s row, and the flash ID logged when a write is refused |
| (new) | `r3c/0007` | ours: the K114s row, fail-closed (below) |

## 2. The light sensor (issue #67)

The base's `t6050-die0.dtsi` now has the AOP's `als` child (VD6286), and the sound tree already runs the AOP. On r3b
the driver said "no ALS calibration named in the device tree; the sensor stays off" (agent-run). This Mac's factory
calibration, `apple/aop-als-cal.bin`, is already installed (193 bytes, the vendor firmware extract). The base driver
only takes T8140's 80-byte message; #1983 builds the 216-byte message the 14-inch M5 Max firmware accepts from a
193-byte blob. Its author names the file only in the K114c tree, noting that "the 14-inch M5 Pro" firmware never asks
for the endpoint; whether this Mac's firmware asks is what the trial shows. If it does not, the driver logs a warning
and goes on: the call site is written so that "a failure here costs the sensor, not the AOP" (`drivers/soc/apple/aop.rs`),
so the microphones and the jack are not at stake. `#1929` (the CT817 enable sequence) is not carried: #1983 alone gave
readings on the K114c (upstream-reported).

## 3. The NVRAM read path (issue #64)

`dts/t6050-k114s-nvram.dtsi` (`K114S_R3_NVRAM`) enables the QSPI controller with the boot NOR's `nvram` partition and
the `nvram` alias, copied from rolotrealanis98's J716s node (itself after `t6050-j775d.dts`); the values equal this
Mac's ADT (`/arm-io/qspi/spinor/anvram`: `0x700000`, `0xc0000`, 12 banks of 64 KiB; docs/platform-audit.md). The
partition's `reg` is static, so no loader fill-in is needed. Only the partition is described, so the rest of the NOR
has no device node.

Writes are gated twice: `spi_apple_qspi.read_only` (on by default; root must clear it for one call) and the board row.
`r3c/0007` adds a K114s row with the J716s's GigaDevice ID `0xc88317` **by assumption**: the K114s's flash ID has not
been read. If it differs, the existing JEDEC check refuses every program and erase before WREN, so the first boot can
only read and report the real ID. No block-protect bit is tolerated. The startup-disk tools themselves (one-time
"Restart into macOS once", never the default) come later, after a read-only probe on this Mac.

## 4. The tree

`dts/t6050-k114s-r3c.dts` is the configured AVD tree (`t6050-k114s-r3b-avd.dts`, unchanged) built on the r3c kernel's
includes, plus the calibration name and the NVRAM fragment. Neither touches a pin.

| Check | Result | Label |
| --- | --- | --- |
| The AVD tree on the r3c includes, against the configured tree `ee8ec11a` | differences are the base's only: three new disabled pmgr power states (`dispext1-3_adma`), the ATC usb-aon domains `apple,always-on`, the three display ADMACs' new binding (all three `disabled`), the SoC `ranges` widened to `0x4_0000_0000` | agent-run |
| The r3c tree against the configured tree | the above plus the `flash@0` node and partition, `spi@505118000` okay, the `nvram` alias, `als` `firmware-name` (`tests/dtb-node-diff.py`) | agent-run |
| `lint-dtb.py`, `lint-sound-dtb.py`, `lint-display-gpu-dtb.py` | pass | agent-run |
| `linux/audio/tree-check --root` on the tree unflattened into a replica | "the Stage A tree: jack link only, no amplifier, no speaker channel" (the configured tree gives the same) | emulator/replica |
| The tree | `a92c679a5c55a34442b703a7ff645c1ec169c931e009b30691e318476b030851`, 149,568 bytes | agent-run |
| `build/make-stage2.sh` with the pin loader (control: the AVD tree) | `7fa59a2a…`, the configured `m1n1/boot-ctxr.bin`, byte for byte | agent-run |
| The same with the r3c tree | `boot-ctxr-r3c.bin` `677f04ca04234dacf5e127429abb0e6c55263b55b4f501fcd7d4481e80262ac0`, 4,546,810 bytes | agent-run |

## 5. Build and checks

    # a clone of aurora-silicon/linux
    git checkout -b r3c 677be395b9d2e15d98696107ebf88191f08efbf9
    for p in $RECIPE/patches/j714s-27.2/linux/0*.patch; do git am --3way "$p"; done          # betizzel 1bc6e1523b
    grep -v '^#' patches/linux/r3c.series | grep . | while read p; do git am --3way patches/linux/$p; done
    printf -- '-17.v272-18-k114s-r3c' > localversion.10-pkgrel
    cp $RECIPE/installer/recipes/linux-aurora-j714s/config $O/.config
    scripts/kconfig/merge_config.sh -m -O $O $O/.config patches/linux/config/k114s-r3.config; kmake O=$O olddefconfig
    K114S_LABEL=K114S-R3C kmake O=$O -j18 Image modules dtbs

| Check | Result | Label |
| --- | --- | --- |
| The 21 recipe patches applied one by one, against the recipe's `linux-j714s-27.2.patch` on `677be395` | the same git tree `f401b56bd5db`; the patch and `config` equal the PKGBUILD's `sha256sums` | agent-run |
| The series reproduced from this repository's files onto a fresh base | the built tree, `04f5a8d55db8` | agent-run |
| `build/validate-config.py` (ours) and the recipe's `validate-config.py` | pass: 385 requirements, 0 not met; theirs exit 0 | agent-run |
| Build (clang 23.1.3, Rust 1.98.1) | 295 s; `Image` 54,348,288 bytes, sha256 `37fadebcde044b39577016987c8c1bbaaeb545211dd8d72a66d010c4fa52e6fb`; 1972 modules; no warning in a file the series changes | agent-run |
| `tools/asahi/qspi-nvram-tests.py` with the K114s row | 32 PASS, 0 FAIL | agent-run |
| QEMU `k114s-qemu-smoke shell` | PASS, banner `#1 SMP PREEMPT K114S-R3C` | emulator/replica |
| QEMU, every module (`k114s-qemu-smoke modules`) | `ok=1965 failed=7`, the same seven as every earlier kernel; no Oops, BUG or WARNING | emulator/replica |
| `packaging/linux-k114s/check-package.sh` (with the build's `Module.symvers`) | all passed; it now maps an r3c release to `linux-k114s` | agent-run |

## 6. The trial

A one-boot trial of both halves together: the r3c tree through `m1n1/boot-ctxr-r3c.bin` (aura-try) and the r3c kernel
through a Limine one-shot (`k114s-boot-once arm Omarchy/linux-k114s --with-stage2-trial`). Both are spent by the boot
that takes them, so a hang is followed by the configured Stage 2 on the default entry (r3b). It has to be armed from a
normal boot, and it needs r3c installed first, which retires r3a, so the order is: a plain boot of the proven default,
then the install, then the armed boot. Each reboot has its own acknowledgement. Not yet run.

What the trial must show: the speaker gates; the cards, the microphone, video decode, Touch ID, Wi-Fi, Bluetooth, the
battery and the GPU desktop as on r3b; whether the light sensor reports lux; the NVRAM partition readable and the
flash's real ID. Lid sleep (suspend-to-idle) is a separate, attended step after promotion. The camera and deep sleep
need a new loader (the K114s ISP row of `patches/aura/camera/0001`, aura #214's T6050 sleep controller wake sources)
and are a second trial.
