# Camera (Apple ISP) for the K114s (#33)

**Status (2026-11-20).** The K114s one-boot trial handed the ISP over to Linux. The driver stopped at
probe because the device tree lacks a physical camera activity-light description. The normal r3c
tree keeps the camera disabled. The trial source is reproducible against the current r3c-upstream
kernel and remains separate from the default tree.

## What was found

Initial state (2026-11-15, agent-run): `CONFIG_VIDEO_APPLE_ISP=m`; `/lib/firmware/apple` has the six `isp_*.dat` files; the
live device tree has `/soc/isp@580000000` (`apple,t6050-isp`) with `status = "disabled"`, no
`memory-region`, no `apple,platform-id`, and no `isp` alias; `/dev/video*` and `/dev/media*` do not exist; the
loader log (`aura_stage2.log`) has no ISP hand-off line at all, only `dapf: Initialized /arm-io/dart-isp0`.
Without an `isp` alias the loader's `dt_set_t6050_isp()` returns silently before it reads the board table.

ADT (agent-run: `sudo python3 -I tests/k114s-adt-camera-facts.py`, read-only: 23 shared facts, the sensor type, and the loader gate, including the OS firmware key):

| | K114s (ADT of the 27.2 stub) | K116s (aura #188, linux #1648) | K114c (linux #1756) |
| --- | --- | --- | --- |
| `isp0` `sensor-type` | **0xba** | 0xbc | 0xb9 |
| firmware uuid | `980F533B-34EA-3FBA-878C-809F6AF57345` | same | not stated |
| `cam-connections-scheme` | 0x10 | 0x10 | 0x10 |
| `isp0` windows, interrupts | `0x580000000` +0x3ff0000, `0x280900000` +0x3f4; 513 to 516, 526 | same | same |
| `dart-isp0` | 3 instances `0x5828c0000/e0000/900000`, dapf `0x5828d0000`, irq 531, sid 0 and 12, exclave 4 5 8 9, remap 1 6 7 10 11 | same | same |
| pmgr | FAB9_SOC 0x398, ISP_SYS 0x3a0, ISPSENS0 0x100 | same | same |
| firmware segments | two: text 0xc1c000 and data 0x13d0000 bytes, iova 0 and 0xc1c000, remap `0x10000000000` and `0x10000c1c000` | same | same layout |
| `isp0` children (sensor nodes) | none | none | none |

So the K114s equals the K116s in everything except the sensor type. The same ADT, replayed through the
loader's gate (the OS firmware key, `t6050_isp_segments_valid` and the layout checks of aura `dt_set_t6050_isp`), passes with a
K114s row of 0xba and is refused with the K114c row (0xb9) or the K116s one (0xbc): that is why a row of
its own is needed. The segment addresses (`0x1000109c000`, `0x100026a0000`) are placed by iBoot and move
after an update, so the loader reads them at boot; no tree here carries them. The ADT does not describe a camera-light GPIO (`eic` `cil` 1, `mil` 1, no `cil-gpio-offset`), same as the K114c. The missing property does not establish whether the laptop has a physical light or how macOS drives it. The table's firmware key is the OS firmware (`/chosen` `firmware-version`, aura `os_firmware`), which must be
`mBoot-20457.41.3` (V27_2); the checker requires it and refuses any other. The system firmware
(`system-firmware-version`, `mBoot-20457.60.65.0.1`, the 27.3 beta 1 system iBoot, V27_3B) is a different
property and is not part of the key; the K116s's value is not recorded upstream, so it is not compared.

## What was added

| File | What |
| --- | --- |
| `patches/aura/camera/0001-kboot-T6050-hand-the-K114s-camera-over-on-27.2.patch` | one table row, `{"apple,k114s", 0xba, V27_2}`, plus comments. Applies with `git am` on the loader base this repository builds: aura `22b71758` + betizzel's seven patches (`build/native/setup.sh`) + `patches/aura/0001-0003`, checked as the whole series; not built (no aarch64 build host here). It lives in its own folder so the display recipe's `git am patches/aura/*.patch` (docs/r3-display-gpu.md) stays the display loader and the D-series binary stays reproducible |
| `dts/t6050-k114s-isp.dtsi` | draft, off by default (`K114S_R3_ISP`), not included by any tree: includes the base tree's `t6050-j716c-isp.dtsi`, as the K116s tree does. Not compiled: this host has no `dtc` and no kernel tree |
| `tests/k114s-adt-camera-facts.py` | reads the ADT (root, read-only, or `--adt FILE`), compares with the K116s values, replays the loader gate |
| `tests/test-adt-camera-facts.py` | replica test: a made-up ADT from the public K116s values passes; wrong sensor type, interrupt, power-state offset, segment address and layout fail. No Apple data |
| `tests/hardware/k114s-camera-check.sh` | report the Apple ISP capture device and light description; `--capture` saves one local frame from that device |

Tests run: `git am` of betizzel's seven, `patches/aura/0001-0003` and `patches/aura/camera/0001` in order on aura `22b71758` (applies); `python3 tests/test-adt-camera-facts.py` (all ok, with a planted serial number and MAC address), `python3 -I tests/k114s-adt-camera-facts.py` on this Mac (exit 0).
The camera trial loader is the r3 loader (`patches/aura/0001-0003`) plus `patches/aura/camera/0001`, built as its own Stage 2
variant or `aura-try` image, never folded into a display trial. Not run: a DTS compile and `tests/lint-dtb.py` of the new fragment (no `dtc`); the aura build; the KUnit
case of linux #1831 (no build host).

## What the one-boot trial proved

On November 18, the K114s booted the camera Stage 2 once using its own 27.2 loader row. The loader
reported the hand-off and supplied platform ID `0xba`. The matching ISP module reached probe and
returned `ENODEV`. The T6050 driver's `camera_light` path requires both a memory resource named
`cil` and `apple,cil-config`; it also reads the pin back before starting a stream. Neither resource
description was available. The ISP created no capture device. The AVD decoder may still expose
video and media nodes, so their presence alone does not prove camera enumeration.

The trial returned to the configured r3c boot path. The camera Stage 2 image and its matching module
were kept as private build artifacts. The earlier watchdog acknowledgment covered that one boot.

## What carries over from the K114c

[Joshua Warren's K114c recipe](https://joshuawarren.com/blog/omarchy-m5-proled-complete-recipe/)
reports 720p30 NV12 capture. It identifies the daily kernel and boot images by filename and digest.
The recipe's feature ledger is private, so the exact daily kernel's camera commits cannot be
reconstructed from the recipe alone. The public ISP building blocks can be compared independently.

| Component | K114s disposition |
| --- | --- |
| Loader and firmware | Retain the existing K114s row (`0xba`, `V27_2`); the trial exercised it. [Aura #206](https://github.com/aurora-silicon/aura/pull/206) and [#225](https://github.com/aurora-silicon/aura/pull/225) concern the K114c's `0xb9` sensor. The installed ISP data files still need matching to the K114s 27.2 firmware for capture. |
| Kernel and tree | Keep the r3c-upstream watchdog range from [Linux #1854](https://github.com/aurora-silicon/linux/pull/1854). The separate [#1831](https://github.com/aurora-silicon/linux/pull/1831) backport recognizes the 27.2 firmware property. The [camera trial tree](../dts/t6050-k114s-r3c-camera.dts) layers the ISP aliases and resources on the normal r3c source and starts the ISP disabled until loader hand-off. |
| Sensor preset | Preset 5 from the shared J716c/K116s layout remains a hypothesis. [Linux #2566](https://github.com/aurora-silicon/linux/pull/2566) describes K114c preset 6 and its crop. This K114s has sensor type `0xba`; the trial ended before verifying which preset gives correctly framed output. |
| Activity indicator | [Linux #2561](https://github.com/aurora-silicon/linux/pull/2561), merge `abc619193559`, replaces the #1744 software indicator series. The board opts in through a DCP phandle. The display can show a green square, and capture can continue when the square cannot be shown. The merged ISP source lacks r3c's physical-light probe and stream checks. A direct substitution would lose those checks. Keep r3c's protection and evaluate the display overlay separately once the physical path is known. |

## Build and next attended check

Apply [the 27.2 parser patch](../patches/linux/camera/0001-media-apple-isp-add-firmware-version-27-2.patch)
after the r3c-upstream series. Use the running release's configuration, symbol table and module
toolchain to build `apple-isp.ko`. Compile `t6050-k114s-r3c-camera.dts` with the r3c includes
and the same private PMP input as the normal tree. The November 20 rebuild matched the
configured control DTB and the original camera trial DTB and Stage 2 byte for byte. The ISP
module built for the running r3c-upstream release and retained both physical-light checks.
The camera helper passed isolated checks for AVD-only, ISP without the light description,
ISP with a light description, and the wrong board. Only the ISP-with-light fixture invoked capture. Keep the module, DTB, loader and
firmware artifacts outside git. The normal tree and both verified UKIs remain the recovery path.

Before another trial, obtain the K114s activity-light resource and configuration from board-specific
evidence, including the register, pin configuration and polarity expected by the driver, or an
equivalent kernel-supported physical indicator with verified fail-closed behavior. Do not infer
those values from the K114c or J714c. Then use a fresh attended window and Jarvis's one-boot
watchdog acknowledgment. Verify the ISP probe and the physical light during a local frame capture,
then verify that the light goes out when capture ends. Run
`tests/hardware/k114s-camera-check.sh --capture` for a one-frame ISP capture. Once that passes,
check the camera preview in the intended meeting app or browser and confirm the light follows start
and stop there as well. Record dimensions, format, frame count, indicator observations and the
normal boot readback. Keep frames local.
