# r3c: the K114s kernel on betizzel's v272-18, with the light sensor and NVRAM pieces

**r3c and its Stage 2 (`677f04ca…`) are the verified default on the K114s.** Both the one-boot trial and
the first normal boot passed (section 6). The light sensor reports lux. The trial found the NVRAM partition and its
flash ID, and the first normal boot read the full partition. The owner asked to "check all repos and adopt their code" (intake 2026-11-17:
kernel v272-18, lid sleep, camera, deep sleep and the release 9 packages). r3c is the kernel half of that. Evidence
labels: **agent-run**, **owner-observed**, **emulator/replica**, **upstream-reported**.

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
| (new) | `r3c/0004` | Joshua Warren's 193-byte light-sensor calibration change (`242ce586c5`). [aurora-silicon/linux #1983](https://github.com/aurora-silicon/linux/pull/1983) merged into `integration/aurora` on 2026-11-20 at `8fd2d5e8b402`. |
| (new) | `r3c/0005`, `0006` | rolotrealanis98/m5pro-linux `contrib/pending/nvram` 0002, 0003 (Rolando Trevino, GPL-2.0-only; sha256 `926c73c7…`, `622ec6e8…` as their README lists): T6050 QSPI NVRAM writes, the J716s row, and the flash ID logged when a write is refused |
| (new) | `r3c/0007` | ours: the K114s row, fail-closed (below) |

## 2. The light sensor (issue #67)

