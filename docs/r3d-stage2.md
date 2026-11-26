# r3d Stage 2: the K114s tree on the r3d includes, and Aura b15

**In use on 2026-11-26.** The live ESP has Stage 2 `3e46007a`, using the self-built
Aura `v1.0.0b15` loader with the K114s camera row (`06b38fd0`) and the camera tree
`b7efcc0d`. The camera tree builds on `a0897a5a` with the video encoder and its
DARTs still disabled ([camera promotion](r3-camera.md)). The loader override is
`/usr/lib/asahi-boot/m1n1-ctxr.bin`. The local pacman hook flags new Aura packages
while the override stands.

**2026-11-24 trial record.** Test A booted once and was not promoted. Test A4
(Aura b13 and tree `a0897a5a`) passed and was promoted at 05:47Z as Stage 2
`bd329c9f`. Test B4 (self-built Aura b15 loader `788277b6` and the same tree)
passed and was promoted at 05:56Z as `6b984811`. An ordinary boot at 05:58Z
confirmed loader `1.0.0b15`. These were the loader and tree trials for the
[r3d kernel](r3d-kernel.md).

## 1. Test A tree

The Test A revision of `dts/t6050-k114s-r3d.dts` started from the configured r3c tree
(`t6050-k114s-r3c.dts`). It added two board values required by r3d’s shared `t6050-k114-k116.dtsi`:
- `T6050_K_N1_FIRMWARE`: `"apple/centauri/k114s-ftab.bin"`;
- `T6050_K_BOARD_ID`: `0x14`.

