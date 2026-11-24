# r3d Stage 2: the K114s tree on the r3d includes, and Aura b15

Status 2026-11-24: **built and checked offline; not booted.** This is the loader-and-tree batch of the owner's request
to "get this device on the latest known code and fixes" (docs/r3d-kernel.md). The owner chose this batch next and
standing one-boot tests ("Reboot when ready, tell me"). Evidence labels: **agent-run**, **inferred**.

## 1. The tree

`dts/t6050-k114s-r3d.dts` is the configured r3c tree (`t6050-k114s-r3c.dts`), unchanged, plus the two board values
that r3d's shared `t6050-k114-k116.dtsi` now takes from the board file:
- `T6050_K_N1_FIRMWARE`: `"apple/centauri/k114s-ftab.bin"`;
- `T6050_K_BOARD_ID`: `0x14`.

The values are those of r3d's own `t6050-k114s.dts`. Without them the build stops.

Build with `build/build-r3a-dtb.sh <r3d kernel tree> t6050-k114s-r3d <out>`, with the private PMP tunables in
`K114S_PMP_TUNABLES` (sha256 `df27244e4900…`). The result is `a3e272802b797cc701a03b5fb8b781de4831b328193d2341eccf3dfc253296d4`,
151,568 bytes (agent-run). The build reproduces byte for byte from this repository.

The node diff (`tests/dtb-node-diff.py`) is against the configured blob `8258c8a8…`: 2 nodes are added and none removed
(agent-run).
- **Added:** `memory-controller@2220000000` (`apple,t6050-mcc`, with `apple,boot-dma-devices = <&dcp>`). The r3d kernel
  has `CONFIG_APPLE_MCC=y`, so its driver probes on the K114s for the first time. It waits for the display coprocessor
  to retire the boot scanout, then enables system-level-cache allocation on each of its 16 windows. Those 16 windows sit
  inside this Mac's four enabled memory controllers: the ADT `/arm-io/mcc` has `amcc-count` 8, `amcc-enable-mask` `0xf`
  and `dcs-count-per-amcc` 4, and translates amcc0-3 to `0x22_2000_0000`, `0x22_2200_0000`, `0x22_2400_0000` and
  `0x22_2600_0000`, `0x140000` each (agent-run, read from the ADT MTD). None of the windows lands in a disabled
  controller. This is the part of the tree with real risk, and the test boot is its proof.
- `/chosen/framebuffer@0` gets `display = <&dcp>`, and four DARTs get `reg-names`. The four MTP nodes are disabled and
  then re-enabled, so they end up as before.
- **Unchanged:** PCIe port 0 and the N1 (Wi-Fi and Bluetooth), the exposed pins, the USB-C ports, the PMP, the AOP
  and the sound node. All other differences are phandle renumbering: an independent check mapped every changed cell
  through both phandle tables and found no real change.

| Check | Result | Label |
| --- | --- | --- |
| `lint-dtb.py`, `lint-sound-dtb.py`, `lint-display-gpu-dtb.py`, `lint-usb-dtb.py` | pass (also on `8258c8a8`) | agent-run |
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
| A | b13 (installed) + tree `a3e27280` | `f1cef979d60a840d9241be29f06c3d826af090213ff851843451bbdfe8637b0f` |
| B | b15 + tree `a3e27280` | `48d461ac6e78ebc256701fbc3c7bc784a4a8091f020fe27c75f8b698953344a1` |

- **How it boots:** each test goes through `aura-try`, which arms the trial file once. The configured Stage 2 stays the
  default, so a hang is followed by `d1254de6` at the next power-on. The trial watchdog does not arm on this Mac, so a
  hang needs a long press on the power button.
- **What must pass:** the r3d checks (the speaker gate and both cards, P9, kernel health, the 120 Hz 10-bit panel, the
  GPU, the light sensor, the NVRAM read path, the SEP, the microphone, network, Bluetooth, the battery and bit-exact
  decode). Also: the MCC driver bound with no error, the keyboard and trackpad, and the USB-C ports enumerating.
- **Promotion:** a test that passes is promoted. Both pinned trees and, for B, the loader become the tested ones.
  `update-boot-ctxr` must then write the tested file again.