The base's `t6050-die0.dtsi` now has the AOP's `als` child (VD6286), and the sound tree already runs the AOP. On r3b
the driver said "no ALS calibration named in the device tree; the sensor stays off" (agent-run). This Mac's factory
calibration, `apple/aop-als-cal.bin`, is already installed (193 bytes, the vendor firmware extract). The base driver
only takes T8140's 80-byte message. The #1983 driver change builds a 216-byte message from the 193-byte blob.
The merged PR names `apple/aop-als-cal.bin` on the shared `aop_als` node in `t6050-die0.dtsi`, so both K114
and both K116 trees inherit it. The r3c tree supplies the same value through its K114s override.
`setup_als_calibration()` checks for the ALS endpoint (0x21) before looking up the file. The r3b.c4 log
printed "no ALS calibration named in the device tree", confirming the K114s firmware announced the endpoint
(agent-run). The following outcomes come from `setup_als_calibration()` in `drivers/soc/apple/aop.rs` on r3c.
[Merged device-tree change](https://github.com/aurora-silicon/linux/commit/64a0eccc0514962d6f8230654ec8f32eb261e411).

| Outcome | Kernel log | Sensor |
| --- | --- | --- |
| The firmware never announces the ALS endpoint | nothing | no calibration sent |
| No `firmware-name` in the tree (r3b.c4 here) | "no ALS calibration named in the device tree; the sensor stays off" | off |
| The file is missing | `ALS calibration "apple/aop-als-cal.bin" not available (...); the sensor stays off` (warning) | off |
| The file is not a valid calibration: neither 193 bytes nor an 80-byte message with T8140's operation code and body length (`als_calibration_message()`; an 80-byte file with a wrong header is refused the same way) | "ALS calibration ... is neither an 80-byte calibration message nor a 193-byte sensor blob", then "ALS calibration failed (EINVAL)" | off |
| The firmware refuses it | "ALS calibration rejected (status ...)", then "ALS calibration failed (EIO)" | off |
| Accepted | nothing | reports lux |

None of these stops the AOP: the call site goes on to its other services (`aop.rs`, "a failure here costs the
sensor, not the AOP"), so the microphones and the jack are not at stake. `owner-session-r3c/r3c-check.sh` prints
the boot-log lines containing "ALS calibration". `#1929` (the CT817 enable
sequence) is not carried: #1983 alone gave readings on the K114c (upstream-reported).

## 3. The NVRAM read path (issue #64)

`dts/t6050-k114s-nvram.dtsi` (`K114S_R3_NVRAM`) enables the QSPI controller with the boot NOR's `nvram` partition and
the `nvram` alias, copied from rolotrealanis98's J716s node (itself after `t6050-j775d.dts`); the values equal this
Mac's ADT (`/arm-io/qspi/spinor/anvram`: `0x700000`, `0xc0000`, 12 banks of 64 KiB; docs/platform-audit.md). The
partition's `reg` is static, so no loader fill-in is needed. Only the partition is described, so the rest of the NOR
has no device node.

Writes are gated twice: `spi_apple_qspi.read_only` (on by default; root must clear it for one call) and the board row.
`r3c/0007` adds a K114s row with the J716s's GigaDevice ID `0xc88317`. When the row was written, this was an
assumption: the K114s's flash ID had not been read. Had it differed, the existing JEDEC check would have refused every
program and erase before WREN. The trial boot read the real ID (`/sys/bus/spi/devices/spi1.0/spi-nor/jedec_id` is
`c88317c88317`, agent-run 2026-11-17), which matches the row. The write gate also rejects any block-protect bit. The remaining test is to parse
the boot variables read-only before trying a one-time restart into macOS.

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
| `packaging/linux-k114s/check-package.sh` (with the build's `Module.symvers`) | all passed. It maps an r3c release to `linux-k114s`, and r3c versions get the same binary checks as r3b.c4 (the brightness floor, the Display P3 default, the 500-nit EDR cap, the unknown-SDR EDR guard, the SEP admission) except the dropped VRR minimum, plus the K114s NVRAM row and the 193-byte calibration message | agent-run |

## 6. The trial

A one-boot trial of both halves together: the r3c tree through `m1n1/boot-ctxr-r3c.bin` (aura-try) and the r3c kernel
through a Limine one-shot (`k114s-boot-once arm Omarchy/linux-k114s --with-stage2-trial`). Both are spent by the boot
that takes them, so a hang is followed by the configured Stage 2 on the default entry (r3b). It has to be armed from a
normal boot, and it needs r3c installed first, which retires r3a, so the order is: a plain boot of the proven default,
then the install, then the armed boot. Each reboot has its own acknowledgement.

What the trial had to show: the speaker gates; the cards, the microphone, video decode, Touch ID, Wi-Fi, Bluetooth, the
battery and the GPU desktop as on r3b; whether the light sensor reports lux; the NVRAM partition present and the
flash's real ID (a full read of the partition was left to the first normal boot). Lid sleep (suspend-to-idle) is a separate, attended step after promotion. The camera and deep sleep
need a new loader (the K114s ISP row of `patches/aura/camera/0001`, aura #214's T6050 sleep controller wake sources)
and are a second trial.

### Results (2026-11-17)

The plain boot of r3b came up at 17:41Z on the AVD Stage 2's normal path. r3c was installed in the r3a slot, and the
trial was armed from that boot. The trial boot's kernel started at 18:05:54Z.

| Check | Result | Label |
| --- | --- | --- |
| The trial took both halves | `/chosen/aurora,trial` = `m1n1/boot-ctxr-r3c.bin`; kernel `7.3.0-17.v272-18-k114s-r3c-ARCH`, `#1 SMP PREEMPT K114S-R3C`; the Limine one-shot was consumed and `aura-try` reads spent | agent-run |
| Speaker gates | tree-check, the `/sound` compatible `apple,k114-macaudio`, `speaker-readiness` exit 0, no amplifier I2C address; cards `AppleK114` and `AppleK114HPAI` | agent-run |
| Kernel log | no error-like line that the r3b boot did not have; 0 Oops, BUG, trace or WARNING lines | agent-run |
| Light sensor | `aop-sensors-als` `in_illuminance_input` 2502, 2504, 2508 lux over 3 s; 4928 later in the same boot, as the room light changed. No "ALS calibration" line: the firmware asked (r3b.c4 printed its line) and accepted the 193-byte blob (section 2) | agent-run |
| NVRAM | `mtd1: 000c0000 00001000 "nvram"`; flash ID `c88317c88317`, the row's `0xc88317`; `spi_apple_qspi.read_only` = `Y`. Nothing was written | agent-run |
| Video decode | H.264, HEVC and VP9 at 1920x1080: hardware frames equal software (md5), with `LIBVA_DRIVER_NAME` set to `asahi`, to `v4l2_request`, and unset; `/dev/video10`, `/dev/media0` | agent-run |
| Touch ID, microphone, Wi-Fi, Bluetooth, battery, GPU | the sensor node and `aurora-sep` active; the default input records live audio; `wlan0` up; Bluetooth powered; battery capacity read, 0 `manufacture_year` lines; Hyprland on `renderD128` | agent-run |
| P9 | holds | agent-run |

**Promoted** at 19:49Z, with the owner's go-ahead in T3. `r3c-promote.sh` ran from the trial boot:
- both pinned trees are the r3c tree (`a92c679a…`);
- `update-boot-ctxr` wrote `m1n1/boot-ctxr.bin` = `677f04ca…`, the trial file byte for byte;
- `default_entry` is `Omarchy/linux-k114s`;
- the trial copy is off the ESP.

At that promotion, r3b.c4 stayed in the menu as the way back, and P9 began pinning the r3c files (owner-approved).
The two-slot rollout on 2026-11-18 later reused that slot for the r3c upstream build; section 7 gives the current
default and fallback.

### First normal boot

The owner updated and rebooted successfully on November 17 local time (00:12:35 UTC on November 18). The running
kernel was r3c, the one-boot marker was absent, and P9 confirmed the configured Stage 2, both pinned trees and the
Limine default. The live device tree still exposes no amplifier or speaker channel. The IIO sensor reported
1,446 lux. All 786,432 bytes of the named NVRAM partition read through the read-only MTD device, and the driver
write gate stayed closed (`read_only=Y`). The MTD index differed from the trial, so identify the partition by name.

Sleep at that boot: r3c admits the K114s for suspend-to-idle (`r3c/0001`), and `suspend.target`, `hibernate.target`,
`hybrid-sleep.target` and `suspend-then-hibernate.target` stay masked until the attended procedure.

On 2026-11-18 UTC, the owner covered and uncovered the light sensor on the normal r3c boot while the agent
sampled `aop-sensors-als`. Median illuminance was 0.64 lux before covering, 0.00 lux while covered and
0.64 lux after uncovering (105 samples). Lid angle remains unverified. The K114s ADT has no `las` node.
[#67 cover-test evidence](https://github.com/chrisohearn/omarchy-m5p-oled/issues/67#issuecomment-6966175366).

Still open:
- lid sleep, twice, on battery only, with the owner attending (the targets are unmasked only for it);
- Bluetooth audio with the paired AirPods (#41);
- the camera and deep-sleep trial.

## 7. Upstream recovery backports

The follow-up series in [`patches/linux/r3c-upstream.series`](../patches/linux/r3c-upstream.series)
applies after `r3c.series`, on the same v272-18 base and config. It covers two merged Aurora Linux fixes:

- The N1 backport adds ownership tracking and recovery when firmware-managed suspend fails. The recovery
  worker can recreate the PCI functions and register Wi-Fi and Bluetooth again. Bluetooth headset audio still
  needs SCO transport. [Aurora Linux #2113](https://github.com/aurora-silicon/linux/pull/2113)
- [#2117](https://github.com/aurora-silicon/linux/pull/2117) waits for backlight policy before restoring the panel
  level. The normal r3c boot on this K114s logged one premature backlight restore warning.

For a build that can be distinguished from the installed r3c kernel, apply the follow-up patches and use a
separate output directory:

```sh
while IFS= read -r patch; do
    case "$patch" in ''|'#'*) continue ;; esac
    git am --3way "$K114S_REPO/patches/linux/$patch"
done < "$K114S_REPO/patches/linux/r3c-upstream.series"
printf '%s\n' '-17.v272-18-k114s-r3c-upstream' > localversion.10-pkgrel
mkdir -p "$O"
cp "$R3C_OBJ/.config" "$O/.config"
export KBUILD_BUILD_TIMESTAMP="$(date -Ru)"
kmake O="$O" olddefconfig
kmake O="$O" Image modules dtbs
```

The kernel tree after applying the three patches is `c7cb77152d8d4c886b5fc19e3588da2bf8f36c9e`.

The archived series reconstructs the same kernel tree. The candidate config is byte-identical to r3c and
passes all 385 requirements. The four upstream Centauri and backlight host fixtures pass with GCC and Clang,
and the unchanged NVRAM safety suite passes all 32 checks. The Image, all 1,972 modules and DTBs build.
The Image SHA-256 is `cc66c35d70d020ac4a4f28d2db82ce443f33d28e834a677b1372386eb0947622`.

QEMU boots `7.3.0-17.v272-18-k114s-r3c-upstream-ARCH` to userspace. Its module sweep loads 1,965 modules and
reports the same seven failures as the original r3c baseline.

### K114s boot evidence

On 2026-11-18 UTC, this Image passed two Limine one-shot trials and a normal boot as the default.
All three boots used the configured r3c Stage 2 and passed P9 and the speaker gate. The panel ran
at 120 Hz, and backlight restore logged no errors. Wi-Fi connected, Bluetooth powered on,
and the ambient light sensor reported lux. PipeWire streamed from the built-in microphone.
The AVD hardware decode test matched software frames at 1080p for H.264, HEVC, and VP9.

The new default entry is `Omarchy/linux-k114s-r3b`. The original r3c image remains selectable as
`Omarchy/linux-k114s`. Both images matched their recorded hashes after the default boot.

### Firmware sleep proof

The Centauri refusal recovery requires a firmware-managed suspend and the PCI root port property
`apple,function-warm-reset`. The K114s tree lacks that property, and this build has
`CONFIG_APPLE_SOC_SLEEP` disabled. Host fixtures cover the recovery worker. An attended
suspend-to-idle cycle would check radio continuity. A hardware test of refusal recovery requires
both a supported firmware-managed sleep path and the root port property. The J716c deep-sleep
correction belongs to the newer sleep series. [Aurora Linux #2177](https://github.com/aurora-silicon/linux/pull/2177)