The values came from r3d’s own `t6050-k114s.dts`. The wrapper also enabled:
- `T6050_ANE`, defined before `t6050-peripherals.dtsi` is included: the Neural Engine (#2293);
- `t6050-media.dtsi`: the video encoder, ProRes and both JPEG engines (#2278);
- `t6050-isp.dtsi`: the shared camera tree (#2275).

In the Test A tree, `neural-processor@508000000`, `video-encoder@2283100000`, `prores@48d000000` and the two `jpeg` nodes
were `okay`. The camera's `isp@580000000` and its DARTs stayed `disabled` pending loader hand-off and the K114s activity-light description (#231).
USB-C (`t6050-k114-k116-usb.dtsi`) and the GPU used this repository’s fragments. The USB-C lint passed.

The build used `build/build-r3a-dtb.sh <r3d kernel tree> t6050-k114s-r3d <out>` with PMP tunables in
`K114S_PMP_TUNABLES` (sha256 `df27244e4900…`). The result was `26c3407f8793e3e11adcc0642f5bb2d35c3882dd50772d557b7c817631929d70`,
153,819 bytes (agent-run). Without the three engine and camera enables it was `a3e27280…`, which the first review caught (P1).

The node diff (`tests/dtb-node-diff.py`) against the pre-trial blob `8258c8a8…` found 12 added nodes
and zero removed (agent-run).
- **Added:**
  - `memory-controller@2220000000` (`apple,t6050-mcc`, with `apple,boot-dma-devices = <&dcp>`). The r3d kernel has
    `CONFIG_APPLE_MCC=y`, so its driver probes on the K114s for the first time. It waits for the display coprocessor to
    retire the boot scanout, then enables system-level-cache allocation on each of its 16 windows. Those windows sit
    inside this Mac's four enabled memory controllers: the ADT `/arm-io/mcc` has `amcc-count` 8, `amcc-enable-mask`
    `0xf` and `dcs-count-per-amcc` 4, and translates amcc0-3 to `0x22_2000_0000`, `0x22_2200_0000`, `0x22_2400_0000`
    and `0x22_2600_0000`, `0x140000` each (agent-run, read from the ADT MTD).
  - The Neural Engine's firmware reservations `reserved-memory/ane-firmware-text@0` and `ane-firmware-data@0` (`reg 0`,
    disabled; the loader fills them in), the ISP sensor preset, and further PMGR power controllers.
- **Status changes:**
  - `disabled` -> `okay` on the Neural Engine, the video encoder at `0x2283100000`, ProRes, both JPEG engines, their
    DARTs, and about 15 PMGR power domains. These include `fab9-soc` (`@398`, which loses its power-domains parent and
    becomes `firmware-owned` and `no-auto-pm`) and `isp-sys` (`@3a0`, now `apple,always-on`). So the camera node stays
    `disabled` while part of its power tree is on.
  - The four MTP nodes are disabled and then re-enabled, so they end up as before.
- **Other:** the ISP node's `reg`, `interrupts` and `reg-names` change and its `clocks` go. The ISP DARTs gain
  `remap-streams`. `/chosen/framebuffer@0` gets `display = <&dcp>`, and the DARTs get `reg-names`.
- **Unchanged:** PCIe port 0 and the N1, the exposed pins, the USB-C ports, the PMP, the AOP and the sound node.

Test A exercised the MCC, five engines and their power domains. The check covered a clean MCC enable,
new error-priority kernel messages and each engine’s binding.

| Check | Result | Label |
| --- | --- | --- |
| `lint-dtb.py`, `lint-sound-dtb.py`, `lint-display-gpu-dtb.py`, `lint-usb-dtb.py` | pass on `26c3407f` (also on `8258c8a8`) | agent-run |
| `linux/audio/tree-check --root` on an unflattened replica | "the Stage A tree: jack link only, no amplifier, no speaker channel" | agent-run |
| `t6050-aop.dtsi` (it would enable the AOP's speaker DMA) | not in the include list | agent-run |

The pre-trial tree `8258c8a8` differed from the rebuild using its recorded inputs. The diff used the original blob.

## 2. Pre-trial loader and b15 build

The pre-trial Stage 2 `d1254de6` was Aura `1.0.0b13` (omacom/m1n1 `703a0a92`, the omacom package) plus `8258c8a8` plus
the U-Boot trailer. The byte-identical rebuild confirmed the `build/make-stage2.sh` layout.

Aura `v1.0.0b15` (aurora-silicon/aura, tagged 2026-11-22) was built from the tag with the package's flags:
`make RELEASE=1 CHAINLOADING=1 ESP_STAGE2=1 USE_CLANG=1`, rust 1.99.0, the Omarchy logos. The result was `788277b6…`,
3,932,160 bytes (agent-run). Building b13 with the same recipe produced a file about 202 KB different from the omacom package,
most likely because of the compiler.

The b15 build included these changes:
- **#399:** usb-drd defaults for every ATC port (inferred).
- PCIe root-port and AOP firmware handling, firmware-27 DCP clocks on the legacy path, and fail-closed T6050 bandwidth
  blocks (inferred).
- The speaker-safety node of #328 is already in b13 (agent-run, by strings).
- Aura's b15 qualification lists no T6050 Mac. Main, which has the live-DCP hand-off that stops the boot hard, was not
  built.

## 3. Original A and B test plan

The original plan paired two one-boot tests against the same tree to isolate the loader change. Only Test A ran
with this tree. A4 and B4 used the revised tree (section 4).

| Test | Stage 2 | sha256 |
| --- | --- | --- |
| A | b13 (installed) + tree `26c3407f` | `d9aab35c6d7a25755b8d39ceb5f80ce3fbae02ecbb595b06b2024fa75b36459d` |
| B | b15 + tree `26c3407f` | `1ac3c9315cad838889dc0886b986a6f002878b759b0924c3c4fada657ab8cfb7` |

- **Boot method.** The plan called for arming each trial file once with `aura-try`. After a hang, the next power-on
  would use the configured Stage 2. Test A fell back to `d1254de6`. The Test B kit would pin the fallback at arming,
  either `d9aab35c` if Test A was promoted or `d1254de6`. The trial watchdog did not arm on this Mac, so recovery
  from a hang required holding the power button.
- **Planned checks:** the r3d checks: the speaker gate and both cards, P9, kernel health, the 120 Hz 10-bit panel, the
  GPU, the light sensor, the NVRAM read path, the SEP, the microphone, network, Bluetooth, the battery and bit-exact
  decode. Test A also checked:
  - the MCC: its node in the booted tree, its line "system level cache allocation enabled on N planes", and none of
    its failure or warning lines;
  - no error-priority kernel line that the previous boot did not have, which catches an engine that fails to probe;
  - the Apple MTP keyboard and multi-touch.

  The check recorded driver bindings for the Neural Engine, encoder, ProRes and both JPEG engines. The ISP
  was expected to stay unbound because its node was disabled.
- **Promotion plan:** promote both pinned trees from the passing test and the loader from Test B.
  The promote script was to verify that `update-boot-ctxr`'s own recipe (loader + tree + `boot.bin`'s
  U-Boot trailer) gives the tested file. It would then require the written Stage 2 to be that file byte for byte. On failure or
  interruption, the script would restore the trees, Stage 2 and P9.
- **Repair-tool prerequisite for Test B.** At the time, the macOS repair tool recognised the r2c bundle’s installed
  loader (3,997,696 bytes) and the pin loader (4,063,232 bytes). Test A kept the pre-trial Stage 2’s Aura b13
  prefix (3,932,160 bytes), which the tool did not recognise. Test B would add another unknown prefix, so the
  plan required adding both the new loader and the U-Boot trailer to the repair tool before promotion (#234).

## 4. Test A result, and the encoder (2026-11-24)

Test A (`d9aab35c`, tree `26c3407f`) booted once through `aura-try` at 04:29Z (agent-run, record
`owner-session-s2a/trial.20261124T042950.OFCJ`). Results:
- **Passed:**
  - the r3d checks: the speaker gate and both cards, P9, 0 Oops/WARNING lines, 120 Hz 10-bit, the GPU, the light
    sensor, NVRAM read-only, the SEP, the microphone, network, Bluetooth, the battery and bit-exact decode;
  - the Apple MTP keyboard and multi-touch;
  - the MCC: "system level cache allocation enabled on 16 planes", and none of its failure lines;
  - the engines: the Neural Engine bound to `ane_t6021`, ProRes to `apple-prores`, and both JPEG engines to
    `apple-jpeg`.
- **Failed:** the video encoder. `apple-ave 2283100000.video-encoder: error -ENODEV: unsupported firmware (text CRC
  1e27a926)`. After the failed probe, the five VENC0 power states stay `sync_state() pending`, which holds them on.
  Test A was not promoted.

`dts/t6050-k114s-r3d.dts` now disables the encoder and its two DARTs. The six VENC0 power states stay described and
enabled, so genpd finds them unused and powers them down at boot. Disabling them as well would leave nothing to turn
them off, which the review of PR #237 caught (P1). `FAB0_SOC` stays on for the JPEG engines.

| | Tree | Test file |
| --- | --- | --- |
| Test A4: b13 loader (installed) + the tree | `a0897a5a0b31de4c5300d74367a3747354febc9b4aca26edd2b0f98d3ff6fc30` (153,831 bytes) | `bd329c9fa8efffbc677b30c3202b439d85d5446caef5a01e43b989cfa4497aa5` |
| Test B4: Aura b15 + the same tree | same | `6b9848118206371b050f2b606181f1776cf904432a01ca8a04c58c9350ec68b3` |

These were the retry builds after Test A. The four lints pass, and `tree-check` gives jack only, no amplifier and
no speaker channel (agent-run).

What A4 must pass is section 3's list, without the encoder. The engines that must bind are the Neural Engine,
ProRes and both JPEG engines; the encoder and the ISP must stay unbound. A4 also checks that no new error-priority
kernel line appears. Test B4 falls back to whatever Stage 2 is configured when it is armed: A4's file if A4 was
promoted. The encoder can come back once the AVE driver accepts the K114s 27.2 encoder firmware.
