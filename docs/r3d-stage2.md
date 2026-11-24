# r3d Stage 2: the K114s tree on the r3d includes, and Aura b15

Status 2026-11-24: **built and checked offline; not booted.** This is the loader-and-tree batch of the owner's request
to "get this device on the latest known code and fixes" (docs/r3d-kernel.md). The owner chose this batch next and
standing one-boot tests ("Reboot when ready, tell me"). Evidence labels: **agent-run**, **inferred**.

## 1. The tree

`dts/t6050-k114s-r3d.dts` is the configured r3c tree (`t6050-k114s-r3c.dts`), unchanged, plus the two board values
that r3d's shared `t6050-k114-k116.dtsi` now takes from the board file:
- `T6050_K_N1_FIRMWARE`: `"apple/centauri/k114s-ftab.bin"`;
- `T6050_K_BOARD_ID`: `0x14`.

The values are those of r3d's own `t6050-k114s.dts`. Without them the build stops. The wrapper also carries the
enables that r3d's board file makes at board level:
- `T6050_ANE`, defined before `t6050-peripherals.dtsi` is included: the Neural Engine (#2293);
- `t6050-media.dtsi`: the video encoder, ProRes and both JPEG engines (#2278);
- `t6050-isp.dtsi`: the shared camera tree (#2275).

In the built tree, `neural-processor@508000000`, `video-encoder@2283100000`, `prores@48d000000` and the two `jpeg` nodes
are `okay`. The camera's `isp@580000000` and its DARTs stay `disabled` until a loader hands the camera over; the K114s
also needs its activity light described first (#231). USB-C (`t6050-k114-k116-usb.dtsi`) and the GPU stay this
repository's own fragments, and the USB-C lint passes.

Build with `build/build-r3a-dtb.sh <r3d kernel tree> t6050-k114s-r3d <out>`, with the private PMP tunables in
`K114S_PMP_TUNABLES` (sha256 `df27244e4900…`). The result is `26c3407f8793e3e11adcc0642f5bb2d35c3882dd50772d557b7c817631929d70`,
153,819 bytes (agent-run). Without the three engine and camera enables it was `a3e27280…`, which the first review caught (P1).

The node diff (`tests/dtb-node-diff.py`) is against the configured blob `8258c8a8…` (agent-run). 12 nodes are added and
none removed. The changes are real; this is not just phandle renumbering:
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

So test A tries out the MCC, five engines and their power domains, not just the MCC. Its check gates on the MCC
enabling cleanly, on no new error-priority kernel line, and on each engine's binding (agent-run evidence goes in the
boot record).

| Check | Result | Label |
| --- | --- | --- |
| `lint-dtb.py`, `lint-sound-dtb.py`, `lint-display-gpu-dtb.py`, `lint-usb-dtb.py` | pass on `26c3407f` (also on `8258c8a8`) | agent-run |
| `linux/audio/tree-check --root` on an unflattened replica | "the Stage A tree: jack link only, no amplifier, no speaker channel" | agent-run |
| `t6050-aop.dtsi` (it would enable the AOP's speaker DMA) | not in the include list | agent-run |

The configured `8258c8a8` itself does not rebuild byte for byte from its recorded inputs: its source state was not
saved. So the diff above is against the blob.

## 2. The loader

The configured Stage 2 `d1254de6` is Aura `1.0.0b13` (omacom/m1n1 `703a0a92`, the omacom package) plus `8258c8a8` plus
the U-Boot trailer. Rebuilt here, it is byte-identical, which confirms the `build/make-stage2.sh` layout.

Aura `v1.0.0b15` (aurora-silicon/aura, tagged 2026-11-22) was built from the tag with the package's flags:
`make RELEASE=1 CHAINLOADING=1 ESP_STAGE2=1 USE_CLANG=1`, rust 1.99.0, the Omarchy logos. The result is `788277b6…`,
3,932,160 bytes (agent-run). It is a faithful source build, not omacom's bytes: the same recipe for b13 differs from
the package in about 202 KB, most likely because of the compiler.

What b15 changes on this Mac:
- **#399:** usb-drd defaults for every ATC port (inferred).
- PCIe root-port and AOP firmware handling, firmware-27 DCP clocks on the legacy path, and fail-closed T6050 bandwidth
  blocks (inferred).
- The speaker-safety node of #328 is already in b13 (agent-run, by strings).
- Aura's b15 qualification lists no T6050 Mac. Main, which has the live-DCP hand-off that stops the boot hard, was not
  built.

## 3. The test boots

There are two one-boot tests, in this order, each with its own record. If the second fails, the cause is the loader.

| Test | Stage 2 | sha256 |
| --- | --- | --- |
| A | b13 (installed) + tree `26c3407f` | `d9aab35c6d7a25755b8d39ceb5f80ce3fbae02ecbb595b06b2024fa75b36459d` |
| B | b15 + tree `26c3407f` | `1ac3c9315cad838889dc0886b986a6f002878b759b0924c3c4fada657ab8cfb7` |

- **How it boots:** each test goes through `aura-try`, which arms the trial file once. The configured Stage 2 stays the
  default, so a hang is followed by the configured file at the next power-on. For test A that is `d1254de6`. For test
  B it is whatever is configured when B is armed: `d9aab35c` if test A was promoted, else `d1254de6`. The test B kit
  pins that file, not `d1254de6`. The trial watchdog does not arm on this Mac, so a hang needs a long press on the
  power button.
- **What must pass:** the r3d checks: the speaker gate and both cards, P9, kernel health, the 120 Hz 10-bit panel, the
  GPU, the light sensor, the NVRAM read path, the SEP, the microphone, network, Bluetooth, the battery and bit-exact
  decode. Test A also gates on:
  - the MCC: its node in the booted tree, its line "system level cache allocation enabled on N planes", and none of
    its failure or warning lines;
  - no error-priority kernel line that the previous boot did not have, which catches an engine that fails to probe;
  - the Apple MTP keyboard and multi-touch.

  The binding of the Neural Engine, the encoder, ProRes and both JPEG engines is recorded for each device. The ISP is
  expected to stay unbound, because its node is disabled.
- **Promotion:** a test that passes is promoted: both pinned trees and, for B, the loader become the tested ones.
  Before anything changes, the promote script proves that `update-boot-ctxr`'s own recipe (loader + tree + `boot.bin`'s
  U-Boot trailer) gives the tested file. It then requires the written Stage 2 to be that file byte for byte. If
  anything fails or is interrupted, it restores the trees, the Stage 2 and P9.
- **Test B waits for the macOS repair tool.** `macos/tools/k114s_repair.py` recognises a Stage 2 only by the loader
  prefixes it knows: the r2c bundle's installed loader (3,997,696 bytes) and the pin loader (4,063,232 bytes). The
  Stage 2 configured since 2026-11-23 (`d1254de6`, Aura b13 at 3,932,160 bytes, with the aurora9 U-Boot trailer) is
  already unknown to it. Test A keeps that loader, so it changes nothing here. Test B would configure another unknown
  prefix, so it is not promoted until the repair tool knows the configured loader and trailer (#234).
